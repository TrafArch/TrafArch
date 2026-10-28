import 'package:transit_card_analyzer/features/reference_data/data/tu_region_live_source.dart';
import 'package:flutter/material.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_engine.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/station_codes.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tu_station_repository.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_process_parser.dart';
import 'package:transit_card_analyzer/features/trips/trip_stream_view.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';

void main() {
  late Database db;
  late StationCodeTable stations;
  late AnalysisEngine engine;
  setUp(() {
    // Use the actual shipped database, not a fixture with invented route names.
    db = sqlite3.open(
      'assets/data/TrafArch_Database_TU.sqlite',
      mode: OpenMode.readOnly,
    );
    stations = StationCodeTable.empty.withLiveSources([
      TuRegionLiveSource(TuStationRepository(db)),
    ]);
    engine = AnalysisEngine(
      KnowledgeBase.fromJsonStrings(stationCodes: stations),
    );
  });
  tearDown(() => db.close());

  test(
    'Beijing bus route and hexadecimal stop ordinal survive 1E annotation',
    () {
      final trip = analyze(engine, '0001000A000100', bus: true);
      expect(trip.lineLabel, '1');
      expect(trip.resolvedBusLineLabel, '1');
      expect(trip.stationLabel, '第10站');
      expect(trip.matchedProcessTrip!.lineCode, '0001');
      expect(trip.matchedProcessTrip!.stationCode, '000A');
    },
  );

  test(
    'Beijing BRT uses full 16-bit line and station codes from shipped DB',
    () {
      final trip = analyze(engine, '04430001000100', bus: true);
      expect(trip.lineLabel, '快速公交1线');
      expect(trip.stationLabel, '德茂庄');
      expect(trip.stationType, 'BRT');
      expect(trip.stationConfidence, StationMatchConfidence.exact);
    },
  );

  test('bus must not reuse an identical metro code', () {
    final trip = analyze(engine, '5E001B00300000', bus: true);
    expect(trip.stationLabel, isNot('北邵洼'));
    expect(trip.lineLabel, isNot('昌平线'));
  });

  test(
    'Beijing metro 1A low station codes retain HEX and leading zero semantics',
    () {
      final match = stations.matchTuStationByCardId(
        rawStationId: '000000000000000A',
        cityCode: '1000',
        lineValue: 1,
      );
      expect(match.confidence, StationMatchConfidence.exact);
      expect(match.stationName, '公主坟');
      expect(match.lineName, '1号线');
    },
  );

  test(
    'Beijing metro 1A low numeric station is not rejected after zero stripping',
    () {
      final match = stations.matchTuStationByCardId(
        rawStationId: '0000000000000004',
        cityCode: '1000',
        lineValue: 1,
      );
      expect(match.stationName, '古城');
    },
  );

  test('Beijing metro 1E preserves A-F station and line keys', () {
    final trip = analyze(engine, '5E001B00300000', bus: false);
    expect(trip.lineLabel, '昌平线');
    expect(trip.stationLabel, '北邵洼');
  });

  test('70-wrapped 1E record decodes the same location as the raw record', () {
    final raw = cycleBytes('04430001000100', bus: true);
    final parsed = const TUnionProcessParser().parseCycleTrip([
      0x70,
      raw.length,
      ...raw,
    ]);
    expect(parsed, isNotNull);
    expect(parsed!.lineStationCode, '04430001000100');
    expect(parsed.cityCode, '1000');
  });

  testWidgets(
    'unpaired Beijing bus process event displays route and stop ordinal',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final app = AppDependencies(database: database);
      addTearDown(app.dispose);
      final record = const TUnionProcessParser().parseCycleTrip(
        cycleBytes('0001000A000100', bus: true),
      )!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TripStreamView(
                stream: [ProcessTripEntry(record)],
                app: app,
                isRemote: (_) => false,
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('站点10'), findsOneWidget);
      expect(find.text('1路'), findsOneWidget);
    },
  );

  testWidgets('Beijing 1A bus record uses the same decoded route as 1E', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final app = AppDependencies(database: database);
    addTearDown(app.dispose);
    final record = BusTransitRecord(
      statusCode: 1,
      entryCityCode: '1000',
      entryLineCode: '0001',
      entryStationCode: '0A',
      entryOperatorCode: '0001',
      entryTime: _time,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TripStreamView(
              stream: [BusRecordEntry(record, isEntry: true)],
              app: app,
              isRemote: (_) => false,
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('站点10'), findsOneWidget);
    expect(find.text('1路'), findsOneWidget);
  });
}

final _time = DateTime(2026, 10, 20, 8, 30);

TransitTrip analyze(AnalysisEngine engine, String field, {required bool bus}) {
  final bytes = cycleBytes(field, bus: bus);
  final cycle = const TUnionProcessParser().parseCycleTrip(bytes)!;
  return engine
      .analyze(
        ParsedCard(
          parserName: 'TU regression',
          info: const TUnionCardInfo(cityCode: '1000'),
          selectedAidHex: 'A000000632010105',
          transactions: [
            TUnionTransaction(
              sequence: 1,
              overdraftLimitFen: 0,
              amountFen: 200,
              rawType: 9,
              terminalId: '000000000001',
              time: _time,
            ),
          ],
          transitProcessRecords: [
            TUnionProcessRecord(
              sfi: 0x1E,
              recordNumber: 1,
              recordName: '循环记录 1',
              raw: bytes,
              trip: cycle,
            ),
          ],
        ),
        now: _time,
      )
      .trips
      .single;
}

List<int> cycleBytes(String field, {required bool bus}) => [
  4,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  1,
  bus ? 2 : 1,
  for (var i = 0; i < field.length; i += 2)
    int.parse(field.substring(i, i + 2), radix: 16),
  0,
  0,
  0,
  200,
  0,
  0,
  0x27,
  0x10,
  0x20,
  0x26,
  0x10,
  0x20,
  0x08,
  0x30,
  0,
  0x10,
  0,
  1,
  1,
  0x10,
  0,
  0xFF,
  0xFF,
  0xFF,
  0xFF,
  0,
  0,
  0,
  0,
  0,
  0,
];
