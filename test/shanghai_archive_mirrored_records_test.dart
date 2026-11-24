import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/application/cu_archive_projection.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/presentation/shanghai_archive_mirrored_records.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/reference_match.dart';
import 'package:transit_card_analyzer/features/transit_analysis/cu_transaction_analysis.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_file_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_models.dart';

void main() {
  const aid = 'A000000632010105';
  for (final testCase in [
    (credit: true, newAid: aid, expected: 1),
    (credit: true, newAid: 'another-wallet', expected: 2),
    (credit: false, newAid: aid, expected: 2),
  ]) {
    test('旧上海与新 TU 充值作用域：$testCase', () {
      final old = _batch('old', applicationId: aid, recharge: testCase.credit);
      final recent = _batch(
        'new',
        parser: CardParserIds.tunion,
        displayCardType: 'shanghai_transit_union',
        applicationId: testCase.newAid,
        recharge: testCase.credit,
      );
      final batches = [recent, old];
      final projection = presentArchiveTrips(
        ArchiveHistory.projectRecords(batches),
        batches: batches,
        onDiagnostics: (_) {},
      );
      expect(projection.journeys, hasLength(testCase.expected));
      if (testCase.expected == 1) {
        expect(
          projection.journeys.single.events.expand((e) => e.sourceIds).toSet(),
          {'old', 'new'},
        );
      }
    });
  }

  for (final sfi in [0x06, 0x18]) {
    test('同一上海钱包新批次已证实充值镜像，旧批次只保留 CU 文件 $sfi', () {
      final full = _batch('full', applicationId: aid, recharge: true, sfi: sfi);
      final cuOnly = _batch(
        'cu',
        parser: CardParserIds.tunion,
        displayCardType: 'shanghai_transit_union',
        applicationId: aid,
        includeTu: false,
        recharge: true,
        sfi: sfi,
      );
      final history = ArchiveHistoryResult(card: null, batches: [full, cuOnly]);
      final cu = projectCuArchive(history);
      expect(cu.transactions, hasLength(1));
      final partition = partitionShanghaiArchiveMirroredRecords(
        history: history,
        cityUnion: cu,
      );
      expect(partition.independent, isEmpty);
      expect(cu.sources[partition.mirrored.single]!.map((s) => s.batchId), [
        'full',
        'cu',
      ]);
    });
  }

  test('同批 CU 0x06 两个槽位有相同充值原文，一个 TU 观察只能解释一个槽位', () {
    final history = ArchiveHistoryResult(
      card: null,
      batches: [
        _batch(
          'full',
          applicationId: aid,
          recharge: true,
          sfi: 0x06,
          duplicateCu: true,
        ),
        _batch(
          'repeat',
          applicationId: aid,
          recharge: true,
          sfi: 0x06,
          duplicateCu: true,
        ),
      ],
    );
    final cu = projectCuArchive(history);
    final partition = partitionShanghaiArchiveMirroredRecords(
      history: history,
      cityUnion: cu,
    );
    expect(cu.transactions, hasLength(2));
    expect(partition.independent, hasLength(1));
    expect(partition.mirrored, hasLength(1));
    expect(cu.sources.values.map((s) => s.length), [2, 2]);
  });

  test(
    'same captured Shanghai batch folds matching CU and preserves evidence',
    () {
      final batch = _batch('one');
      final history = ArchiveHistoryResult(card: null, batches: [batch]);
      final cu = projectCuArchive(history);
      final result = partitionShanghaiArchiveMirroredRecords(
        history: history,
        cityUnion: cu,
      );
      expect(result.mirrored, cu.transactions);
      expect(result.independent, isEmpty);
      expect(cu.sources[result.mirrored.single]!.single.batchId, 'one');
      expect(batch.decoded.snapshot!.encode(), batch.decoded.rawJson);
    },
  );

  test('every source batch needs its own matching TU observation', () {
    final history = ArchiveHistoryResult(
      card: null,
      batches: [_batch('one'), _batch('two', includeTu: false)],
    );
    final cu = projectCuArchive(history);
    expect(cu.transactions, hasLength(1));
    expect(cu.sources.values.single, hasLength(2));
    final result = partitionShanghaiArchiveMirroredRecords(
      history: history,
      cityUnion: cu,
    );
    expect(result.mirrored, isEmpty);
    expect(result.independent, cu.transactions);
  });

  test('all matching source batches remain attached to the folded view', () {
    final history = ArchiveHistoryResult(
      card: null,
      batches: [_batch('one'), _batch('two')],
    );
    final cu = projectCuArchive(history);
    final result = partitionShanghaiArchiveMirroredRecords(
      history: history,
      cityUnion: cu,
    );
    expect(result.mirrored, cu.transactions);
    expect(
      cu.sources[result.mirrored.single]!.map((source) => source.batchId),
      ['one', 'two'],
    );
  });

  test('TU in a different capture cannot substitute for missing same-batch evidence', () {
    final history = ArchiveHistoryResult(
      card: null,
      batches: [
        _batch('cu-only', includeTu: false),
        _batch('tu-only', includeCu: false),
      ],
    );
    final cu = projectCuArchive(history);
    final result = partitionShanghaiArchiveMirroredRecords(
      history: history,
      cityUnion: cu,
    );
    expect(result.mirrored, isEmpty);
    expect(result.independent, cu.transactions);
  });

  for (final parser in [null, CardParserIds.tunion, CardParserIds.cityUnion]) {
    test('archive parser $parser cannot fold CU observations', () {
      final history = ArchiveHistoryResult(
        card: null,
        batches: [_batch('other', parser: parser)],
      );
      final cu = projectCuArchive(history);
      final result = partitionShanghaiArchiveMirroredRecords(
        history: history,
        cityUnion: cu,
      );
      expect(result.mirrored, isEmpty);
      expect(result.independent, cu.transactions);
    });
  }

  test(
    'captured civil time works independently of current device timezone',
    () {
      final batch = _batch('different-zone', capturedOffsetMinutes: -300);
      final history = ArchiveHistoryResult(card: null, batches: [batch]);
      final cu = projectCuArchive(history);
      final result = partitionShanghaiArchiveMirroredRecords(
        history: history,
        cityUnion: cu,
      );
      expect(result.mirrored, cu.transactions);
    },
  );

  for (final mode in [
    'missing-civil',
    'bad-date',
    'wrong-amount',
    'wrong-raw',
  ]) {
    test('archive evidence problem $mode keeps CU visible', () {
      final history = ArchiveHistoryResult(
        card: null,
        batches: [_batch('bad', mode: mode)],
      );
      final cu = projectCuArchive(history);
      final result = partitionShanghaiArchiveMirroredRecords(
        history: history,
        cityUnion: cu,
      );
      expect(result.mirrored, isEmpty);
      expect(result.independent, cu.transactions);
    });
  }

  for (final mode in ['wrong-consume', 'wrong-composite', 'wrong-type-name']) {
    test('conflicting captured transaction type $mode keeps CU visible', () {
      final history = ArchiveHistoryResult(
        card: null,
        batches: [_batch('type-conflict', mode: mode)],
      );
      final cu = projectCuArchive(history);
      final result = partitionShanghaiArchiveMirroredRecords(
        history: history,
        cityUnion: cu,
      );
      expect(result.mirrored, isEmpty);
      expect(result.independent, cu.transactions);
    });
  }

  test('source-free CU view cannot be folded by unrelated batch evidence', () {
    final view = _view();
    final history = ArchiveHistoryResult(card: null, batches: [_batch('one')]);
    final cu = CuArchiveProjection(
      transactions: [view],
      sources: const {},
      issues: const [],
    );
    final result = partitionShanghaiArchiveMirroredRecords(
      history: history,
      cityUnion: cu,
    );
    expect(result.mirrored, isEmpty);
    expect(result.independent, [view]);
  });

  test('one archived TU observation cannot cover two CU source slots', () {
    final history = ArchiveHistoryResult(
      card: null,
      batches: [_batch('two-slots', duplicateCu: true)],
    );
    final cu = projectCuArchive(history);
    expect(cu.sources.values.single, hasLength(2));
    final result = partitionShanghaiArchiveMirroredRecords(
      history: history,
      cityUnion: cu,
    );
    expect(result.mirrored, isEmpty);
    expect(result.independent, cu.transactions);
  });
}

CuTransactionView _view({
  int number = 1,
  int sfi = 0x18,
  bool recharge = false,
}) => CuTransactionView(
  record: CityUnionFileParser.parseWalletRecord(
    sfi,
    [
      0,
      14,
      0,
      0,
      0,
      0,
      0,
      1,
      0x90,
      recharge ? 2 : 9,
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
    kind: recharge
        ? CityUnionTransactionKind.recharge
        : CityUnionTransactionKind.consumption,
    recordNumber: number,
  ),
  transactionTime: DateTime.utc(2026, 10, 24, 15, 4, 4),
  location: ReferenceMatch(ReferenceMatchStatus.unknown, const []),
);

ArchiveBatchEvidence _batch(
  String id, {
  String? parser = CardParserIds.shanghaiTunion,
  bool includeTu = true,
  bool includeCu = true,
  bool duplicateCu = false,
  bool recharge = false,
  int sfi = 0x18,
  String? displayCardType,
  String? applicationId,
  int capturedOffsetMinutes = 480,
  String? mode,
}) {
  final view = _view(sfi: sfi, recharge: recharge);
  final snapshot = CardSessionSnapshot(
    context: ArchiveContext(
      systemId: parser,
      applicationId: applicationId,
      currencyCode: 'CNY',
      minorUnitDigits: 2,
      clockBasis: 'device-local-card-time-unverified',
      extensions: {'displayCardType': ?displayCardType},
    ),
    extensions: {
      if (includeCu)
        'cuProjection': captureCuProjection([
          view,
          if (duplicateCu) _view(number: 2, sfi: sfi, recharge: recharge),
        ]),
    },
    trips: [
      if (includeTu)
        TransitTrip(
          time: DateTime(2026, 10, 24, 23, 4, 4),
          amountFen: mode == 'wrong-amount' ? 500 : 400,
          overdraftLimitFen: 0,
          isConsume: !recharge && mode != 'wrong-consume',
          isCompositeConsume: !recharge && mode != 'wrong-composite',
          typeName: recharge || mode == 'wrong-type-name' ? '充值' : '复合消费',
          sequence: 14,
          terminalId: '200011012618',
          rawHex: mode == 'wrong-raw'
              ? view.record.rawHex.replaceFirst('00 0E', '00 0F')
              : view.record.rawHex,
        ),
    ],
  );
  final json = jsonDecode(snapshot.encode()) as Map<String, dynamic>;
  if (includeTu) {
    final trip = (json['trips'] as List).single as Map;
    final civil = mode == 'bad-date'
        ? '2026-02-30T23:04:04.000'
        : '2026-10-24T23:04:04.000';
    if (mode == 'missing-civil') {
      trip.remove('capturedTimes');
    } else {
      trip['time'] = DateTime.utc(2026, 10, 24, 23, 4, 4)
          .subtract(Duration(minutes: capturedOffsetMinutes))
          .millisecondsSinceEpoch;
      trip['capturedTimes'] = {
        'time': {
          'civil': civil,
          'conversionOffsetMinutes': capturedOffsetMinutes,
          'basis': 'parser-local-unverified',
        },
      };
    }
  }
  return ArchiveBatchEvidence(
    id: id,
    readAt: 1,
    storedParseVersion: 1,
    origin: 'test',
    timeSource: 'test',
    decoded: CardSessionSnapshot.decodeResult(jsonEncode(json)),
    issues: const [],
  );
}
