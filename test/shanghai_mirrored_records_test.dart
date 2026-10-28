import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/reference_data/data/city_union_lookup_rules.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/reference_match.dart';
import 'package:transit_card_analyzer/features/transit_analysis/cu_transaction_analysis.dart';
import 'package:transit_card_analyzer/features/trips/shanghai_mirrored_records.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_file_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

void main() {
  test(
    'Shanghai matching exit, zero-fare entry and recharge remain available',
    () {
      final exit = _cu(_bytes());
      final entry = _cu(_bytes(sequence: 13, amount: 0));
      final recharge = _cu(_bytes(sequence: 6, amount: 2000, type: 2));
      final input = [exit, entry, recharge];
      final before = input.map((view) => view.record.toJson()).toList();
      final result = _partition(input.map(_tu), input);

      expect(result.mirrored, orderedEquals(input));
      expect(result.independent, isEmpty);
      expect(result.mirroredCount, 3);
      expect(identical(result.mirrored.first, exit), isTrue);
      expect(input.map((view) => view.record.toJson()).toList(), before);
      expect(() => result.mirrored.clear(), throwsUnsupportedError);
    },
  );

  for (final parserId in [
    null,
    CardParserIds.tunion,
    CardParserIds.cityUnion,
  ]) {
    test(
      'ordinary parser $parserId keeps all CU records in primary display',
      () {
        final view = _cu(_bytes());
        final result = partitionShanghaiMirroredRecords(
          parserId: parserId,
          tunionTransactions: [_tu(view)],
          cityUnionTransactions: [view],
        );
        expect(result.mirrored, isEmpty);
        expect(result.independent, [view]);
      },
    );
  }

  test('raw-byte disagreement cannot fold otherwise equal transactions', () {
    final view = _cu(_bytes());
    final changedReserved = _cu(_bytes()..[2] = 1);
    final result = _partition([_tu(view)], [changedReserved]);
    expect(result.mirrored, isEmpty);
    expect(result.independent, [changedReserved]);
  });

  test(
    'spaces, line breaks and hexadecimal letter case do not change bytes',
    () {
      final view = _cu(_bytes());
      final tu = _tu(
        view,
        rawHex: view.record.rawHex.toLowerCase().replaceAll(' ', '\n'),
      );
      final result = _partition([tu], [view]);
      expect(result.mirrored, [view]);
    },
  );

  for (final raw in <String?>[null, '', '00', 'GG' * 23, '0' * 45, '0' * 48]) {
    test('missing or malformed TU raw evidence stays independent: $raw', () {
      final view = _cu(_bytes());
      final tu = _tu(view, rawHex: raw, preserveMissingRaw: true);
      final result = _partition([tu], [view]);
      expect(result.mirrored, isEmpty);
      expect(result.independent, [view]);
    });
  }

  for (final field in [
    'sequence',
    'amount',
    'type',
    'terminal',
    'date',
    'time',
  ]) {
    test('same bytes with conflicting decoded $field stays independent', () {
      final original = _cu(_bytes());
      final changed = _copyCu(
        original,
        sequence: field == 'sequence' ? 15 : null,
        amount: field == 'amount' ? 500 : null,
        type: field == 'type' ? 2 : null,
        terminal: field == 'terminal' ? '200011012619' : null,
        date: field == 'date' ? '2026-10-25' : null,
        time: field == 'time' ? '23:04:05' : null,
      );
      final result = _partition([_tu(original)], [changed]);
      expect(result.mirrored, isEmpty);
      expect(result.independent, [changed]);
    });
  }

  test('malformed CU raw evidence cannot be used to fold records', () {
    final original = _cu(_bytes());
    final changed = _copyCu(original, rawHex: 'not a transaction');
    final result = _partition([_tu(original)], [changed]);
    expect(result.mirrored, isEmpty);
    expect(result.independent, [changed]);
  });

  for (final (date, time) in const [
    ('', ''),
    ('2026-02-30', '23:04:04'),
    ('2026-10-24', '24:61:00'),
  ]) {
    test('invalid captured CU calendar fields stay visible: $date $time', () {
      final original = _cu(_bytes());
      final changed = _copyCu(original, date: date, time: time);
      final result = _partition([_tu(original)], [changed]);
      expect(result.mirrored, isEmpty);
      expect(result.independent, [changed]);
    });
  }

  for (final raw in ['00' * 23, 'FF' * 23]) {
    test('blank raw bytes cannot support conflicting populated fields', () {
      final original = _cu(_bytes());
      final changed = _copyCu(original, rawHex: raw);
      final result = _partition([_tu(original, rawHex: raw)], [changed]);
      expect(result.mirrored, isEmpty);
      expect(result.independent, [changed]);
    });
  }

  for (final sfi in [0x06, 0x10, 0x1A]) {
    test(
      'CU file 0x${sfi.toRadixString(16)} remains a separate application channel',
      () {
        final original = _cu(_bytes());
        final otherFile = _cu(_bytes(), sfi: sfi);
        final result = _partition([_tu(original)], [otherFile]);
        expect(result.mirrored, isEmpty);
        expect(result.independent, [otherFile]);
      },
    );
  }

  test('matching compares card calendar time despite CU UTC projection', () {
    final view = _cu(_bytes());
    expect(view.transactionTime, DateTime.utc(2026, 10, 24, 15, 4, 4));
    final result = _partition([_tu(view)], [view]);
    expect(result.mirrored, [view]);
  });

  test('CU records without a TU counterpart retain their original order', () {
    final mirrored = _cu(_bytes());
    final first = _cu(_bytes(sequence: 15));
    final last = _cu(_bytes(sequence: 13));
    final result = _partition([_tu(mirrored)], [first, mirrored, last]);
    expect(result.mirrored, [mirrored]);
    expect(result.independent, [first, last]);
  });

  test('one TU observation cannot fold two separate CU observations', () {
    final first = _cu(_bytes(), recordNumber: 1);
    final second = _cu(_bytes(), recordNumber: 2);
    final result = _partition([_tu(first)], [first, second]);
    expect(result.mirrored, [first]);
    expect(result.independent, [second]);
  });

  test(
    'two matching TU observations can fold two preserved CU observations',
    () {
      final first = _cu(_bytes(), recordNumber: 1);
      final second = _cu(_bytes(), recordNumber: 2);
      final result = _partition([_tu(first), _tu(second)], [first, second]);
      expect(result.mirrored, [first, second]);
      expect(result.independent, isEmpty);
    },
  );
}

ShanghaiMirroredRecords _partition(
  Iterable<TUnionTransaction> tu,
  Iterable<CuTransactionView> cu,
) => partitionShanghaiMirroredRecords(
  parserId: CardParserIds.shanghaiTunion,
  tunionTransactions: tu,
  cityUnionTransactions: cu,
);

List<int> _bytes({int sequence = 14, int amount = 400, int type = 9}) => [
  sequence >> 8,
  sequence & 0xFF,
  0,
  0,
  0,
  (amount >> 24) & 0xFF,
  (amount >> 16) & 0xFF,
  (amount >> 8) & 0xFF,
  amount & 0xFF,
  type,
  0x20,
  0x00,
  0x11,
  0x01,
  0x26,
  0x18,
  0x20,
  0x26,
  0x10,
  0x24,
  0x23,
  0x04,
  0x04,
];

CuTransactionView _cu(List<int> bytes, {int sfi = 0x18, int recordNumber = 1}) {
  final record = CityUnionFileParser.parseWalletRecord(
    sfi,
    bytes,
    kind: CityUnionTransactionKind.consumption,
    recordNumber: recordNumber,
  );
  return CuTransactionView(
    record: record,
    transactionTime: CityUnionLookupRules.transactionTime(
      record.transactionDate,
      record.transactionTime,
    ),
    location: ReferenceMatch(ReferenceMatchStatus.unknown, const []),
  );
}

TUnionTransaction _tu(
  CuTransactionView view, {
  String? rawHex,
  bool preserveMissingRaw = false,
}) => TUnionTransaction(
  sequence: view.record.sequence,
  overdraftLimitFen: 0,
  amountFen: view.record.amountRaw,
  rawType: view.record.transactionType,
  terminalId: view.record.terminalNumber!,
  time: DateTime.parse(
    '${view.record.transactionDate}T${view.record.transactionTime}',
  ),
  recordNumber: view.record.recordNumber,
  rawHex: preserveMissingRaw ? rawHex : rawHex ?? view.record.rawHex,
);

CuTransactionView _copyCu(
  CuTransactionView view, {
  int? sequence,
  int? amount,
  int? type,
  String? terminal,
  String? date,
  String? time,
  String? rawHex,
}) {
  final record = view.record as CjT331WalletLocalConsumption;
  return CuTransactionView(
    record: CjT331WalletLocalConsumption(
      sourceSfi: record.sfi,
      recordNumber: record.recordNumber,
      sequence: sequence ?? record.sequence,
      sequenceHex: record.sequenceHex,
      reservedHex: record.reservedHex,
      amountRaw: amount ?? record.amountRaw,
      amountHex: record.amountHex,
      transactionType: type ?? record.transactionType,
      terminalNumber: terminal ?? record.terminalNumber,
      transactionDate: date ?? record.transactionDate,
      transactionTime: time ?? record.transactionTime,
      fields: record.fields,
      rawHex: rawHex ?? record.rawHex,
    ),
    transactionTime: view.transactionTime,
    location: view.location,
  );
}
