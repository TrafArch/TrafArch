import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/features/trips/trip_filters.dart';

void main() {
  for (final newestFirst in [true, false]) {
    test(
      'fare adjustment pairs with exit in either input order ($newestFirst)',
      () {
        final adjustment = _fare();
        final exit = _exit();
        final journeys = projectJourneys(
          newestFirst ? [exit, adjustment] : [adjustment, exit],
        );

        expect(journeys, hasLength(1));
        final journey = journeys.single;
        expect(journey.state, JourneyState.completed);
        expect(journey.startsWithFareAdjustment, isTrue);
        expect(journey.events.map((event) => event.payload), ['fare', 'exit']);
        expect(journey.events.first.role, JourneyEventRole.fareAdjustment);
        expect(journey.start?.station, '补票地点');
        expect(journey.end?.station, '出站地点');
        expect(journey.duration, isNull);
        expect(journey.isCrossCity, isTrue);
        expect(journey.cityLabel, isNull);
        expect(journey.balanceAfterText, isNull);
      },
    );
  }

  test('same-city fare adjustment retains the accepting city label', () {
    final journey = projectJourneys([
      _exit(city: '3310', cityLabel: '杭州'),
      _fare(),
    ]).single;

    expect(journey.state, JourneyState.completed);
    expect(journey.isCrossCity, isFalse);
    expect(journey.cityLabel, '杭州');
  });

  test(
    'consecutive transaction sequences establish a pair without 1E slots',
    () {
      final journey = projectJourneys([_exit(slot: null), _fare(slot: null)])
          .single;

      expect(journey.state, JourneyState.completed);
      expect(journey.startsWithFareAdjustment, isTrue);
    },
  );

  test(
    'reliable adjacent physical slots establish a pair without sequences',
    () {
      final journey = projectJourneys([
        _exit(sequence: null),
        _fare(sequence: null),
      ]).single;

      expect(journey.state, JourneyState.completed);
    },
  );

  test(
    'physical slot evidence can bridge one missing transaction sequence',
    () {
      final journey = projectJourneys([_exit(sequence: null), _fare()]).single;

      expect(journey.state, JourneyState.completed);
    },
  );

  test('fare adjustment charge stays separate from the exit charge', () {
    final journey = projectJourneys([
      _exit(amount: '-¥2.00'),
      _fare(amount: '-¥3.00'),
    ]).single;

    expect(journey.amountText, '-¥2.00');
    expect(journey.fareAdjustmentAmountText, '-¥3.00');
    expect(journey.events.first.amountText, '-¥3.00');
    expect(journey.events.last.amountText, '-¥2.00');
  });

  test('confirmed exit balance survives fare adjustment pairing', () {
    final journey = projectJourneys([
      _exit(balance: '¥15.00', confirmedBalanceFen: 1500),
      _fare(),
    ]).single;

    expect(journey.balanceAfterText, '¥15.00');
  });

  test(
    'unpaired fare adjustment remains incomplete with its original details',
    () {
      final event = _fare(amount: '-¥3.00');
      final journey = projectJourneys([event]).single;

      expect(journey.state, JourneyState.incomplete);
      expect(journey.state, isNot(JourneyState.inProgress));
      expect(journey.start, isNull);
      expect(journey.end, isNull);
      expect(journey.duration, isNull);
      expect(journey.amountText, '-¥3.00');
      expect(journey.events.single, same(event));
      expect(journey.events.single.endpoint.station, '补票地点');
    },
  );

  final refused = <String, List<JourneyEvent<String>> Function()>{
    'different wallets': () => [_exit(scope: 'another-wallet'), _fare()],
    'unknown wallet': () => [_exit(scope: null), _fare(scope: null)],
    'different captures': () => [
      _exit(sources: {'other'}),
      _fare(),
    ],
    'empty capture identity': () => [
      _exit(sources: {''}),
      _fare(sources: {''}),
    ],
    'unknown adjustment city': () => [_exit(), _fare(city: null)],
    'unknown exit city': () => [_exit(city: null), _fare()],
    'erased adjustment city': () => [_exit(), _fare(city: 'FFFF')],
    'zero exit city': () => [_exit(city: '0000'), _fare()],
    'missing adjustment time': () => [_exit(), _fare(minute: null)],
    'missing exit time': () => [_exit(minute: null), _fare()],
    'reversed timestamps': () => [_exit(minute: 5), _fare()],
    'identical timestamps': () => [_exit(minute: 10), _fare()],
    'more than 24 hours': () => [_exit(minute: 1451), _fare()],
    'no sequence or slot evidence': () => [
      _exit(sequence: null, slot: null),
      _fare(sequence: null, slot: null),
    ],
    'slot gap without sequences': () => [
      _exit(sequence: null, slot: 1),
      _fare(sequence: null, slot: 3),
    ],
    'equal physical slots': () => [
      _exit(sequence: null),
      _fare(sequence: null, slot: 1),
    ],
    'sequence conflict despite adjacent slots': () => [
      _exit(sequence: 43),
      _fare(),
    ],
    'bus fare adjustment': () => [
      _exit(mode: TripModeFilter.bus),
      _fare(mode: TripModeFilter.bus),
    ],
    'unknown transport': () => [
      _exit(mode: TripModeFilter.other),
      _fare(mode: TripModeFilter.other),
    ],
    'mismatched transport': () => [_exit(mode: TripModeFilter.bus), _fare()],
  };
  for (final fault in refused.entries) {
    test('fare adjustment pairing rejects ${fault.key}', () {
      final events = fault.value();
      final journeys = projectJourneys(events);

      expect(journeys, hasLength(2));
      expect(
        journeys.where((journey) => journey.state == JourneyState.completed),
        isEmpty,
      );
      expect(journeys.expand((journey) => journey.events), containsAll(events));
    });
  }

  test('duplicate physical slots do not establish a fare adjustment pair', () {
    final events = [
      _exit(sequence: null),
      _fare(sequence: null),
      _event('duplicate-slot', JourneyEventRole.unknown, minute: 0, slot: 2),
    ];
    final journeys = projectJourneys(events);

    expect(journeys, hasLength(3));
    expect(
      journeys.where((journey) => journey.state == JourneyState.completed),
      isEmpty,
    );
  });

  test(
    'unknown time of a real entry blocks replacement by fare adjustment',
    () {
      final journeys = projectJourneys([
        _exit(),
        _fare(),
        _event('unknown-entry-time', JourneyEventRole.entry, minute: null),
      ]);
      expect(journeys, hasLength(3));
      expect(
        journeys.where((journey) => journey.state == JourneyState.completed),
        isEmpty,
      );
    },
  );

  test(
    'conflicting physical slots cannot be overridden by consecutive sequences',
    () {
      for (final slot in [1, 3]) {
        final journeys = projectJourneys([_exit(), _fare(slot: slot)]);
        expect(journeys, hasLength(2));
      }
      final journeys = projectJourneys([
        _exit(),
        _fare(),
        _event('duplicate-slot', JourneyEventRole.unknown, minute: 0, slot: 2),
      ]);
      expect(journeys, hasLength(3));
    },
  );

  for (final newestFirst in [true, false]) {
    test(
      'an unclosed real entry blocks a replacement origin ($newestFirst)',
      () {
        final events = [
          _event(
            'real-entry',
            JourneyEventRole.entry,
            minute: 0,
            sequence: 40,
            slot: 3,
          ),
          _fare(),
          _exit(),
        ];
        final journeys = projectJourneys(
          newestFirst ? events.reversed : events,
        );

        expect(journeys, hasLength(3));
        expect(
          journeys.where((journey) => journey.state == JourneyState.completed),
          isEmpty,
        );
        expect(
          journeys.expand((journey) => journey.events).length,
          events.length,
        );
      },
    );

    test('multiple fare adjustments remain ambiguous ($newestFirst)', () {
      final events = [
        _event(
          'earlier-fare',
          JourneyEventRole.fareAdjustment,
          minute: 0,
          sequence: 40,
          slot: 3,
        ),
        _fare(),
        _exit(),
      ];
      final journeys = projectJourneys(newestFirst ? events.reversed : events);

      expect(journeys, hasLength(3));
      expect(
        journeys.where((journey) => journey.state == JourneyState.completed),
        isEmpty,
      );
    });
  }

  test(
    'a previous normal exit closes the older entry before the fare adjustment',
    () {
      final journeys = projectJourneys([
        _exit(),
        _fare(),
        _event(
          'older-exit',
          JourneyEventRole.exit,
          minute: 5,
          sequence: 40,
          slot: 3,
        ),
        _event(
          'older-entry',
          JourneyEventRole.entry,
          minute: 0,
          sequence: 39,
          slot: 4,
        ),
      ]);

      expect(journeys, hasLength(2));
      expect(
        journeys.every((journey) => journey.state == JourneyState.completed),
        isTrue,
      );
      expect(
        journeys.where((journey) => journey.startsWithFareAdjustment),
        hasLength(1),
      );
      expect(
        journeys
            .expand((journey) => journey.events)
            .map((event) => event.payload),
        containsAll(['fare', 'exit', 'older-entry', 'older-exit']),
      );
    },
  );

  test(
    'an intervening unknown event cannot be skipped to match fare and exit',
    () {
      final journeys = projectJourneys([
        _exit(),
        _event('unknown', JourneyEventRole.unknown, minute: 15),
        _fare(),
      ]);

      expect(journeys, hasLength(3));
      expect(
        journeys.where((journey) => journey.state == JourneyState.completed),
        isEmpty,
      );
    },
  );

  test('fare adjustment does not become an ordinary entry balance anchor', () {
    final journeys = projectJourneys([
      _exit(amount: '-¥2.00', recordedFen: 1300, processAmountFen: 200),
      _fare(recordedFen: 1500, processAmountFen: 0),
    ]);

    expect(journeys, hasLength(1));
    expect(journeys.single.state, JourneyState.completed);
    expect(journeys.single.balanceAfterText, isNull);
    expect(journeys.single.events.first.processBalance!.recordedFen, 1500);
    expect(journeys.single.events.last.processBalance!.recordedFen, 1300);
  });
}

JourneyEvent<String> _fare({
  int? minute = 10,
  int? sequence = 41,
  int? slot = 2,
  String? scope = 'wallet-CNY',
  Set<String> sources = const {'read'},
  String? city = '3310',
  TripModeFilter mode = TripModeFilter.rail,
  String amount = '-¥0.00',
  int? recordedFen,
  int processAmountFen = 0,
}) => _event(
  'fare',
  JourneyEventRole.fareAdjustment,
  minute: minute,
  sequence: sequence,
  slot: slot,
  scope: scope,
  sources: sources,
  city: city,
  cityLabel: '杭州',
  mode: mode,
  amount: amount,
  recordedFen: recordedFen,
  processAmountFen: processAmountFen,
);

JourneyEvent<String> _exit({
  int? minute = 25,
  int? sequence = 42,
  int? slot = 1,
  String? scope = 'wallet-CNY',
  Set<String> sources = const {'read'},
  String? city = '3370',
  String cityLabel = '绍兴',
  TripModeFilter mode = TripModeFilter.rail,
  String amount = '-¥0.00',
  String? balance,
  int? confirmedBalanceFen,
  int? recordedFen,
  int processAmountFen = 0,
}) => _event(
  'exit',
  JourneyEventRole.exit,
  minute: minute,
  sequence: sequence,
  slot: slot,
  scope: scope,
  sources: sources,
  city: city,
  cityLabel: cityLabel,
  mode: mode,
  amount: amount,
  balance: balance,
  confirmedBalanceFen: confirmedBalanceFen,
  recordedFen: recordedFen,
  processAmountFen: processAmountFen,
);

JourneyEvent<String> _event(
  String id,
  JourneyEventRole role, {
  int? minute = 10,
  int? sequence,
  int? slot,
  String? scope = 'wallet-CNY',
  Set<String> sources = const {'read'},
  String? city = '3310',
  String cityLabel = '杭州',
  TripModeFilter mode = TripModeFilter.rail,
  String? amount,
  String? balance,
  int? confirmedBalanceFen,
  int? recordedFen,
  int processAmountFen = 0,
}) => JourneyEvent(
  payload: id,
  role: role,
  mode: mode,
  scopeKey: scope,
  sourceIds: sources,
  cityCode: city,
  cityLabel: cityLabel,
  sequence: sequence,
  processPositions: slot == null ? const {} : {'read': slot},
  endpoint: JourneyEndpoint(
    line: '4号线',
    station: role == JourneyEventRole.fareAdjustment ? '补票地点' : '出站地点',
    time: minute == null ? null : DateTime.utc(2026, 10, 30, 14, minute),
  ),
  amountText: amount,
  balanceAfterText: balance,
  confirmedBalanceFen: confirmedBalanceFen,
  processBalance: recordedFen == null
      ? null
      : JourneyProcessBalanceEvidence(
          recordedFen: recordedFen,
          amountFen: processAmountFen,
          currencyCode: 'CNY',
          currencySymbol: '¥',
          positions: slot == null ? const {} : {'read': slot},
        ),
);
