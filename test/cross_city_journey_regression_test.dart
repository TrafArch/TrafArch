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
import 'package:transit_card_analyzer/features/trips/trip_cards_view.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_card.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_presenter.dart';
import 'package:transit_card_analyzer/features/trips/trip_filters.dart';
import 'package:transit_card_analyzer/features/trips/trip_journey_adapter.dart';
import 'package:transit_card_analyzer/features/trips/trip_presentation_context.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_process_parser.dart';

// Exact 1E slots 15/16 from transit_card_log_20261027_230916.txt, without
// public identity files or status words. Each endpoint retains its own city.
const _reportedHex = {
  15:
      '040000413106236069010003003500000000000000000005DC20261026073814'
      '331001663310FFFFFFFF000000000000',
  16:
      '030000413101908195010089001000000000000000000005DC20261026060651'
      '337003493370FFFFFFFF000000000000',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  late ReferenceDataController reference;

  setUpAll(() async {
    directory = Directory.systemTemp.createTempSync('trafarch-cross-city-');
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
    'reported Hangzhou fare adjustment and Shaoxing exit form one journey',
    () {
      // Original 1E slots 2/3 from transit_card_log_20261030_181503.txt.
      const hex = {
        2: '040000413101908075010089001000000000000000000005DC20261030155834337003493370FFFFFFFF000000000000',
        3: '080000413101984302010004001400000000000000000005DC20261030143450331001663310FFFFFFFF000000000000',
      };
      final records = [
        for (final slot in hex.entries)
          TUnionProcessRecord(
            sfi: 0x1E,
            recordNumber: slot.key,
            recordName: '循环记录${slot.key}',
            raw: _bytes(slot.value),
            trip: const TUnionProcessParser().parseCycleTrip(
              _bytes(slot.value),
            ),
          ),
      ];
      final positions = buildProcessJourneyPositions(records);
      final display = _display(reference);
      final events = [
        for (final record in records)
          describeJourneyEvent(
            ProcessTripEntry(record.trip!),
            display,
            describeTripEntry(
              ProcessTripEntry(record.trip!),
              display,
              remote: false,
            ),
            processPositions: positions[record.trip!]!,
          ),
      ];
      final journeys = projectJourneys(events);
      expect(journeys, hasLength(1));
      final journey = journeys.single;
      expect(journey.state, JourneyState.completed);
      expect(journey.start?.station, '景芳');
      expect(journey.start?.line, '4号线');
      expect(journey.end?.station, '中国轻纺城');
      expect(journey.end?.line, '1号线');
      expect(journey.isCrossCity, isTrue);
      expect(journey.duration, isNull);
      expect(
        journey.events.any((event) => event.role == JourneyEventRole.entry),
        isFalse,
      );
      expect(journey.events.first.role.name, 'fareAdjustment');
      expect(journey.balanceAfterText, isNull);
      expect(records.last.trip!.rawHex, hex[3]);
    },
  );

  test('reported Shaoxing entry and Hangzhou exit form one live journey', () {
    final records = _reportedRecords();
    final positions = buildProcessJourneyPositions(records);
    final display = _display(reference);
    final events = [
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
    expect(events.first.processPositions, {'live': 15});
    expect(events.last.processPositions, {'live': 16});
    expect(events.map((event) => event.cityCode), ['3310', '3370']);

    final journeys = projectJourneys(events);
    expect(journeys, hasLength(1));
    _expectReportedJourney(journeys.single);
    expect(records.first.trip!.rawHex, _reportedHex[15]);
    expect(records.last.trip!.rawHex, _reportedHex[16]);
  });

  test(
    'saved reported endpoints pair after JSON restore without rewriting cities',
    () {
      final records = _savedRecords(reference);
      final before = jsonEncode([for (final record in records) record.fields]);
      final projection = presentArchiveTrips(records, onDiagnostics: (_) {});
      final events = [
        for (final entry in projection.entries) entry.journeyEvent!,
      ];
      expect(events.first.processPositions, {'saved-capture': 15});
      expect(events.last.processPositions, {'saved-capture': 16});

      final journeys = projectJourneys(events);
      expect(journeys, hasLength(1));
      _expectReportedJourney(journeys.single);
      expect(jsonEncode([for (final record in records) record.fields]), before);
      expect(records.first.fields['cityCode'], '3310');
      expect(records.last.fields['cityCode'], '3370');
    },
  );

  testWidgets(
    'saved cross city rail card shows both stations with generic heading',
    (tester) async {
      final projection = presentArchiveTrips(
        _savedRecords(reference),
        onDiagnostics: (_) {},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TripCardsView(
                entries: projection.entries,
                sourceLabels: archiveTripSourceLabels,
                summaryText: projection.summaryText,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('轨道交通'), findsOneWidget);
      expect(find.text('绍兴轨道交通'), findsNothing);
      expect(find.text('杭州轨道交通'), findsNothing);
      expect(find.text('中国轻纺城'), findsOneWidget);
      expect(find.text('善贤'), findsOneWidget);
      expect(find.text('1小时31分钟'), findsOneWidget);
      expect(find.text('异地用卡'), findsOneWidget);
      expect(find.byKey(const ValueKey('journey-arrow')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final mode in [TripModeFilter.rail, TripModeFilter.bus]) {
    test('$mode consecutive transactions may pair across known cities', () {
      final journeys = projectJourneys([
        _event(
          role: JourneyEventRole.exit,
          city: '3310',
          minute: 25,
          sequence: 42,
          mode: mode,
        ),
        _event(
          role: JourneyEventRole.entry,
          city: '3370',
          minute: 10,
          sequence: 41,
          mode: mode,
        ),
      ]);
      expect(journeys, hasLength(1));
      expect(journeys.single.state, JourneyState.completed);
      expect(journeys.single.isCrossCity, isTrue);
      expect(journeys.single.cityLabel, isNull);
    });

    testWidgets('$mode cross city heading omits a single city prefix', (
      tester,
    ) async {
      final events = [
        _event(
          role: JourneyEventRole.entry,
          city: '3370',
          minute: 10,
          mode: mode,
        ),
        _event(
          role: JourneyEventRole.exit,
          city: '3310',
          minute: 25,
          mode: mode,
        ),
      ];
      await _showTicket(
        tester,
        JourneyPresentation(
          events: events,
          mode: mode,
          state: JourneyState.completed,
          cityLabel: '绍兴',
          start: events.first.endpoint,
          end: events.last.endpoint,
        ),
      );
      final name = mode == TripModeFilter.bus ? '公共汽电车' : '轨道交通';
      expect(find.text(name), findsOneWidget);
      expect(find.text('绍兴$name'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'one accepting city keeps its heading even for an out of town card',
    (tester) async {
      final events = [
        _event(role: JourneyEventRole.entry, city: '3310', minute: 10),
        _event(role: JourneyEventRole.exit, city: '3310', minute: 25),
      ];
      await _showTicket(
        tester,
        JourneyPresentation(
          events: events,
          mode: TripModeFilter.rail,
          state: JourneyState.completed,
          cityLabel: '杭州',
          start: events.first.endpoint,
          end: events.last.endpoint,
        ),
      );
      expect(find.text('杭州轨道交通'), findsOneWidget);
      expect(find.text('轨道交通'), findsNothing);
    },
  );

  test('a shared application record may contain two accepting cities', () {
    final journeys = projectJourneys([
      _event(
        role: JourneyEventRole.entry,
        city: '3370',
        minute: 10,
        application: 'same-application',
      ),
      _event(
        role: JourneyEventRole.exit,
        city: '3310',
        minute: 25,
        application: 'same-application',
      ),
    ]);
    expect(journeys, hasLength(1));
    expect(journeys.single.state, JourneyState.completed);
    expect(journeys.single.isCrossCity, isTrue);
    expect(journeys.single.cityLabel, isNull);
  });

  for (final (name, exit) in [
    (
      'unknown city',
      _event(role: JourneyEventRole.exit, city: null, minute: 25, sequence: 42),
    ),
    (
      'zero city',
      _event(
        role: JourneyEventRole.exit,
        city: '0000',
        minute: 25,
        sequence: 42,
      ),
    ),
    (
      'blank city',
      _event(
        role: JourneyEventRole.exit,
        city: 'FFFF',
        minute: 25,
        sequence: 42,
      ),
    ),
    (
      'different wallet',
      _event(
        role: JourneyEventRole.exit,
        city: '3310',
        minute: 25,
        sequence: 42,
        scope: 'other-wallet',
      ),
    ),
    (
      'different capture',
      _event(
        role: JourneyEventRole.exit,
        city: '3310',
        minute: 25,
        sequence: 42,
        source: 'other-capture',
      ),
    ),
    (
      'missing sequence',
      _event(role: JourneyEventRole.exit, city: '3310', minute: 25),
    ),
    (
      'sequence gap',
      _event(
        role: JourneyEventRole.exit,
        city: '3310',
        minute: 25,
        sequence: 43,
      ),
    ),
    (
      'backwards clock',
      _event(
        role: JourneyEventRole.exit,
        city: '3310',
        minute: 5,
        sequence: 42,
      ),
    ),
    (
      'over 24 hours',
      _event(
        role: JourneyEventRole.exit,
        city: '3310',
        minute: 1500,
        sequence: 42,
      ),
    ),
  ]) {
    test('cross city $name cannot establish a journey', () {
      final journeys = projectJourneys([
        _event(
          role: JourneyEventRole.entry,
          city: '3370',
          minute: 10,
          sequence: 41,
        ),
        exit,
      ]);
      expect(journeys, hasLength(2));
      expect(
        journeys.any((journey) => journey.state == JourneyState.completed),
        isFalse,
      );
    });
  }

  for (final line in <String?>[null, '', ' ', '200路']) {
    test('cross city buses with exit route $line do not pair with 100路', () {
      final journeys = projectJourneys([
        _event(
          role: JourneyEventRole.entry,
          city: '3370',
          minute: 10,
          sequence: 41,
          mode: TripModeFilter.bus,
        ),
        _event(
          role: JourneyEventRole.exit,
          city: '3310',
          minute: 25,
          sequence: 42,
          mode: TripModeFilter.bus,
          line: line,
        ),
      ]);
      expect(journeys, hasLength(2));
    });
  }

  for (final minute in <int?>[15, null]) {
    test('cross city journey cannot skip an intervening event at $minute', () {
      final journeys = projectJourneys([
        _event(
          role: JourneyEventRole.exit,
          city: '3310',
          minute: 25,
          sequence: 42,
        ),
        _event(role: JourneyEventRole.unknown, city: '3310', minute: minute),
        _event(
          role: JourneyEventRole.entry,
          city: '3370',
          minute: 10,
          sequence: 41,
        ),
      ]);
      expect(journeys, hasLength(3));
      expect(
        journeys.any((journey) => journey.state == JourneyState.completed),
        isFalse,
      );
    });
  }
}

void _expectReportedJourney<T>(JourneyPresentation<T> journey) {
  expect(journey.state, JourneyState.completed);
  expect(journey.isCrossCity, isTrue);
  expect(journey.cityLabel, isNull);
  expect(journey.mode, TripModeFilter.rail);
  expect(journey.start?.station, '中国轻纺城');
  expect(journey.start?.line, '1号线');
  expect(journey.end?.station, '善贤');
  expect(journey.end?.line, '3号线');
  expect(journey.duration, const Duration(hours: 1, minutes: 31, seconds: 23));
  expect(journey.events.map((event) => event.cityCode).toSet(), {
    '3370',
    '3310',
  });
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

List<int> _bytes(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

List<ArchiveHistoryRecord> _savedRecords(ReferenceDataController reference) {
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
  final json = snapshot.encode();
  final restored = CardSessionSnapshot.decode(json)!;
  expect(restored.encode(), json);
  final cycle =
      (jsonDecode(restored.encode()) as Map<String, dynamic>)['cycle'] as List;
  return [
    for (var i = 0; i < records.length; i++)
      ArchiveHistoryRecord(
        kind: ArchiveRecordKind.process,
        fields: {
          ...Map<String, dynamic>.from(cycle[i] as Map),
          'capturedDisplay': captureProcessDisplay(
            reference.knowledge!,
            records[i].trip!,
          ),
        },
        context: context,
        cardCityCode: '3370',
        sources: [
          ArchiveRecordSource('saved-capture', 'cycle[$i]', 11, {
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

TripPresentationContext _display(ReferenceDataController reference) =>
    TripPresentationContext(
      currency: Currency.cny,
      cityNameOf: reference.cityNameOf,
      resolveStationMatch: reference.resolveStationMatch,
      resolveCycleStationMatch: reference.resolveCycleStationMatch,
      resolveLineName: reference.resolveLineName,
      resolveBusLocation: reference.resolveBusLocation,
    );

JourneyEvent<TripEntryInfo> _event({
  required JourneyEventRole role,
  required String? city,
  required int? minute,
  int? sequence,
  TripModeFilter mode = TripModeFilter.rail,
  String? line = '100路',
  String scope = 'wallet',
  String source = 'capture',
  String? application,
}) => JourneyEvent(
  payload: const TripEntryInfo(
    sourceLabel: '合成记录',
    title: '记录',
    isConsume: true,
  ),
  role: role,
  mode: mode,
  endpoint: JourneyEndpoint(
    line: line,
    station: role == JourneyEventRole.entry ? '起点' : '终点',
    time: minute == null ? null : DateTime(2026, 10, 26, 0, minute),
  ),
  cityCode: city,
  cityLabel: city == '3370' ? '绍兴' : '杭州',
  sequence: sequence,
  scopeKey: scope,
  sourceIds: {source},
  applicationRecordId: application,
);

Future<void> _showTicket(
  WidgetTester tester,
  JourneyPresentation<TripEntryInfo> journey,
) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: TripEntryCard(
          info: journey.events.first.payload,
          remote: true,
          onTap: () {},
          journey: journey,
        ),
      ),
    ),
  ),
);
