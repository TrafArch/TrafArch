import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_presenter.dart';
import 'package:transit_card_analyzer/features/trips/trip_filters.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_process_parser.dart';

void main() {
  test('captured endpoint owner cities establish cross city without rewriting acquirer', () {
    final records = _records(entryOwner: '3370', exitOwner: '3320');
    final before = jsonEncode([for (final r in records) r.fields]);
    final journey = projectJourneys(_events(records)).single;
    expect(journey.state, JourneyState.completed);
    expect(journey.isCrossCity, isTrue);
    expect(journey.cityLabel, isNull);
    expect(journey.events.map((e) => e.cityCode), everyElement('3370'));
    expect(journey.end!.station, '捕获终点');
    expect(jsonEncode([for (final r in records) r.fields]), before);
  });

  test(
    'derived city presentation is not restricted to one city pair or mode',
    () {
      for (final mode in [TripModeFilter.rail, TripModeFilter.bus]) {
        final captured = _events(
          _records(entryOwner: '1000', exitOwner: '2500'),
        );
        final events = [
          for (final event in captured)
            _copy(
              event,
              mode: mode,
              line: mode == TripModeFilter.bus ? '跨城线路' : null,
            ),
        ];
        final journey = projectJourneys(events).single;
        expect(journey.state, JourneyState.completed);
        expect(journey.isCrossCity, isTrue);
        expect(journey.cityLabel, isNull);
      }
    },
  );

  test('legacy capture without owner city retains its own frozen display and raw city', () {
    final records = _records();
    final before = jsonEncode([for (final r in records) r.fields]);
    final journey = projectJourneys(_events(records)).single;
    expect(journey.isCrossCity, isFalse);
    expect(journey.cityLabel, '受理城');
    expect(journey.end!.station, '捕获终点');
    expect(jsonEncode([for (final r in records) r.fields]), before);
  });

  test('placeholder owner cities cannot supply cross city proof', () {
    for (final invalid in ['', '0000', '9999', 'FFFF', '332', 'unknown']) {
      final journey = projectJourneys(_events(_records(exitOwner: invalid)))
          .single;
      expect(journey.isCrossCity, isFalse, reason: invalid);
      expect(journey.cityLabel, '受理城', reason: invalid);
    }
  });

  test(
    'owner cities cannot join different captures or bridge missing slots',
    () {
      final events = _events(_records(entryOwner: '3370', exitOwner: '3320'));
      for (final exit in [
        _copy(events.first, sources: {'another-capture'}),
        _copy(events.first, positions: {'capture': 4}),
      ]) {
        final journeys = projectJourneys([exit, events.last]);
        expect(journeys, hasLength(2));
        expect(journeys.any((j) => j.state == JourneyState.completed), isFalse);
      }
    },
  );

  test('same owner city does not become cross city because an alias lacks new metadata', () {
    final cycle = _events(_records(entryOwner: '3320', exitOwner: '3320'));
    final aliases = [
      for (final event in cycle) ...[
        _copy(
          event,
          identity: 'one-journey',
          source: JourneyEvidenceSource.cycle,
        ),
        _copy(
          event,
          identity: 'one-journey',
          source: JourneyEvidenceSource.transaction,
          rawEndpoint: true,
          sequence: event.role == JourneyEventRole.entry ? 1 : 2,
        ),
      ],
    ];
    final journey = projectJourneys(aliases).single;
    expect(journey.state, JourneyState.completed);
    expect(journey.isCrossCity, isFalse);
    expect(journey.cityLabel, '映射城市3320');
    expect(journey.events, hasLength(4));
  });

  for (final role in [JourneyEventRole.entry, JourneyEventRole.exit]) {
    test('$role only with an old alias cannot prove a cross city journey', () {
      final cycle = _events(_records(entryOwner: '3320', exitOwner: '3320'))
          .singleWhere((event) => event.role == role);
      final journeys = projectJourneys([
        _copy(
          cycle,
          identity: 'one-operation',
          source: JourneyEvidenceSource.cycle,
        ),
        _copy(
          cycle,
          identity: 'one-operation',
          source: JourneyEvidenceSource.transaction,
          rawEndpoint: true,
          sequence: 1,
        ),
      ]);
      expect(journeys, hasLength(1));
      expect(
        journeys.single.state,
        role == JourneyEventRole.entry
            ? JourneyState.inProgress
            : JourneyState.incomplete,
      );
      expect(journeys.single.events, hasLength(2));
      expect(journeys.single.isCrossCity, isFalse);
    });
  }

  test('transaction captured owner city survives JSON and remains display metadata', () {
    final trip = TransitTrip(
      time: DateTime(2026, 11, 4, 10),
      amountFen: 0,
      overdraftLimitFen: 0,
      isConsume: true,
      typeName: '复合消费',
      sequence: 1,
      terminalId: '000000000001',
      cityCode: '3370',
      locationCityCode: '3320',
      stationConfidence: null,
    );
    final json = CardSessionSnapshot(trips: [trip]).encode();
    final fields = ((jsonDecode(json) as Map)['trips'] as List).single as Map;
    expect(fields['cityCode'], '3370');
    expect((fields['capturedDisplay'] as Map)['locationCityCode'], '3320');
    final restored = CardSessionSnapshot.decode(json)!;
    expect(restored.trips.single.cityCode, '3370');
    expect(restored.trips.single.locationCityCode, '3320');
    expect(restored.encode(), json);
  });
}

const _context = ArchiveContext(
  systemId: 'TU',
  applicationId: 'A000000632010105',
  currencyCode: 'CNY',
  minorUnitDigits: 2,
  clockBasis: 'captured-local',
  timeZoneOffsetMinutes: 480,
);

List<ArchiveHistoryRecord> _records({String? entryOwner, String? exitOwner}) {
  const hex = [
    '0441310188306200000A1135150100000000000000000005DC20261104094123337003493370FFFFFFFF000000000000',
    '0341310143052900000A01211A0400000000000000000005DC20261104074947337003493370FFFFFFFF000000000000',
  ];
  final cycles = [
    for (final raw in hex)
      const TUnionProcessParser().parseCycleTrip([
        for (var i = 0; i < raw.length; i += 2)
          int.parse(raw.substring(i, i + 2), radix: 16),
      ])!,
  ];
  final json = jsonDecode(
    CardSessionSnapshot(context: _context, processTrips: cycles).encode(),
  ) as Map;
  return [
    for (var i = 0; i < cycles.length; i++)
      ArchiveHistoryRecord(
        kind: ArchiveRecordKind.process,
        fields: {
          ...Map<String, dynamic>.from((json['cycle'] as List)[i] as Map),
          'capturedDisplay': {
            'cityName': '受理城市',
            'line': '捕获线路',
            'station': i == 0 ? '捕获终点' : '捕获起点',
            if ((i == 0 ? exitOwner : entryOwner) case final String owner) ...{
              'locationCityCode': owner,
              'locationCityName': '映射城市$owner',
            },
          },
        },
        context: _context,
        sources: [
          ArchiveRecordSource('capture', 'cycle[$i]', 15, {
            'record': {
              'sfi': 0x1E,
              'recordNumber': i + 1,
              'recordNumberIsReliable': true,
              'rawHex': cycles[i].rawHex,
            },
          }),
        ],
      ),
  ];
}

List<JourneyEvent<TripEntryInfo>> _events(List<ArchiveHistoryRecord> records) =>
    [
      for (final entry in presentArchiveTrips(
        records,
        onDiagnostics: (_) {},
      ).entries)
        entry.journeyEvent!,
    ];

JourneyEvent<TripEntryInfo> _copy(
  JourneyEvent<TripEntryInfo> event, {
  TripModeFilter? mode,
  String? line,
  Set<String>? sources,
  Map<String, int>? positions,
  String? identity,
  JourneyEvidenceSource? source,
  bool rawEndpoint = false,
  int? sequence,
}) => JourneyEvent(
  payload: event.payload,
  mode: mode ?? event.mode,
  role: event.role,
  endpoint: rawEndpoint
      ? JourneyEndpoint(
          line: event.endpoint.line,
          station: event.endpoint.station,
          time: event.endpoint.time,
          timeText: event.endpoint.timeText,
        )
      : line == null
      ? event.endpoint
      : JourneyEndpoint(
          line: line,
          station: event.endpoint.station,
          time: event.endpoint.time,
          timeText: event.endpoint.timeText,
          locationCityCode: event.endpoint.locationCityCode,
          locationCityLabel: event.endpoint.locationCityLabel,
        ),
  cityCode: event.cityCode,
  cityLabel: event.cityLabel,
  scopeKey: event.scopeKey,
  sourceIds: sources ?? event.sourceIds,
  processPositions: positions ?? event.processPositions,
  railAppTypeCode: mode == TripModeFilter.bus ? null : event.railAppTypeCode,
  applicationRecordId: identity,
  evidenceSource: source ?? event.evidenceSource,
  sequence: sequence,
);
