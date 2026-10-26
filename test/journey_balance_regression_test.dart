import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_engine.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_process_parser.dart';

// Screenshot-shaped synthetic records: amounts/times come from the report;
// terminal IDs and the 1E byte layout below are fixtures, not a card APDU capture.
final _events = [
  (41, DateTime(2026, 10, 26, 11, 37, 49), 700),
  (40, DateTime(2026, 10, 26, 10, 19, 42), 0),
  (39, DateTime(2026, 10, 23, 15, 22, 20), 5000),
  (38, DateTime(2026, 10, 23, 14, 56, 16), 0),
];

void main() {
  for (final bus in [false, true]) {
    test('进出站/上下车当笔扣费后余额，bus=$bus，保留原始1E余额', () {
      final card = _card(bus: bus, recorded: [12550, 12550, 17550, 17550]);
      final trips = AnalysisEngine(KnowledgeBase.empty()).analyze(card).trips;
      expect(trips.map((t) => t.sequence), [41, 40, 39, 38]);
      expect(trips.map((t) => t.balanceAfterFen), [11850, 12550, 12550, 17550]);
      expect(trips.map((t) => t.balanceAfterIsRecorded), everyElement(isFalse));
      expect(trips.map((t) => t.balanceAfterLabel), everyElement('交易后余额'));
      expect(trips.map((t) => t.matchedProcessTrip?.balanceFen), [
        12550,
        12550,
        17550,
        17550,
      ]);
      expect(
        trips.map((t) => t.rideStatusName),
        bus ? ['下车', '上车', '下车', '上车'] : ['出站', '进站', '出站', '进站'],
      );
      expect(trips.map((t) => t.isEntry), [false, true, false, true]);
      for (var i = 0; i < trips.length; i++) {
        expect(
          trips[i].matchedProcessTrip,
          same(card.transitProcessRecords[i].trip),
        );
        expect(trips[i].matchedProcessTrip!.rawHex, isNotEmpty);
      }
    });
  }

  test('1E已写入扣费后余额的卡不重复扣减', () {
    final card = _card(recorded: [11850, 12550, 12550, 17550]);
    final trips = AnalysisEngine(KnowledgeBase.empty()).analyze(card).trips;
    expect(trips.map((t) => t.balanceAfterFen), [11850, 12550, 12550, 17550]);
    expect(trips.map((t) => t.balanceAfterIsRecorded), everyElement(isFalse));
  });

  test('0元有效钱包不会被1E旧余额覆盖', () {
    final card = _card(wallet: 0, recorded: [700, 700, 5700, 5700]);
    final trips = AnalysisEngine(KnowledgeBase.empty()).analyze(card).trips;
    expect(trips.map((t) => t.balanceAfterFen), [0, 700, 700, 5700]);
  });

  test('未读到钱包仅保留记录余额，不将未知前后语义传播到更旧交易', () {
    final card = _card(wallet: null, recorded: [12550, null, null, null]);
    final trips = AnalysisEngine(KnowledgeBase.empty()).analyze(card).trips;
    expect(trips.map((t) => t.balanceAfterFen), [12550, null, null, null]);
    expect(trips.first.balanceAfterIsRecorded, isTrue);
    expect(trips.first.balanceAfterLabel, '记录余额');
  });
}

ParsedCard _card({
  int? wallet = 11850,
  bool bus = false,
  required List<int?> recorded,
}) => ParsedCard(
  parserId: CardParserIds.tunion,
  parserName: 'TU balance regression',
  info: TUnionCardInfo(cityCode: '1000', balanceFen: wallet),
  transactionFileObserved: true,
  transactions: [
    for (final (i, event) in _events.indexed)
      TUnionTransaction(
        recordNumber: i + 1,
        sequence: event.$1,
        time: event.$2,
        amountFen: event.$3,
        overdraftLimitFen: 0,
        rawType: 0x09,
        terminalId: '123456789012',
      ),
  ],
  transitProcessRecords: [
    for (final (i, event) in _events.indexed)
      if (recorded[i] != null) _process(event, recorded[i]!, i + 1, bus),
  ],
);

TUnionProcessRecord _process(
  (int, DateTime, int) event,
  int balance,
  int slot,
  bool bus,
) {
  final time = event.$2;
  final raw = <int>[
    event.$3 == 0 ? 0x03 : 0x04,
    0,
    0,
    0x12,
    0x34,
    0x56,
    0x78,
    0x90,
    0x12,
    bus ? 0x02 : 0x01,
    0,
    1,
    0,
    1,
    0,
    1,
    0,
    for (final shift in [24, 16, 8, 0]) (event.$3 >> shift) & 255,
    for (final shift in [24, 16, 8, 0]) (balance >> shift) & 255,
    for (final part in [
      time.year ~/ 100,
      time.year % 100,
      time.month,
      time.day,
      time.hour,
      time.minute,
      time.second,
    ])
      (part ~/ 10) * 16 + part % 10,
    0x10,
    0x00,
    ...List.filled(14, 0),
  ];
  return TUnionProcessRecord(
    sfi: 0x1E,
    recordNumber: slot,
    recordName: '循环记录 $slot',
    raw: raw,
    trip: const TUnionProcessParser().parseCycleTrip(raw)!,
  );
}
