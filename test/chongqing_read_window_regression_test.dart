import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_controller.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';
import 'package:transit_card_analyzer/features/reference_data/application/reference_data_controller.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/station_codes.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/features/scan/domain/scan_presentation.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_presenter.dart';
import 'package:transit_card_analyzer/features/trips/trip_filters.dart';
import 'package:transit_card_analyzer/features/trips/trip_journey_adapter.dart';
import 'package:transit_card_analyzer/features/trips/trip_journey_evidence.dart';
import 'package:transit_card_analyzer/features/trips/trip_presentation_context.dart';
import 'package:transit_card_analyzer/platform/storage/log_exporter.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/local/apdu_exchange.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_reader.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_trip_matcher.dart';

// The two fixture windows are separate physical reads. Transaction/process
// payloads are captured evidence; public identity and GET BALANCE below are
// synthetic. No real card number is replayed, and no reference asset is edited.
//
// SIMULATED continuation is explicitly NOT a captured F4 response: the later
// log never requested F4#6/#7/#8. Those test responses reuse the earlier read's
// captured 1E slots #3/#4/#5, to prove behavior only IF a subsequent read returns
// them. Unspecified APDUs receive a fixture boundary 6A83, not a claimed card SW.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  late ReferenceDataController reference;
  late KnowledgeBase knowledge;
  late List<Map<String, dynamic>> windows;

  setUpAll(() async {
    directory = Directory.systemTemp.createTempSync('trafarch-cq-windows-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => directory.path);
    reference = ReferenceDataController(rootBundle);
    await reference.initialize();
    expect(reference.error, isNull);
    knowledge = reference.knowledge!;
    expect(knowledge.loadIssues, isEmpty);
    final fixture = jsonDecode(
      await File('test/fixtures/chongqing_read_windows.json').readAsString(),
    ) as Map<String, dynamic>;
    windows = (fixture['windows'] as List).cast<Map<String, dynamic>>();
    expect(windows, hasLength(2));
  });

  tearDownAll(() {
    reference.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, null);
    directory.deleteSync(recursive: true);
  });

  test('重庆前一晚独立会话十笔交易只关联本次收到的五条1E', () async {
    final replay = await _readWindow(windows[0], balanceFen: 790);
    _expectWindow(replay, _early, firstSequence: 2212, knowledge: knowledge);
    _expectApplicationLinks(replay, {2212, 2211, 2210}, knowledge);
    _expectReferenceNames(reference, replay, _early);
  });

  test('重庆次日独立会话十笔交易不借用前一晚已读到的进站证据', () async {
    final replay = await _readWindow(windows[1], balanceFen: 540);
    _expectWindow(replay, _later, firstSequence: 2215, knowledge: knowledge);
    _expectApplicationLinks(replay, {2215, 2214, 2213}, knowledge);
    _expectReferenceNames(reference, replay, _later);

    final view = ScanPresentation(TransitReadOutcome(replay.card), knowledge);
    final trip = view.analysis!.trips.singleWhere((t) => t.sequence == 2210);
    expect(trip.terminalId, '413180034103');
    expect(trip.amountFen, 0);
    expect(trip.rideStatusName, isNull);
    expect(trip.isEntry, isFalse);
    expect(trip.lineLabel, isNull);
    expect(trip.stationLabel, isNull);
    final events = _liveEvents(view, reference);
    final unknown = events.singleWhere((event) => event.sequence == 2210);
    expect(unknown.role, JourneyEventRole.unknown);
    expect(unknown.mode, TripModeFilter.other);
    final journeys = projectJourneys(events);
    final related = journeys
        .where(
          (journey) => journey.events.any((event) => event.sequence == 2210),
        )
        .toList();
    expect(related, hasLength(1));
    expect(related.single.state, JourneyState.incomplete);
    expect(related.single.start, isNull);
    expect(related.single.end, isNull);
    expect(
      journeys.any(
        (journey) =>
            journey.events.any((event) => event.sequence == 2210) &&
            journey.events.any((event) => event.sequence == 2211),
      ),
      isFalse,
    );
  });

  test('重庆前一晚2210与2211合成鹿山到学堂湾并保留450分及790分余额', () async {
    final replay = await _readWindow(windows[0], balanceFen: 790);
    final view = ScanPresentation(TransitReadOutcome(replay.card), knowledge);
    final journey = _journeyWithSequence(
      projectJourneys(_liveEvents(view, reference)),
      2210,
    );
    _expectLushanJourney(journey);
    expect(
      journey.events.map((event) => event.sequence),
      unorderedEquals([2210, 2211]),
    );
    expect(
      view.analysis!.trips
          .singleWhere((trip) => trip.sequence == 2211)
          .balanceAfterFen,
      790,
    );
    // Raw file-specific terminals remain different: the time/role evidence
    // establishes the association without rewriting the original 0x18 POS.
    expect(
      replay.card.transactions
          .singleWhere((t) => t.sequence == 2210)
          .terminalId,
      '413180034103',
    );
    expect(replay.cycles[2].trip!.terminalId, '1022401000000000');
  });

  test('SIMULATED F4第6至8条补读后才恢复2210及旧的5号线到10号线行程', () async {
    final replay = await _readWindow(
      windows[1],
      balanceFen: 540,
      simulatedContinuationFrom: windows[0],
    );
    final expected = [..._later, ..._simulatedContinuation];
    _expectWindow(replay, expected, firstSequence: 2215, knowledge: knowledge);
    _expectReferenceNames(reference, replay, expected);
    expect(
      replay.commands,
      containsAll(['00B206F400', '00B207F400', '00B208F400']),
    );
    expect(
      replay.cycles.skip(5).map((record) => record.rawHex),
      _splitHex(windows[0]['cycles'] as String, 48).skip(2).map(_spacedHex),
    );
    final view = ScanPresentation(TransitReadOutcome(replay.card), knowledge);
    final journeys = projectJourneys(_liveEvents(view, reference));
    _expectLushanJourney(_journeyWithSequence(journeys, 2210));
    final earlier = _journeyWithSequence(journeys, 2208);
    expect(earlier.state, JourneyState.completed);
    expect(earlier.start?.line, '5号线');
    expect(earlier.start?.station, '石桥铺');
    expect(earlier.end?.line, '10号线');
    expect(earlier.end?.station, '鹿山');
    expect(earlier.duration, const Duration(hours: 1, minutes: 7, seconds: 12));
    expect(_money(earlier.amountText), '-¥3.50');
    expect(_money(earlier.balanceAfterText), '¥12.40');
  });

  test('重庆两个实测窗口及SIMULATED补读经stage和JSON恢复后与实时投影一致', () async {
    for (final scenario in [
      (window: 0, balance: 790, simulated: false),
      (window: 1, balance: 540, simulated: false),
      (window: 1, balance: 540, simulated: true),
    ]) {
      final replay = await _readWindow(
        windows[scenario.window],
        balanceFen: scenario.balance,
        simulatedContinuationFrom: scenario.simulated ? windows[0] : null,
      );
      final view = ScanPresentation(TransitReadOutcome(replay.card), knowledge);
      final live = projectJourneys(_liveEvents(view, reference));
      final archived = await _archiveJourneys(
        view,
        'cq-window-${scenario.window}-simulated-${scenario.simulated}',
        DateTime.parse(windows[scenario.window]['capturedAt'] as String),
      );
      expect(
        archived.map(_journeySummary).toList(),
        live.map(_journeySummary).toList(),
        reason: '${scenario.window}, SIMULATED=${scenario.simulated}',
      );
      if (scenario.window == 0 || scenario.simulated) {
        _expectLushanJourney(_journeyWithSequence(archived, 2210));
      } else {
        final unknown = _journeyWithSequence(archived, 2210);
        expect(unknown.state, JourneyState.incomplete);
        expect(unknown.events.single.role, JourneyEventRole.unknown);
      }
    }
  });
}

class _Replay {
  const _Replay(this.card, this.commands);
  final ParsedCard card;
  final List<String> commands;
  List<TUnionProcessRecord> get cycles => [
    for (final record in card.transitProcessRecords)
      if (record.sfi == 0x1E) record,
  ];
}

Future<_Replay> _readWindow(
  Map<String, dynamic> window, {
  required int balanceFen,
  Map<String, dynamic>? simulatedContinuationFrom,
}) async {
  final public = List<int>.filled(30, 0)
    ..setRange(0, 8, [0, 0, 0x69, 0, 0, 0, 0, 0])
    ..setRange(8, 10, [2, 1])
    ..setRange(10, 20, [
      0x31,
      0x99,
      0x99,
      0x99,
      0x99,
      0x99,
      0x99,
      0x99,
      0x99,
      1,
    ])
    ..setRange(20, 28, [0x20, 0x26, 1, 1, 0x20, 0x99, 0x12, 0x31]);
  final management = List<int>.filled(60, 0)..setRange(6, 8, [0x69, 0]);
  final transactions = _splitHex(window['transactions'] as String, 23);
  final capturedCycles = _splitHex(window['cycles'] as String, 48);
  final cycles = [
    ...capturedCycles,
    // SIMULATED F4#6/#7/#8: captured prior #3/#4/#5, not measured later slots.
    if (simulatedContinuationFrom != null)
      ..._splitHex(simulatedContinuationFrom['cycles'] as String, 48).skip(2),
  ];
  final responses = <String, List<int>>{
    '00A40000023F0000': [0x90, 0],
    '00A4040008A00000063201010500': [0x90, 0],
    '00B0950000': [...public, 0x90, 0],
    '00B0970000': [...management, 0x90, 0],
    '805C000204': [
      (balanceFen >> 24) & 0xFF,
      (balanceFen >> 16) & 0xFF,
      (balanceFen >> 8) & 0xFF,
      balanceFen & 0xFF,
      0x90,
      0,
    ],
    '00B201C500': [..._hex(window['transactions'] as String), 0x90, 0],
    '00B201D400': [..._hex(window['rail'] as String), 0x90, 0],
    '00B202D400': [..._hex(window['bus'] as String), 0x90, 0],
    '00B201F500': [..._hex(window['cycles'] as String), 0x90, 0],
    for (final (index, raw) in transactions.indexed)
      '00B2${_byte(index + 1)}C400': [..._hex(raw), 0x90, 0],
    for (final (index, raw) in cycles.indexed)
      '00B2${_byte(index + 1)}F400': [..._hex(raw), 0x90, 0],
  };
  final commands = <String>[];
  final unit = CommonUnitTu(
    ApduExchange(
      transceive: (command) async {
        final key = command.map(_byte).join();
        commands.add(key);
        return responses[key] ?? const [0x6A, 0x83];
      },
    ),
  );
  final info = CardInfo();
  final records = <ApduRecord>[];
  expect(await unit.select(info, records), isTrue);
  final card = await unit.read(info, records);
  expect(card, isNotNull);
  expect(card!.info.balanceFen, balanceFen);
  expect(card.info.applicationSerial, '31999999999999999901');
  expect(card.info.cityCode, '6900');
  expect(commands, contains('00B201F500'));
  return _Replay(card, commands);
}

void _expectWindow(
  _Replay replay,
  List<_CycleExpectation> expected, {
  required int firstSequence,
  required KnowledgeBase knowledge,
}) {
  expect(replay.card.transactions, hasLength(10));
  expect(replay.cycles, hasLength(expected.length));
  expect(
    replay.card.transactions.map((transaction) => transaction.sequence),
    List.generate(10, (index) => firstSequence - index),
  );
  expect(
    replay.cycles.map((record) => record.recordNumber),
    List.generate(expected.length, (index) => index + 1),
  );
  expect(
    replay.cycles.every((record) => record.recordNumberIsReliable),
    isTrue,
  );
  final trips = ScanPresentation(
    TransitReadOutcome(replay.card),
    knowledge,
  ).analysis!.trips;
  expect(trips, hasLength(10));
  for (final (index, transaction) in replay.card.transactions.indexed) {
    final trip = trips.singleWhere(
      (trip) => trip.sequence == transaction.sequence,
    );
    expect(trip.terminalId, transaction.terminalId);
    expect(trip.rawHex, transaction.rawHex);
    expect(trip.amountFen, transaction.amountFen);
    expect(trip.time, transaction.time);
    if (index >= expected.length) {
      expect(trip.displayProcessKey, isNull, reason: '${transaction.sequence}');
      expect(
        trip.matchedProcessTrip,
        isNull,
        reason: '${transaction.sequence}',
      );
      expect(trip.rideStatusName, isNull, reason: '${transaction.sequence}');
      continue;
    }
    final wanted = expected[index];
    final record = replay.cycles[index].trip!;
    expect(transaction.sequence, wanted.sequence);
    expect(record.lineStationCode, wanted.field);
    expect(record.typeCode, wanted.type);
    expect(record.appTypeCode, wanted.busLine == null ? 1 : 2);
    expect(record.cityCode, '6900');
    expect(trip.displayProcessKey, cycleDisplayKey(record));
    expect(trip.matchedProcessTrip?.rawHex, record.rawHex);
    expect(trip.cityCode, '6900');
    if (wanted.busLine != null) {
      expect(trip.rideStatusName, '单次消费');
      expect(trip.appTypeName, '公共汽电车');
      expect(trip.resolvedBusLineLabel, wanted.busLine);
      expect(trip.lineLabel, isNot(contains('号线')));
      expect(trip.stationLabel, isNot('大龙山'));
      expect(trip.stationLabel, isNot('鹿山'));
    } else {
      expect(trip.rideStatusName, wanted.type == 3 ? '进站' : '出站');
      expect(trip.lineLabel, wanted.line);
      expect(trip.stationLabel, wanted.station);
      expect(trip.stationConfidence, StationMatchConfidence.exact);
    }
  }
}

void _expectApplicationLinks(
  _Replay replay,
  Set<int> linked,
  KnowledgeBase knowledge,
) {
  final trips = ScanPresentation(
    TransitReadOutcome(replay.card),
    knowledge,
  ).analysis!.trips;
  for (final trip in trips) {
    expect(
      trip.displayApplicationKey != null,
      linked.contains(trip.sequence),
      reason: '1A link for ${trip.sequence}',
    );
  }
}

void _expectReferenceNames(
  ReferenceDataController reference,
  _Replay replay,
  List<_CycleExpectation> expected,
) {
  for (final (index, wanted) in expected.indexed) {
    final trip = replay.cycles[index].trip!;
    final match = reference.resolveCycleStationMatch(
      '6900',
      trip.lineStationCode,
      terminalId: trip.terminalId,
      time: trip.time,
      appType: trip.appTypeCode,
    );
    if (wanted.busLine != null) {
      expect(match.isUnmatched, isTrue);
      final bus = reference.resolveBusLocation('6900', trip.lineStationCode);
      expect(bus.lineLabel, wanted.busLine);
      expect(bus.match.stationName ?? '', isEmpty);
    } else {
      expect(match.confidence, StationMatchConfidence.exact);
      expect(match.lineName, wanted.line);
      expect(match.stationName, wanted.station);
      expect(match.entry?.sourceField, 'M0.e0.a');
      expect(match.entry?.sourceKey, wanted.sourceKey);
      expect(
        match.entry?.rawValueJson,
        jsonEncode(['', wanted.line, wanted.station]),
      );
    }
  }
}

List<JourneyEvent<TripEntryInfo>> _liveEvents(
  ScanPresentation view,
  ReferenceDataController reference,
) {
  final rails = [for (final r in view.transitProcessRecords) ?r.railTransit];
  final buses = [for (final r in view.transitProcessRecords) ?r.busTransit];
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
  final display = TripPresentationContext(
    currency: view.cardCurrency,
    cityNameOf: reference.cityNameOf,
    resolveStationMatch: reference.resolveStationMatch,
    resolveCycleStationMatch: reference.resolveCycleStationMatch,
    resolveLineName: reference.resolveLineName,
    resolveBusLocation: reference.resolveBusLocation,
  );
  return [
    for (final entry in stream)
      describeJourneyEvent(
        entry,
        display,
        describeTripEntry(entry, display, remote: false),
        applicationRecordId: evidence[entry]?.applicationRecordId,
        processPositions: evidence[entry]?.processPositions ?? const {},
      ),
  ];
}

Future<List<JourneyPresentation<TripEntryInfo>>> _archiveJourneys(
  ScanPresentation view,
  String batch,
  DateTime capturedAt,
) async {
  final database = AppDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  );
  final controller = ArchiveController(
    CardRepository(database),
    const MethodChannelLogExporter(),
    (_) {},
  );
  try {
    controller.stage(view, batch, capturedAt, const []);
    expect(controller.pending, isNotNull);
    expect(controller.pending!.transactionCount, 10);
    final encoded = controller.pending!.sessionDataJson!;
    final restored = CardSessionSnapshot.decode(encoded)!;
    expect(restored.encode(), encoded);
    expect(
      restored.trips.map(_tripSummary),
      view.analysis!.trips.map(_tripSummary),
    );
    expect(
      restored.processTrips.map((trip) => trip.rawHex),
      view.cycleProcessTrips.map((trip) => trip.rawHex),
    );
    final json = jsonDecode(restored.encode()) as Map<String, dynamic>;
    final provenance = json['recordProvenance'] as Map;
    final records = <ArchiveHistoryRecord>[
      for (final section in const {
        'trips': ArchiveRecordKind.transaction,
        'rails': ArchiveRecordKind.rail,
        'buses': ArchiveRecordKind.bus,
        'cycle': ArchiveRecordKind.process,
      }.entries)
        for (final (index, fields) in (json[section.key] as List).indexed)
          ArchiveHistoryRecord(
            kind: section.value,
            fields: fields as Map<String, dynamic>,
            context: restored.context,
            cardCityCode: restored.cardCityCode,
            sources: [
              ArchiveRecordSource(
                batch,
                '${section.key}[$index]',
                restored.parseVersion,
                provenance['${section.key}[$index]'],
              ),
            ],
          ),
    ];
    final projection = presentArchiveTrips(records, onDiagnostics: (_) {});
    expect(projection.transactionCount, 10);
    return projectJourneys([
      for (final entry in projection.entries) entry.journeyEvent!,
    ]);
  } finally {
    controller.dispose();
    await database.close();
  }
}

Object _tripSummary(TransitTrip trip) => (
  trip.sequence,
  trip.terminalId,
  trip.time.millisecondsSinceEpoch,
  trip.amountFen,
  trip.lineLabel,
  trip.stationLabel,
  trip.rideStatusName,
  trip.displayProcessKey,
  trip.displayApplicationKey,
  trip.matchedProcessTrip?.rawHex,
  trip.balanceAfterFen,
);

Object _journeySummary(JourneyPresentation<TripEntryInfo> journey) => (
  journey.state,
  journey.mode,
  _endpointSummary(journey.start),
  _endpointSummary(journey.end),
  journey.duration,
  _money(journey.amountText),
  _money(journey.balanceAfterText),
  journey.events.map((event) => event.sequence).join(','),
);

Object? _endpointSummary(JourneyEndpoint? endpoint) => endpoint == null
    ? null
    : (
        endpoint.line,
        endpoint.station,
        endpoint.time == null
            ? null
            : (
                endpoint.time!.year,
                endpoint.time!.month,
                endpoint.time!.day,
                endpoint.time!.hour,
                endpoint.time!.minute,
                endpoint.time!.second,
              ),
      );

JourneyPresentation<TripEntryInfo> _journeyWithSequence(
  List<JourneyPresentation<TripEntryInfo>> journeys,
  int sequence,
) => journeys.singleWhere(
  (journey) => journey.events.any((event) => event.sequence == sequence),
);

void _expectLushanJourney(JourneyPresentation<TripEntryInfo> journey) {
  expect(journey.state, JourneyState.completed);
  expect(journey.mode, TripModeFilter.rail);
  expect(journey.start?.line, '10号线');
  expect(journey.start?.station, '鹿山');
  expect(journey.end?.line, '3号线');
  expect(journey.end?.station, '学堂湾');
  expect(journey.duration, const Duration(hours: 1, minutes: 40, seconds: 57));
  expect(_money(journey.amountText), '-¥4.50');
  expect(_money(journey.balanceAfterText), '¥7.90');
}

String? _money(String? value) {
  final text = value?.replaceAll(RegExp(r'\s+'), '');
  // Live consumption labels include a minus on zero; archived formatting
  // omits it. Compare the same zero amount without changing either source.
  return text == '-¥0.00' ? '¥0.00' : text;
}

String _byte(int value) =>
    value.toRadixString(16).padLeft(2, '0').toUpperCase();
List<int> _hex(String value) => [
  for (var offset = 0; offset < value.length; offset += 2)
    int.parse(value.substring(offset, offset + 2), radix: 16),
];
String _spacedHex(String value) => _hex(value).map(_byte).join(' ');
List<String> _splitHex(String value, int bytes) => [
  for (var offset = 0; offset < value.length; offset += bytes * 2)
    value.substring(offset, offset + bytes * 2),
];

class _CycleExpectation {
  const _CycleExpectation(
    this.sequence,
    this.field,
    this.type, {
    this.line,
    this.station,
    this.sourceKey,
    this.busLine,
  });
  final int sequence;
  final String field;
  final int type;
  final String? line;
  final String? station;
  final String? sourceKey;
  final String? busLine;
}

const _early = [
  _CycleExpectation(2212, '01940000000000', 6, busLine: '194'),
  _CycleExpectation(
    2211,
    '03040200000000',
    4,
    line: '3号线',
    station: '学堂湾',
    sourceKey: '69000304',
  ),
  _CycleExpectation(
    2210,
    '10221000000000',
    3,
    line: '10号线',
    station: '鹿山',
    sourceKey: '69001022',
  ),
  _CycleExpectation(
    2209,
    '10220600000000',
    4,
    line: '10号线',
    station: '鹿山',
    sourceKey: '69001022',
  ),
  _CycleExpectation(
    2208,
    '05141200000000',
    3,
    line: '5号线',
    station: '石桥铺',
    sourceKey: '69000514',
  ),
];
const _later = [
  _CycleExpectation(2215, '05090022000000', 6, busLine: '509'),
  _CycleExpectation(
    2214,
    '18164203000000',
    4,
    line: '18号线',
    station: '石坪桥',
    sourceKey: '69001816',
  ),
  _CycleExpectation(
    2213,
    '18074202000000',
    3,
    line: '18号线',
    station: '巴滨路湿地公园',
    sourceKey: '69001807',
  ),
  _CycleExpectation(2212, '01940000000000', 6, busLine: '194'),
  _CycleExpectation(
    2211,
    '03040200000000',
    4,
    line: '3号线',
    station: '学堂湾',
    sourceKey: '69000304',
  ),
];
// SIMULATED later F4#6/#7/#8, copied from the earlier captured slots #3/#4/#5.
const _simulatedContinuation = [
  _CycleExpectation(
    2210,
    '10221000000000',
    3,
    line: '10号线',
    station: '鹿山',
    sourceKey: '69001022',
  ),
  _CycleExpectation(
    2209,
    '10220600000000',
    4,
    line: '10号线',
    station: '鹿山',
    sourceKey: '69001022',
  ),
  _CycleExpectation(
    2208,
    '05141200000000',
    3,
    line: '5号线',
    station: '石桥铺',
    sourceKey: '69000514',
  ),
];
