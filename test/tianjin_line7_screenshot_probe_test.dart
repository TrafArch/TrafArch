import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/reference_data/application/reference_data_controller.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/station_codes.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/features/scan/domain/scan_presentation.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_engine.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_presenter.dart';
import 'package:transit_card_analyzer/features/trips/trip_filters.dart';
import 'package:transit_card_analyzer/features/trips/trip_journey_adapter.dart';
import 'package:transit_card_analyzer/features/trips/trip_journey_evidence.dart';
import 'package:transit_card_analyzer/features/trips/trip_presentation_context.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_process_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_trip_matcher.dart';

// Screenshot field probes, NOT captured APDU responses or a complete card read.
// The screenshot supplies the times, types, terminals, 14-character location
// fields, 1E recorded balances/city/acquirer/reserved bytes and 18 sequences.
// It does not establish APDU wrapping, status words, physical record slots,
// card identity, GET BALANCE, overdraft or the 1E transaction-amount bytes.
//
// The 48-byte 1E bodies below use the production parser's documented layout;
// their amounts are explicitly synthetic variants (0/90/900 fen). The direct
// 18 models have synthetic amounts (entry=0, exit=90) and overdraft=0. Their
// rawHex is a synthetic standard-layout body, never a claimed screenshot APDU.
// Exact timestamps establish display association despite different 18/1E POS.
// No physical slot, card number or wallet-balance anchor is invented.
//
// The developer-supplied TU city database stores these keys directly in
// region_天津_1121: M0.i0.a / 00070018 and 00070020. Expectations preserve
// these raw keys, without adding the city prefix or changing number bases.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  late ReferenceDataController reference;
  late KnowledgeBase knowledge;

  setUpAll(() async {
    directory = Directory.systemTemp.createTempSync('trafarch-tianjin7-probe-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => directory.path);
    reference = ReferenceDataController(rootBundle);
    await reference.initialize();
    expect(reference.error, isNull);
    knowledge = reference.knowledge!;
    expect(knowledge.loadIssues, isEmpty);
  });

  tearDownAll(() {
    reference.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, null);
    directory.deleteSync(recursive: true);
  });

  for (final syntheticAmountFen in [0, 90, 900]) {
    test('截图1E字段经实际解析及发布库定位天津7号线，合成金额$syntheticAmountFen分', () {
      for (final point in [_entry, _exit]) {
        final record = _cycle(point, syntheticAmountFen);
        final cycle = record.trip!;
        _expectScreenshotFields(record, point, syntheticAmountFen);

        final match = reference.resolveCycleStationMatch(
          cycle.cityCode,
          cycle.lineStationCode,
          terminalId: cycle.terminalId,
          time: cycle.time,
          appType: cycle.appTypeCode,
        );
        expect(match.confidence, StationMatchConfidence.exact);
        expect(match.lineName, '7号线');
        expect(match.stationName, point.station);
        expect(match.entry?.sourceKey, point.sourceKey);
        expect(match.entry?.system, 'tu');

        final display = _display(reference, Currency.cny);
        final entry = ProcessTripEntry(cycle);
        final info = describeTripEntry(entry, display, remote: false);
        expect(info.title, '${point.status} · ${point.station}');
        expect(info.line, '7号线');
        expect(info.rawHex, cycle.rawHex);
        expect(info.fields, contains(('终端编号', point.terminal1E)));
        expect(info.fields, contains(('线路站点字段（原始）', point.field)));
        expect(info.fields, contains(('城市代码', '1121')));
        expect(info.fields, contains(('受理方标识', '11131121FFFFFFFF')));
        expect(info.fields, contains(('记录余额', point.recordedBalanceText)));
        final event = describeJourneyEvent(entry, display, info);
        expect(event.mode, TripModeFilter.rail);
        expect(event.role, point.role);
        expect(event.cityCode, '1121');
        expect(event.endpoint.station, point.station);
        expect(event.endpoint.line, '7号线');
        expect(event.balanceAfterText, isNull);
        expect(event.confirmedBalanceFen, isNull);
      }
    });

    test('截图时间关联经分析及实时行程投影为丽江道至天塔，合成1E金额$syntheticAmountFen分', () {
      final card = _card(syntheticAmountFen: syntheticAmountFen);
      final analysis = AnalysisEngine(knowledge).analyze(card);
      final view = ScanPresentation(TransitReadOutcome(card), knowledge);
      expect(view.tunionDetected, isTrue);
      expect(view.cityUnionDetected, isFalse);
      expect(view.dualApplicationDetected, isFalse);
      expect(view.cityUnionFiles, isEmpty);
      expect(view.cityUnionTransactions, isEmpty);
      expect(card.info.applicationSerial, isNull);
      expect(card.info.balanceFen, isNull);
      expect(analysis.wallet.balanceFen, isNull);
      expect(view.analysis!.wallet.balanceFen, isNull);
      expect(view.transitProcessRecords, hasLength(2));
      expect(view.cycleProcessTrips, hasLength(2));

      for (final result in [analysis, view.analysis!]) {
        expect(result.trips, hasLength(2));
        for (final point in [_entry, _exit]) {
          final transaction = card.transactions.singleWhere(
            (transaction) => transaction.sequence == point.sequence,
          );
          final cycle = card.transitProcessRecords
              .singleWhere((record) => record.trip!.time == point.time)
              .trip!;
          final trip = result.trips.singleWhere(
            (trip) => trip.sequence == point.sequence,
          );
          expect(trip.cityCode, '1121');
          expect(trip.lineLabel, '7号线');
          expect(trip.stationLabel, point.station);
          expect(trip.stationConfidence, StationMatchConfidence.exact);
          expect(trip.appTypeName, '城市轨道交通');
          expect(trip.isCompositeConsume, isTrue);
          expect(trip.rideStatusName, point.status);
          expect(trip.rideStatusSource, isNull);
          expect(trip.isEntry, point.cycleType == 0x03);
          expect(trip.time, point.time);
          expect(trip.terminalId, point.terminal18);
          expect(trip.rawHex, transaction.rawHex);
          expect(trip.displayProcessKey, cycleDisplayKey(cycle));
          expect(trip.displayApplicationKey, isNull);
          expect(cycle.lineStationCode, point.field);
          expect(cycle.terminalId, point.terminal1E);
          expect(cycle.balanceFen, point.recordedBalanceFen);
          expect(transaction.amountFen, point.syntheticTransactionAmountFen);
          expect(transaction.rawType, 0x09);
          expect(transaction.overdraftLimitFen, 0);
          expect(transaction.recordNumber, isNull);
          expect(transaction.rawHex, hasLength(46));
        }
      }

      final live = _live(view, reference);
      expect(live.stream, hasLength(2));
      expect(
        live.stream.every((entry) => entry is TransactionTripEntry),
        isTrue,
      );
      expect(live.events.map((event) => event.sequence), [62, 61]);
      for (final entry in live.stream) {
        expect(live.evidence[entry]!.processPositions, isEmpty);
        expect(live.evidence[entry]!.applicationRecordId, isNull);
      }
      for (final event in live.events) {
        expect(event.mode, TripModeFilter.rail);
        expect(event.cityCode, '1121');
        expect(event.scopeKey, 'live:TU:CNY');
        expect(event.evidenceSource, JourneyEvidenceSource.transaction);
        expect(event.processPositions, isEmpty);
        expect(event.balanceAfterText, isNull);
        expect(event.confirmedBalanceFen, isNull);
        expect(event.processBalance, isNull);
      }
      final entryEvent = live.events.singleWhere(
        (event) => event.sequence == 61,
      );
      final exitEvent = live.events.singleWhere(
        (event) => event.sequence == 62,
      );
      expect(entryEvent.role, JourneyEventRole.entry);
      expect(exitEvent.role, JourneyEventRole.exit);
      expect(entryEvent.endpoint.station, '丽江道');
      expect(exitEvent.endpoint.station, '天塔');
      expect(entryEvent.endpoint.time, DateTime(2026, 2, 8, 18, 59, 21));
      expect(exitEvent.endpoint.time, DateTime(2026, 2, 8, 19, 14, 49));

      final journey = projectJourneys(live.events).single;
      expect(journey.state, JourneyState.completed);
      expect(journey.mode, TripModeFilter.rail);
      expect(journey.start?.line, '7号线');
      expect(journey.start?.station, '丽江道');
      expect(journey.end?.line, '7号线');
      expect(journey.end?.station, '天塔');
      expect(journey.duration, const Duration(minutes: 15, seconds: 28));
      expect(journey.events, hasLength(2));
      expect(journey.balanceAfterText, isNull);
      expect(journey.isCrossCity, isFalse);
      // This debit is a fixture value, not proof of the screenshot's fare.
      expect(journey.amountText, '-¥0.90');
    });
  }

  test('截图未给物理槽位时，独立1E两端不凭时间相近补造完整行程', () {
    final card = _card(syntheticAmountFen: 0, includeTransactions: false);
    final view = ScanPresentation(TransitReadOutcome(card), knowledge);
    final live = _live(view, reference);
    expect(live.stream, hasLength(2));
    expect(live.stream.every((entry) => entry is ProcessTripEntry), isTrue);
    expect(live.events.map((event) => event.endpoint.station), ['天塔', '丽江道']);
    expect(live.events.map((event) => event.role), [
      JourneyEventRole.exit,
      JourneyEventRole.entry,
    ]);
    for (final event in live.events) {
      expect(event.sequence, isNull);
      expect(event.processPositions, isEmpty);
      expect(event.balanceAfterText, isNull);
      expect(event.processBalance, isNull);
    }
    final journeys = projectJourneys(live.events);
    expect(journeys, hasLength(2));
    expect(
      journeys.any((journey) => journey.state == JourneyState.completed),
      isFalse,
    );
    expect(
      journeys.every((journey) => journey.balanceAfterText == null),
      isTrue,
    );
    expect(
      card.transitProcessRecords.map((record) => record.trip!.balanceFen),
      [1720, 1810],
    );
  });
}

typedef _ScreenshotPoint = ({
  int sequence,
  int cycleType,
  String terminal18,
  String terminal1E,
  String field,
  String timestamp,
  DateTime time,
  int recordedBalanceFen,
  String recordedBalanceHex,
  String recordedBalanceText,
  String reservedHex,
  String station,
  String sourceKey,
  String status,
  JourneyEventRole role,
  int syntheticTransactionAmountFen,
});

final _ScreenshotPoint _entry = (
  sequence: 61,
  cycleType: 0x03,
  terminal18: '413180114327',
  terminal1E: '0000000007180605',
  field: '00070018000000',
  timestamp: '20260208185921',
  time: DateTime(2026, 2, 8, 18, 59, 21),
  recordedBalanceFen: 1810,
  recordedBalanceHex: '00000712',
  recordedBalanceText: '¥18.10',
  reservedHex: '000000000000',
  station: '丽江道',
  sourceKey: '00070018',
  status: '进站',
  role: JourneyEventRole.entry,
  syntheticTransactionAmountFen: 0,
);

final _ScreenshotPoint _exit = (
  sequence: 62,
  cycleType: 0x04,
  terminal18: '413180114512',
  terminal1E: '0000000007200609',
  field: '00070020000000',
  timestamp: '20260208191449',
  time: DateTime(2026, 2, 8, 19, 14, 49),
  recordedBalanceFen: 1720,
  recordedBalanceHex: '000006B8',
  recordedBalanceText: '¥17.20',
  reservedHex: '020000000000',
  station: '天塔',
  sourceKey: '00070020',
  status: '出站',
  role: JourneyEventRole.exit,
  syntheticTransactionAmountFen: 90,
);

TUnionProcessRecord _cycle(_ScreenshotPoint point, int syntheticAmountFen) {
  final hex =
      '${_hex(point.cycleType, 2)}${point.terminal1E}01${point.field}'
      '${_hex(syntheticAmountFen, 8)}${point.recordedBalanceHex}'
      '${point.timestamp}112111131121FFFFFFFF${point.reservedHex}';
  final raw = _bytes(hex);
  expect(raw, hasLength(48));
  final trip = const TUnionProcessParser().parseCycleTrip(raw);
  expect(trip, isNotNull);
  return TUnionProcessRecord(
    sfi: 0x1E,
    recordNumber: 0,
    recordNumberIsReliable: false,
    recordName: '截图字段合成探针（无物理槽位）',
    raw: raw,
    trip: trip,
  );
}

void _expectScreenshotFields(
  TUnionProcessRecord record,
  _ScreenshotPoint point,
  int syntheticAmountFen,
) {
  final cycle = record.trip!;
  expect(record.recordNumberIsReliable, isFalse);
  expect(cycle.typeCode, point.cycleType);
  expect(cycle.appTypeCode, 0x01);
  expect(cycle.terminalId, point.terminal1E);
  expect(cycle.lineStationCode, point.field);
  expect(cycle.lineStationCode, hasLength(14));
  expect(cycle.lineCode, '0007');
  expect(cycle.stationCode, point == _entry ? '0018' : '0020');
  expect(cycle.operatorCode, '0000');
  expect(cycle.amountFen, syntheticAmountFen);
  expect(cycle.balanceFen, point.recordedBalanceFen);
  expect(cycle.time, point.time);
  expect(cycle.cityCode, '1121');
  expect(cycle.acquirerId, '11131121FFFFFFFF');
  expect(cycle.rawHex, record.rawHex.replaceAll(' ', ''));
  expect(cycle.rawHex!.substring(42, 50), point.recordedBalanceHex);
  expect(cycle.rawHex!.substring(84), point.reservedHex);
}

ParsedCard _card({
  required int syntheticAmountFen,
  bool includeTransactions = true,
}) => ParsedCard(
  parserId: CardParserIds.tunion,
  parserName: '交通联合',
  // No identity or current-wallet response is visible in this screenshot.
  info: const TUnionCardInfo(balanceFen: null),
  transactions: [
    if (includeTransactions)
      for (final point in [_exit, _entry])
        TUnionTransaction(
          sequence: point.sequence,
          overdraftLimitFen: 0,
          amountFen: point.syntheticTransactionAmountFen,
          rawType: 0x09,
          terminalId: point.terminal18,
          time: point.time,
          // Synthetic 23-byte 18 body. Null recordNumber does not claim a slot.
          rawHex:
              '${_hex(point.sequence, 4)}000000'
              '${_hex(point.syntheticTransactionAmountFen, 8)}09'
              '${point.terminal18}${point.timestamp}',
        ),
  ],
  transitProcessRecords: [
    for (final point in [_exit, _entry]) _cycle(point, syntheticAmountFen),
  ],
);

typedef _LiveProbe = ({
  List<TripEntry> stream,
  Map<TripEntry, LiveJourneyEvidence> evidence,
  List<JourneyEvent<TripEntryInfo>> events,
});

_LiveProbe _live(ScanPresentation view, ReferenceDataController reference) {
  final rails = [
    for (final record in view.transitProcessRecords) ?record.railTransit,
  ];
  final buses = [
    for (final record in view.transitProcessRecords) ?record.busTransit,
  ];
  final stream = buildTripStream(
    trips: view.analysis!.trips,
    rails: rails,
    buses: buses,
    processTrips: view.cycleProcessTrips,
  );
  final evidence = buildLiveJourneyEvidence(
    stream: stream,
    processRecords: view.transitProcessRecords,
    rails: rails,
    buses: buses,
  );
  final display = _display(reference, view.cardCurrency);
  return (
    stream: stream,
    evidence: evidence,
    events: [
      for (final entry in stream)
        describeJourneyEvent(
          entry,
          display,
          describeTripEntry(entry, display, remote: false),
          applicationRecordId: evidence[entry]?.applicationRecordId,
          processPositions: evidence[entry]?.processPositions ?? const {},
        ),
    ],
  );
}

TripPresentationContext _display(
  ReferenceDataController reference,
  Currency currency,
) => TripPresentationContext(
  currency: currency,
  cityNameOf: reference.cityNameOf,
  resolveStationMatch: reference.resolveStationMatch,
  resolveCycleStationMatch: reference.resolveCycleStationMatch,
  resolveLineName: reference.resolveLineName,
  resolveBusLocation: reference.resolveBusLocation,
);

String _hex(int value, int width) =>
    value.toRadixString(16).toUpperCase().padLeft(width, '0');

List<int> _bytes(String hex) => [
  for (var index = 0; index < hex.length; index += 2)
    int.parse(hex.substring(index, index + 2), radix: 16),
];
