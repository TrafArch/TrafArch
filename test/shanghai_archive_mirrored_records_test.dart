import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/application/cu_archive_projection.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/presentation/shanghai_archive_mirrored_records.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/reference_match.dart';
import 'package:transit_card_analyzer/features/transit_analysis/cu_transaction_analysis.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_file_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_models.dart';

void main() {
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

CuTransactionView _view({int number = 1}) => CuTransactionView(
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
  int capturedOffsetMinutes = 480,
  String? mode,
}) {
  final view = _view();
  final snapshot = CardSessionSnapshot(
    context: ArchiveContext(systemId: parser),
    extensions: {
      if (includeCu)
        'cuProjection': captureCuProjection([
          view,
          if (duplicateCu) _view(number: 2),
        ]),
    },
    trips: [
      if (includeTu)
        TransitTrip(
          time: DateTime(2026, 10, 24, 23, 4, 4),
          amountFen: mode == 'wrong-amount' ? 500 : 400,
          overdraftLimitFen: 0,
          isConsume: mode != 'wrong-consume',
          isCompositeConsume: mode != 'wrong-composite',
          typeName: mode == 'wrong-type-name' ? '充值' : '复合消费',
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
