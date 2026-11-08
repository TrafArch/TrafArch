import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_controller.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/application/card_records_export.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/presentation/card_detail_page.dart';
import 'package:transit_card_analyzer/features/archive/presentation/local_card_history_records.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/features/scan/domain/scan_presentation.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/features/trips/local_card_trip_presenter.dart';
import 'package:transit_card_analyzer/features/trips/trip_cards_view.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_card.dart';
import 'package:transit_card_analyzer/features/trips/trip_filters.dart';
import 'package:transit_card_analyzer/features/trips/trips_page.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/log_exporter.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

import 'support/test_database.dart';

class _App extends AppDependencies {
  _App(this.card)
    : super(
        database: testDatabase(),
        bundle: MissingTestAssets(),
        settingsStore: MemorySettingsStore(),
        logger: AppLogger(store: MemoryLogStore()),
      );

  final ParsedCard card;

  @override
  ParsedCard? get parsedCard => card;

  @override
  ReadResult? get localReadResult => card.localCard;

  @override
  Currency get cardCurrency =>
      Currency.fromCode(card.localCard?.info.currencyCode);

  @override
  String? get cardCityCode => null;

  @override
  String? cityNameOf(String? code) => null;
}

ApduRecord _trip({
  int recordNumber = 1,
  int? fileSelector,
  int statusCode = 0,
  int posType = 0x09,
  int balanceDelta = -320,
  DateTime? timestamp,
  bool isMetro = false,
  bool isBus = false,
  int cityCode = 0,
  String? terminalHex,
  List<int>? rawBody,
}) {
  final record = ApduRecord()
    ..recordNumber = recordNumber
    ..fileSelector = fileSelector ?? TripFile.metro.p2
    ..statusCode = statusCode
    ..posType = posType
    ..balanceDelta = balanceDelta
    ..timestamp = timestamp ?? DateTime(2026, 10, 21, 12, 30)
    ..isMetro = isMetro
    ..isBus = isBus
    ..cityCode = cityCode
    ..terminalHex = terminalHex
    ..type = 2;
  if (rawBody != null) record.rawBody = Uint8List.fromList(rawBody);
  return record;
}

ParsedCard _whctcCard({List<ApduRecord> trips = const []}) {
  final info = CardInfo()
    ..isWHCTC = true
    ..cardNumber = '0102030405'
    ..cityCode = 5210
    ..balance = 1000;
  return ParsedCard(
    parserId: CardParserIds.localCard,
    parserName: '地方交通卡 · 武汉通',
    info: const TUnionCardInfo(applicationSerial: '0102030405'),
    transactions: const [],
    localCard: ReadResult(info: info, records: trips, extras: CardExtras()),
  );
}

void main() {
  group('local_card_trip_presenter', () {
    test('武汉通行程适配票据卡：消费、序号、时间、金额与详情字段', () {
      final record = _trip(
        recordNumber: 2,
        posType: 0x06,
        balanceDelta: -1000,
        timestamp: DateTime(2026, 10, 21, 12, 30),
        terminalHex: '123456789012',
        rawBody: [0x00, 0x02],
      );
      final presentation = describeLocalTrip(record, currencySymbol: '¥');
      expect(presentation.source, LocalTripSourceFilter.metro);
      expect(presentation.mode, TripModeFilter.rail);
      expect(presentation.info.title, '消费 · 序号 2');
      expect(presentation.info.timeText, '2026-10-21 12:30:00');
      expect(presentation.info.amountText, '-¥10.00');
      expect(presentation.info.isConsume, isTrue);
      expect(presentation.info.fields, contains(('记录类型', '消费')));
      expect(presentation.info.fields, contains(('交易序号', '2')));
      expect(presentation.info.fields, contains(('类型字节', '0x06')));
      expect(presentation.info.fields, contains(('终端 HEX', '123456789012')));
      expect(presentation.journeyEvent!.endpoint.time!.year, 2026);
    });

    test('公交行程按 isBus 映射方式，充值按平衡增量展示为正', () {
      final bus = describeLocalTrip(
        _trip(isBus: true, fileSelector: TripFile.bus.p2, balanceDelta: -200),
        currencySymbol: '¥',
      );
      expect(bus.mode, TripModeFilter.bus);
      expect(bus.source, LocalTripSourceFilter.bus);
      final recharge = describeLocalTrip(
        _trip(posType: 0x02, balanceDelta: 5000),
        currencySymbol: '¥',
      );
      expect(recharge.info.title, '充值 · 序号 1');
      expect(recharge.info.amountText, '+¥50.00');
      expect(recharge.info.isConsume, isFalse);
    });

    test('未知时间与缺失原始字节：时间未知、金额为空、不展示余额', () {
      final unknown = describeLocalTrip(
        _trip(
          balanceDelta: 0,
          timestamp: DateTime.fromMillisecondsSinceEpoch(0),
        ),
        currencySymbol: '¥',
      );
      expect(unknown.info.timeText, isNull);
      expect(unknown.info.amountText, isNull);
      expect(unknown.info.rawHex, isNull);
      expect(unknown.journeyEvent!.endpoint.time, isNull);
      expect(
        projectJourneys([unknown.journeyEvent!]).single.balanceAfterText,
        isNull,
      );
    });

    test('归档字段还原：restoreLocalTripRecord 往返保留关键字段', () {
      final original = _trip(
        recordNumber: 3,
        posType: 0x06,
        balanceDelta: -1000,
        timestamp: DateTime(2026, 10, 21, 12, 30),
        isBus: true,
        terminalHex: '123456789012',
        rawBody: [0x00, 0x03, 0x01],
      );
      final fields = <String, dynamic>{
        'recordNumber': original.recordNumber,
        'fileSelector': original.fileSelector,
        'statusCode': original.statusCode,
        'posType': original.posType,
        'timestamp': original.timestamp.millisecondsSinceEpoch,
        'balanceDelta': original.balanceDelta,
        'cityCode': original.cityCode,
        'isMetro': original.isMetro,
        'isBus': original.isBus,
        'label': original.label,
        'terminalHex': original.terminalHex,
        'rawBody': original.rawBody == null
            ? null
            : List<int>.of(original.rawBody!),
      };
      final restored = restoreLocalTripRecord(fields);
      expect(restored, isNotNull);
      expect(restored!.recordNumber, 3);
      expect(restored.posType, 0x06);
      expect(restored.balanceDelta, -1000);
      expect(restored.isBus, isTrue);
      expect(restored.terminalHex, '123456789012');
      final presentation = describeLocalTrip(restored, currencySymbol: '¥');
      expect(presentation.mode, TripModeFilter.bus);
      expect(presentation.info.rawHex, '000301');
      expect(restoreLocalTripRecord(const {}), isNull);
    });
  });

  testWidgets('TripsPage 展示地方交通卡行程（实时读取）', (tester) async {
    final app = _App(
      _whctcCard(
        trips: [
          _trip(
            recordNumber: 1,
            posType: 0x06,
            balanceDelta: -1000,
            timestamp: DateTime(2026, 10, 21, 12, 30),
          ),
        ],
      ),
    );
    addTearDown(app.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TripsPage(app: app))),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无行程数据'), findsNothing);
    expect(find.text('武汉通'), findsWidgets);
    expect(find.text('地方交通卡 · 1 条记录'), findsOneWidget);
    final view = tester.widget<TripCardsView>(
      find.byWidgetPredicate((widget) => widget is TripCardsView),
    );
    expect(view.entries, hasLength(1));
    expect(view.entries.single.mode, TripModeFilter.rail);
    expect(find.text('记录 1 条'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TripsPage 无地方卡行程时不显示地方卡区块', (tester) async {
    final app = _App(_whctcCard());
    addTearDown(app.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TripsPage(app: app))),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂无行程数据'), findsOneWidget);
    expect(find.text('地方交通卡 · '), findsNothing);
  });

  test('归档保存 localCardTrips 扩展并可导出', () async {
    final repository = CardRepository(testDatabase());
    final controller = ArchiveController(
      repository,
      const MethodChannelLogExporter(),
      (_) {},
    );
    addTearDown(controller.dispose);
    final card = _whctcCard(
      trips: [
        _trip(
          recordNumber: 1,
          posType: 0x06,
          balanceDelta: -1000,
          timestamp: DateTime(2026, 10, 21, 12, 30),
          terminalHex: '123456789012',
        ),
      ],
    );
    controller.stage(
      ScanPresentation(TransitReadOutcome(card), KnowledgeBase.empty()),
      'whctc-capture',
      DateTime.utc(2026, 10, 26),
      const [],
    );
    final pending = controller.pending!;
    expect(pending.transactionCount, 1);
    final captured = pending.sessionDataJson!;
    final decoded = CardSessionSnapshot.decodeResult(captured).snapshot!;
    expect(decoded.extensions['localCardTrips'], isA<Map<String, dynamic>>());
    expect(decoded.encode(), captured);
    expect(await controller.accept(pending.pendingSaveId), isTrue);

    final saved = (await repository.getAllCards()).single;
    final history = await ArchiveHistory(repository).load(saved.id);
    final local = history.localCardRecords
        .where((record) => record.cardType == 'localCardTrips')
        .toList();
    expect(local, hasLength(1));
    expect(restoreLocalTripRecord(local.single.fields), isNotNull);

    final exported = buildArchiveHistoryExport([history]);
    expect(exported, contains('地方交通卡行程（1 条）'));
    expect(exported, contains('消费 · 序号 1'));
    expect(exported, contains('-¥10.00'));
  });

  testWidgets('卡片详情用票据式行程卡展示地方卡行程', (tester) async {
    final repository = CardRepository(testDatabase());
    final controller = ArchiveController(
      repository,
      const MethodChannelLogExporter(),
      (_) {},
    );
    addTearDown(controller.dispose);
    controller.stage(
      ScanPresentation(
        TransitReadOutcome(
          _whctcCard(
            trips: [
              _trip(
                recordNumber: 1,
                posType: 0x06,
                balanceDelta: -1000,
                timestamp: DateTime(2026, 10, 21, 12, 30),
              ),
            ],
          ),
        ),
        KnowledgeBase.empty(),
      ),
      'whctc-capture',
      DateTime.utc(2026, 10, 26),
      const [],
    );
    final pending = controller.pending!;
    expect(await controller.accept(pending.pendingSaveId), isTrue);
    final saved = (await repository.getAllCards()).single;

    await tester.pumpWidget(
      MaterialApp(
        home: CardDetailPage(repository: repository, cardId: saved.id),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('地方交通卡 · 1 条记录'), findsOneWidget);
    final tripCard = tester.widget<TripEntryCard>(find.byType(TripEntryCard));
    expect(tripCard.journey, isNotNull);
    expect(tripCard.info.amountText, '-¥10.00');
    expect(tripCard.info.fields, contains(('记录类型', '消费')));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byType(TripEntryCard));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TripEntryCard));
    await tester.pumpAndSettle();
    expect(find.textContaining('记录来源：地铁流水'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('恢复现场投影含 localCardTrips 且票据还原可复用', (tester) async {
    final snapshot = CardSessionSnapshot(
      parseVersion: 15,
      context: const ArchiveContext(
        systemId: CardParserIds.localCard,
        currencyCode: 'CNY',
        minorUnitDigits: 2,
      ),
      extensions: {
        'localCardTrips': {
          'cardKindLabel': '武汉通',
          'version': 1,
          'records': [
            {
              'recordNumber': 1,
              'fileSelector': TripFile.metro.p2,
              'statusCode': 0,
              'posType': 0x06,
              'timestamp': DateTime(2026, 10, 21, 12, 30)
                  .millisecondsSinceEpoch,
              'balanceDelta': -1000,
              'cityCode': 0,
              'isMetro': false,
              'isBus': false,
              'terminalHex': '123456789012',
              'rawBody': [0x00, 0x01, 0x02],
            },
          ],
        },
      },
    );
    final batch = ArchiveBatchEvidence(
      id: 'recovered',
      readAt: DateTime(2026, 10, 26).millisecondsSinceEpoch,
      storedParseVersion: 15,
      origin: 'memory_recovery',
      timeSource: 'captured',
      decoded: CardSessionSnapshot.decodeResult(snapshot.encode()),
      issues: const [],
    );
    final history = ArchiveHistoryResult(
      card: null,
      batches: [batch],
      localCardRecords: ArchiveHistory.projectLocalCardRecords([batch]),
    );
    final local = history.localCardRecords
        .where((record) => record.cardType == 'localCardTrips')
        .toList();
    expect(local, hasLength(1));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ArchivedLocalCardTrips(records: local),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('地方交通卡 · 1 条记录'), findsOneWidget);
    expect(find.text('-¥10.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}