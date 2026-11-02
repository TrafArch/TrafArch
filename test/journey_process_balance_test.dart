import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/features/trips/trip_filters.dart';

// These are balance relationships from the real Beijing 2026-10-27 read.
// Pairing, source validation, and balance projection all run through the public
// projection API. Raw balances are deliberately kept separate from confirmed
// transaction balances: rail and bus records on this card use different timing.
void main() {
  test('上海扣除额度后的负余额仍通过原始进出账本核验', () {
    final events = [
      _cycle(
        'exit',
        role: JourneyEventRole.exit,
        minute: 25,
        slot: 1,
        recordedFen: 300,
        amountFen: 200,
        balanceOffsetFen: -800,
      ),
      _cycle(
        'entry',
        role: JourneyEventRole.entry,
        minute: 10,
        slot: 2,
        recordedFen: 500,
        amountFen: 0,
        balanceOffsetFen: -800,
      ),
    ];
    final journey = _exitJourney(projectJourneys(events));
    expect(journey.state, JourneyState.completed);
    expect(journey.balanceAfterText, '¥-5.00');
    expect(journey.amountText, '-¥2.00');
    expect(events.first.processBalance!.recordedFen, 300);
    expect(events.last.processBalance!.recordedFen, 500);
  });

  test('异地单次公交15050由同钱包前后相邻余额闭合确认行程后余额', () {
    final events = _singleBus();
    final journey = projectJourneys(events)
        .singleWhere((j) => j.events.any((e) => e.payload == 'single'));
    expect(journey.state, JourneyState.single);
    expect(journey.balanceAfterText, '¥150.50');
    expect(events[1].processBalance!.recordedFen, 15050);
  });

  test('单次公交原值为扣前余额时由局部锚确认扣后值且不改原值', () {
    final events = _singleBus(rawBalance: 15150);
    final journey = projectJourneys(events)
        .singleWhere((j) => j.state == JourneyState.single);
    expect(journey.balanceAfterText, '¥150.50');
    expect(events[1].processBalance!.recordedFen, 15150);
  });

  for (final fault in [
    'slot-gap',
    'different-wallet',
    'different-batch',
    'unknown-city',
    'bad-currency',
    'anchor-debit',
    'conflicting-confirmed',
    'intervening-recharge',
    'unknown-time',
    'duplicate-slot',
    'missing-older-pair',
    'older-balance-conflict',
    'older-confirmed-conflict',
    'older-slot-gap',
    'older-interval-recharge',
    'older-conflicting-application',
    'older-conflicting-sequence',
  ]) {
    test('单次公交余额证据不足时不推算: $fault', () {
      final events = _singleBus(fault: fault);
      final single = projectJourneys(events)
          .singleWhere((j) => j.events.any((e) => e.payload == 'single'));
      expect(single.balanceAfterText, isNull);
    });
  }

  test('345路上车14350下车14150扣200直接显示14150且不重复扣款', () {
    final events = _busPair();
    final journey = _exitJourney(projectJourneys(events));

    expect(journey.state, JourneyState.completed);
    expect(journey.balanceAfterText, '¥141.50');
    expect(journey.amountText, '-¥2.00');
    expect(journey.events.map((event) => event.payload), ['entry', 'exit']);
    expect(events.last.processBalance!.recordedFen, 14350);
    expect(events.first.processBalance!.recordedFen, 14150);
  });

  test('专70与945路各自的进出余额闭合不依赖当前钱包', () {
    for (final (before, after, expected) in [
      (14450, 14350, '¥143.50'),
      (14550, 14450, '¥144.50'),
    ]) {
      final journey = _exitJourney(
        projectJourneys(
          _busPair(entryBalance: before, exitBalance: after, fare: 100),
        ),
      );
      expect(journey.balanceAfterText, expected);
    }
  });

  test('轨道相同raw需更晚相邻零金额进站14550局部锚证明扣费后余额', () {
    final events = _railPair();
    final journeys = projectJourneys(events);
    final journey = _exitJourney(journeys);

    expect(journey.state, JourneyState.completed);
    expect(journey.balanceAfterText, '¥145.50');
    expect(journey.amountText, '-¥5.00');
    expect(journey.events.map((event) => event.payload), ['entry', 'exit']);
    final anchor = journeys.singleWhere(
      (item) => item.events.any((event) => event.payload == 'anchor'),
    );
    expect(anchor.state, JourneyState.inProgress);
    expect(anchor.balanceAfterText, isNull);
    expect(events[1].processBalance!.recordedFen, 15050);
    expect(events[2].processBalance!.recordedFen, 15050);
  });

  test('相同raw无局部锚时不把原始余额直接当行程后余额也不直接减fare', () {
    final journey = _exitJourney(
      projectJourneys(_railPair(includeAnchor: false)),
    );
    expect(journey.state, JourneyState.completed);
    expect(journey.balanceAfterText, isNull);
  });

  test('局部锚余额不等于raw减fare时保持未知', () {
    final journey = _exitJourney(
      projectJourneys(_railPair(anchorBalance: 14450)),
    );
    expect(journey.state, JourneyState.completed);
    expect(journey.balanceAfterText, isNull);
  });

  test('可靠出站交易余额优先于原始1E推导值', () {
    final journey = _exitJourney(
      projectJourneys(
        _busPair(confirmedExit: 14000, balanceAfterText: '¥140.00'),
      ),
    );
    expect(journey.balanceAfterText, '¥140.00');
  });

  test('锚原始余额与锚已确认余额冲突时不用于旧行程', () {
    final journey = _exitJourney(
      projectJourneys(_railPair(anchorConfirmedBalance: 14650)),
    );
    expect(journey.balanceAfterText, isNull);
  });

  test('同批次未知时间的资金事件不能被当作区间之外', () {
    final events = _busPair(recordId: 'application');
    events.add(
      const JourneyEvent<String>(
        payload: 'unknown-time-payment',
        mode: TripModeFilter.other,
        role: JourneyEventRole.unknown,
        scopeKey: 'wallet-CNY',
        sourceIds: {'read'},
        evidenceSource: JourneyEvidenceSource.transaction,
      ),
    );
    final journey = _exitJourney(projectJourneys(events));
    expect(journey.state, JourneyState.completed);
    expect(journey.balanceAfterText, isNull);
  });

  test('局部锚与其已确认余额一致时仍可证明旧行程', () {
    final journey = _exitJourney(
      projectJourneys(_railPair(anchorConfirmedBalance: 14550)),
    );
    expect(journey.balanceAfterText, '¥145.50');
  });

  test('已知资金事件插入出站与锚之间时不跨越推导', () {
    final events = _railPair();
    events.insert(
      1,
      JourneyEvent<String>(
        payload: 'intervening-recharge',
        mode: TripModeFilter.other,
        role: JourneyEventRole.unknown,
        scopeKey: 'wallet-CNY',
        sourceIds: const {'read'},
        cityCode: '1000',
        endpoint: JourneyEndpoint(time: DateTime(2026, 10, 7, 11, 27)),
        evidenceSource: JourneyEvidenceSource.transaction,
        amountText: '+¥1.00',
      ),
    );
    final journey = _exitJourney(projectJourneys(events));
    expect(journey.state, JourneyState.completed);
    expect(journey.balanceAfterText, isNull);
  });

  test('明确应用pair内出现已知充值时即使公交原始余额闭合也不推导', () {
    final events = _busPair(recordId: 'application');
    events.insert(
      1,
      JourneyEvent<String>(
        payload: 'intervening-recharge',
        mode: TripModeFilter.other,
        role: JourneyEventRole.unknown,
        scopeKey: 'wallet-CNY',
        sourceIds: const {'read'},
        cityCode: '1000',
        endpoint: JourneyEndpoint(time: DateTime(2026, 10, 7, 11, 15)),
        evidenceSource: JourneyEvidenceSource.transaction,
        amountText: '+¥1.00',
      ),
    );
    final journey = _exitJourney(projectJourneys(events));
    expect(journey.state, JourneyState.completed);
    expect(journey.balanceAfterText, isNull);
    expect(journey.events.map((event) => event.payload), ['entry', 'exit']);
  });

  for (final (name, anchorSlot, anchorRole, anchorAmount) in [
    ('槽位缺口', 15, JourneyEventRole.entry, 0),
    ('相同槽号', 17, JourneyEventRole.entry, 0),
    ('非零进站金额', 16, JourneyEventRole.entry, 100),
    ('未知事件角色', 16, JourneyEventRole.unknown, 0),
    ('单次消费角色', 16, JourneyEventRole.single, 0),
  ]) {
    test('轨道局部锚$name不构成扣费后证据', () {
      final events = _railPair(includeAnchor: false);
      events.insert(
        0,
        _cycle(
          'anchor',
          role: anchorRole,
          minute: 30,
          slot: anchorSlot,
          recordedFen: 14550,
          amountFen: anchorAmount,
          mode: TripModeFilter.rail,
        ),
      );
      _expectNoDerivedBalance(events);
    });
  }

  test('锚必须在出站之后而不能只凭更小槽号', () {
    final events = _railPair(includeAnchor: false);
    events.add(
      _cycle(
        'anchor',
        role: JourneyEventRole.entry,
        minute: 5,
        slot: 16,
        recordedFen: 14550,
        amountFen: 0,
        mode: TripModeFilter.rail,
      ),
    );
    _expectNoDerivedBalance(events);
  });

  test('锚自身余额positions不属于锚来源时不能借其他事件来源', () {
    final events = _railPair(includeAnchor: false);
    events.insert(
      0,
      _cycle(
        'anchor',
        role: JourneyEventRole.entry,
        minute: 30,
        slot: 16,
        recordedFen: 14550,
        amountFen: 0,
        mode: TripModeFilter.rail,
        sources: const {'other-read'},
        evidencePositions: const {'read': 16},
      ),
    );
    _expectNoDerivedBalance(events);
  });

  test('两个独立事件占用同一锚槽号时不能选择其中一个', () {
    final events = _railPair();
    events.insert(
      0,
      _cycle(
        'duplicate-anchor',
        role: JourneyEventRole.unknown,
        minute: 35,
        slot: 16,
        recordedFen: 14550,
        amountFen: 0,
        mode: TripModeFilter.rail,
      ),
    );
    _expectNoDerivedBalance(events);
  });

  for (final (name, positions) in [
    ('没有原始槽位', <String, int>{}),
    ('槽位不连续', {'read': 9}),
    ('零槽位', {'read': 0}),
    ('负槽位', {'read': -1}),
    ('跨读取批次', {'other-read': 12}),
    ('不属于来源的槽位', {'unrelated': 12}),
  ]) {
    test('完整应用pair仍不能用$name推导公交余额', () {
      final events = _busPair(recordId: 'application');
      events[1] = _cycle(
        'entry',
        role: JourneyEventRole.entry,
        minute: 10,
        slot: 12,
        recordedFen: 14350,
        amountFen: 0,
        applicationRecordId: 'application',
        sources: const {'read', 'other-read'},
        evidencePositions: positions,
      );
      final journey = _exitJourney(projectJourneys(events));
      expect(journey.state, JourneyState.completed);
      expect(journey.balanceAfterText, isNull);
    });
  }

  test('全列表重复原始槽位也会使完整应用pair的余额证据失效', () {
    final events = _busPair(recordId: 'application');
    events.add(
      _cycle(
        'duplicate-entry-slot',
        role: JourneyEventRole.unknown,
        minute: 1,
        slot: 12,
        recordedFen: 14350,
        amountFen: 0,
      ),
    );
    final journey = _exitJourney(projectJourneys(events));
    expect(journey.state, JourneyState.completed);
    expect(journey.balanceAfterText, isNull);
  });

  for (final (name, before, after, entryAmount, fare) in [
    ('负进站余额', -1, 14150, 0, 200),
    ('负出站余额', 14350, -1, 0, 200),
    ('进站有金额', 14350, 14150, 100, 200),
    ('零扣款', 14350, 14350, 0, 0),
    ('负扣款', 14350, 14150, 0, -200),
    ('余额差不等于扣款', 14350, 14050, 0, 200),
  ]) {
    test('公交$name不推导行程后余额', () {
      _expectNoDerivedBalance(
        _busPair(
          entryBalance: before,
          exitBalance: after,
          entryAmount: entryAmount,
          fare: fare,
        ),
      );
    });
  }

  test('未知币种不能被格式化成默认人民币', () {
    _expectNoDerivedBalance(_busPair(currencyCode: null));
    _expectNoDerivedBalance(_busPair(currencyCode: ''));
  });

  test('进出两侧币种不一致不能混合比较数值', () {
    final events = _busPair();
    events[1] = _cycle(
      'entry',
      role: JourneyEventRole.entry,
      minute: 10,
      slot: 12,
      recordedFen: 14350,
      amountFen: 0,
      currencyCode: 'HKD',
      currencySymbol: 'HK\$',
    );
    _expectNoDerivedBalance(events);
  });

  test('币种小数位不一致不能混合比较数值', () {
    final events = _busPair();
    events[1] = _cycle(
      'entry',
      role: JourneyEventRole.entry,
      minute: 10,
      slot: 12,
      recordedFen: 14350,
      amountFen: 0,
      minorUnitDigits: 0,
    );
    _expectNoDerivedBalance(events);
  });

  test('同侧1A和1E折叠仍保留唯一1E余额证据及全部原始payload', () {
    final events = _busPair(recordId: 'application');
    events.insert(
      0,
      _application('application-exit', JourneyEventRole.exit, 25),
    );
    events.insert(
      2,
      _application('application-entry', JourneyEventRole.entry, 10),
    );
    final journey = _exitJourney(projectJourneys(events));
    expect(journey.state, JourneyState.completed);
    expect(journey.balanceAfterText, '¥141.50');
    expect(journey.events.map((event) => event.payload).toSet(), {
      'application-entry',
      'application-exit',
      'entry',
      'exit',
    });
  });

  test('折叠来源的并集不能替余额证据补上其原事件没有的批次', () {
    final events = _busPair(recordId: 'application');
    events[0] = _cycle(
      'exit',
      role: JourneyEventRole.exit,
      minute: 25,
      slot: 11,
      recordedFen: 14150,
      amountFen: 200,
      applicationRecordId: 'application',
      sources: const {'read', 'borrowed-read'},
      eventPositions: const {'borrowed-read': 11},
      evidencePositions: const {'borrowed-read': 11},
    );
    events[1] = _cycle(
      'entry',
      role: JourneyEventRole.entry,
      minute: 10,
      slot: 12,
      recordedFen: 14350,
      amountFen: 0,
      applicationRecordId: 'application',
      sources: const {'read'},
      eventPositions: const {'borrowed-read': 12},
      evidencePositions: const {'borrowed-read': 12},
    );
    events.insert(
      1,
      _application(
        'application-entry',
        JourneyEventRole.entry,
        10,
        sources: const {'read', 'borrowed-read'},
      ),
    );
    final journey = _exitJourney(projectJourneys(events));
    expect(journey.state, JourneyState.completed);
    expect(journey.balanceAfterText, isNull);
  });

  test('单独出站和进行中进站不凭记录余额产生行程后余额', () {
    final pair = _busPair();
    _expectNoDerivedBalance([pair.first]);
    final ongoing = projectJourneys([pair.last]).single;
    expect(ongoing.state, JourneyState.inProgress);
    expect(ongoing.balanceAfterText, isNull);
  });

  test('withPayload保留余额证据和已确认数值且不改变原始来源', () {
    final original = _busPair(confirmedExit: 14150).first;
    final mapped = original.withPayload(42);
    expect(mapped.payload, 42);
    expect(mapped.processBalance, same(original.processBalance));
    expect(mapped.confirmedBalanceFen, 14150);
    expect(mapped.sourceIds, {'read'});
    expect(mapped.processBalance!.positions, {'read': 11});
  });
}

List<JourneyEvent<String>> _singleBus({int rawBalance = 15050, String? fault}) {
  final anchorTime = DateTime(2026, 10, 7, 11, 22);
  JourneyEvent<String> make(bool anchor, {String? id}) {
    final slot = anchor ? (fault == 'slot-gap' ? 17 : 18) : 19;
    final sources = anchor && fault == 'different-batch'
        ? const {'other'}
        : const {'read'};
    return JourneyEvent(
      payload: id ?? (anchor ? 'next-entry' : 'single'),
      mode: anchor ? TripModeFilter.rail : TripModeFilter.bus,
      role: anchor ? JourneyEventRole.entry : JourneyEventRole.single,
      scopeKey: anchor && fault == 'different-wallet' ? 'other' : 'wallet-CNY',
      sourceIds: sources,
      cityCode: anchor ? (fault == 'unknown-city' ? null : '1000') : '1610',
      endpoint: JourneyEndpoint(
        time: anchor ? anchorTime : DateTime(2026, 9, 24, 18, 29, 29),
      ),
      processPositions: {sources.single: slot},
      processBalance: JourneyProcessBalanceEvidence(
        recordedFen: anchor ? 15050 : rawBalance,
        amountFen: anchor ? (fault == 'anchor-debit' ? 1 : 0) : 100,
        currencyCode: fault == 'bad-currency' ? 'HKD' : 'CNY',
        currencySymbol: '¥',
        positions: {sources.single: slot},
      ),
      confirmedBalanceFen: anchor && fault == 'conflicting-confirmed'
          ? 15150
          : null,
    );
  }

  JourneyEvent<String> older(bool entry) {
    final slot = entry ? 21 : (fault == 'older-slot-gap' ? 22 : 20);
    final balance = entry
        ? 15250
        : (fault == 'older-balance-conflict' ? 15050 : 15150);
    return JourneyEvent(
      payload: entry ? 'older-entry' : 'older-exit',
      mode: TripModeFilter.bus,
      role: entry ? JourneyEventRole.entry : JourneyEventRole.exit,
      scopeKey: 'wallet-CNY',
      sourceIds: const {'read'},
      cityCode: '1000',
      applicationRecordId: fault == 'older-conflicting-application'
          ? (entry ? 'older-a' : 'older-b')
          : null,
      sequence: fault == 'older-conflicting-sequence'
          ? (entry ? 30 : 32)
          : null,
      endpoint: JourneyEndpoint(
        line: '345路',
        time: DateTime(2026, 9, 24, 17, entry ? 0 : 30),
      ),
      processPositions: {'read': slot},
      processBalance: JourneyProcessBalanceEvidence(
        recordedFen: balance,
        amountFen: entry ? 0 : 100,
        currencyCode: 'CNY',
        currencySymbol: '¥',
        positions: {'read': slot},
      ),
      confirmedBalanceFen: !entry && fault == 'older-confirmed-conflict'
          ? 15250
          : null,
    );
  }

  return [
    make(true),
    make(false),
    if (fault != 'missing-older-pair') ...[older(false), older(true)],
    if (fault == 'duplicate-slot') make(true, id: 'duplicate'),
    if (fault == 'intervening-recharge' || fault == 'unknown-time')
      JourneyEvent(
        payload: 'recharge',
        mode: TripModeFilter.other,
        role: JourneyEventRole.unknown,
        scopeKey: 'wallet-CNY',
        sourceIds: const {'read'},
        endpoint: JourneyEndpoint(
          time: fault == 'unknown-time'
              ? null
              : anchorTime.subtract(const Duration(hours: 1)),
        ),
      ),
    if (fault == 'older-interval-recharge')
      JourneyEvent(
        payload: 'older-recharge',
        mode: TripModeFilter.other,
        role: JourneyEventRole.unknown,
        scopeKey: 'wallet-CNY',
        sourceIds: const {'read'},
        endpoint: JourneyEndpoint(time: DateTime(2026, 9, 24, 18)),
      ),
  ];
}

JourneyPresentation<String> _exitJourney(
  List<JourneyPresentation<String>> journeys,
) => journeys.singleWhere(
  (journey) => journey.events.any((event) => event.payload == 'exit'),
);

void _expectNoDerivedBalance(List<JourneyEvent<String>> events) {
  final journeys = projectJourneys(events);
  expect(journeys.every((journey) => journey.balanceAfterText == null), isTrue);
  expect(
    journeys.expand((journey) => journey.events).map((event) => event.payload),
    unorderedEquals(events.map((event) => event.payload)),
  );
}

List<JourneyEvent<String>> _busPair({
  int entryBalance = 14350,
  int exitBalance = 14150,
  int entryAmount = 0,
  int fare = 200,
  String? recordId,
  String? currencyCode = 'CNY',
  int? confirmedExit,
  String? balanceAfterText,
}) => [
  _cycle(
    'exit',
    role: JourneyEventRole.exit,
    minute: 25,
    slot: 11,
    recordedFen: exitBalance,
    amountFen: fare,
    applicationRecordId: recordId,
    currencyCode: currencyCode,
    confirmedBalanceFen: confirmedExit,
    balanceAfterText: balanceAfterText,
  ),
  _cycle(
    'entry',
    role: JourneyEventRole.entry,
    minute: 10,
    slot: 12,
    recordedFen: entryBalance,
    amountFen: entryAmount,
    applicationRecordId: recordId,
    currencyCode: currencyCode,
  ),
];

List<JourneyEvent<String>> _railPair({
  bool includeAnchor = true,
  int anchorBalance = 14550,
  int? anchorConfirmedBalance,
}) => [
  if (includeAnchor)
    _cycle(
      'anchor',
      role: JourneyEventRole.entry,
      minute: 30,
      slot: 16,
      recordedFen: anchorBalance,
      amountFen: 0,
      mode: TripModeFilter.rail,
      confirmedBalanceFen: anchorConfirmedBalance,
    ),
  _cycle(
    'exit',
    role: JourneyEventRole.exit,
    minute: 25,
    slot: 17,
    recordedFen: 15050,
    amountFen: 500,
    mode: TripModeFilter.rail,
  ),
  _cycle(
    'entry',
    role: JourneyEventRole.entry,
    minute: 10,
    slot: 18,
    recordedFen: 15050,
    amountFen: 0,
    mode: TripModeFilter.rail,
  ),
];

JourneyEvent<String> _cycle(
  String id, {
  required JourneyEventRole role,
  required int minute,
  required int slot,
  required int recordedFen,
  required int amountFen,
  TripModeFilter mode = TripModeFilter.bus,
  String? applicationRecordId,
  Set<String> sources = const {'read'},
  Map<String, int>? eventPositions,
  Map<String, int>? evidencePositions,
  String? currencyCode = 'CNY',
  String currencySymbol = '¥',
  int minorUnitDigits = 2,
  int? confirmedBalanceFen,
  String? balanceAfterText,
  int balanceOffsetFen = 0,
}) => JourneyEvent<String>(
  payload: id,
  mode: mode,
  role: role,
  endpoint: JourneyEndpoint(
    line: mode == TripModeFilter.bus ? '345路' : '13号线',
    station: role == JourneyEventRole.entry ? '起点' : '终点',
    time: DateTime(2026, 10, 7, 11, minute),
  ),
  scopeKey: 'wallet-CNY',
  sourceIds: sources,
  cityCode: '1000',
  cityLabel: '北京',
  processPositions: eventPositions ?? {'read': slot},
  applicationRecordId: applicationRecordId,
  evidenceSource: JourneyEvidenceSource.cycle,
  amountText: role == JourneyEventRole.exit
      ? '-¥${(amountFen / 100).toStringAsFixed(2)}'
      : null,
  balanceAfterText: balanceAfterText,
  confirmedBalanceFen: confirmedBalanceFen,
  processBalance: JourneyProcessBalanceEvidence(
    recordedFen: recordedFen,
    balanceOffsetFen: balanceOffsetFen,
    amountFen: amountFen,
    currencyCode: currencyCode,
    currencySymbol: currencySymbol,
    minorUnitDigits: minorUnitDigits,
    positions: evidencePositions ?? {'read': slot},
  ),
);

JourneyEvent<String> _application(
  String id,
  JourneyEventRole role,
  int minute, {
  Set<String> sources = const {'read'},
}) => JourneyEvent<String>(
  payload: id,
  mode: TripModeFilter.bus,
  role: role,
  endpoint: JourneyEndpoint(
    line: '345路',
    time: DateTime(2026, 10, 7, 11, minute),
  ),
  scopeKey: 'wallet-CNY',
  sourceIds: sources,
  cityCode: '1000',
  applicationRecordId: 'application',
  evidenceSource: JourneyEvidenceSource.application,
  amountText: role == JourneyEventRole.exit ? '-¥2.00' : null,
);
