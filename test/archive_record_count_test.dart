import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_record_count.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_records_json.dart';
import 'package:transit_card_analyzer/features/archive/application/cu_archive_projection.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_document.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_identity.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/presentation/shanghai_archive_mirrored_records.dart';
import 'package:transit_card_analyzer/features/cards/cards_page.dart';
import 'package:transit_card_analyzer/features/archive/presentation/card_detail_page.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/reference_match.dart';
import 'package:transit_card_analyzer/features/transit_analysis/cu_transaction_analysis.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_models.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_file_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_trip_matcher.dart';

import 'support/test_database.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  for (final unreadable in [
    '{"v":99}',
    '{broken',
    '{"v":2,"trips":[{"amountFen":100}],"rails":[],"buses":[],"cycle":[]}',
  ]) {
    test(
      'unreadable retained batch does not present a partial count: $unreadable',
      () {
        final history = _history(
          _card(count: 10),
          batches: [
            _batch('good', CardSessionSnapshot(trips: [_trip(1)]).encode()),
            _batch('bad', unreadable),
          ],
        );
        final count = ArchiveRecordCount.fromHistory(history);
        expect(count.savedRecordCount, isNull);
        expect(count.isUnavailable, isTrue);
        expect(count.listText, '记录数待核实');
      },
    );
  }

  test('unreadable CU entry does not present a partial count', () {
    final projection = captureCuProjection([_cu()]);
    (projection['transactions'] as List).add({'record': {}});
    final history = _history(
      _card(
        snapshot: CardSessionSnapshot(extensions: {'cuProjection': projection})
            .encode(),
      ),
    );
    expect(projectCuArchive(history).issues, isNotEmpty);
    final count = ArchiveRecordCount.fromHistory(history);
    expect(count.savedRecordCount, isNull);
    expect(count.listText, '记录数待核实');
  });

  test(
    'saved count includes independent process rows beyond the ten-entry file',
    () {
      final snapshot = CardSessionSnapshot(
        trips: [for (var i = 1; i <= 10; i++) _trip(i)],
        processTrips: [for (var i = 11; i <= 30; i++) _process(i)],
      ).encode();
      final history = _history(_card(count: 10, snapshot: snapshot));
      final count = ArchiveRecordCount.fromHistory(history);
      expect(count.savedRecordCount, 30);
      expect(count.latestTransactionCount, 10);
      expect(count.label, '已保存记录');
      expect(count.valueText, '30条');
      expect(count.listText, '已保存 30 条');
      expect(history.card!.transactionCount, 10);
    },
  );

  test('overlapping and repeated batches count each complete record once', () {
    final first = CardSessionSnapshot(
      trips: [for (var i = 1; i <= 10; i++) _trip(i)],
    ).encode();
    final later = CardSessionSnapshot(
      trips: [for (var i = 6; i <= 15; i++) _trip(i)],
    ).encode();
    final count = ArchiveRecordCount.fromHistory(
      _history(
        _card(count: 10, snapshot: later),
        batches: [
          _batch('one', first),
          _batch('two', later),
          _batch('replay', first),
        ],
      ),
    );
    expect(count.savedRecordCount, 15);
  });

  test(
    'a process already saved as a transaction annotation is counted once',
    () {
      final linked = _process(1);
      final snapshot = CardSessionSnapshot(
        trips: [_trip(1, processKey: cycleDisplayKey(linked))],
        processTrips: [linked, _process(2)],
      ).encode();
      final count = ArchiveRecordCount.fromHistory(
        _history(_card(count: 1, snapshot: snapshot)),
      );
      expect(count.savedRecordCount, 2);
    },
  );

  test('CU repeat reads deduplicate slots while independent SFIs count', () {
    String payload(List<CuTransactionView> views) => CardSessionSnapshot(
      extensions: {'cuProjection': captureCuProjection(views)},
    ).encode();
    final first = payload([_cu(recordNumber: 1), _cu(sfi: 0x1A)]);
    final later = payload([_cu(recordNumber: 5)]);
    final count = ArchiveRecordCount.fromHistory(
      _history(
        _card(snapshot: later),
        batches: [_batch('one', first), _batch('two', later)],
      ),
    );
    expect(count.savedRecordCount, 2);
  });

  test('replaying a field import preserves genuine repeated rows without inflation', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = CardRepository(db);
    final document = CardArchiveDocument(
      card: _card(),
      batches: [],
      fieldObservationTimes: {},
      importedRecords: [
        {'station_code': '0001', 'amount': '-1.00'},
        {'station_code': '0001', 'amount': '-1.00'},
      ],
    );
    await repository.importDocuments([document]);
    await repository.importDocuments([document]);
    final count = ArchiveRecordCount.fromHistory(
      await ArchiveHistory(repository).load('card'),
    );
    expect(count.savedRecordCount, 2);
  });

  test(
    'displaced scalar summaries contribute their retained records',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repository = CardRepository(db);
      for (final sequence in [1, 2]) {
        await repository.importDocuments([
          CardArchiveDocument(
            card: _card(
              snapshot: CardSessionSnapshot(trips: [_trip(sequence)]).encode(),
              at: sequence * 100,
            ),
            batches: [],
            fieldObservationTimes: {},
          ),
        ]);
      }
      final history = await ArchiveHistory(repository).load('card');
      expect(
        history.batches.any((batch) => batch.origin == 'imported_summary'),
        isTrue,
      );
      expect(ArchiveRecordCount.fromHistory(history).savedRecordCount, 2);
    },
  );

  test('a legacy numeric summary is labelled as the latest read rather than history', () {
    final count = ArchiveRecordCount.fromHistory(_history(_card(count: 10)));
    expect(count.savedRecordCount, isNull);
    expect(count.latestTransactionCount, 10);
    expect(count.label, '最近读取交易');
    expect(count.valueText, '10条');
    expect(count.listText, '最近读取 10 条');
  });

  test(
    'observation-only snapshots do not turn a known latest count into zero',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repository = CardRepository(db);
      await repository.saveIdentity(
        fingerprint: 'summary-only',
        identity: const CardArchiveIdentity(cardType: 'china_tunion'),
        transactionCount: 10,
      );
      final history = (await ArchiveHistory(repository).loadAll()).single;
      final count = ArchiveRecordCount.fromHistory(history);
      expect(count.savedRecordCount, isNull);
      expect(count.listText, '最近读取 10 条');
    },
  );

  test('explicitly empty history differs from an absent unknown summary', () {
    final empty = ArchiveRecordCount.fromHistory(
      _history(_card(count: 0, snapshot: const CardSessionSnapshot().encode())),
    );
    expect(empty.savedRecordCount, 0);
    expect(empty.listText, '已保存 0 条');
    final unknown = ArchiveRecordCount.fromHistory(_history(_card()));
    expect(unknown.savedRecordCount, isNull);
    expect(unknown.valueText, '—');
  });

  test(
    'summary stream follows batch-only additions, removal and card deletion',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repository = CardRepository(db);
      final iterator = StreamIterator(watchArchiveCardSummaries(repository));
      addTearDown(iterator.cancel);
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current, isEmpty);

      final original = CardArchiveDocument(
        card: _card(count: 10),
        batches: [
          _batch('one', CardSessionSnapshot(trips: [_trip(1)]).encode()),
        ],
        fieldObservationTimes: {},
      );
      await repository.importDocuments([original]);
      expect(
        await iterator.moveNext().timeout(const Duration(seconds: 3)),
        isTrue,
      );
      expect(iterator.current.single.recordCount.savedRecordCount, 1);

      await db
          .into(db.cardReadBatches)
          .insert(
            _batch('two', CardSessionSnapshot(trips: [_trip(2)]).encode()),
          );
      expect(
        await iterator.moveNext().timeout(const Duration(seconds: 3)),
        isTrue,
      );
      expect(iterator.current.single.recordCount.savedRecordCount, 2);
      expect(iterator.current.single.card.transactionCount, 10);

      await (db.delete(
        db.cardReadBatches,
      )..where((table) => table.id.equals('two'))).go();
      expect(
        await iterator.moveNext().timeout(const Duration(seconds: 3)),
        isTrue,
      );
      expect(iterator.current.single.recordCount.savedRecordCount, 1);

      await repository.deleteCard('card');
      expect(
        await iterator.moveNext().timeout(const Duration(seconds: 3)),
        isTrue,
      );
      expect(iterator.current, isEmpty);
    },
  );

  test(
    'field-only imports refresh a summary stream without duplicate emissions',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repository = CardRepository(db);
      final iterator = StreamIterator(watchArchiveCardSummaries(repository));
      addTearDown(iterator.cancel);
      await iterator.moveNext();
      final original = CardArchiveDocument(
        card: _card(),
        batches: [],
        fieldObservationTimes: {},
        importedRecords: [
          {'amount': '-1.00'},
        ],
      );
      await repository.importDocuments([original]);
      await iterator.moveNext().timeout(const Duration(seconds: 3));
      expect(iterator.current.single.recordCount.savedRecordCount, 1);
      await repository.importDocuments([
        original.copyWith(
          importedRecords: [
            {'amount': '-1.00'},
            {'amount': '-2.00'},
          ],
        ),
      ]);
      await iterator.moveNext().timeout(const Duration(seconds: 3));
      expect(iterator.current.single.recordCount.savedRecordCount, 2);

      await repository.importDocuments([original]);
      await repository.renameCard('card', '已改名');
      await iterator.moveNext().timeout(const Duration(seconds: 3));
      expect(iterator.current.single.card.customName, '已改名');
      expect(iterator.current.single.recordCount.savedRecordCount, 2);
    },
  );

  for (final malformed in [true, false]) {
    test(
      '${malformed ? 'malformed' : 'unsupported'} canonical documents keep other card summaries available',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final repository = CardRepository(db);
        final damaged = CardArchiveDocument(
          card: _card(count: 10).copyWith(
            id: 'damaged',
            cardFingerprint: 'fingerprint-damaged',
            officialName: const Value('损坏档案卡'),
          ),
          batches: [],
          fieldObservationTimes: {},
          importedRecords: [
            {'amount': '-2.00'},
          ],
        );
        await repository.importDocuments([
          CardArchiveDocument(
            card: _card(),
            batches: [],
            fieldObservationTimes: {},
            importedRecords: [
              {'amount': '-1.00'},
            ],
          ),
          damaged,
        ]);
        await db.customStatement(
          'UPDATE archive_documents SET payload_json=? WHERE card_id=?',
          [
            malformed ? '{broken' : '{"format":"trafarch.card","version":99}',
            'damaged',
          ],
        );

        final summaries = await watchArchiveCardSummaries(repository).first
            .timeout(const Duration(seconds: 3));
        expect(summaries, hasLength(2));
        expect(
          summaries
              .singleWhere((summary) => summary.card.id == 'card')
              .recordCount
              .savedRecordCount,
          1,
        );
        final damagedSummary = summaries.singleWhere(
          (summary) => summary.card.id == 'damaged',
        );
        expect(damagedSummary.card.officialName, '损坏档案卡');
        expect(damagedSummary.recordCount.savedRecordCount, isNull);
        expect(damagedSummary.recordCount.latestTransactionCount, 10);
        expect(damagedSummary.recordCount.listText, '记录数待核实');
      },
    );
  }

  test(
    'clean canonical rows agree with detail and export even with stale indexes',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repository = CardRepository(db);
      final original = CardArchiveDocument(
        card: _card(),
        batches: [
          _batch('one', CardSessionSnapshot(trips: [_trip(1)]).encode()),
        ],
        fieldObservationTimes: {},
      );
      await repository.importDocuments([original]);
      final complete = original.copyWith(
        batches: [
          ...original.batches,
          _batch(
            'canonical-only',
            CardSessionSnapshot(trips: [_trip(2)]).encode(),
          ),
        ],
        importedRecords: [
          {'amount': '-1.00'},
          {'amount': '-1.00'},
        ],
      );
      await db.customStatement(
        'UPDATE archive_documents SET payload_json=?,dirty=0 WHERE card_id=?',
        [complete.encode(), 'card'],
      );
      final detail = ArchiveRecordCount.fromHistory(
        await ArchiveHistory(repository).load('card'),
      );
      final summary = (await watchArchiveCardSummaries(
        repository,
      ).first).single;
      expect(detail.savedRecordCount, 4);
      expect(summary.recordCount.savedRecordCount, detail.savedRecordCount);
    },
  );

  test(
    'one out-of-range CU display time keeps other card summaries available',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repository = CardRepository(db);
      final projection = captureCuProjection([_cu()]);
      ((projection['transactions'] as List).single as Map)['timeUtcMillis'] =
          8640000000000000;
      await repository.importDocuments([
        CardArchiveDocument(
          card: _card(),
          batches: [],
          fieldObservationTimes: {},
          importedRecords: [
            {'amount': '-1.00'},
          ],
        ),
        CardArchiveDocument(
          card: _card(
            snapshot: CardSessionSnapshot(
              extensions: {'cuProjection': projection},
            ).encode(),
          ).copyWith(id: 'damaged', cardFingerprint: 'fingerprint-damaged'),
          batches: [],
          fieldObservationTimes: {},
        ),
      ]);
      final summaries = await watchArchiveCardSummaries(repository).first;
      expect(summaries, hasLength(2));
      expect(
        summaries
            .singleWhere((summary) => summary.card.id == 'card')
            .recordCount
            .savedRecordCount,
        1,
      );
      final damaged = summaries.singleWhere(
        (summary) => summary.card.id == 'damaged',
      );
      expect(damaged.recordCount.savedRecordCount, isNull);
      expect(damaged.recordCount.listText, '记录数待核实');
    },
  );

  test('Shanghai display mirrors remain two saved source rows matching JSON export', () {
    final view = CuTransactionView(
      record: CityUnionFileParser.parseWalletRecord(
        0x18,
        const [
          0,
          14,
          0,
          0,
          0,
          0,
          0,
          1,
          0x90,
          9,
          0x20,
          0,
          0x11,
          1,
          0x26,
          0x18,
          0x20,
          0x26,
          0x10,
          0x24,
          0x23,
          4,
          4,
        ],
        kind: CityUnionTransactionKind.consumption,
        recordNumber: 1,
      ),
      transactionTime: DateTime.utc(2026, 10, 24, 15, 4, 4),
      location: ReferenceMatch(ReferenceMatchStatus.unknown, const []),
    );
    final captured = jsonDecode(
      CardSessionSnapshot(
        context: const ArchiveContext(systemId: CardParserIds.shanghaiTunion),
        extensions: {
          'cuProjection': captureCuProjection([view]),
        },
        trips: [
          TransitTrip(
            time: DateTime.utc(2026, 10, 24, 15, 4, 4),
            amountFen: 400,
            overdraftLimitFen: 0,
            isConsume: true,
            isCompositeConsume: true,
            typeName: '复合消费',
            sequence: 14,
            terminalId: '200011012618',
            rawHex: view.record.rawHex,
          ),
        ],
      ).encode(),
    ) as Map<String, dynamic>;
    ((captured['trips'] as List).single as Map)['capturedTimes'] = {
      'time': {
        'civil': '2026-10-24T23:04:04.000',
        'conversionOffsetMinutes': 480,
        'basis': 'parser-local-unverified',
      },
    };
    final history = _history(_card(snapshot: jsonEncode(captured)));
    final cu = projectCuArchive(history);
    expect(
      partitionShanghaiArchiveMirroredRecords(
        history: history,
        cityUnion: cu,
      ).mirroredCount,
      1,
    );
    expect(ArchiveRecordCount.fromHistory(history).savedRecordCount, 2);
    expect(projectArchiveRecords([history]), hasLength(2));
  });

  testWidgets('one damaged archive keeps names and healthy cards in the list', (
    tester,
  ) async {
    final db = testDatabase();
    final app = AppDependencies(
      database: db,
      settingsStore: MemorySettingsStore(),
      logger: AppLogger(store: MemoryLogStore()),
    );
    addTearDown(app.dispose);
    await app.cardRepository.importDocuments([
      CardArchiveDocument(
        card: _card(),
        batches: [],
        fieldObservationTimes: {},
        importedRecords: [
          {'amount': '-1.00'},
        ],
      ),
      CardArchiveDocument(
        card: _card(count: 10).copyWith(
          id: 'damaged',
          cardFingerprint: 'fingerprint-damaged',
          officialName: const Value('损坏档案卡'),
        ),
        batches: [],
        fieldObservationTimes: {},
      ),
    ]);
    await db.customStatement(
      'UPDATE archive_documents SET payload_json=? WHERE card_id=?',
      ['{broken', 'damaged'],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CardsPage(app: app)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('累计记录测试卡'), findsOneWidget);
    expect(find.text('损坏档案卡'), findsOneWidget);
    expect(find.text('已保存 1 条'), findsOneWidget);
    expect(find.text('记录数待核实'), findsOneWidget);
    expect(find.byTooltip('卡片操作'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
    'card list displays cumulative saved records and refreshes batch-only changes',
    (tester) async {
      final db = testDatabase();
      final app = AppDependencies(
        database: db,
        settingsStore: MemorySettingsStore(),
        logger: AppLogger(store: MemoryLogStore()),
      );
      addTearDown(app.dispose);
      await app.cardRepository.importDocuments([
        CardArchiveDocument(
          card: _card(count: 10),
          batches: [
            _batch(
              'one',
              CardSessionSnapshot(
                trips: [for (var i = 1; i <= 15; i++) _trip(i)],
              ).encode(),
            ),
          ],
          fieldObservationTimes: {},
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CardsPage(app: app)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('已保存 15 条'), findsOneWidget);
      expect(find.text('10条'), findsNothing);

      await db
          .into(db.cardReadBatches)
          .insert(
            _batch('two', CardSessionSnapshot(trips: [_trip(16)]).encode()),
          );
      await tester.pumpAndSettle();
      expect(find.text('已保存 16 条'), findsOneWidget);
      expect(
        (await app.cardRepository.getAllCards()).single.transactionCount,
        10,
      );
      await tester.tap(find.text('累计记录测试卡'));
      await tester.pumpAndSettle();
      expect(find.byType(CardDetailPage), findsOneWidget);
      expect(find.text('已保存记录'), findsOneWidget);
      expect(find.text('16条'), findsOneWidget);
      expect(find.text('10条'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}

SavedCard _card({int? count, String? snapshot, int at = 100}) => SavedCard(
  id: 'card',
  cardFingerprint: 'fingerprint-card',
  cardType: 'china_tunion',
  officialName: '累计记录测试卡',
  identificationSource: 'unknown',
  transactionCount: count,
  sessionDataJson: snapshot,
  createdAt: 100,
  updatedAt: at,
  lastReadAt: at,
);

CardReadBatch _batch(String id, String payload) => CardReadBatch(
  id: id,
  cardId: 'card',
  cardFingerprint: 'fingerprint-card',
  readAt: 100,
  parseVersion: 1,
  payloadJson: payload,
);

ArchiveHistoryResult _history(
  SavedCard card, {
  List<CardReadBatch> batches = const [],
}) => ArchiveHistory.project(ArchiveRows(card: card, batches: batches));

TransitTrip _trip(int sequence, {String? processKey}) => TransitTrip(
  time: DateTime.utc(2026, 10, 27, 8, sequence),
  amountFen: 100,
  overdraftLimitFen: 0,
  isConsume: true,
  typeName: '消费',
  sequence: sequence,
  terminalId: sequence.toString().padLeft(6, '0'),
  displayProcessKey: processKey,
);

TUnionTripRecord _process(int sequence) => TUnionTripRecord(
  typeCode: 6,
  terminalId: sequence.toString().padLeft(16, '0'),
  appTypeCode: 0,
  lineStationCode: '00000000000000',
  amountFen: 100,
  balanceFen: 1000,
  time: DateTime.utc(2026, 10, 27, 8, sequence),
  cityCode: '1000',
);

CuTransactionView _cu({int recordNumber = 1, int sfi = 0x06}) =>
    CuTransactionView(
      record: CityUnionFileParser.parseWalletRecord(
        sfi,
        [
          0,
          1,
          0,
          0,
          0,
          0,
          0,
          0,
          1,
          6,
          0x20,
          0,
          0x11,
          0x0A,
          1,
          0,
          0x20,
          0x24,
          9,
          0x20,
          0x12,
          0,
          0,
        ],
        kind: CityUnionTransactionKind.foreignConsumption,
        recordNumber: recordNumber,
      ),
      transactionTime: DateTime.utc(2024, 9, 20, 4),
      regionCode: '2000',
      carrier: 2,
      location: ReferenceMatch(ReferenceMatchStatus.unknown, []),
    );
