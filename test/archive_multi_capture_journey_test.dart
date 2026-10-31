import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';
import 'package:transit_card_analyzer/features/transit_analysis/balance_interpretation.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/features/trips/trip_cards_view.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_card.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_details.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_process_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_trip_matcher.dart';

typedef _Journey = JourneyPresentation<TripCardPresentation<ArchiveRecordKind>>;

void main() {
  test('同一原始1A进站由进行中更新为完成后只呈现完成行程并保留两批证据', () {
    final payloads = [
      _snapshot(rails: [_rail(status: 1, withExit: false)], marker: 'entry'),
      _snapshot(rails: [_rail()], marker: 'completed'),
    ];
    final history = _history(payloads);
    final before = _savedFields(history);

    final journeys = _journeys(history);

    expect(history.records, hasLength(2));
    expect(journeys, hasLength(1));
    expect(journeys.single.state, JourneyState.completed);
    expect(journeys.single.duration, const Duration(minutes: 28));
    expect(journeys.single.events, hasLength(3));
    expect(journeys.single.events.expand((event) => event.sourceIds).toSet(), {
      'read-0',
      'read-1',
    });
    _expectUnchanged(history, payloads, before);
  });

  test('八次相同完整读取只显示一段行程并保留全部原批次及十六侧详情', () {
    final payloads = [
      for (var i = 0; i < 8; i++)
        _snapshot(rails: [_rail()], marker: 'full-read-$i'),
    ];
    final history = _history(payloads);
    final before = _savedFields(history);

    final journeys = _journeys(history);

    expect(history.batches, hasLength(8));
    expect(history.records, hasLength(1));
    expect(history.records.single.sources, hasLength(8));
    expect(journeys, hasLength(1));
    expect(journeys.single.state, JourneyState.completed);
    expect(journeys.single.events, hasLength(16));
    expect(journeys.single.events.expand((event) => event.sourceIds).toSet(), {
      for (var i = 0; i < 8; i++) 'read-$i',
    });
    _expectUnchanged(history, payloads, before);
  });

  test('进行中的1A在后续被0x18消费两侧时仍与已完成行程共用原始1A证据', () {
    final application = _rail();
    final payloads = [
      _snapshot(rails: [_rail(status: 1, withExit: false)], marker: 'pending'),
      _snapshot(
        rails: [application],
        trips: [
          for (final entry in [true, false])
            _trip(
              entry: entry,
              applicationKey: TunionApplicationSide(
                rail: application,
                isEntry: entry,
              ).key,
            ),
        ],
        processes: [_cycle(entry: true), _cycle(entry: false)],
        marker: 'completed-by-transactions',
      ),
    ];
    final history = _history(payloads);
    final before = _savedFields(history);

    final journeys = _journeys(history);

    expect(journeys, hasLength(1));
    expect(journeys.single.state, JourneyState.completed);
    expect(journeys.single.events, hasLength(3));
    expect(
      journeys.single.events.map((event) => event.payload.source).toSet(),
      {ArchiveRecordKind.rail, ArchiveRecordKind.transaction},
    );
    expect(journeys.single.events.expand((event) => event.sourceIds).toSet(), {
      'read-0',
      'read-1',
    });
    _expectUnchanged(history, payloads, before);
  });

  test('独立读取的进站与出站不因交易序号连续或原始槽号相邻而跨批次配对', () {
    final payloads = [
      _snapshot(
        trips: [_trip(entry: true)],
        processes: [_cycle(entry: true)],
        marker: 'entry-only',
      ),
      _snapshot(
        trips: [_trip(entry: false)],
        processes: [_cycle(entry: false)],
        marker: 'exit-only',
      ),
    ];
    final history = _history(payloads);
    final before = _savedFields(history);

    final journeys = _journeys(history);

    expect(journeys, hasLength(2));
    expect(
      journeys.any((journey) => journey.state == JourneyState.completed),
      isFalse,
    );
    expect(
      journeys.map((journey) => journey.state),
      contains(JourneyState.inProgress),
    );
    _expectUnchanged(history, payloads, before);
  });

  test('相同0x18原文的未知到已知余额不拆散各自批次内已经完成的行程', () {
    final payloads = [
      _snapshot(
        trips: [_trip(entry: true), _trip(entry: false)],
        marker: 'unknown-balance',
      ),
      _snapshot(
        trips: [_trip(entry: true), _trip(entry: false, balance: 9700)],
        marker: 'known-balance',
      ),
    ];
    final history = _history(payloads);
    final before = _savedFields(history);

    final journeys = _journeys(history);

    expect(journeys, hasLength(1));
    expect(journeys.single.state, JourneyState.completed);
    expect(journeys.single.balanceAfterText, '¥ 97.00');
    expect(journeys.single.events, hasLength(4));
    _expectUnchanged(history, payloads, before);
  });

  test('相同0x18原文关联不同捕获的1A原文仍按完整原批次呈现一段行程', () {
    final first = _rail(issuerMarker: 1);
    final second = _rail(issuerMarker: 2);
    expect(first.rawHex, isNot(second.rawHex));
    final payloads = [
      for (final (index, application) in [first, second].indexed)
        _snapshot(
          rails: [application],
          trips: [
            for (final entry in [true, false])
              _trip(
                entry: entry,
                applicationKey: TunionApplicationSide(
                  rail: application,
                  isEntry: entry,
                ).key,
              ),
          ],
          marker: 'application-link-$index',
        ),
    ];
    final history = _history(payloads);
    final before = _savedFields(history);

    final journeys = _journeys(history);

    expect(journeys, hasLength(1));
    expect(journeys.single.state, JourneyState.completed);
    expect(journeys.single.events, hasLength(4));
    expect(journeys.single.events.expand((event) => event.sourceIds).toSet(), {
      'read-0',
      'read-1',
    });
    _expectUnchanged(history, payloads, before);
  });

  test('同批次重复的相同原始进站候选保持多义不得被全历史去重后恢复成完成', () {
    final payloads = [
      _snapshot(
        trips: [_trip(entry: true), _trip(entry: true), _trip(entry: false)],
        marker: 'ambiguous-duplicate-entry',
      ),
    ];
    final history = _history(payloads);
    final before = _savedFields(history);

    final journeys = _journeys(history);

    expect(
      journeys.any((journey) => journey.state == JourneyState.completed),
      isFalse,
    );
    expect(
      journeys.expand((journey) => journey.events).length,
      3,
      reason: '同一批次两个原始路径上的候选不能当作重复读取折叠',
    );
    _expectUnchanged(history, payloads, before);
  });

  test('旧批次的两个相同进站候选不得被后续干净完整行程吸收其中任意一个', () {
    final payloads = [
      _snapshot(
        trips: [_trip(entry: true), _trip(entry: true)],
        marker: 'two-ambiguous-pending-occurrences',
      ),
      _snapshot(
        trips: [_trip(entry: true), _trip(entry: false)],
        marker: 'clean-completed-capture',
      ),
    ];
    final history = _history(payloads);
    final before = _savedFields(history);

    final journeys = _journeys(history);

    expect(journeys, hasLength(3));
    expect(
      journeys.where((journey) => journey.state == JourneyState.completed),
      hasLength(1),
    );
    expect(
      journeys.where((journey) => journey.state == JourneyState.inProgress),
      hasLength(2),
    );
    expect(journeys.expand((journey) => journey.events).length, 4);
    _expectUnchanged(history, payloads, before);
  });

  test('相同站名和时间但原始1A进站终端不同的两批记录保持两段进行中', () {
    final payloads = [
      _snapshot(
        rails: [_rail(status: 1, withExit: false)],
        marker: 'first-entry-terminal',
      ),
      _snapshot(
        rails: [
          _rail(status: 1, withExit: false, entryTerminal: '0000003000010099'),
        ],
        marker: 'different-entry-terminal',
      ),
    ];
    final history = _history(payloads);
    final before = _savedFields(history);

    final journeys = _journeys(history);

    expect(journeys, hasLength(2));
    expect(
      journeys.every((journey) => journey.state == JourneyState.inProgress),
      isTrue,
    );
    expect(journeys.every((journey) => journey.events.length == 1), isTrue);
    _expectUnchanged(history, payloads, before);
  });

  test('相同交易原文的两个已确认余额冲突不能静默采用最新金额', () {
    final payloads = [
      _snapshot(
        trips: [_trip(entry: true), _trip(entry: false, balance: 9700)],
        marker: 'first-confirmed-balance',
      ),
      _snapshot(
        trips: [_trip(entry: true), _trip(entry: false, balance: 9600)],
        marker: 'conflicting-confirmed-balance',
      ),
    ];
    final history = _history(payloads);
    final before = _savedFields(history);

    final journeys = _journeys(history);

    expect(journeys, isNotEmpty);
    expect(
      journeys.every((journey) => journey.state == JourneyState.completed),
      isTrue,
    );
    if (journeys.length == 1) {
      expect(journeys.single.balanceAfterText, isNull);
    } else {
      expect(
        journeys.map((journey) => journey.balanceAfterText).toSet(),
        containsAll(['¥ 97.00', '¥ 96.00']),
      );
    }
    expect(journeys.expand((journey) => journey.events).length, 4);
    _expectUnchanged(history, payloads, before);
  });

  test('同一进站对应两个不同的已完成出站证据必须同时保留而不选择最新终点', () {
    final payloads = [
      _snapshot(rails: [_rail(destination: 2)], marker: 'destination-two'),
      _snapshot(rails: [_rail(destination: 3)], marker: 'destination-three'),
    ];
    final history = _history(payloads);
    final before = _savedFields(history);

    final journeys = _journeys(history);

    expect(journeys, hasLength(2));
    expect(
      journeys.every((journey) => journey.state == JourneyState.completed),
      isTrue,
    );
    expect(
      journeys.map((journey) => journey.end!.station).toSet(),
      hasLength(2),
    );
    expect(journeys.expand((journey) => journey.events).length, 4);
    _expectUnchanged(history, payloads, before);
  });

  test('八达通TU同一历史行程不随当前钱包观察变化拆分且不借用观察金额作行程后余额', () {
    for (final withVerifiedAccount in [false, true]) {
      final payloads = [
        _snapshot(
          rails: [_rail()],
          context: _octopusContext(
            10000,
            verifiedAmount: withVerifiedAccount ? 6000 : null,
            evidence: 'independent-account-read-a',
          ),
          marker: 'first-wallet-observation',
        ),
        _snapshot(
          rails: [_rail()],
          context: _octopusContext(
            9700,
            verifiedAmount: withVerifiedAccount ? 5700 : null,
            evidence: 'independent-account-read-b',
          ),
          marker: 'later-wallet-observation',
        ),
      ];
      final history = _history(payloads);
      final before = _savedFields(history);

      final journeys = _journeys(history);

      expect(journeys, hasLength(1), reason: 'verified=$withVerifiedAccount');
      expect(journeys.single.state, JourneyState.completed);
      expect(journeys.single.balanceAfterText, isNull);
      expect(journeys.single.events, hasLength(4));
      expect(
        history.batches.map((batch) {
          final interpretation =
              batch
                      .decoded
                      .snapshot!
                      .context
                      .extensions['balanceInterpretation']
                  as Map;
          expect(interpretation['product'], 'octopusTunion');
          expect(interpretation['semantics'], 'tuObservation');
          expect(interpretation['accountCurrency'], 'HKD');
          return interpretation['observedAmountMinor'];
        }).toSet(),
        {10000, 9700},
      );
      if (withVerifiedAccount) {
        expect(
          history.batches.map((batch) {
            final interpretation =
                batch
                        .decoded
                        .snapshot!
                        .context
                        .extensions['balanceInterpretation']
                    as Map;
            return interpretation['accountBalanceMinor'];
          }).toSet(),
          {6000, 5700},
        );
      }
      _expectUnchanged(history, payloads, before);
    }
  });

  test('八达通TU余额上下文语义账户币种或未知扩展不同不能按当前观察标量归一化合并', () {
    for (final difference in [
      'semantics',
      'accountCurrency',
      'unknownExtension',
    ]) {
      final changed = Map<String, dynamic>.from(
        _octopusContext(9700).extensions['balanceInterpretation'] as Map,
      );
      if (difference == 'semantics') {
        changed['semantics'] = 'unknown';
      } else if (difference == 'accountCurrency') {
        changed['accountCurrency'] = 'CNY';
      } else {
        changed['futureWalletMeaning'] = {'rawCode': '0007'};
      }
      final payloads = [
        _snapshot(
          rails: [_rail()],
          context: _octopusContext(10000),
          marker: 'known-wallet-semantics',
        ),
        _snapshot(
          rails: [_rail()],
          context: ArchiveContext(
            systemId: _context.systemId,
            applicationId: _context.applicationId,
            currencyCode: _context.currencyCode,
            minorUnitDigits: _context.minorUnitDigits,
            timeZoneOffsetMinutes: _context.timeZoneOffsetMinutes,
            clockBasis: _context.clockBasis,
            extensions: {'balanceInterpretation': changed},
          ),
          marker: 'different-wallet-$difference',
        ),
      ];
      final history = _history(payloads);
      final before = _savedFields(history);

      final journeys = _journeys(history);

      expect(journeys, hasLength(2), reason: difference);
      expect(
        journeys.every((journey) => journey.state == JourneyState.completed),
        isTrue,
      );
      expect(
        journeys.every((journey) => journey.balanceAfterText == null),
        isTrue,
      );
      expect(journeys.expand((journey) => journey.events).length, 4);
      _expectUnchanged(history, payloads, before);
    }
  });

  for (final (label, context) in [
    (
      '币种',
      const ArchiveContext(
        systemId: 'TU',
        applicationId: 'A000000632010105',
        currencyCode: 'HKD',
        minorUnitDigits: 2,
        timeZoneOffsetMinutes: 480,
        clockBasis: 'device-local-card-time-unverified',
      ),
    ),
    (
      '应用',
      const ArchiveContext(
        systemId: 'TU',
        applicationId: 'A000000632010106',
        currencyCode: 'CNY',
        minorUnitDigits: 2,
        timeZoneOffsetMinutes: 480,
        clockBasis: 'device-local-card-time-unverified',
      ),
    ),
    (
      '时钟',
      const ArchiveContext(
        systemId: 'TU',
        applicationId: 'A000000632010105',
        currencyCode: 'CNY',
        minorUnitDigits: 2,
        timeZoneOffsetMinutes: 480,
        clockBasis: 'different-captured-clock',
      ),
    ),
  ]) {
    test('相同原文处在不同$label上下文时保持两段已完成行程', () {
      final payloads = [
        _snapshot(rails: [_rail()], marker: 'first-context'),
        _snapshot(rails: [_rail()], context: context, marker: 'other-context'),
      ];
      final history = _history(payloads);
      final before = _savedFields(history);

      final journeys = _journeys(history);

      expect(journeys, hasLength(2));
      expect(
        journeys.every((journey) => journey.state == JourneyState.completed),
        isTrue,
      );
      expect(journeys.expand((journey) => journey.events).length, 4);
      _expectUnchanged(history, payloads, before);
    });
  }

  test('截短交易原文不能作为跨批次重复操作凭据且原始档案保持不变', () {
    final payloads = [
      for (var i = 0; i < 2; i++)
        jsonEncode(
          jsonDecode(
            _snapshot(trips: [_trip(entry: false)], marker: 'short-raw-$i'),
          )..['trips'][0]['rawHex'] = '000042AB',
        ),
    ];
    final history = _history(payloads);
    final before = _savedFields(history);

    final journeys = _journeys(history);

    expect(history.records, hasLength(1));
    expect(history.records.single.sources, hasLength(2));
    expect(journeys, hasLength(2));
    expect(journeys.every((journey) => journey.events.length == 1), isTrue);
    _expectUnchanged(history, payloads, before);
  });

  testWidgets('档案视图采用预先投影的行程并保留来源方式筛选及三份原始详情', (tester) async {
    final history = _history([
      _snapshot(rails: [_rail(status: 1, withExit: false)], marker: 'entry'),
      _snapshot(rails: [_rail()], marker: 'completed'),
    ]);
    final projection = presentArchiveTrips(
      history.records,
      batches: history.batches,
      onDiagnostics: (_) {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TripCardsView(
              entries: projection.entries,
              projectedJourneys: projection.journeys,
              sourceLabels: const {
                ArchiveRecordKind.transaction: '0x18 交易',
                ArchiveRecordKind.rail: '0x1A 轨道',
                ArchiveRecordKind.bus: '0x1A 公交',
                ArchiveRecordKind.process: '0x1E 过程',
              },
              summaryText: '合并后的归档行程',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TripEntryCard), findsOneWidget);
    expect(find.text('进行中 1'), findsNothing);

    await _selectFilter(tester, '全部来源', '0x18 交易');
    expect(find.byType(TripEntryCard), findsNothing);
    await _selectFilter(tester, '0x18 交易', '0x1A 轨道');
    expect(find.byType(TripEntryCard), findsOneWidget);

    await _selectFilter(tester, '全部方式', '公共汽电车');
    expect(find.byType(TripEntryCard), findsNothing);
    await _selectFilter(tester, '公共汽电车', '城市轨道交通');
    expect(find.byType(TripEntryCard), findsOneWidget);

    await tester.tap(find.byType(TripEntryCard));
    await tester.pumpAndSettle();
    expect(find.text('行程记录'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(3));
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    expect(find.byType(TripDetailRow), findsWidgets);
    expect(find.text('记录来源：0x1A 轨道记录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _selectFilter(
  WidgetTester tester,
  String current,
  String next,
) async {
  await tester.tap(find.text(current));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(MenuItemButton, next));
  await tester.pumpAndSettle();
}

List<_Journey> _journeys(ArchiveHistoryResult history) => presentArchiveTrips(
  history.records,
  batches: history.batches,
  onDiagnostics: (_) {},
).journeys;

ArchiveHistoryResult _history(List<String> payloads) => ArchiveHistory.project(
  ArchiveRows(
    card: const SavedCard(
      id: 'multi-capture-card',
      cardFingerprint: 'synthetic-multi-capture-fingerprint',
      cardType: 'china_tunion',
      identificationSource: 'test',
      cardNumber: '00000001',
      createdAt: 1,
      updatedAt: 8,
    ),
    batches: [
      for (var i = 0; i < payloads.length; i++)
        CardReadBatch(
          id: 'read-$i',
          cardId: 'multi-capture-card',
          cardFingerprint: 'synthetic-multi-capture-fingerprint',
          readAt: i + 1,
          parseVersion: 12,
          payloadJson: payloads[i],
        ),
    ],
  ),
);

String _snapshot({
  List<TransitRecord> rails = const [],
  List<TransitTrip> trips = const [],
  List<TUnionTripRecord> processes = const [],
  ArchiveContext context = _context,
  required String marker,
}) => CardSessionSnapshot(
  parseVersion: 12,
  context: context,
  cardCityCode: '1000',
  rails: rails,
  trips: trips,
  processTrips: processes,
  extensions: {
    'captureAttemptId': marker,
    'unknownCapturedField': {'raw': '0001', 'attempt': marker},
  },
  rawEvidence: [
    for (var i = 0; i < rails.length; i++)
      {'kind': 'record', 'sfi': 0x1A, 'number': 1, 'rawHex': rails[i].rawHex},
    for (var i = 0; i < processes.length; i++)
      {
        'kind': 'record',
        'sfi': 0x1E,
        'number': processes[i].isEntry ? 2 : 1,
        'rawHex': processes[i].rawHex,
      },
  ],
  recordProvenance: {
    for (var i = 0; i < rails.length; i++)
      'rails[$i]': {
        'sfi': 0x1A,
        'recordNumber': 1,
        'rawHex': rails[i].rawHex,
        'capturedDisplay': {
          'entry': {'line': '15号线', 'station': '金安桥'},
          'exit': {'line': '15号线', 'station': '终点${rails[i].exitStationId}'},
        },
      },
    for (var i = 0; i < processes.length; i++)
      'cycle[$i]': {
        'sfi': 0x1E,
        'recordNumber': processes[i].isEntry ? 2 : 1,
        'recordNumberIsReliable': true,
        'rawHex': processes[i].rawHex,
        'capturedDisplay': {
          'line': '15号线',
          'station': processes[i].isEntry ? '金安桥' : '终点站',
        },
      },
  },
).encode();

const _context = ArchiveContext(
  systemId: 'TU',
  applicationId: 'A000000632010105',
  currencyCode: 'CNY',
  minorUnitDigits: 2,
  timeZoneOffsetMinutes: 480,
  clockBasis: 'device-local-card-time-unverified',
);

ArchiveContext _octopusContext(
  int observedAmount, {
  int? verifiedAmount,
  String evidence = 'independent-account-read',
}) {
  final interpretation = BalanceInterpretation.fromCardInfo(
    TUnionCardInfo(
      applicationSerial: '03104850000000123456',
      balanceFen: observedAmount,
    ),
    parserId: CardParserIds.tunion,
    selectedAidHex: 'A000000632010105',
    verifiedAccountBalance: verifiedAmount == null
        ? null
        : VerifiedAccountBalance(
            amountMinor: verifiedAmount,
            currency: 'HKD',
            evidenceSource: evidence,
          ),
  );
  expect(interpretation.product, BalanceProduct.octopusTunion);
  expect(interpretation.semantics, BalanceSemantics.tuObservation);
  return ArchiveContext(
    systemId: _context.systemId,
    applicationId: _context.applicationId,
    currencyCode: _context.currencyCode,
    minorUnitDigits: _context.minorUnitDigits,
    timeZoneOffsetMinutes: _context.timeZoneOffsetMinutes,
    clockBasis: _context.clockBasis,
    extensions: {'balanceInterpretation': interpretation.toJson()},
  );
}

// Complete synthetic 85-byte 0x1A rail bodies, optionally with the documented
// 128-byte record envelope. Every side is decoded by the real parser.
TransitRecord _rail({
  int status = 2,
  bool withEntry = true,
  bool withExit = true,
  int destination = 2,
  int? issuerMarker,
  String entryTerminal = '0000003000010001',
}) {
  final raw = List<int>.filled(0x55, 0);
  raw[0] = status;
  if (withEntry) {
    _putHex(raw, 0x01, '1000');
    _putHex(raw, 0x05, '01011000FFFFFFFF');
    _putHex(raw, 0x15, '1000751301000001');
    _putHex(raw, 0x25, entryTerminal);
    _putHex(raw, 0x35, '20261031140229');
    raw[0x47] = 0x15;
    _putInt(raw, 0x4D, 10000);
  }
  if (withExit) {
    _putHex(raw, 0x03, '1000');
    _putHex(raw, 0x0D, '01011000FFFFFFFF');
    _putHex(raw, 0x1D, '1000751301000000');
    raw[0x24] = destination;
    _putHex(raw, 0x2D, '0000003000010002');
    _putHex(raw, 0x3C, '20261031143029');
    raw[0x48] = 0x15;
    _putInt(raw, 0x51, 300);
  }
  final payload = issuerMarker == null
      ? raw
      : <int>[
          0x27,
          1,
          0x7D,
          1,
          1,
          0,
          ...List<int>.filled(8, 0),
          ...raw,
          issuerMarker,
          ...List<int>.filled(28, 0),
        ];
  final parsed = const TUnionProcessParser().parseRailTransit(1, payload);
  expect(parsed, isNotNull);
  return parsed!;
}

TUnionTripRecord _cycle({required bool entry}) {
  final raw = List<int>.filled(48, 0);
  raw[0] = entry ? 3 : 4;
  _putHex(raw, 1, entry ? '0000003000010001' : '0000003000010002');
  raw[9] = 1;
  _putHex(raw, 0x0A, entry ? '00150001000100' : '00150002000100');
  _putInt(raw, 0x11, entry ? 0 : 300);
  _putInt(raw, 0x15, 10000);
  _putHex(raw, 0x19, entry ? '20261031140229' : '20261031143029');
  _putHex(raw, 0x20, '1000');
  _putHex(raw, 0x22, '01011000FFFFFFFF');
  final parsed = const TUnionProcessParser().parseCycleTrip(raw);
  expect(parsed, isNotNull);
  return parsed!;
}

TransitTrip _trip({required bool entry, int? balance, String? applicationKey}) {
  final process = _cycle(entry: entry);
  final raw = List<int>.filled(23, 0);
  raw[1] = entry ? 40 : 41;
  _putInt(raw, 5, entry ? 0 : 300);
  raw[9] = 9;
  _putHex(raw, 10, entry ? '003000010001' : '003000010002');
  _putHex(raw, 16, entry ? '20261031140229' : '20261031143029');
  return TransitTrip(
    time: process.time,
    amountFen: entry ? 0 : 300,
    overdraftLimitFen: 0,
    isConsume: true,
    isCompositeConsume: true,
    typeName: '复合消费',
    sequence: entry ? 40 : 41,
    terminalId: entry ? '003000010001' : '003000010002',
    cityCode: '1000',
    cityName: '北京市',
    lineLabel: '15号线',
    stationLabel: entry ? '金安桥' : '终点站',
    stationType: '地铁',
    appTypeName: '城市轨道交通',
    rideStatusName: entry ? '进站' : '出站',
    isEntry: entry,
    balanceAfterFen: balance,
    balanceAfterIsRecorded: balance == null ? null : false,
    displayProcessKey: cycleDisplayKey(process),
    displayApplicationKey: applicationKey,
    matchedProcessTrip: process,
    rawHex: _hex(raw),
  );
}

void _putHex(List<int> target, int start, String hex) {
  target.setRange(start, start + hex.length ~/ 2, [
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}

void _putInt(List<int> target, int start, int value) {
  for (var i = 0; i < 4; i++) {
    target[start + i] = (value >> ((3 - i) * 8)) & 0xFF;
  }
}

String _hex(List<int> raw) => raw
    .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join();

String _savedFields(ArchiveHistoryResult history) =>
    jsonEncode([for (final record in history.records) record.fields]);

void _expectUnchanged(
  ArchiveHistoryResult history,
  List<String> originalPayloads,
  String fieldsBefore,
) {
  expect(_savedFields(history), fieldsBefore);
  expect(history.batches, hasLength(originalPayloads.length));
  for (final batch in history.batches) {
    final index = int.parse(batch.id.split('-').last);
    expect(batch.decoded.rawJson, originalPayloads[index]);
    expect(batch.decoded.snapshot!.encode(), originalPayloads[index]);
  }
}
