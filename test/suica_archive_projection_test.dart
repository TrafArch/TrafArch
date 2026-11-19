import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_record_count.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_records_json.dart';
import 'package:transit_card_analyzer/features/archive/application/card_records_export.dart';
import 'package:transit_card_analyzer/features/archive/application/suica_archive_projection.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_identity.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/presentation/card_detail_page.dart';
import 'package:transit_card_analyzer/features/trips/suica_trip_list.dart';

import 'support/test_database.dart';

void main() {
  test('new corrected station capture wins without rewriting old evidence', () {
    final old = _record();
    final corrected = _record();
    final oldPresentation = old['presentation'] as Map;
    final correctedPresentation = corrected['presentation'] as Map;
    (oldPresentation['start'] as Map)['station'] = '旧站名';
    (correctedPresentation['start'] as Map)['station'] = '修正后站名';
    final history = _history([
      [corrected],
      [old],
    ]);
    final projection = projectSuicaArchive(history);
    expect(projection.records, hasLength(1));
    expect(projection.records.single.sources, hasLength(2));
    expect(projection.trips.single.journey.start?.station, '修正后站名');
    expect(projection.trips.single.journey.cityLabel, '日本');
    final retained =
        history.batches.last.decoded.snapshot!.extensions['suica'] as Map;
    final row = (retained['records'] as List).single as Map;
    expect(((row['presentation'] as Map)['start'] as Map)['station'], '旧站名');
    expect(row['rawHex'], old['rawHex']);
    // A capture without a newer reread still keeps its frozen station words.
    expect(
      projectSuicaArchive(
        _history([
          [old],
        ]),
      ).trips.single.journey.start?.station,
      '旧站名',
    );
  });

  test(
    'legacy initialized slots are hidden from Suica history counts and exports',
    () {
      final history = _history([
        [
          _record(),
          for (var block = 1; block < 20; block += 2)
            _unknownRecord(block: block),
        ],
        [
          _record(block: 1),
          for (var block = 0; block < 20; block += 2)
            _unknownRecord(block: block),
        ],
      ]);

      final projection = projectSuicaArchive(history);
      expect(projection.records, hasLength(1));
      expect(projection.records.single.sources, hasLength(2));
      expect(projection.issues, isEmpty);
      expect(projection.hasHistoryObservation, isTrue);
      expect(projectArchiveRecords([history]), hasLength(1));
      expect(ArchiveRecordCount.fromHistory(history).savedRecordCount, 1);
      final text = buildArchiveHistoryExport([history]);
      expect(text, contains('Suica 历史记录（1 条）'));
      expect(text, isNot(contains('  · 未知记录 · 未知处理')));
      for (final batch in history.batches) {
        final saved = batch.decoded.snapshot!.extensions['suica'] as Map;
        final rows = saved['records'] as List;
        expect(rows, hasLength(11));
        expect(
          rows.where(
            (row) => row['rawHex'] == '00000080000000000000000000000000',
          ),
          hasLength(10),
        );
      }
    },
  );

  test('legacy unknown records with other evidence remain visible', () {
    final history = _history([
      [
        _unknownRecord(rawHex: '00000080000000000000000000000100'),
        _unknownRecord(rawHex: '00000081000000000000000000000000', block: 2),
        _unknownRecord(rawHex: '000000800000000000000000000000', block: 3),
      ],
    ]);
    final projection = projectSuicaArchive(history);
    expect(projection.records, hasLength(3));
    expect(projection.issues, isEmpty);
    expect(ArchiveRecordCount.fromHistory(history).savedRecordCount, 3);
    expect(projectArchiveRecords([history]), hasLength(3));
  });

  test(
    'legacy blank-only Suica history cannot revive a stale positive count',
    () {
      final history = _historyPayloads([
        _payload([
          for (var block = 0; block < 10; block++) _unknownRecord(block: block),
          _unknownRecord(rawHex: '00000000000000000000000000000000', block: 10),
        ]),
      ], transactionCount: 10);

      final projection = projectSuicaArchive(history);
      expect(projection.records, isEmpty);
      expect(projection.issues, isEmpty);
      expect(projection.hasHistoryObservation, isTrue);
      final count = ArchiveRecordCount.fromHistory(history);
      expect(count.savedRecordCount, 0);
      expect(count.listText, '已保存 0 条');
      expect(count.latestTransactionCount, 10);
      expect(projectArchiveRecords([history]), isEmpty);
      expect(
        buildArchiveHistoryExport([history]),
        isNot(contains('  · 未知记录 · 未知处理')),
      );
      expect(history.card!.transactionCount, 10);
      final saved =
          history.batches.single.decoded.snapshot!.extensions['suica'] as Map;
      expect(saved['records'], hasLength(11));
    },
  );

  test(
    'unobserved Suica history still retains a positive summary as unverified',
    () {
      final payload = CardSessionSnapshot(
        context: _context,
        extensions: const {
          'suica': {'version': 1, 'historyObserved': false, 'records': []},
        },
      ).encode();
      final count = ArchiveRecordCount.fromHistory(
        _historyPayloads([payload], transactionCount: 10),
      );
      expect(count.savedRecordCount, isNull);
      expect(count.latestTransactionCount, 10);
      expect(count.listText, '最近读取 10 条');
    },
  );

  test('same-day Suica history keeps captured order when only shopping has a clock time', () {
    final rail = _record(sequence: 3);
    final shopping = _record(sequence: 2, block: 1)
      ..['timestamp'] = DateTime(2025, 10, 20, 12).millisecondsSinceEpoch;
    (shopping['details'] as Map)['hasTime'] = true;
    (shopping['details'] as Map)['kind'] = 'shopping';
    final display = shopping['presentation'] as Map;
    (display['info'] as Map)['title'] = '购物 / 电子货币';
    (display['info'] as Map)['timeText'] = '2025-10-20 12:00';
    final rows = projectArchiveRecords([
      _history([
        [rail, shopping],
      ]),
    ]);
    expect(rows.map((row) => row['record_type']), ['铁路 · 乘车扣款', '购物 / 电子货币']);
  });

  test('Suica saved rows retain frozen endpoints and JPY balances without inventing a fare', () {
    final history = _history([
      [_record()],
    ]);
    final rows = projectArchiveRecords([history]);
    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row['card_number'], isNull);
    expect(row['entry_station'], '捕获时起点');
    expect(row['exit_station'], '捕获时终点');
    expect(row['entry_line'], '捕获时线路');
    expect(row['entry_station_code'], '00/01/01');
    expect(row['exit_station_code'], '00/01/03');
    expect(row['time'], '2025-10-20');
    expect(row['entry_time'], isNull);
    expect(row['exit_time'], isNull);
    expect(row['time_basis'], contains('日期'));
    expect(row['amount'], isNull);
    expect(row['amount_raw'], '900');
    expect(row['amount_unit'], contains('交易后余额'));
    expect(row['currency'], 'JPY');
    expect(row['balance'], '900');
    expect(ArchiveRecordCount.fromHistory(history).savedRecordCount, 1);
    final text = buildArchiveHistoryExport([history]);
    expect(text, contains('Suica 历史记录（1 条）'));
    expect(text, contains('捕获时起点 → 捕获时终点'));
    expect(text, contains('JP￥900'));
    expect(text, isNot(contains('行程记录：（无）')));
  });

  test('history rotation deduplicates a transaction across block numbers and keeps distinct counters', () {
    final history = _history([
      [_record(block: 1), _record(sequence: 3, block: 0)],
      [_record(block: 0)],
    ]);
    expect(projectArchiveRecords([history]), hasLength(2));
    expect(ArchiveRecordCount.fromHistory(history).savedRecordCount, 2);
  });

  test(
    'two identical occurrences within a read are not silently collapsed',
    () {
      final history = _history([
        [_record(block: 0), _record(block: 1)],
        [_record(block: 2)],
      ]);
      expect(projectArchiveRecords([history]), hasLength(2));
    },
  );

  test('malformed frozen presentation keeps other rows and makes total count unknown', () {
    final broken = _record(sequence: 3)..['presentation'] = {'version': 99};
    final history = _history([
      [_record(), broken],
    ]);
    expect(projectArchiveRecords([history]), hasLength(1));
    expect(ArchiveRecordCount.fromHistory(history).isUnavailable, isTrue);
    final text = buildArchiveHistoryExport([history]);
    expect(text, contains('Suica 诊断'));
    expect(text, contains('"version":99'));
  });

  test(
    'a failed Suica history read without earlier observations stays unknown',
    () {
      final payload = CardSessionSnapshot(
        context: const ArchiveContext(
          systemId: 'felica_suica',
          applicationId: 'felica-service:090F',
          currencyCode: 'JPY',
          minorUnitDigits: 0,
          observedFields: {'balanceFen': false, 'transactionCount': false},
        ),
        extensions: const {
          'suica': {'version': 1, 'historyObserved': false, 'records': []},
        },
      ).encode();
      final history = _historyPayloads([payload]);
      final count = ArchiveRecordCount.fromHistory(history);
      expect(count.savedRecordCount, isNull);
      expect(count.latestTransactionCount, isNull);
      expect(count.listText, '已保存记录 —');
      expect(history.balanceText, isNull);
    },
  );

  test('captured device timezone changes do not duplicate the same raw Suica transaction', () {
    final inAnotherZone = _record(block: 1)
      ..['timestamp'] =
          DateTime(2025, 10, 20).millisecondsSinceEpoch +
          const Duration(hours: 8).inMilliseconds;
    final history = _history([
      [inAnotherZone],
      [_record()],
    ]);
    expect(projectArchiveRecords([history]), hasLength(1));
    expect(ArchiveRecordCount.fromHistory(history).savedRecordCount, 1);
  });

  testWidgets(
    'unobserved Suica history stays unknown in detail and text export',
    (tester) async {
      final payload = CardSessionSnapshot(
        context: _context,
        extensions: const {
          'suica': {'version': 1, 'historyObserved': false, 'records': []},
        },
      ).encode();
      final text = buildArchiveHistoryExport([
        _historyPayloads([payload]),
      ]);
      expect(text, contains('尚未读取到 Suica 历史记录'));
      expect(text, isNot(contains('行程记录：（无）')));
      final repository = CardRepository(testDatabase());
      await repository.saveIdentity(
        fingerprint: 'felica:suica:idm:0102030405060708',
        identity: const CardArchiveIdentity(cardType: 'suica'),
        sessionDataJson: payload,
      );
      final card = (await repository.getAllCards()).single;
      await tester.pumpWidget(
        MaterialApp(
          home: CardDetailPage(repository: repository, cardId: card.id),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('尚未读取到 Suica 历史记录'), findsOneWidget);
      expect(find.text('暂无行程数据'), findsNothing);
    },
  );

  test(
    'future Suica section is not reported as a successful empty history',
    () {
      final payload = CardSessionSnapshot(
        context: _context,
        extensions: const {
          'suica': {'version': 9, 'records': []},
        },
      ).encode();
      final history = _historyPayloads([payload]);
      expect(ArchiveRecordCount.fromHistory(history).isUnavailable, isTrue);
      expect(buildArchiveHistoryExport([history]), contains('Suica 诊断'));
    },
  );

  test('archive JPY uses integer yen and does not reuse the CNY symbol', () {
    expect(_context.formatAmount(900), 'JP￥900');
    expect(_context.formatAmount(-900), '-JP￥900');
    expect(_context.formatAmount(0), 'JP￥0');
    expect(
      const ArchiveContext(
        currencyCode: 'CNY',
        minorUnitDigits: 2,
      ).formatAmount(900),
      '¥ 9.00',
    );
  });

  testWidgets(
    'saved Suica detail uses the frozen trip list without an empty TU placeholder',
    (tester) async {
      final repository = CardRepository(testDatabase());
      await repository.saveIdentity(
        fingerprint: 'felica:suica:idm:0102030405060708',
        identity: const CardArchiveIdentity(cardType: 'suica'),
        balanceFen: 900,
        currencyCode: 'JPY',
        transactionCount: 1,
        sessionDataJson: _payload([_record()]),
      );
      final card = (await repository.getAllCards()).single;
      await tester.pumpWidget(
        MaterialApp(
          home: CardDetailPage(repository: repository, cardId: card.id),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SuicaTripList), findsOneWidget);
      expect(find.text('暂无行程数据'), findsNothing);
      expect(find.textContaining('捕获时起点'), findsWidgets);
      expect(find.textContaining('JP￥900'), findsWidgets);
    },
  );
}

const _context = ArchiveContext(
  systemId: 'felica_suica',
  applicationId: 'felica-service:090F',
  currencyCode: 'JPY',
  minorUnitDigits: 0,
);

Map<String, dynamic> _unknownRecord({
  String rawHex = '00000080000000000000000000000000',
  int block = 1,
}) => {
  'rawHex': rawHex,
  'blockNumber': block,
  'timestamp': null,
  'balanceYen': 0,
  'currencyCode': 'JPY',
  'amountIsBalance': true,
  'decoded': false,
  'details': {
    'recordSequence': 0,
    'regionCode': 0,
    'hasTime': false,
    'kind': 'unknown',
    'terminalCode': 0,
    'processCode': 0,
    'balanceChangeYen': null,
    'entryStation': null,
    'exitStation': null,
    'busOperatorCode': null,
  },
  'presentation': {
    'version': 1,
    'mode': 'other',
    'dateText': '日期未知',
    'state': 'single',
    'info': {
      'sourceLabel': 'Suica 090F 历史',
      'title': '未知记录 · 未知处理（0x00）',
      'timeText': '时间未解析',
      'amountText': null,
      'isConsume': false,
      'subText': '交易后余额 JP￥0',
      'category': '未知记录',
      'badges': <String>[],
      'rawHex': rawHex,
      'fields': <List<String>>[],
    },
    'point': {'timeText': '时刻未解析', 'line': null, 'station': null},
    'start': null,
    'end': null,
    'balanceAfterText': 'JP￥0',
  },
};

Map<String, dynamic> _record({int sequence = 2, int block = 0}) => {
  'rawHex':
      '16010000335401010103840300${sequence.toRadixString(16).padLeft(4, '0')}00',
  'blockNumber': block,
  'timestamp': DateTime(2025, 10, 20).millisecondsSinceEpoch,
  'balanceYen': 900,
  'currencyCode': 'JPY',
  'amountIsBalance': true,
  'decoded': true,
  'details': {
    'recordSequence': sequence,
    'hasTime': false,
    'kind': 'rail',
    'terminalCode': 0x16,
    'processCode': 1,
    'balanceChangeYen': -100,
    'entryStation': {
      'areaCode': 0,
      'lineCode': 1,
      'stationCode': 1,
      'status': 'available',
    },
    'exitStation': {
      'areaCode': 0,
      'lineCode': 1,
      'stationCode': 3,
      'status': 'available',
    },
  },
  'presentation': {
    'version': 1,
    'mode': 'rail',
    'dateText': '2025-10-20',
    'state': 'completed',
    'info': {
      'sourceLabel': 'Suica 090F 历史',
      'title': '铁路 · 乘车扣款',
      'timeText': '2025-10-20',
      'amountText': '余额差 -JP￥100',
      'isConsume': true,
      'subText': '交易后余额 JP￥900',
      'category': '铁路',
      'badges': <String>[],
      'fields': <List<String>>[],
    },
    'point': {'timeText': '时刻未记录', 'line': '捕获时线路', 'station': '捕获时起点'},
    'start': {'timeText': '时刻未记录', 'line': '捕获时线路', 'station': '捕获时起点'},
    'end': {'timeText': '时刻未记录', 'line': '捕获时线路', 'station': '捕获时终点'},
    'balanceAfterText': 'JP￥900',
  },
};

String _payload(List<Map<String, dynamic>> records) => CardSessionSnapshot(
  context: _context,
  extensions: {
    'suica': {'version': 1, 'records': records},
  },
).encode();

ArchiveHistoryResult _history(List<List<Map<String, dynamic>>> reads) =>
    _historyPayloads(reads.map(_payload).toList());

ArchiveHistoryResult _historyPayloads(
  List<String> payloads, {
  int? transactionCount,
}) => ArchiveHistory.project(
  ArchiveRows(
    card: SavedCard(
      id: 'suica-card',
      cardFingerprint: 'felica:suica:idm:0102030405060708',
      cardType: 'suica',
      identificationSource: 'parser_only',
      createdAt: 0,
      updatedAt: 0,
      transactionCount: transactionCount,
    ),
    batches: [
      for (var i = 0; i < payloads.length; i++)
        CardReadBatch(
          id: 'read-$i',
          cardId: 'suica-card',
          cardFingerprint: 'felica:suica:idm:0102030405060708',
          readAt: 100 - i,
          parseVersion: 1,
          payloadJson: payloads[i],
        ),
    ],
  ),
);
