import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_application_display.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';
import 'package:transit_card_analyzer/features/reference_data/application/reference_data_controller.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_card.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_presenter.dart';
import 'package:transit_card_analyzer/features/trips/trip_filters.dart';
import 'package:transit_card_analyzer/features/trips/trip_journey_adapter.dart';
import 'package:transit_card_analyzer/features/trips/trip_presentation_context.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_process_parser.dart';

// Complete 1E bodies at slots 1/2 in transit_card_log_20261104_174831.txt.
// Both raw acceptance cities are 3370. Independently checked native TU rows:
// Shaoxing M0.W.a 33700121 = ["", "绍兴城际", "钱清"], and
// Ningbo M0.W.a 33201135 = ["", "宁波城际", "宁波"]. A card's acceptance
// city must not hide a station in another city's table or rewrite raw cities.
const _reportedHex = {
  1:
      '0441310188306200000A1135150100000000000000000005DC20261104094123'
      '337003493370FFFFFFFF000000000000',
  2:
      '0341310143052900000A01211A0400000000000000000005DC20261104074947'
      '337003493370FFFFFFFF000000000000',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  late ReferenceDataController reference;

  setUpAll(() async {
    directory = Directory.systemTemp.createTempSync('trafarch-intercity-log-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => directory.path);
    reference = ReferenceDataController(rootBundle);
    await reference.initialize();
    expect(reference.knowledge!.loadIssues, isEmpty);
  });

  tearDownAll(() {
    reference.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, null);
    directory.deleteSync(recursive: true);
  });

  test(
    'reported same-acceptance-city intercity ride resolves both endpoints',
    () {
      final records = _reportedRecords();
      final journey = projectJourneys(_liveEvents(records, reference)).single;

      _expectReportedJourney(journey);
      _expectRawRecords(records);
    },
  );

  test(
    'new captured intercity display retains cross-city station evidence',
    () {
      final records = _savedRecords(reference, restoreFields: false);
      final before = jsonEncode([for (final record in records) record.fields]);
      final projection = presentArchiveTrips(records, onDiagnostics: (_) {});
      final journey = projectJourneys([
        for (final entry in projection.entries) entry.journeyEvent!,
      ]).single;

      _expectReportedJourney(journey);
      expect(jsonEncode([for (final record in records) record.fields]), before);
      _expectSavedRaw(records);
    },
  );

  test('captured intercity endpoints and cities survive JSON restore', () {
    final records = _savedRecords(reference, restoreFields: true);
    final before = jsonEncode([for (final record in records) record.fields]);
    final projection = presentArchiveTrips(records, onDiagnostics: (_) {});
    final journey = projectJourneys([
      for (final entry in projection.entries) entry.journeyEvent!,
    ]).single;

    _expectReportedJourney(journey);
    expect(jsonEncode([for (final record in records) record.fields]), before);
    _expectSavedRaw(records);
  });

  testWidgets('reported intercity card uses generic rail heading', (
    tester,
  ) async {
    final journey = projectJourneys(_liveEvents(_reportedRecords(), reference))
        .single;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TripEntryCard(
              info: journey.events.first.payload,
              remote: false,
              onTap: () {},
              journey: journey,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('轨道交通'), findsOneWidget);
    expect(find.text('绍兴轨道交通'), findsNothing);
    expect(find.text('宁波轨道交通'), findsNothing);
    expect(find.text('钱清'), findsOneWidget);
    expect(find.text('宁波'), findsOneWidget);
    expect(find.text('绍兴城际'), findsOneWidget);
    expect(find.text('宁波城际'), findsOneWidget);
    expect(find.text('11351501000000'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

void _expectReportedJourney<T>(JourneyPresentation<T> journey) {
  expect(journey.mode, TripModeFilter.rail);
  expect(journey.state, JourneyState.completed);
  expect(journey.events, hasLength(2));
  expect(journey.start?.station, '钱清');
  expect(journey.start?.line, '绍兴城际');
  expect(journey.end?.station, '宁波');
  expect(journey.end?.line, '宁波城际');
  expect(_civilParts(journey.start?.time), [2026, 11, 4, 7, 49, 47]);
  expect(_civilParts(journey.end?.time), [2026, 11, 4, 9, 41, 23]);
  expect(journey.duration, const Duration(seconds: 6696));
  expect(journey.isCrossCity, isTrue);
  expect(journey.cityLabel, isNull);
}

List<TUnionProcessRecord> _reportedRecords() => [
  for (final entry in _reportedHex.entries)
    TUnionProcessRecord(
      sfi: 0x1E,
      recordNumber: entry.key,
      recordName: '循环记录${entry.key}',
      raw: _bytes(entry.value),
      trip: const TUnionProcessParser().parseCycleTrip(_bytes(entry.value)),
    ),
];

void _expectRawRecords(List<TUnionProcessRecord> records) {
  expect(records.map((record) => record.recordNumber), [1, 2]);
  expect(records.map((record) => record.trip!.cityCode), ['3370', '3370']);
  expect(records.map((record) => record.trip!.appTypeCode), [0x0A, 0x0A]);
  expect(records.map((record) => record.trip!.amountFen), [0, 0]);
  expect(records.map((record) => record.trip!.balanceFen), [1500, 1500]);
  expect(records.map((record) => record.trip!.lineStationCode), [
    '11351501000000',
    '01211A04000000',
  ]);
  expect(records.map((record) => record.trip!.rawHex), _reportedHex.values);
}

List<JourneyEvent<TripEntryInfo>> _liveEvents(
  List<TUnionProcessRecord> records,
  ReferenceDataController reference,
) {
  final display = _display(reference);
  final positions = buildProcessJourneyPositions(records);
  return [
    for (final source in records)
      describeJourneyEvent(
        ProcessTripEntry(source.trip!),
        display,
        describeTripEntry(
          ProcessTripEntry(source.trip!),
          display,
          remote: false,
        ),
        processPositions: positions[source.trip!]!,
      ),
  ];
}

List<ArchiveHistoryRecord> _savedRecords(
  ReferenceDataController reference, {
  required bool restoreFields,
}) {
  const context = ArchiveContext(
    systemId: 'TU',
    applicationId: 'A000000632010105',
    currencyCode: 'CNY',
    minorUnitDigits: 2,
    clockBasis: 'captured-local',
    timeZoneOffsetMinutes: 480,
  );
  final records = _reportedRecords();
  final snapshot = CardSessionSnapshot(
    context: context,
    processTrips: [for (final record in records) record.trip!],
  );
  final encoded = snapshot.encode();
  final restored = CardSessionSnapshot.decode(encoded)!;
  expect(restored.encode(), encoded);
  _expectRawRecords(records);
  final cycle = (jsonDecode(restored.encode()) as Map)['cycle'] as List;
  return [
    for (var i = 0; i < records.length; i++)
      ArchiveHistoryRecord(
        kind: ArchiveRecordKind.process,
        fields: _jsonFields({
          ...Map<String, dynamic>.from(cycle[i] as Map),
          'capturedDisplay': captureProcessDisplay(
            reference.knowledge!,
            records[i].trip!,
          ),
        }, restore: restoreFields),
        context: context,
        cardCityCode: '3370',
        sources: [
          ArchiveRecordSource('intercity-capture', 'cycle[$i]', 14, {
            'record': {
              'sfi': 0x1E,
              'recordNumber': records[i].recordNumber,
              'recordNumberIsReliable': true,
              'rawHex': records[i].trip!.rawHex,
            },
          }),
        ],
      ),
  ];
}

Map<String, dynamic> _jsonFields(
  Map<String, dynamic> fields, {
  required bool restore,
}) => restore
    ? Map<String, dynamic>.from(jsonDecode(jsonEncode(fields)) as Map)
    : fields;

void _expectSavedRaw(List<ArchiveHistoryRecord> records) {
  expect(records.map((record) => record.fields['cityCode']), ['3370', '3370']);
  expect(records.map((record) => record.fields['rawHex']), _reportedHex.values);
  expect(records.map((record) => record.fields['amountFen']), [0, 0]);
  expect(records.map((record) => record.fields['balanceFen']), [1500, 1500]);
}

TripPresentationContext _display(ReferenceDataController reference) =>
    TripPresentationContext(
      currency: Currency.cny,
      cityNameOf: reference.cityNameOf,
      resolveStationMatch: reference.resolveStationMatch,
      resolveCycleStationMatch: reference.resolveCycleStationMatch,
      resolveLineName: reference.resolveLineName,
      resolveBusLocation: reference.resolveBusLocation,
    );

List<int> _bytes(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

List<int>? _civilParts(DateTime? time) => time == null
    ? null
    : [time.year, time.month, time.day, time.hour, time.minute, time.second];
