import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_identity.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_types.dart';
import 'package:transit_card_analyzer/features/archive/presentation/card_detail_page.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_card.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_details.dart';
import 'package:transit_card_analyzer/features/trips/trip_stream_view.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';

import 'support/test_database.dart';

void main() {
  testWidgets(
    'saved history opens offline as trip cards and readable details',
    (tester) async {
      final db = testDatabase();
      final repository = CardRepository(db);
      final id = await _save(repository, _snapshot(trips: [_transaction()]));

      // A new repository, with no AppDependencies, scan controller or resolver.
      await _open(tester, CardRepository(db), id);
      expect(find.byType(TripEntryCard), findsOneWidget);
      expect(find.textContaining('苏洋'), findsOneWidget);
      expect(find.text('-HK\$ 4.50'), findsOneWidget);
      expect(find.text('2026-10-19 · 1 条'), findsOneWidget);
      expect(find.textContaining('批次 ·'), findsNothing);
      expect(find.text('查看完整原始快照'), findsNothing);
      _expectNoJson();

      await tester.tap(find.byType(TripEntryCard));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(TripDetailRow), findsWidgets);
      expect(find.text('交易序号'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('交易时间'), findsOneWidget);
      expect(find.textContaining('2026-10-19 23:58:00'), findsWidgets);
      expect(find.text('原始数据（HEX）'), findsNothing);
      _expectNoJson();
      await _close(tester);
    },
  );

  testWidgets('all saved sources share cards and source plus mode filtering', (
    tester,
  ) async {
    final repository = CardRepository(testDatabase());
    final id = await _save(
      repository,
      _snapshot(
        trips: [_transaction()],
        rails: [_rail],
        buses: [_bus],
        cycle: [_process],
      ),
    );
    await _open(tester, repository, id);
    expect(find.byType(TripEntryCard), findsNWidgets(6));
    expect(find.textContaining('人民广场'), findsOneWidget);
    expect(find.textContaining('世纪大道'), findsOneWidget);
    expect(find.text('交易 1 条 · 过程及应用记录 3 条'), findsOneWidget);

    await _filter(tester, '0x1E 过程');
    expect(find.byType(TripEntryCard), findsOneWidget);
    expect(find.textContaining('上车'), findsOneWidget);
    await _filter(tester, '城市轨道交通');
    expect(find.byType(TripEntryCard), findsNothing);
    expect(find.text('当前筛选条件下没有记录'), findsOneWidget);
    await _filter(tester, '全部方式');
    await _filter(tester, '0x1A 轨道');
    expect(find.byType(TripEntryCard), findsNWidgets(3));
    await _filter(tester, '全部来源');
    await _filter(tester, '公共汽电车');
    expect(find.byType(TripEntryCard), findsNWidgets(3));
    await _filter(tester, '全部方式');
    expect(find.byType(TripEntryCard), findsNWidgets(6));
    _expectNoJson();
    await _close(tester);
  });

  testWidgets('cross-batch duplicates retain attribution and wallet contexts', (
    tester,
  ) async {
    final repository = CardRepository(testDatabase());
    final trip = _transaction()..remove('currency');
    final id = await _save(repository, _snapshot(trips: [trip]));
    await _save(
      repository,
      _snapshot(trips: [trip], marker: 'second capture'),
      day: 21,
    );
    await _save(
      repository,
      _snapshot(trips: [trip], currency: 'JPY', digits: 0),
      day: 22,
    );
    final history = await ArchiveHistory(repository).load(id);
    expect(history.records, hasLength(2));
    expect(history.records.map((r) => r.sources.length), containsAll([1, 2]));
    final before = (await repository.getArchiveRows(id)).batches;

    await _open(tester, repository, id);
    expect(find.byType(TripEntryCard), findsNWidgets(2));
    expect(find.text('-HK\$ 4.50'), findsOneWidget);
    expect(find.text('-JPY 450'), findsOneWidget);
    await tester.tap(
      find.ancestor(
        of: find.text('-HK\$ 4.50'),
        matching: find.byType(TripEntryCard),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('2 个批次'), findsOneWidget);
    _expectNoJson();
    await tester.scrollUntilVisible(
      find.text('诊断与原始证据'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('诊断与原始证据'));
    await tester.pumpAndSettle();
    expect(find.textContaining('"sources"'), findsOneWidget);
    expect(find.textContaining('"batchId"'), findsOneWidget);
    expect(find.textContaining('trips[0]'), findsOneWidget);
    expect(
      (await repository.getArchiveRows(id)).batches.map((b) => b.payloadJson),
      before.map((b) => b.payloadJson),
    );
    await _close(tester);
  });

  for (final version in [1, 2]) {
    testWidgets('legacy v$version keeps unknown currency and clock readable', (
      tester,
    ) async {
      final repository = CardRepository(testDatabase());
      final legacy = _transaction()
        ..remove('currency')
        ..remove('capturedTimes');
      final id = await _save(repository, {
        'v': version,
        'trips': [legacy],
        if (version == 1) 'rail': _rail,
        if (version == 2) ...{
          'rails': [_rail],
          'buses': <Object>[],
          'cycle': <Object>[],
        },
      });
      await _open(tester, repository, id);
      expect(find.byType(TripEntryCard), findsNWidgets(3));
      expect(find.text('-币种未知 4.50'), findsOneWidget);
      expect(find.textContaining('时区未知'), findsWidgets);
      expect(find.textContaining('人民广场'), findsOneWidget);
      expect(find.textContaining('批次 ·'), findsNothing);
      expect(find.text('查看完整原始快照'), findsNothing);
      _expectNoJson();
      await _close(tester);
    });
  }

  testWidgets(
    'unsupported batch stays diagnostic while valid trips remain usable',
    (tester) async {
      final repository = CardRepository(testDatabase());
      final id = await _save(repository, _snapshot(trips: [_transaction()]));
      await _save(repository, {'v': 99, 'future': 'kept verbatim'}, day: 21);
      await _open(tester, repository, id);
      expect(find.byType(TripEntryCard), findsOneWidget);
      expect(find.textContaining('部分历史记录无法完整显示'), findsOneWidget);
      expect(find.textContaining('unsupported'), findsNothing);
      expect(find.textContaining('future'), findsNothing);
      await tester.ensureVisible(find.text('批次诊断与原始快照'));
      await tester.tap(find.text('批次诊断与原始快照'));
      await tester.pumpAndSettle();
      expect(find.textContaining('unsupported'), findsOneWidget);
      await tester.tap(find.textContaining('unsupported'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看完整原始快照').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('kept verbatim'), findsOneWidget);
      await _close(tester);
    },
  );

  testWidgets('unknown legacy amounts remain readable on a phone width', (
    tester,
  ) async {
    final repository = CardRepository(testDatabase());
    final trip = _transaction()..remove('currency');
    final id = await _save(repository, {
      'v': 1,
      'trips': [trip],
    });
    await _open(tester, repository, id, size: const Size(390, 1100));
    expect(tester.takeException(), isNull);
    expect(find.text('-币种未知 4.50'), findsOneWidget);
    expect(find.text('余额 币种未知 12.34'), findsOneWidget);
    await _close(tester);
  });

  testWidgets(
    'live trip stream retains shared filtering and readable details',
    (tester) async {
      final app = AppDependencies(database: testDatabase());
      addTearDown(app.dispose);
      final stream = buildTripStream(
        trips: [
          for (final (sequence, station, mode) in [
            (1, '实时轨道站', '城市轨道交通'),
            (2, '实时公交站', '公共汽电车'),
          ])
            TransitTrip(
              time: DateTime(2026, 10, 20, 12),
              amountFen: 200,
              overdraftLimitFen: 0,
              isConsume: true,
              typeName: '消费',
              sequence: sequence,
              terminalId: '000000000001',
              stationLabel: station,
              appTypeName: mode,
            ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TripStreamView(
                stream: stream,
                app: app,
                isRemote: (_) => false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TripEntryCard), findsNWidgets(2));
      await _filter(tester, '公共汽电车');
      expect(find.byType(TripEntryCard), findsOneWidget);
      expect(find.textContaining('实时公交站'), findsOneWidget);
      await _filter(tester, '0x1E 过程');
      expect(find.byType(TripEntryCard), findsNothing);
      await _filter(tester, '全部来源');
      await tester.tap(find.byType(TripEntryCard));
      await tester.pumpAndSettle();
      expect(find.byType(TripDetailRow), findsWidgets);
      expect(find.text('交易序号'), findsOneWidget);
      _expectNoJson();
      await _close(tester);
    },
  );
}

Map<String, Object?> _transaction() => {
  'time': 1792454280000,
  'capturedTimes': {
    'time': {'civil': '2026-10-19T23:58:00', 'isUtc': false},
  },
  'amountFen': 450,
  'consume': true,
  'sequence': 42,
  'terminalId': '000000004200',
  'typeName': '消费',
  'rideStatusName': '出站',
  'stationLabel': '苏洋',
  'lineLabel': '2号线',
  'cityCode': '3910',
  'cityName': '福州市',
  'appTypeName': '城市轨道交通',
  'balanceAfterFen': 1234,
  'currency': 'HKD',
  'rawHex': '000042AB',
};

const _rail = {
  'status': 2,
  'entryTime': 1792450000000,
  'exitTime': 1792451000000,
  'entryStationId': '0001',
  'exitStationId': '0002',
  'entryStationName': '人民广场',
  'exitStationName': '世纪大道',
  'entryCityCode': '2000',
  'exitCityCode': '2000',
  'lineName': '2号线',
  'entryAmountFen': 0,
  'exitAmountFen': 300,
};
const _bus = {
  'status': 1,
  'entryTime': 1792440000000,
  'exitTime': 1792441000000,
  'entryCityCode': '3910',
  'exitCityCode': '3910',
  'entryLineCode': '0008',
  'exitLineCode': '0008',
  'entryStationCode': '01',
  'exitStationCode': '02',
  'amountFen': 200,
  'mileage': 5,
  'directionCode': 0,
};
const _process = {
  'time': 1792442000000,
  'typeCode': 3,
  'terminalId': '000000000009',
  'appTypeCode': 2,
  'lineStationCode': '00080001',
  'amountFen': 0,
  'balanceFen': 1000,
  'cityCode': '3910',
};

Map<String, Object?> _snapshot({
  List<Object?> trips = const [],
  List<Object?> rails = const [],
  List<Object?> buses = const [],
  List<Object?> cycle = const [],
  String currency = 'HKD',
  int digits = 2,
  String marker = 'first capture',
}) => {
  'v': 3,
  'parseVersion': 1,
  'cityCode': '2000',
  'context': {
    'systemId': 'TU',
    'applicationId': 'wallet-01',
    'currencyCode': currency,
    'minorUnitDigits': digits,
    'timeZoneOffsetMinutes': 480,
    'clockBasis': 'card-civil',
  },
  'trips': trips,
  'rails': rails,
  'buses': buses,
  'cycle': cycle,
  'rawEvidence': [],
  'recordProvenance': {},
  'captureMarker': marker,
};

Future<String> _save(
  CardRepository repository,
  Map<String, Object?> payload, {
  int day = 20,
}) async {
  await repository.saveIdentity(
    fingerprint: 'archive-trip-card-offline',
    identity: const CardArchiveIdentity(
      cardType: CardTypes.chinaTunion,
      officialName: '离线通勤卡',
    ),
    cardNumber: '00000042',
    balanceFen: 9000,
    currencyCode: 'CNY',
    sessionDataJson: jsonEncode(payload),
    readAt: DateTime.utc(2026, 10, day),
  );
  return (await repository.getAllCards()).single.id;
}

Future<void> _open(
  WidgetTester tester,
  CardRepository repository,
  String id, {
  Size size = const Size(800, 2000),
}) async {
  // Enough height to exercise all source cards without lazy-list ambiguity.
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: CardDetailPage(repository: repository, cardId: id),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _filter(WidgetTester tester, String label) async {
  final chip = find.widgetWithText(FilterChip, label);
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

void _expectNoJson() {
  expect(find.textContaining('"context"'), findsNothing);
  expect(find.textContaining('"record"'), findsNothing);
  expect(find.textContaining('"sources"'), findsNothing);
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}
