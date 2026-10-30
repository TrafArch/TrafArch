import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/features/trips/trip_journey_evidence.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_process_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_trip_matcher.dart';

void main() {
  test('沈阳真实单次公交交易继承同批1E第7槽而不获得1A身份', () {
    final record = _cycle();
    final transaction = _transaction(record.trip!);
    final evidence = _evidence([transaction], [record])[transaction]!;

    expect(record.trip!.time, DateTime(2026, 10, 17, 14, 18, 25));
    expect(record.trip!.amountFen, 180);
    expect(record.trip!.balanceFen, 1280);
    expect(evidence.processPositions, {'live': 7});
    expect(evidence.applicationRecordId, isNull);
    expect(transaction.trip.sequence, 577);
    expect(transaction.trip.balanceAfterFen, 1280);
    expect(transaction.trip.matchedProcessTrip, same(record.trip));
  });

  for (final type in [0x05, 0x06]) {
    test('单次公交类型$type的明确消费角色继承物理槽位', () {
      final record = _cycle(type: type);
      final transaction = _transaction(record.trip!, matched: false);

      expect(
        _evidence([transaction], [record])[transaction]!.processPositions,
        {'live': 7},
      );
    });

    test('单次公交类型$type的已匹配原记录提供明确消费角色', () {
      final record = _cycle(type: type);
      final transaction = _transaction(record.trip!, status: null);

      expect(
        _evidence([transaction], [record])[transaction]!.processPositions,
        {'live': 7},
      );
    });
  }

  final rejected = <String, TransactionTripEntry Function(TUnionTripRecord)>{
    '同POS相差一秒的展示关联': (cycle) => _transaction(
      cycle,
      matched: false,
      time: cycle.time.add(const Duration(seconds: 1)),
    ),
    '同POS金额不同的展示关联': (cycle) =>
        _transaction(cycle, matched: false, amountFen: 181),
    '城市不同': (cycle) => _transaction(cycle, cityCode: '1000'),
    '城市缺失': (cycle) => _transaction(cycle, cityCode: null),
    '城市全零': (cycle) => _transaction(cycle, cityCode: '0000'),
    '城市擦除值': (cycle) => _transaction(cycle, cityCode: 'FFFF'),
    '明确上车角色': (cycle) => _transaction(cycle, status: '上车'),
    '明确下车角色': (cycle) => _transaction(cycle, status: '下车'),
    '明确补票角色': (cycle) => _transaction(cycle, status: '补票'),
    '明确充值角色': (cycle) => _transaction(cycle, status: '充值'),
    '非消费交易': (cycle) => _transaction(cycle, isConsume: false),
    '非公交单次消费': (cycle) => _transaction(cycle, matched: false, mode: '城市轨道交通'),
    '角色缺失且没有已匹配原记录': (cycle) =>
        _transaction(cycle, matched: false, status: null),
    '没有任何来源关联': (cycle) => _transaction(cycle, matched: false, display: false),
  };
  for (final variant in rejected.entries) {
    test('单次公交不提升${variant.key}', () {
      final record = _cycle();
      final transaction = variant.value(record.trip!);
      final evidence = _evidence([transaction], [record])[transaction]!;

      expect(evidence.processPositions, isEmpty);
      expect(evidence.applicationRecordId, isNull);
    });
  }

  test('多个相同单次公交候选不任选1E槽位', () {
    final first = _cycle();
    final second = _cycle(slot: 8);
    final transaction = _transaction(first.trip!);

    expect(
      _evidence([transaction], [first, second])[transaction]!.processPositions,
      isEmpty,
    );
  });

  test('两笔公交交易竞争同一1E时均不继承槽位', () {
    final record = _cycle();
    final first = _transaction(record.trip!);
    final second = _transaction(record.trip!, sequence: 578);
    final evidence = _evidence([first, second], [record]);

    expect(evidence[first]!.processPositions, isEmpty);
    expect(evidence[second]!.processPositions, isEmpty);
  });

  test('单次公交原始槽位不可靠时不继承兼容编号', () {
    final record = _cycle(reliable: false);
    final transaction = _transaction(record.trip!);

    expect(
      _evidence([transaction], [record])[transaction]!.processPositions,
      isEmpty,
    );
  });
}

Map<TripEntry, LiveJourneyEvidence> _evidence(
  List<TripEntry> stream,
  List<TUnionProcessRecord> records,
) => buildLiveJourneyEvidence(
  stream: stream,
  processRecords: records,
  rails: const [],
  buses: const [],
);

TransactionTripEntry _transaction(
  TUnionTripRecord cycle, {
  DateTime? time,
  int? amountFen,
  String? status = '单次消费',
  String mode = '公共汽电车',
  String? cityCode = '2210',
  bool isConsume = true,
  bool matched = true,
  bool display = true,
  int sequence = 577,
}) => TransactionTripEntry(
  TransitTrip(
    time: time ?? cycle.time,
    amountFen: amountFen ?? cycle.amountFen,
    overdraftLimitFen: 0,
    isConsume: isConsume,
    typeName: '复合消费',
    isCompositeConsume: true,
    sequence: sequence,
    terminalId: '413101217487',
    cityCode: cityCode,
    appTypeName: mode,
    rideStatusName: status,
    balanceAfterFen: 1280,
    balanceAfterIsRecorded: false,
    matchedProcessTrip: matched ? cycle : null,
    displayProcessKey: display ? cycleDisplayKey(cycle) : null,
  ),
);

TUnionProcessRecord _cycle({
  int type = 0x06,
  int slot = 7,
  bool reliable = true,
}) {
  final raw = [
    for (var i = 0; i < _shenyangSingleBus.length; i += 2)
      int.parse(_shenyangSingleBus.substring(i, i + 2), radix: 16),
  ];
  raw[0] = type;
  return TUnionProcessRecord(
    sfi: 0x1E,
    recordNumber: slot,
    recordNumberIsReliable: reliable,
    recordName: '循环记录 $slot',
    raw: raw,
    trip: const TUnionProcessParser().parseCycleTrip(raw)!,
  );
}

// Exact 1E #7 body from the complete 19:51 reading in the supplied
// transit_card_log_20261030_195428.txt; no card identity is included.
// Type 0x05 variants above are explicitly synthetic.
const _shenyangSingleBus =
    '0600004131012174870200030250000000000000B40000050020261017141825221012172210FFFFFFFF000000000000';
