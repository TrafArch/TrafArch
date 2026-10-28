import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_application_display.dart';
import 'package:transit_card_analyzer/features/reference_data/application/reference_data_controller.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tu_region_live_source.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tu_station_repository.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/station_codes.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/tu_lookup_service.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_engine.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

// These fields are synthetic layout probes, not a captured Chongqing card log.
// Names and original keys were checked independently against TripReader's
// M0.e0.a and the published region_重庆_6900 table. No asset is modified.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  late ReferenceDataController controller;
  late KnowledgeBase knowledge;

  setUpAll(() async {
    directory = Directory.systemTemp.createTempSync('trafarch-chongqing-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => directory.path);
    controller = ReferenceDataController(rootBundle);
    await controller.initialize();
    knowledge = controller.knowledge!;
    expect(knowledge.loadIssues, isEmpty);
  });

  tearDownAll(() {
    controller.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, null);
    directory.deleteSync(recursive: true);
  });

  for (final (field, key, station) in [
    ('18010000000000', '69001801', '跳磴南'),
    ('18000100000000', '69001801', '跳磴南'),
    ('18100000000000', '69001810', '李家沱大桥'),
    ('18001000000000', '69001810', '李家沱大桥'),
    ('00180001000000', '69001801', '跳磴南'),
  ]) {
    test('published Chongqing 18 resolver completes synthetic $field', () {
      final match = controller.resolveCycleStationMatch(
        '6900',
        field,
        appType: 1,
      );
      expect(match.confidence, StationMatchConfidence.exact);
      expect(match.lineName, '18号线');
      expect(match.stationName, station);
      expect(match.entry?.sourceKey, key);
      expect(match.entry?.sourceField, 'M0.e0.a');
      expect(match.entry?.rawValueJson, '["","18号线","$station"]');
      if (field == '18000100000000' || field == '18001000000000') {
        expect(match.evidence.map((e) => e.sourceKey), contains('690018'));
        expect(match.evidence.map((e) => e.sourceKey), contains(key));
      }
    });

    test('paired and archived Chongqing record agree for synthetic $field', () {
      final record = _record(field);
      final result = AnalysisEngine(knowledge).analyze(_card(record));
      final trip = result.trips.single;
      expect(trip.lineLabel, '18号线');
      expect(trip.stationLabel, station);
      expect(trip.stationConfidence, StationMatchConfidence.exact);
      expect(trip.matchedProcessTrip?.lineStationCode, field);
      final captured = captureProcessDisplay(knowledge, record);
      expect(captured['line'], '18号线');
      expect(captured['station'], station);
      expect(record.lineStationCode, field);
    });
  }

  test('unknown and absent stations retain only the proven line prefix', () {
    for (final field in ['1800FF00000000', '18000000000000']) {
      final match = controller.resolveCycleStationMatch(
        '6900',
        field,
        appType: 1,
      );
      expect(match.confidence, StationMatchConfidence.exact);
      expect(match.lineName, '18号线');
      expect(match.stationName ?? '', isEmpty);
      expect(match.entry?.sourceKey, '690018');
      final captured = captureProcessDisplay(knowledge, _record(field));
      expect(captured['line'], '18号线');
      expect(captured.containsKey('station'), isFalse);
    }
  });

  for (final field in ['18990100000000', '18000101000000']) {
    test('non-padding bytes cannot become a known station: $field', () {
      final match = controller.resolveCycleStationMatch(
        '6900',
        field,
        appType: 1,
      );
      // In the first field the compact station is unknown 99; later 01 is
      // not station evidence. In the second, 0101 cannot be truncated to 01.
      expect(match.lineName, '18号线');
      expect(match.stationName ?? '', isEmpty);
      expect(match.entry?.sourceKey, '690018');
      final captured = captureProcessDisplay(knowledge, _record(field));
      expect(captured['line'], '18号线');
      expect(captured.containsKey('station'), isFalse);
    });
  }

  test('non-rail classifications cannot complete a Chongqing rail station', () {
    for (final appType in [null, 0, 2, 0xFE]) {
      final match = controller.resolveCycleStationMatch(
        '6900',
        '18000100000000',
        appType: appType,
      );
      expect(match.isUnmatched, isTrue);
      if (appType != null) {
        final captured = captureProcessDisplay(
          knowledge,
          _record('18000100000000', appType: appType),
        );
        expect(captured['station'], isNot('跳磴南'));
      }
    }
  });

  test(
    'a complete key conflict stays ambiguous before fragment completion',
    () {
      final repository = _ConflictingRailRepository(knowledge.tuStations!);
      final conflicting = KnowledgeBase(
        cities: knowledge.cities,
        issuers: knowledge.issuers,
        terminalRules: knowledge.terminalRules,
        stationCodes: StationCodeTable.empty.withLive(
          TuRegionLiveSource(repository),
        ),
        tuLookup: TuLookupService(repository),
      );
      // The original full key is 69001801 (跳磴南). A faulty fallback on this
      // synthetic field could instead read line=18/station=10 (李家沱大桥).
      final record = _record('18011000000000');
      final trip = AnalysisEngine(conflicting)
          .analyze(_card(record))
          .trips
          .single;
      expect(trip.stationConfidence, StationMatchConfidence.ambiguous);
      expect(trip.stationLabel, isNot('李家沱大桥'));
      final captured = captureProcessDisplay(conflicting, record);
      expect(captured.containsKey('station'), isFalse);
    },
  );
}

TUnionTripRecord _record(String field, {int appType = 1}) => TUnionTripRecord(
  typeCode: 6,
  terminalId: '0000000000000001',
  appTypeCode: appType,
  lineStationCode: field,
  amountFen: 300,
  balanceFen: 9700,
  time: DateTime(2026, 10, 27, 12),
  cityCode: '6900',
);

ParsedCard _card(TUnionTripRecord record) => ParsedCard(
  parserName: 'synthetic Chongqing station completion regression',
  selectedAidHex: 'A000000632010105',
  info: const TUnionCardInfo(cityCode: '1000'),
  transactions: [
    TUnionTransaction(
      sequence: 1,
      overdraftLimitFen: 0,
      amountFen: 300,
      rawType: 9,
      terminalId: '000000000001',
      time: record.time,
    ),
  ],
  transitProcessRecords: [
    TUnionProcessRecord(
      sfi: 0x1E,
      recordNumber: 1,
      recordName: 'synthetic 1E layout probe',
      raw: const [],
      trip: record,
    ),
  ],
);

// Controlled competing reference evidence for an ambiguity test; the backing
// published database remains read-only and all production lookup code runs.
class _ConflictingRailRepository extends TuStationRepository {
  _ConflictingRailRepository(TuStationRepository original) : super(original.db);

  @override
  Iterable<StationCodeEntry> railCandidates(String city) sync* {
    yield* super.railCandidates(city);
    if (city == '6900') {
      yield const StationCodeEntry(
        code: '69001801',
        sourceKey: '69001801',
        sourceField: 'M0.e0.a',
        line: '18号线',
        station: '合成冲突站点',
        system: 'tu',
        kind: 'metro',
      );
    }
  }
}
