import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/application/cu_archive_projection.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/recovery/recovery_state.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/reference_match.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/station_codes.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/features/transit_analysis/cu_transaction_analysis.dart';
import 'package:transit_card_analyzer/features/trips/cu_transaction_list.dart';
import 'package:transit_card_analyzer/features/trips/cu_trip_presenter.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/features/trips/trip_cards_view.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_card.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_presenter.dart';
import 'package:transit_card_analyzer/features/trips/trip_filters.dart';
import 'package:transit_card_analyzer/features/trips/trips_page.dart';
import 'package:transit_card_analyzer/platform/memory/memory_platform.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_file_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'CU uses its carrier and civil date without claiming a direction or fare',
    () {
      final before = _view(sequence: 10, amount: 0);
      final after = _view(sequence: 11);
      final bytesBefore = before.record.toJson();
      final entries = [describeCuTrip(after), describeCuTrip(before)];
      final journeys = projectJourneys([
        for (final entry in entries) entry.journeyEvent!,
      ]);
      expect(journeys, hasLength(2));
      for (final journey in journeys) {
        expect(journey.mode, TripModeFilter.rail);
        expect(journey.state, JourneyState.incomplete);
        expect(journey.start, isNull);
        expect(journey.end, isNull);
        expect(journey.duration, isNull);
        expect(journey.amountText, '金额未知');
        expect(journey.balanceAfterText, isNull);
      }
      final endpoint = entries.first.journeyEvent!.endpoint;
      expect(endpoint.time, DateTime.utc(2026, 11, 7, 0, 5));
      expect(endpoint.timeText, '2026-11-07 00:05:00');
      expect(endpoint.line, '2号线');
      expect(endpoint.station, '演示站');
      expect(before.record.toJson(), bytesBefore);
    },
  );

  test('CU preserves ambiguity and cannot turn recharge or unknown types into rides', () {
    final candidates = const [
      StationCodeEntry(
        code: '001',
        line: '错误线路甲',
        station: '错误站甲',
        kind: 'metro',
      ),
      StationCodeEntry(
        code: '002',
        line: '错误线路乙',
        station: '错误站乙',
        kind: 'metro',
      ),
    ];
    final ambiguous = describeCuTrip(
      _view(
        location: ReferenceMatch(ReferenceMatchStatus.ambiguous, candidates),
      ),
    );
    expect(ambiguous.mode, TripModeFilter.rail);
    expect(ambiguous.journeyEvent!.endpoint.line, isNull);
    expect(ambiguous.journeyEvent!.endpoint.station, '地点存在歧义');
    expect(ambiguous.info.badges, ['站名歧义']);
    final unknown = describeCuTrip(
      _view(
        carrier: null,
        location: ReferenceMatch(ReferenceMatchStatus.unknown, const []),
      ),
    );
    expect(unknown.mode, TripModeFilter.other);
    final recharge = describeCuTrip(
      _view(sfi: 0x10, kind: CityUnionTransactionKind.recharge),
    );
    expect(recharge.mode, TripModeFilter.other);
    expect(recharge.source, CuTripSourceFilter.recharge);
    expect(recharge.info.isConsume, isFalse);
    expect(describeCuTrip(_view(sfi: 0x1A)).source, CuTripSourceFilter.foreign);
    expect(
      describeCuTrip(_view(sfi: 0x06)).source,
      CuTripSourceFilter.shanghaiForeign,
    );
    final bus = describeCuTrip(_view(carrier: 1, line: '345'));
    expect(bus.mode, TripModeFilter.bus);
    expect(bus.journeyEvent!.endpoint.line, '345路');
    expect(describeCuTrip(_view(carrier: 1, line: '00345')).info.line, '00345');
  });

  test(
    'CU archived tickets consume frozen locations and preserve every source',
    () {
      final capture = captureCuProjection([_view()]);
      final batches = [_batch('a', capture), _batch('b', capture)];
      final projection = projectCuArchive(
        ArchiveHistoryResult(card: null, batches: batches),
      );
      expect(projection.transactions, hasLength(1));
      final transaction = projection.transactions.single;
      final entry = describeCuTrip(
        transaction,
        savedSource: projection.sourceLabels[transaction],
      );
      expect(entry.journeyEvent!.endpoint.line, '2号线');
      expect(entry.journeyEvent!.endpoint.station, '演示站');
      expect(
        entry.info.fields,
        contains((
          '保存来源',
          'a/cuProjection.transactions[0], b/cuProjection.transactions[0]',
        )),
      );
      expect(projection.isRemoteUse(transaction, batches), isTrue);
      for (final batch in batches) {
        expect(batch.decoded.snapshot!.encode(), batch.decoded.rawJson);
      }
      final tuOnly = [
        _batch('tu', capture, systemId: CardParserIds.shanghaiTunion),
      ];
      final tuProjection = projectCuArchive(
        ArchiveHistoryResult(card: null, batches: tuOnly),
      );
      expect(
        tuProjection.isRemoteUse(tuProjection.transactions.single, tuOnly),
        isFalse,
      );
      final dual = [
        _batch(
          'dual',
          capture,
          systemId: CardParserIds.shanghaiTunion,
          cuCity: '2000',
        ),
      ];
      final dualProjection = projectCuArchive(
        ArchiveHistoryResult(card: null, batches: dual),
      );
      expect(
        dualProjection.isRemoteUse(dualProjection.transactions.single, dual),
        isFalse,
      );
      final partial = [...batches, _batch('unknown', capture, cuCity: '0000')];
      final partialProjection = projectCuArchive(
        ArchiveHistoryResult(card: null, batches: partial),
      );
      expect(
        partialProjection.isRemoteUse(
          partialProjection.transactions.single,
          partial,
        ),
        isFalse,
      );
    },
  );

  testWidgets(
    'CU shares TU cards, filters and detail sheet with readable original evidence',
    (tester) async {
      final rail = _view(sequence: 11);
      final bus = _view(sequence: 10, carrier: 1, line: '345');
      final recharge = _view(
        sequence: 9,
        sfi: 0x10,
        kind: CityUnionTransactionKind.recharge,
      );
      final changes = <List<String>>[];
      await _show(
        tester,
        CuTransactionList(
          transactions: [rail, bus, recharge],
          cityNameOf: (_) => '上海',
          isRemote: (_) => true,
          sourceLabels: {rail: 'read-a/record-1'},
          onFiltersChanged: changes.add,
        ),
      );
      expect(find.byType(ExpansionTile), findsNothing);
      expect(find.byType(TripEntryCard), findsNWidgets(3));
      expect(find.text('上海轨道交通'), findsOneWidget);
      expect(find.text('上海公共汽电车'), findsOneWidget);
      expect(find.text('2026年11月7日'), findsNWidgets(2));
      expect(find.text('异地用卡'), findsNWidgets(3));
      expect(find.text('历史行程 2'), findsOneWidget);
      expect(find.text('其他记录 1'), findsOneWidget);
      await tester.tap(find.widgetWithText(InputDecorator, '全部方式'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, '轨道交通'));
      await tester.pumpAndSettle();
      expect(find.byType(TripEntryCard), findsOneWidget);
      expect(changes.last, ['mode:rail']);
      await tester.tap(find.byType(TripEntryCard));
      await tester.pumpAndSettle();
      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      expect(find.text('记录来源：CU 0x18 #1'), findsOneWidget);
      expect(find.text('read-a/record-1'), findsOneWidget);
      final scrollable = find
          .descendant(
            of: find.byType(DraggableScrollableSheet),
            matching: find.byType(Scrollable),
          )
          .first;
      for (final label in ['终端原始编码', '金额原始值', '原始数据（HEX）']) {
        await tester.scrollUntilVisible(
          find.text(label),
          100,
          scrollable: scrollable,
        );
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text(groupTripHex(rail.record.rawHex)), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'CU source and mode selections combine and restore independently',
    (tester) async {
      final changes = <List<String>>[];
      await _show(
        tester,
        CuTransactionList(
          transactions: [_view(), _view(sfi: 0x06)],
          initialFilters: const ['source:shanghaiForeign', 'mode:rail'],
          onFiltersChanged: changes.add,
        ),
      );
      expect(find.byType(TripEntryCard), findsOneWidget);
      expect(
        tester
            .widget<TripEntryCard>(find.byType(TripEntryCard))
            .info
            .sourceLabel,
        'CU 0x06 #1',
      );
      await tester.tap(find.widgetWithText(InputDecorator, '0x06 异地交易'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, '0x18 交易'));
      await tester.pumpAndSettle();
      expect(changes.last, ['source:transaction', 'mode:rail']);
      expect(find.byType(TripEntryCard), findsOneWidget);
      expect(
        tester
            .widget<TripEntryCard>(find.byType(TripEntryCard))
            .info
            .sourceLabel,
        'CU 0x18 #1',
      );
      await _show(tester, CuTransactionList(transactions: [_view(sfi: 0x06)]));
      expect(find.byType(TripEntryCard), findsNothing);
      expect(find.text('当前筛选条件下没有记录'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'CU live trips and recovered captures use the shared UI without archive writes',
    (tester) async {
      final memory = _Memory();
      AppDependencies appFor() {
        final app = AppDependencies(
          database: testDatabase(),
          bundle: MissingTestAssets(),
          memoryPlatform: memory,
          logger: AppLogger(store: MemoryLogStore()),
          settingsStore: MemorySettingsStore(),
        );
        addTearDown(() {
          if (!app.disposed) app.dispose();
        });
        return app;
      }

      final app = appFor();
      await tester.runAsync(app.init);
      final outcome = TransitReadOutcome(
        ParsedCard(
          parserId: CardParserIds.cityUnion,
          parserName: '城市一卡通',
          info: const TUnionCardInfo(balanceFen: 8800),
          transactions: const [],
          cityUnionFiles: [
            const CjT331PublicInfo(
              cityCode: '1000',
              applicationSerialNumber: '12345678',
              fields: [],
              rawHex: '',
            ),
            _view().record,
          ],
        ),
      );
      app.scan.outcome = outcome;
      await tester.runAsync(
        () => app.scan.onCompleted!(
          outcome,
          'cu-live-test',
          DateTime(2026, 11, 7),
          () => true,
        ),
      );
      expect(app.analysis, isNull);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TripsPage(app: app)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('记录 1 条'), findsOneWidget);
      expect(find.text('¥88.00'), findsOneWidget);
      expect(find.byType(TripEntryCard), findsOneWidget);
      expect(
        find.byWidgetPredicate((widget) => widget is TripCardsView),
        findsOneWidget,
      );
      expect(
        tester.widget<TripEntryCard>(find.byType(TripEntryCard)).journey,
        isNotNull,
      );
      app.recoveryFilters['live:cu'] = ['mode:rail'];
      expect(
        await tester.runAsync(() => app.handleMemoryPressure(true)),
        isTrue,
      );
      final frozen = app.pendingCardSave!.sessionDataJson;
      expect(RecoveryState.decode(memory.text!).filters['live:cu'], [
        'mode:rail',
      ]);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
      await app.cardRepository.db.close();
      final restored = appFor();
      await tester.runAsync(restored.init);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TripsPage(app: restored)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('上次读取结果'), findsOneWidget);
      expect(find.byType(TripEntryCard), findsOneWidget);
      expect(find.widgetWithText(InputDecorator, '轨道交通'), findsOneWidget);
      expect(restored.recoveredCapture!.snapshotJson, frozen);
      expect(await restored.cardRepository.getAllCards(), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'CU tickets adapt to narrow windows and large text in both themes',
    (tester) async {
      final output = Platform.environment['TRAFARCH_VISUAL_REVIEW_DIR'];
      String? font;
      final fontFile = Platform.environment['TRAFARCH_VISUAL_FONT'];
      if (output != null && fontFile != null) {
        font = 'CuTripPreview';
        await (FontLoader(font)..addFont(
              Future.value(
                ByteData.sublistView(File(fontFile).readAsBytesSync()),
              ),
            ))
            .load();
        final icons = Platform.environment['TRAFARCH_VISUAL_ICON_FONT'];
        if (icons != null) {
          await (FontLoader('MaterialIcons')..addFont(
                Future.value(
                  ByteData.sublistView(File(icons).readAsBytesSync()),
                ),
              ))
              .load();
        }
      }
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final brightness in Brightness.values) {
        for (final width in [280.0, 430.0, 900.0]) {
          tester.view.physicalSize = Size(width, 1000);
          final key = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(
                fontFamily: font,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xff4e7098),
                  brightness: brightness,
                ),
              ),
              home: RepaintBoundary(
                key: key,
                child: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 1000),
                    textScaler: TextScaler.linear(width == 280 ? 2 : 1),
                  ),
                  child: Scaffold(
                    body: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: CuTransactionList(
                        transactions: [
                          _view(),
                          _view(sequence: 10, carrier: 1, line: '345'),
                        ],
                        cityNameOf: (_) => '上海',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(TripEntryCard), findsNWidgets(2));
          expect(
            tester.takeException(),
            isNull,
            reason: '${brightness.name}/$width',
          );
          if (output != null && width == 430) {
            await tester.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage(pixelRatio: 1);
              try {
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final file = File('$output/cu-trips-${brightness.name}.png');
                await file.parent.create(recursive: true);
                await file.writeAsBytes(bytes!.buffer.asUint8List());
              } finally {
                image.dispose();
              }
            });
          }
        }
      }
    },
  );
}

Future<void> _show(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

CuTransactionView _view({
  int sequence = 11,
  int amount = 300,
  int sfi = 0x18,
  int? carrier = 2,
  String line = '2号线',
  CityUnionTransactionKind kind = CityUnionTransactionKind.consumption,
  ReferenceMatch<StationCodeEntry>? location,
}) => CuTransactionView(
  record: CityUnionFileParser.parseWalletRecord(
    sfi,
    [
      sequence >> 8,
      sequence & 0xff,
      0,
      0,
      0,
      0,
      0,
      amount >> 8,
      amount & 0xff,
      kind == CityUnionTransactionKind.recharge ? 2 : 9,
      0x20,
      0x00,
      0x11,
      0x02,
      0x34,
      0x00,
      0x20,
      0x26,
      0x11,
      0x07,
      0x00,
      0x05,
      0x00,
    ],
    kind: kind,
    recordNumber: 1,
  ),
  transactionTime: DateTime.utc(2026, 11, 6, 16, 5),
  carrier: carrier,
  regionCode: '2000',
  location:
      location ??
      ReferenceMatch(ReferenceMatchStatus.matched, [
        StationCodeEntry(
          code: '2000110234',
          line: line,
          station: '演示站',
          kind: 'metro',
          system: 'cu',
          lineCode: '02',
          stationCode: '34',
        ),
      ]),
);

ArchiveBatchEvidence _batch(
  String id,
  Map<String, dynamic> projection, {
  String systemId = CardParserIds.cityUnion,
  String? cardCity = '1000',
  String? cuCity,
}) => ArchiveBatchEvidence(
  id: id,
  readAt: 1,
  storedParseVersion: 15,
  origin: 'test',
  timeSource: 'test',
  issues: const [],
  decoded: CardSessionSnapshot.decodeResult(
    CardSessionSnapshot(
      cardCityCode: cardCity,
      context: ArchiveContext(systemId: systemId),
      extensions: {'cuProjection': projection},
      rawEvidence: [
        if (cuCity != null)
          {'kind': 'cu_file', 'sfi': '0x15', 'cityCode': cuCity},
      ],
    ).encode(),
  ),
);

class _Memory extends NoopMemoryPlatform {
  String? text;
  @override
  Future<String?> readRecovery() async => text;
  @override
  Future<void> clearRecovery() async => text = null;
  @override
  Future<void> writeRecovery(String content) async => text = content;
}
