import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tu_station_repository.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/station_codes.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/tu_lookup_service.dart';

void main() {
  late Database database;
  late TuLookupService lookup;

  setUpAll(() {
    database = sqlite3.open(
      'assets/data/TrafArch_Database_TU.sqlite',
      mode: OpenMode.readOnly,
    );
    lookup = TuLookupService(TuStationRepository(database));
  });
  tearDownAll(() => database.close());

  // Literal source keys and names are independently checked against original
  // TU city tables and the native intercity line-prefix document. The longer
  // fixtures exercise complete four-byte keys, not the observed two-byte code.
  for (final (city, field, key, line, station) in [
    ('3370', '11351501000000', '33201135', '宁波城际', '宁波'),
    ('3320', '01211A04000000', '33700121', '绍兴城际', '钱清'),
    ('3310', '00990002000000', '335000990002', '杭海城际', '许村'),
    ('5810', '00700001000000', '581000700001', '广清城际', '清城'),
    ('5880', '00710003000000', '581000710003', '广州东环城际', '白云机场北'),
  ]) {
    test('intercity location uses the complete native key $city/$key', () {
      final match = lookup.resolveCycle(
        city: city,
        field: field,
        appType: 0x0A,
      );
      expect(match.confidence, StationMatchConfidence.exact);
      expect(match.stationName, station);
      expect(match.lineName, line);
      expect(match.entry?.sourceKey, key);
      expect(match.evidence.any((item) => item.sourceKey == key), isTrue);
      expect(match.resolvedCityCode, key.substring(0, 4));
    });
  }

  for (final (city, field, appType) in [
    ('3370', '11351501000000', 0x00),
    ('3370', '11351501000000', 0x02),
    ('3370', '11351501000000', 0x0E),
    ('3370', '11351501000000', 0x01),
    ('3370', '113515010000', 0x0A),
    ('3370', '11351501000001', 0x0A),
    ('3370', '11351501010000', 0x0A),
    ('3370', '113G1501000000', 0x0A),
    ('3370', '11FF1501000000', 0x0A), // No complete intercity station.
    ('1000', '11351501000000', 0x0A), // Different native map namespace.
    ('4520', '11351501000000', 0x0A), // Qingdao same suffix is metro.
    ('0000', '11351501000000', 0x0A),
    ('9999', '11351501000000', 0x0A),
  ]) {
    test(
      'unproved intercity context does not resolve $city/$field/$appType',
      () {
        final match = lookup.resolveCycle(
          city: city,
          field: field,
          appType: appType,
        );
        expect(match.stationName, isNot('宁波'));
        expect(match.stationName, isNot('蓝色硅谷'));
      },
    );
  }

  group('source-backed intercity boundary', () {
    late Database memory;

    setUp(() => memory = _sourceDatabase());
    tearDown(() => memory.close());

    StationMatch resolve({DateTime? time}) =>
        TuLookupService(TuStationRepository(memory)).resolveCycle(
          city: '3370',
          field: '11351501000000',
          appType: 0x0A,
          time: time,
        );

    test('two city mappings with identical labels remain ambiguous', () {
      _addCollision(memory, station: '宁波');
      final match = resolve();
      expect(match.confidence, StationMatchConfidence.ambiguous);
      expect(match.stationName, isNull);
      expect(match.resolvedCityCode, isNull);
      expect(match.candidates.map((row) => row.sourceKey).toSet(), {
        '33201135',
        '33701135',
      });
    });

    test(
      'a local complete station cannot hide a conflicting remote mapping',
      () {
        _addCollision(memory, station: '同码冲突站');
        final match = resolve();
        expect(match.confidence, StationMatchConfidence.ambiguous);
        expect(match.lineName, isNull);
        expect(match.stationName, isNull);
        expect(match.resolvedCityCode, isNull);
      },
    );

    for (final (column, value) in [
      ('native_namespace', 'CU'),
      ('lookup_key_namespace', 'CU'),
      ('copy_role', 'replica'),
      ('record_kind', 'terminal_mapping'),
    ]) {
      test('foreign provenance $column cannot enter the rail namespace', () {
        memory.execute('UPDATE record_provenance SET $column=?', [value]);
        expect(resolve().isUnmatched, isTrue);
      });
    }

    for (final (column, value) in [
      ('source_field', 'M0.C.b'),
      ('source_region_code', '3370'),
      ('transport_type', 'bus'),
      ('line_name', '另一线路'),
      ('station_name', ''),
      ('source_key', '332011'),
    ]) {
      test('inconsistent original station $column stays unmatched', () {
        memory.execute('UPDATE city3320 SET $column=?', [value]);
        expect(resolve().isUnmatched, isTrue);
      });
    }

    test(
      'ordinary metro classification cannot supply an intercity station',
      () {
        _document(memory, line: '11号线');
        memory.execute("UPDATE city3320 SET line_name='11号线'");
        expect(resolve().isUnmatched, isTrue);
      },
    );

    test('a line-only prefix cannot supply a station without a full row', () {
      memory.execute('DELETE FROM city3320');
      final match = resolve();
      expect(match.isUnmatched, isTrue);
      expect(match.lineName, isNull);
    });

    test('missing original provenance does not start a cross-city search', () {
      memory.execute('DROP TABLE record_provenance');
      expect(resolve().isUnmatched, isTrue);
    });

    test('a broken provenance query is unavailable, not a partial match', () {
      memory.execute(
        'ALTER TABLE record_provenance RENAME COLUMN copy_role TO broken',
      );
      expect(resolve().confidence, StationMatchConfidence.unavailable);
    });

    test('a foreign optional document namespace cannot supply a candidate', () {
      _document(memory, namespace: 'CU');
      expect(resolve().confidence, StationMatchConfidence.unavailable);
    });

    test('date-specific names use the resolved full city key', () {
      _document(
        memory,
        history: [
          {
            'source_field': 'test.history',
            'source_key': '33201135',
            'raw_value': [
              [
                {r'$date_literal': '2020-01-01T00:00:00Z'},
                '*',
                '*',
                '旧宁波',
              ],
            ],
          },
        ],
      );
      expect(resolve(time: DateTime.utc(2019)).stationName, '旧宁波');
      expect(resolve(time: DateTime.utc(2026)).stationName, '宁波');
      expect(resolve().stationName, '宁波');
    });
  });
}

Database _sourceDatabase() {
  final db = sqlite3.openInMemory();
  db.execute(
    'CREATE TABLE regions(region_id INTEGER,region_code TEXT,region_name TEXT,table_name TEXT,code_source TEXT)',
  );
  for (final city in ['3320', '3370']) {
    db.execute('INSERT INTO regions VALUES(?,?,?,?,?)', [
      int.parse(city),
      city,
      city,
      'city$city',
      'source_key',
    ]);
    db.execute(
      'CREATE TABLE city$city(station_id INTEGER,transport_type TEXT,line_name TEXT,station_name TEXT,source_field TEXT,source_key TEXT,source_region_code TEXT)',
    );
  }
  db.execute('CREATE TABLE reference_documents(name TEXT,json TEXT)');
  db.execute(
    'CREATE TABLE record_provenance(table_name TEXT,station_id INTEGER,native_namespace TEXT,copy_role TEXT,record_kind TEXT,lookup_key_namespace TEXT)',
  );
  db.execute(
    "INSERT INTO city3320 VALUES(1,'metro','宁波城际','宁波','M0.W.a','33201135','3320')",
  );
  db.execute(
    "INSERT INTO record_provenance VALUES('city3320',1,'TU','native','station_mapping','TU')",
  );
  _document(db);
  return db;
}

void _document(
  Database db, {
  String line = '宁波城际',
  String namespace = 'TU',
  List<Object> history = const [],
  List<Object> additional = const [],
}) {
  db.execute('DELETE FROM reference_documents');
  db.execute('INSERT INTO reference_documents VALUES(?,?)', [
    'tu_lookup',
    jsonEncode({
      'format_version': 1,
      'namespace': namespace,
      'terminal_aliases': [],
      'rail_history': history,
      'rail_prefixes': [
        {
          'source_field': 'M0.W.a',
          'source_key': '332011',
          'raw_value': ['', line, ''],
        },
        ...additional,
      ],
    }),
  ]);
}

void _addCollision(Database db, {required String station}) {
  db.execute('INSERT INTO city3370 VALUES(?,?,?,?,?,?,?)', [
    2,
    'metro',
    '宁波城际',
    station,
    'M0.W.a',
    '33701135',
    '3370',
  ]);
  db.execute(
    "INSERT INTO record_provenance VALUES('city3370',2,'TU','native','station_mapping','TU')",
  );
  _document(
    db,
    additional: [
      {
        'source_field': 'M0.W.a',
        'source_key': '337011',
        'raw_value': ['', '宁波城际', ''],
      },
    ],
  );
}
