import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/features/trips/trip_filters.dart';

// Synthetic counterexamples around the real Shenyang balance relationship.
// These test the public projection, including slot validation and pairing.
void main() {
  test('相邻1E公交与已确认充值账本闭合时补齐较早行程余额', () {
    final events = _events();
    expect(_journey(events).balanceAfterText, '¥4.60');
    expect(events[2].processBalance!.recordedFen, 1000);
    expect(events[3].processBalance!.recordedFen, 1000);
  });

  test('充值桥接只在显示时应用上海额度偏移一次', () {
    expect(_journey(_events(offset: -800)).balanceAfterText, '¥-3.40');
  });

  test('没有充值时也可由相邻已确认公交扣款闭合', () {
    expect(
      _journey(_events(fault: 'no-recharge-needed')).balanceAfterText,
      '¥4.60',
    );
  });

  for (final fault in [
    'missing-recharge',
    'wrong-recharge-amount',
    'wrong-recharge-balance',
    'unknown-recharge-type',
    'unconfirmed-recharge',
    'recharge-other-batch',
    'recharge-other-wallet',
    'recharge-other-clock',
    'recharge-same-time',
    'anchor-other-batch',
    'anchor-other-wallet',
    'anchor-other-clock',
    'anchor-slot-gap',
    'anchor-duplicate-slot',
    'unconfirmed-anchor',
    'anchor-balance-conflict',
    'anchor-amount-conflict',
    'unknown-interval-event',
    'unknown-time-event',
    'duplicate-recharge',
    'intervening-consume',
    'exit-confirmed-conflict',
    'anchor-wrong-currency',
  ]) {
    test('充值桥接证据不完整或冲突时保持未知: $fault', () {
      expect(_journey(_events(fault: fault)).balanceAfterText, isNull);
    });
  }
}

JourneyPresentation<String> _journey(List<JourneyEvent<String>> events) =>
    projectJourneys(events).singleWhere(
      (journey) => journey.events.any((event) => event.payload == 'exit'),
    );

List<JourneyEvent<String>> _events({String? fault, int offset = 0}) {
  final anchorBalance = fault == 'no-recharge-needed' ? 280 : 1280;
  JourneyEvent<String> payment({bool duplicate = false}) => JourneyEvent(
    payload: duplicate ? 'duplicate-recharge' : 'recharge',
    mode: TripModeFilter.other,
    role: JourneyEventRole.unknown,
    scopeKey: fault == 'recharge-other-wallet' ? 'wallet2' : 'wallet',
    sourceIds: fault == 'recharge-other-batch'
        ? const {'other'}
        : const {'read'},
    evidenceSource: JourneyEvidenceSource.transaction,
    endpoint: JourneyEndpoint(
      time: fault == 'recharge-other-clock'
          ? DateTime.utc(2026, 10, 17, 13, 28)
          : DateTime(2026, 10, 17, 13, fault == 'recharge-same-time' ? 26 : 28),
    ),
    confirmedBalanceFen: fault == 'unconfirmed-recharge'
        ? null
        : fault == 'wrong-recharge-balance'
        ? 1470
        : 1460,
    walletDeltaFen: fault == 'unknown-recharge-type'
        ? null
        : fault == 'wrong-recharge-amount'
        ? 900
        : 1000,
  );
  final anchor = JourneyEvent<String>(
    payload: 'anchor',
    mode: TripModeFilter.bus,
    role: JourneyEventRole.single,
    scopeKey: fault == 'anchor-other-wallet' ? 'wallet2' : 'wallet',
    sourceIds: fault == 'anchor-other-batch' ? const {'other'} : const {'read'},
    evidenceSource: JourneyEvidenceSource.transaction,
    endpoint: JourneyEndpoint(
      time: fault == 'anchor-other-clock'
          ? DateTime.utc(2026, 10, 17, 14, 18)
          : DateTime(2026, 10, 17, 14, 18),
    ),
    cityCode: '2210',
    processPositions: {'read': fault == 'anchor-slot-gap' ? 6 : 7},
    confirmedBalanceFen: fault == 'unconfirmed-anchor'
        ? null
        : fault == 'anchor-balance-conflict'
        ? 1290
        : anchorBalance,
    walletDeltaFen: fault == 'anchor-amount-conflict' ? -190 : -180,
    processBalance: JourneyProcessBalanceEvidence(
      recordedFen: anchorBalance,
      amountFen: 180,
      currencyCode: fault == 'anchor-wrong-currency' ? 'HKD' : 'CNY',
      currencySymbol: '¥',
      positions: {'read': fault == 'anchor-slot-gap' ? 6 : 7},
    ),
  );
  return [
    anchor,
    if (fault != 'missing-recharge' && fault != 'no-recharge-needed') payment(),
    for (final isEntry in [false, true])
      JourneyEvent<String>(
        payload: isEntry ? 'entry' : 'exit',
        mode: TripModeFilter.rail,
        role: isEntry ? JourneyEventRole.entry : JourneyEventRole.exit,
        scopeKey: 'wallet',
        sourceIds: const {'read'},
        endpoint: JourneyEndpoint(
          time: DateTime(2026, 10, 17, isEntry ? 11 : 13, isEntry ? 46 : 26),
        ),
        cityCode: '2210',
        processPositions: {'read': isEntry ? 9 : 8},
        confirmedBalanceFen: !isEntry && fault == 'exit-confirmed-conflict'
            ? 470
            : null,
        processBalance: JourneyProcessBalanceEvidence(
          recordedFen: 1000,
          amountFen: isEntry ? 0 : 540,
          currencyCode: 'CNY',
          currencySymbol: '¥',
          positions: {'read': isEntry ? 9 : 8},
          balanceOffsetFen: offset,
        ),
      ),
    if (fault == 'duplicate-recharge') payment(duplicate: true),
    if (fault == 'anchor-duplicate-slot')
      anchor.withPayload('duplicate-anchor'),
    if (fault == 'unknown-interval-event' ||
        fault == 'unknown-time-event' ||
        fault == 'intervening-consume')
      JourneyEvent<String>(
        payload: 'other-payment',
        mode: TripModeFilter.other,
        role: JourneyEventRole.unknown,
        scopeKey: 'wallet',
        sourceIds: const {'read'},
        endpoint: JourneyEndpoint(
          time: fault == 'unknown-time-event'
              ? null
              : DateTime(2026, 10, 17, 13, 29),
        ),
        evidenceSource: JourneyEvidenceSource.transaction,
        walletDeltaFen: fault == 'intervening-consume' ? -100 : null,
        confirmedBalanceFen: 1360,
      ),
  ];
}
