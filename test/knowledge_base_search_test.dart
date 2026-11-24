import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tu_region_live_source.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tu_station_repository.dart';

void main() {
  late Database db;
  late TuRegionLiveSource source;

  setUp(() {
    db = sqlite3.openInMemory();
    db.execute('''CREATE TABLE regions(
      region_id INTEGER PRIMARY KEY,
      region_code TEXT NOT NULL,
      region_name TEXT NOT NULL,
      province TEXT,
      table_name TEXT NOT NULL,
      code_source TEXT
    )''');
    db.execute('''CREATE TABLE "region_北京_1000"(
      station_id INTEGER PRIMARY KEY,
      transport_type TEXT,
      line_name TEXT,
      station_name TEXT,
      system_name TEXT,
      source_field TEXT,
      source_key TEXT,
      source_region_code TEXT,
      source_region_name TEXT,
      raw_value_json TEXT,
      confidence TEXT
    )''');
    db.execute(
      "INSERT INTO regions VALUES(1,'1000','北京','北京','region_北京_1000','tu')",
    );
    db.execute(
      "INSERT INTO \"region_北京_1000\" VALUES(1,'metro','2号线','西直门','北京地铁','M0.i0.a','100000020001','1000','北京',NULL,'high')",
    );
    source = TuRegionLiveSource(TuStationRepository(db, userDatabase: db));
  });

  tearDown(() => db.close());

  test(
    'global search finds station, line and source code regardless of case',
    () async {
      final station = await source.searchEntries('1000', 'tu', '西直');
      final line = await source.searchEntries('1000', 'tu', '2号线');
      final code = await source.searchEntries('1000', 'tu', '100000020001');

      expect(station.single.station, '西直门');
      expect(line.single.line, '2号线');
      expect(code.single.code, '100000020001');
    },
  );

  test('search respects TU/CU namespaces and empty query', () async {
    expect(await source.searchEntries('1000', 'cu', '西直门'), isEmpty);
    expect(await source.searchEntries('1000', 'tu', '000020'), isEmpty);
    expect(await source.searchEntries('1000', 'tu', '   '), isEmpty);
  });
}
