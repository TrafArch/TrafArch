import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_identity.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_types.dart';
import 'package:transit_card_analyzer/features/archive/presentation/card_detail_page.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';
import 'package:transit_card_analyzer/features/archive/domain/archive_context.dart';
import 'package:transit_card_analyzer/features/cards/cards_page.dart';
import 'package:transit_card_analyzer/features/trips/trip_cards_view.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';

import 'support/test_database.dart';

void main() {
  testWidgets('上海历史详情默认扣除8元，保存余额和交易金额保持原值', (tester) async {
    final repository = CardRepository(testDatabase());
    final id = await _save(repository);
    await _open(tester, repository, id);

    expect(find.text('¥ 95.00'), findsOneWidget);
    final trips = tester.widget<TripCardsView<ArchiveRecordKind>>(
      find.byType(TripCardsView<ArchiveRecordKind>),
    );
    final transaction = trips.entries.single;
    expect(transaction.info.fields, contains(('交易后余额', '¥ 112.00')));
    expect(transaction.info.amountText, '-¥ 3.00');
    expect(transaction.journeyEvent!.confirmedBalanceFen, 12000);

    final history = await ArchiveHistory(repository).load(id);
    expect(history.card!.balanceFen, 10300);
    expect(history.records.single.fields['balanceAfterFen'], 12000);
    expect(history.records.single.fields['amountFen'], 300);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('非上海卡历史默认保持原余额，上海受理城市不会触发扣减', (tester) async {
    final repository = CardRepository(testDatabase());
    final id = await _save(repository, shanghai: false);
    await _open(tester, repository, id);
    expect(find.text('¥ 103.00'), findsOneWidget);
    final trips = tester.widget<TripCardsView<ArchiveRecordKind>>(
      find.byType(TripCardsView<ArchiveRecordKind>),
    );
    expect(trips.entries.single.info.fields, contains(('交易后余额', '¥ 120.00')));
    expect(trips.entries.single.journeyEvent!.confirmedBalanceFen, 12000);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final system in ['city_union', 'shanghai_tunion']) {
    testWidgets('上海卡档案头部采用CU来源余额，不重复减8元（$system）', (tester) async {
      final app = AppDependencies(
        database: testDatabase(),
        bundle: MissingTestAssets(),
        settingsStore: MemorySettingsStore(),
        logger: AppLogger(store: MemoryLogStore()),
      );
      addTearDown(app.dispose);
      await app.settings.initialize();
      final id = await _save(
        app.cardRepository,
        contextSystem: system,
        contextAid: 'A00000000386980701',
        issuerCity: '2000',
        balanceFen: 8100,
        includeTransaction: false,
      );
      final original = (await app.cardRepository.getAllCards()).single;
      expect(original.cardType, CardTypes.shanghaiTransitUnion);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CardsPage(app: app)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('¥ 81.00'), findsOneWidget);
      expect(find.text('¥ 73.00'), findsNothing);
      await tester.tap(find.text('上海交通卡'));
      await tester.pumpAndSettle();
      for (final include in [false, true, false]) {
        await app.settings.setIncludeShanghaiOverdraft(include);
        await tester.pumpAndSettle();
        expect(find.text('¥ 81.00'), findsOneWidget);
        expect(find.text('¥ 73.00'), findsNothing);
      }
      final history = await ArchiveHistory(app.cardRepository).load(id);
      expect(history.card!.balanceFen, 8100);
      expect(history.card!.sessionDataJson, original.sessionDataJson);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('列表与已打开历史详情随开关立即刷新，反复切换不改存档', (tester) async {
    final app = AppDependencies(
      database: testDatabase(),
      bundle: MissingTestAssets(),
      settingsStore: MemorySettingsStore(),
      logger: AppLogger(store: MemoryLogStore()),
    );
    addTearDown(app.dispose);
    await app.settings.initialize();
    final id = await _save(app.cardRepository);
    final before =
        (await app.cardRepository.getAllCards()).single.sessionDataJson;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CardsPage(app: app)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('¥ 95.00'), findsOneWidget);

    await app.settings.setIncludeShanghaiOverdraft(true);
    await tester.pumpAndSettle();
    expect(find.text('¥ 103.00'), findsOneWidget);
    await tester.tap(find.text('上海交通卡'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CardDetailPage>(find.byType(CardDetailPage)).settings,
      same(app.settings),
    );
    expect(find.text('¥ 103.00'), findsOneWidget);

    for (final include in [false, true, false]) {
      await app.settings.setIncludeShanghaiOverdraft(include);
      await tester.pumpAndSettle();
      expect(find.text(include ? '¥ 103.00' : '¥ 95.00'), findsOneWidget);
      final trips = tester.widget<TripCardsView<ArchiveRecordKind>>(
        find.byType(TripCardsView<ArchiveRecordKind>),
      );
      expect(
        trips.entries.single.info.fields,
        contains(('交易后余额', include ? '¥ 120.00' : '¥ 112.00')),
      );
      expect(trips.entries.single.info.amountText, '-¥ 3.00');
      expect(trips.entries.single.journeyEvent!.confirmedBalanceFen, 12000);
    }
    final history = await ArchiveHistory(app.cardRepository).load(id);
    expect(history.card!.sessionDataJson, before);
    expect(history.card!.balanceFen, 10300);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('历史过程余额与1A进站余额扣8元，金额和原始证据不变', () {
    final process = _processRecord();
    final rail = ArchiveHistoryRecord(
      kind: ArchiveRecordKind.rail,
      fields: {
        'status': 1,
        'entryTime': DateTime.utc(2026, 10, 28, 10).millisecondsSinceEpoch,
        'entryCityCode': '1000',
        'entryBalanceFen': 650,
        'entryAmountFen': 0,
        'rawHex': '0123',
      },
      context: _shanghaiContext,
      cardCityCode: '2900',
      sources: const [],
    );
    final original = jsonEncode([process.fields, rail.fields]);
    ArchiveHistoryRecord? diagnostics;
    final projection = presentArchiveTrips(
      [process, rail],
      includeShanghaiOverdraft: false,
      onDiagnostics: (record) => diagnostics = record,
    );
    final processEntry = projection.entries
        .where((entry) => entry.source == ArchiveRecordKind.process)
        .single;
    expect(processEntry.info.fields, contains(('记录余额', '¥ -5.00')));
    expect(processEntry.info.amountText, '-¥ 2.00');
    final evidence = processEntry.journeyEvent!.processBalance!;
    expect(evidence.recordedFen, 300);
    expect(evidence.amountFen, 200);
    expect(evidence.balanceOffsetFen, -800);
    expect(evidence.format(300), '¥ -5.00');
    final railEntry = projection.entries
        .where((entry) => entry.source == ArchiveRecordKind.rail)
        .single;
    expect(railEntry.info.fields, contains(('进站时余额', '¥ -1.50')));
    expect(railEntry.info.fields, contains(('进入时金额', '¥ 0.00')));
    processEntry.onDiagnostics!();
    expect(diagnostics, same(process));
    expect(jsonEncode([process.fields, rail.fields]), original);

    // A standalone formatter call keeps its previous raw display contract.
    final unchanged = presentArchiveTrips([process], onDiagnostics: (_) {});
    expect(unchanged.entries.single.info.fields, contains(('记录余额', '¥ 3.00')));
  });

  test('历史调整保留CU原始余额并遵循币种精度，未知余额保持未知', () {
    for (final (system, city, currency, digits, expected) in [
      ('city_union', '2000', 'CNY', 2, '¥ 3.00'),
      ('city_union', '1000', 'CNY', 2, '¥ 3.00'),
      ('tunion', '2000', 'CNY', 2, '¥ 3.00'),
      ('shanghai_tunion', '2900', 'HKD', 2, 'HK\$ 3.00'),
      ('shanghai_tunion', '2900', 'CNY', 0, '¥ 300'),
    ]) {
      final record = _processRecord(
        system: system,
        city: city,
        currency: currency,
        digits: digits,
      );
      final result = presentArchiveTrips(
        [record],
        includeShanghaiOverdraft: false,
        onDiagnostics: (_) {},
      );
      expect(result.entries.single.info.fields, contains(('记录余额', expected)));
    }
    final unknown = ArchiveHistoryRecord(
      kind: ArchiveRecordKind.transaction,
      fields: {
        'time': 1793190000000,
        'sequence': 20,
        'consume': true,
        'amountFen': 200,
        'balanceAfterFen': null,
        'balanceAfterIsRecorded': false,
      },
      context: _shanghaiContext,
      cardCityCode: '2900',
      sources: const [ArchiveRecordSource('batch', 'trips[0]', 8, null)],
    );
    final result = presentArchiveTrips(
      [unknown],
      includeShanghaiOverdraft: false,
      onDiagnostics: (_) {},
    );
    expect(
      result.entries.single.info.fields.where(
        (field) => field.$1.contains('余额'),
      ),
      isEmpty,
    );
  });

  test('历史记录的CU来源优先于保存的上海TU卡型，余额和金额均保持原值', () {
    for (final system in ['city_union', 'shanghai_tunion']) {
      final record = _processRecord(
        system: system,
        city: '2000',
        applicationId: 'A00000000386980701',
      );
      final original = jsonEncode(record.fields);
      final result = presentArchiveTrips(
        [record],
        cardType: CardTypes.shanghaiTransitUnion,
        includeShanghaiOverdraft: false,
        onDiagnostics: (_) {},
      );
      final entry = result.entries.single;
      expect(entry.info.fields, contains(('记录余额', '¥ 3.00')));
      expect(entry.info.amountText, '-¥ 2.00');
      expect(entry.journeyEvent!.processBalance!.recordedFen, 300);
      expect(entry.journeyEvent!.processBalance!.balanceOffsetFen, 0);
      expect(jsonEncode(record.fields), original);
    }
  });
}

const _shanghaiContext = ArchiveContext(
  systemId: 'shanghai_tunion',
  applicationId: 'A000000632010105',
  currencyCode: 'CNY',
  minorUnitDigits: 2,
);

ArchiveHistoryRecord _processRecord({
  String system = 'shanghai_tunion',
  String city = '2900',
  String currency = 'CNY',
  int digits = 2,
  String applicationId = 'A000000632010105',
}) => ArchiveHistoryRecord(
  kind: ArchiveRecordKind.process,
  fields: {
    'time': 1793190000000,
    'typeCode': 4,
    'terminalId': '000000000001',
    'appTypeCode': 1,
    'lineStationCode': '00020002',
    'amountFen': 200,
    'balanceFen': 300,
    'cityCode': '1000',
    'rawHex': 'ABCD',
  },
  context: ArchiveContext(
    systemId: system,
    applicationId: applicationId,
    currencyCode: currency,
    minorUnitDigits: digits,
  ),
  cardCityCode: city,
  sources: const [
    ArchiveRecordSource('batch', 'cycle[0]', 8, {
      'record': {
        'sfi': 0x1E,
        'recordNumber': 1,
        'recordNumberIsReliable': true,
        'rawHex': 'ABCD',
      },
    }),
  ],
);

Future<String> _save(
  CardRepository repository, {
  bool shanghai = true,
  String? contextSystem,
  String contextAid = 'A000000632010105',
  String? issuerCity,
  int balanceFen = 10300,
  bool includeTransaction = true,
}) async {
  final parser = contextSystem ?? (shanghai ? 'shanghai_tunion' : 'tunion');
  final payload = {
    'v': 3,
    'parseVersion': 8,
    'cityCode': issuerCity ?? (shanghai ? '2900' : '1000'),
    'context': {
      'systemId': parser,
      'applicationId': contextAid,
      'currencyCode': 'CNY',
      'minorUnitDigits': 2,
      'observedFields': {'balanceFen': true},
    },
    'observations': {'balanceFen': balanceFen, 'currencyCode': 'CNY'},
    'trips': [
      if (includeTransaction)
        {
          'time': DateTime.utc(2026, 10, 28, 12).millisecondsSinceEpoch,
          'amountFen': 300,
          'overdraftFen': 0,
          'consume': true,
          'typeName': '复合消费',
          'composite': true,
          'sequence': 20,
          'terminalId': '000000000001',
          'cityCode': '2900',
          'cityName': '上海',
          'lineLabel': '2号线',
          'stationLabel': '人民广场',
          'appTypeName': '城市轨道交通',
          'balanceAfterFen': 12000,
          'balanceAfterIsRecorded': false,
          'rideStatusName': '出站',
        },
    ],
    'rails': [],
    'buses': [],
    'cycle': [],
    'rawEvidence': [],
    'recordProvenance': {},
  };
  await repository.saveIdentity(
    fingerprint: 'shanghai-display-$shanghai',
    identity: CardArchiveIdentity(
      cardType: shanghai
          ? CardTypes.shanghaiTransitUnion
          : CardTypes.chinaTunion,
      officialName: shanghai ? '上海交通卡' : '其他交通卡',
    ),
    cardNumber: '3104770012345678',
    balanceFen: balanceFen,
    currencyCode: 'CNY',
    sessionDataJson: jsonEncode(payload),
    readAt: DateTime.utc(2026, 10, 28, 13),
  );
  return (await repository.getAllCards()).single.id;
}

Future<void> _open(
  WidgetTester tester,
  CardRepository repository,
  String id,
) async {
  await tester.binding.setSurfaceSize(const Size(800, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: CardDetailPage(repository: repository, cardId: id),
    ),
  );
  await tester.pumpAndSettle();
}
