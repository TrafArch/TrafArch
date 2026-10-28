import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/features/trips/trip_journey_evidence.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_process_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_trip_matcher.dart';

void main() {
  group('交易继承1E物理槽位', () {
    test('同秒同金额同方向同城市的唯一关联保留原物理槽号', () {
      final record = _cycle();
      final transaction = _transaction(record.trip!);
      final evidence = _evidence([transaction], [record]);

      expect(evidence[transaction]!.processPositions, {'live': 9});
      expect(evidence[transaction]!.applicationRecordId, isNull);
      expect(transaction.trip.sequence, 0x21);
      expect(record.recordNumber, 9);
    });

    final variants = <String, TransactionTripEntry Function(TUnionTripRecord)>{
      '相同POS但相差一秒': (cycle) =>
          _transaction(cycle, time: cycle.time.add(const Duration(seconds: 1))),
      '金额不同': (cycle) => _transaction(cycle, amountFen: cycle.amountFen + 1),
      '进出方向相反': (cycle) => _transaction(cycle, status: '进站'),
      '明确标注单次消费': (cycle) => _transaction(cycle, status: '单次消费'),
      '明确标注补票': (cycle) => _transaction(cycle, status: '补票'),
      '交通方式不同': (cycle) => _transaction(cycle, mode: '公共汽电车'),
      '城市不同': (cycle) => _transaction(cycle, cityCode: '2500'),
      '城市缺失': (cycle) => _transaction(cycle, cityCode: null),
      '城市全零': (cycle) => _transaction(cycle, cityCode: '0000'),
      '城市擦除值': (cycle) => _transaction(cycle, cityCode: 'FFFF'),
      '城市格式非法': (cycle) => _transaction(cycle, cityCode: '100'),
      '无展示关联': (cycle) => _transaction(cycle, includeDisplayKey: false),
    };
    for (final variant in variants.entries) {
      test('${variant.key}不继承槽位', () {
        final record = _cycle();
        final transaction = variant.value(record.trip!);
        final evidence = _evidence([transaction], [record]);

        expect(transaction.trip.terminalId, record.trip!.terminalId);
        expect(evidence[transaction]!.processPositions, isEmpty);
        expect(evidence[transaction]!.applicationRecordId, isNull);
      });
    }

    test('只有matchedProcessTrip时仍须逐项核实而不能直接继承槽位', () {
      final record = _cycle();
      final valid = _transaction(
        record.trip!,
        includeDisplayKey: false,
        matchedProcessTrip: record.trip,
      );
      final conflicting = _transaction(
        record.trip!,
        includeDisplayKey: false,
        matchedProcessTrip: record.trip,
        amountFen: record.trip!.amountFen + 1,
      );

      expect(_evidence([valid], [record])[valid]!.processPositions, {
        'live': 9,
      });
      expect(
        _evidence([conflicting], [record])[conflicting]!.processPositions,
        isEmpty,
      );
    });

    test('多个1E候选不任选一个物理槽位', () {
      final first = _cycle();
      final duplicate = _cycle(slot: 10);
      final transaction = _transaction(first.trip!);
      final evidence = _evidence([transaction], [first, duplicate]);

      expect(evidence[transaction]!.processPositions, isEmpty);
    });

    test('两笔交易竞争同一1E记录时双方均不继承槽位', () {
      final record = _cycle();
      final first = _transaction(record.trip!);
      final second = _transaction(record.trip!, sequence: 0x22);
      final evidence = _evidence([first, second], [record]);

      expect(evidence[first]!.processPositions, isEmpty);
      expect(evidence[second]!.processPositions, isEmpty);
    });

    test('唯一展示候选也不能绕过重复物理槽号检查', () {
      final record = _cycle();
      final other = _cycle(rawHex: _railEntry, slot: record.recordNumber);
      final transaction = _transaction(record.trip!);
      final evidence = _evidence([transaction], [record, other]);

      expect(
        cycleDisplayKey(record.trip!),
        isNot(cycleDisplayKey(other.trip!)),
      );
      expect(evidence[transaction]!.processPositions, isEmpty);
    });

    for (final slot in [0, -1]) {
      test('非正物理槽号$slot不用于交易配对', () {
        final record = _cycle(slot: slot);
        final transaction = _transaction(record.trip!);
        expect(
          _evidence([transaction], [record])[transaction]!.processPositions,
          isEmpty,
        );
      });
    }

    test('兼容层重新编号的1E记录不向交易提供物理槽位', () {
      final record = _cycle(reliable: false);
      final transaction = _transaction(record.trip!);
      expect(
        _evidence([transaction], [record])[transaction]!.processPositions,
        isEmpty,
      );
    });
  });

  group('1A和1E同一事件证据', () {
    test('345路两侧各自匹配且公交标注金额不充当上车扣款', () {
      final bus = _bus();
      final entry = _cycle(rawHex: _busEntry, slot: 12);
      final exit = _cycle(rawHex: _busExit, slot: 11);
      final application = BusRecordEntry(bus, isEntry: false);
      final entryEvent = ProcessTripEntry(entry.trip!);
      final exitEvent = ProcessTripEntry(exit.trip!);
      final transaction = _transaction(exit.trip!, mode: '公共汽电车', status: '下车');
      final evidence = _evidence(
        [application, entryEvent, exitEvent, transaction],
        [entry, exit],
        buses: [bus],
      );
      final identity = evidence[application]!.applicationRecordId;

      expect(bus.annotateAmountFen, 500);
      expect(entry.trip!.amountFen, 0);
      expect(identity, isNotNull);
      expect(evidence[entryEvent]!.applicationRecordId, identity);
      expect(evidence[exitEvent]!.applicationRecordId, identity);
      expect(evidence[transaction]!.applicationRecordId, identity);
      expect(evidence[transaction]!.processPositions, {'live': 11});
    });

    final variants = <String, Map<int, int>>{
      '相同终端但时间不同': {0x51: 0x51},
      '扣款金额冲突': {0x55: 0xC9},
      '城市不同': {0x2C: 0x25},
      '城市全零': {0x2C: 0, 0x2D: 0},
      '终端不同': {0x4A: 0x49},
      '终端全零': {for (var i = 0x43; i <= 0x4A; i++) i: 0},
      '终端擦除值': {for (var i = 0x43; i <= 0x4A; i++) i: 0xFF},
    };
    for (final variant in variants.entries) {
      test('${variant.key}不合并1A和1E', () {
        final bus = _bus(bodyPatches: variant.value);
        final record = _cycle(rawHex: _busExit, slot: 11);
        final event = ProcessTripEntry(record.trip!);
        final evidence = _evidence([event], [record], buses: [bus]);

        expect(evidence[event]!.applicationRecordId, isNull);
        expect(evidence[event]!.processPositions, {'live': 11});
      });
    }

    test('同一秒同终端但1E方向相反不合并', () {
      final record = _cycle(rawHex: _busExit, patches: {0: 3});
      final event = ProcessTripEntry(record.trip!);
      final evidence = _evidence([event], [record], buses: [_bus()]);
      expect(evidence[event]!.applicationRecordId, isNull);
    });

    test('同一秒同终端但1E交通方式相反不合并', () {
      final record = _cycle(rawHex: _busExit, patches: {9: 1});
      final event = ProcessTripEntry(record.trip!);
      final evidence = _evidence([event], [record], buses: [_bus()]);
      expect(evidence[event]!.applicationRecordId, isNull);
    });

    test('多个应用侧候选不任选一个1A身份', () {
      final record = _cycle(rawHex: _busExit);
      final event = ProcessTripEntry(record.trip!);
      final first = _bus();
      final second = _bus(bodyPatches: {0x57: 0x41});
      final evidence = _evidence([event], [record], buses: [first, second]);

      expect(first.exitTime, second.exitTime);
      expect(first.exitTerminalId, second.exitTerminalId);
      expect(first.rawHex, isNot(second.rawHex));
      expect(evidence[event]!.applicationRecordId, isNull);
    });

    test('多个1E候选竞争同一应用侧时双方均不建立身份别名', () {
      final first = _cycle(rawHex: _busExit, slot: 11);
      final second = _cycle(rawHex: _busExit, slot: 12, patches: {47: 1});
      final firstEvent = ProcessTripEntry(first.trip!);
      final secondEvent = ProcessTripEntry(second.trip!);
      final evidence = _evidence(
        [firstEvent, secondEvent],
        [first, second],
        buses: [_bus()],
      );

      expect(first.trip!.rawHex, isNot(second.trip!.rawHex));
      expect(evidence[firstEvent]!.applicationRecordId, isNull);
      expect(evidence[secondEvent]!.applicationRecordId, isNull);
      expect(evidence[firstEvent]!.processPositions, {'live': 11});
      expect(evidence[secondEvent]!.processPositions, {'live': 12});
    });

    test('轨道1A处于进闸状态时历史残留出闸字段不建立身份别名', () {
      final record = _cycle();
      final cycle = record.trip!;
      final event = ProcessTripEntry(cycle);
      TransitRecord rail(int status) => TransitRecord(
        statusCode: status,
        exitTime: cycle.time,
        exitCityCode: cycle.cityCode,
        exitTerminalId: cycle.terminalId,
        exitAmountFen: cycle.amountFen,
      );
      final complete = _evidence([event], [record], rails: [rail(2)]);
      final ongoing = _evidence([event], [record], rails: [rail(1)]);

      expect(complete[event]!.applicationRecordId, isNotNull);
      expect(ongoing[event]!.applicationRecordId, isNull);
      expect(ongoing[event]!.processPositions, {'live': 9});
    });

    test('交易的直接1A关联与1E间接关联指向不同记录时不任选身份', () {
      final record = _cycle(rawHex: _busExit, slot: 11);
      final indirect = _bus();
      final direct = _bus(bodyPatches: {0x4A: 0x49});
      final transaction = _transaction(
        record.trip!,
        mode: '公共汽电车',
        status: '下车',
        applicationKey: TunionApplicationSide(bus: direct, isEntry: false).key,
      );
      final evidence = _evidence(
        [transaction],
        [record],
        buses: [indirect, direct],
      );

      expect(evidence[transaction]!.applicationRecordId, isNull);
      expect(evidence[transaction]!.processPositions, {'live': 11});
    });
  });
}

Map<TripEntry, LiveJourneyEvidence> _evidence(
  List<TripEntry> stream,
  List<TUnionProcessRecord> records, {
  List<TransitRecord> rails = const [],
  List<BusTransitRecord> buses = const [],
}) => buildLiveJourneyEvidence(
  stream: stream,
  processRecords: records,
  rails: rails,
  buses: buses,
);

TransactionTripEntry _transaction(
  TUnionTripRecord cycle, {
  DateTime? time,
  int? amountFen,
  String status = '出站',
  String mode = '城市轨道交通',
  String? cityCode = '1000',
  int sequence = 0x21,
  bool includeDisplayKey = true,
  TUnionTripRecord? matchedProcessTrip,
  String? applicationKey,
}) => TransactionTripEntry(
  TransitTrip(
    time: time ?? cycle.time,
    amountFen: amountFen ?? cycle.amountFen,
    overdraftLimitFen: 0,
    isConsume: true,
    typeName: '复合消费',
    isCompositeConsume: true,
    sequence: sequence,
    terminalId: cycle.terminalId,
    cityCode: cityCode,
    appTypeName: mode,
    rideStatusName: status,
    displayProcessKey: includeDisplayKey ? cycleDisplayKey(cycle) : null,
    matchedProcessTrip: matchedProcessTrip,
    displayApplicationKey: applicationKey,
  ),
);

TUnionProcessRecord _cycle({
  int slot = 9,
  bool reliable = true,
  String rawHex = _railExit,
  Map<int, int> patches = const {},
}) {
  final raw = _bytes(rawHex);
  for (final patch in patches.entries) {
    raw[patch.key] = patch.value;
  }
  return TUnionProcessRecord(
    sfi: 0x1E,
    recordNumber: slot,
    recordNumberIsReliable: reliable,
    recordName: '循环记录 $slot',
    raw: raw,
    trip: const TUnionProcessParser().parseCycleTrip(raw)!,
  );
}

BusTransitRecord _bus({Map<int, int> bodyPatches = const {}}) {
  final raw = _bytes(_busApplication);
  for (final patch in bodyPatches.entries) {
    raw[14 + patch.key] = patch.value;
  }
  return const TUnionProcessParser().parseBusTransit(2, raw)!;
}

List<int> _bytes(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

// Beijing payloads from the reported 2026-10-27 read. The variants above change
// one source field at a time so a rejected match is not an invalid fixture.
const _railExit =
    '04000030008900034401080019003000000000012C0000374620261018103656100001011000FFFFFFFF000000000000';
const _railEntry =
    '030000300159000072010F001D00370000000000000000374620261018102739100001011000FFFFFFFF000000000000';
const _busExit =
    '0400000010090015480201590005000100000000C80000374620261018102352100011011000FFFFFFFF000000000000';
const _busEntry =
    '0300000010090015630201590013000100000000000000380E20261018091957100011011000FFFFFFFF000000000000';
const _busApplication =
    '27027D010100000000000000000002100011011000FFFFFFFF00010159133030303332313331000000100900156320261018091957000001F4AB100011011000FFFFFFFF00010159053030303332313331000000100900154820261018102352000000C806400000000000000000000000000000000000000000000000006D59';
