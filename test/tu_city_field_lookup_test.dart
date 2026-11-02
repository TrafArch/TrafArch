import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tu_region_live_source.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tu_station_repository.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/station_codes.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/tu_cycle_station_resolver.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/tu_lookup_service.dart';

void main() {
  late Database db;
  late TuStationRepository repository;
  late TuLookupService lookup;

  setUp(() {
    db = sqlite3.openInMemory();
    db.execute('''
CREATE TABLE regions(
 region_id INTEGER PRIMARY KEY,region_code TEXT,region_name TEXT,
 province TEXT,table_name TEXT,code_source TEXT)
''');
    db.execute(
      'CREATE TABLE reference_documents(name TEXT PRIMARY KEY,json TEXT)',
    );
    db.execute('INSERT INTO reference_documents VALUES(?,?)', [
      'tu_lookup',
      jsonEncode({
        'format_version': 1,
        'namespace': 'TU',
        'terminal_aliases': [
          {
            'source_field': 'M0.u.a',
            'source_key': '413106234418',
            'raw_value': '00990004',
          },
        ],
        'rail_prefixes': [],
        'rail_history': [
          {
            'source_field': 'history',
            'source_key': '112100070018',
            'raw_value': [
              [
                {r'$date_literal': '2020-01-01T00:00:00Z'},
                '*',
                '*',
                '历史站名',
              ],
            ],
          },
        ],
      }),
    ]);
    for (final (city, name) in [
      ('1121', '天津'),
      ('3010', '南京'),
      ('3350', '嘉兴'),
      ('5810', '广州'),
    ]) {
      final table = 'region_${name}_$city';
      db.execute(
        'INSERT INTO regions(region_code,region_name,table_name) VALUES(?,?,?)',
        [city, name, table],
      );
      db.execute('''
CREATE TABLE "$table"(
 station_id INTEGER PRIMARY KEY,transport_type TEXT,line_name TEXT,
 station_name TEXT,system_name TEXT,source_field TEXT,source_key TEXT,
 source_region_code TEXT,source_region_name TEXT,raw_value_json TEXT,confidence TEXT)
''');
    }
    repository = TuStationRepository(db);
    lookup = TuLookupService(repository);
  });
  tearDown(() => db.close());

  void add(
    String city,
    String key,
    String station, {
    String? sourceField,
    String kind = 'metro',
    String line = '7号线',
    String? sourceRegion,
  }) {
    final region = repository.regionOf(city)!;
    db.execute(
      'INSERT INTO "${region.tableName}"(transport_type,line_name,station_name,'
      'source_field,source_key,source_region_code,raw_value_json) VALUES(?,?,?,?,?,?,?)',
      [
        kind,
        line,
        station,
        sourceField ?? StationCodeTable.tuRailSourceField(city),
        key,
        sourceRegion ?? city,
        jsonEncode(['', line, station]),
      ],
    );
    repository.invalidate();
  }

  StationMatch resolve(
    String city,
    String field, {
    int? appType = 1,
    String? terminal,
    DateTime? time,
  }) => lookup.resolveCycle(
    city: city,
    field: field,
    appType: appType,
    terminalId: terminal,
    time: time,
  );

  test(
    'Tianjin reads bare city-table keys without stripping station bytes',
    () {
      add('1121', '00070018', '丽江道');
      add('1121', '00070020', '天塔');
      for (final (field, key, station) in [
        ('00070018000000', '00070018', '丽江道'),
        ('000700200000', '00070020', '天塔'),
      ]) {
        final hit = resolve('1121', field);
        expect(hit.confidence, StationMatchConfidence.exact);
        expect(hit.stationName, station);
        expect(hit.entry?.sourceKey, key);
        expect(hit.entry?.datasetFile, 'tu:1121');
        expect(hit.evidence.any((e) => e.sourceKey == key), isTrue);
      }
      expect(resolve('1121', '00070019000000').isUnmatched, isTrue);
    },
  );

  test(
    'Nanjing explicitly accepts developer M0.W.a while rejecting local maps',
    () {
      add('3010', '00060001', '测试六号站', sourceField: 'M0.W.a', line: '6号线');
      add('3010', '00060002', '本地终端不可混入', sourceField: 'M0.E.a', line: '6号线');
      expect(resolve('3010', '00060001000000').stationName, '测试六号站');
      expect(resolve('3010', '00060002000000').isUnmatched, isTrue);
    },
  );

  test(
    'Guangzhou raw line12 wins before hexadecimal fragment fallback to18',
    () {
      add('5810', '00120001', '十二号站', line: '12号线');
      add('5810', '581000180001', '广州东站', line: '18号线');
      final table = StationCodeTable.empty.withLive(
        TuRegionLiveSource(repository),
      );
      final hit = resolveTuCycleStation(
        stations: table,
        lookup: lookup,
        cityCode: '5810',
        field: '00120001000000',
        appType: 1,
      );
      expect(hit.lineName, '12号线');
      expect(hit.stationName, '十二号站');
      expect(hit.entry?.sourceKey, '00120001');
      expect(resolve('5810', '00180001000000').stationName, '广州东站');
    },
  );

  test('city, source field and explicit rail application remain isolated', () {
    add('1121', '00070018', '天津站点');
    add('3010', '00070018', '南京站点', sourceField: 'M0.W.a');
    expect(resolve('1121', '00070018000000').stationName, '天津站点');
    expect(resolve('3010', '00070018000000').stationName, '南京站点');
    for (final app in [null, 0, 2, 3]) {
      expect(
        resolve('1121', '00070018000000', appType: app).isUnmatched,
        isTrue,
      );
    }
    expect(resolve('3350', '00070018000000').isUnmatched, isTrue);
    expect(resolve('9999', '00070018000000').isUnmatched, isTrue);
    expect(resolve('1121', '00070018').isUnmatched, isTrue);
  });

  test('bus, operator, process and known basic-terminal rows are excluded', () {
    add('1121', '00010001', '公交不可混入', kind: 'bus');
    add('1121', '00010002', '运营商不可混入', kind: 'operator');
    add('1121', '00010003', '其他来源不可混入', sourceField: 'M0.S.c');
    add('1121', '00010004', '处理终端不可混入', sourceField: 'M0.S.a');
    add('1121', '00010005', '其他城市不可混入', sourceRegion: '3010');
    add('3350', '413106234418', '长安（东方学院）', line: '杭海城际');
    for (final field in [
      '00010001000000',
      '00010002000000',
      '00010003000000',
      '00010004000000',
      '00010005000000',
    ]) {
      expect(resolve('1121', field).isUnmatched, isTrue, reason: field);
    }
    expect(resolve('3350', '41310623441800').isUnmatched, isTrue);
  });

  test(
    'explicit tram and light-rail rows retain their rail transport kinds',
    () {
      add('1121', '00020001', '有轨站点', kind: 'tram', line: '有轨线');
      add('1121', '00020002', '轻轨站点', kind: 'light_rail', line: '轻轨线');
      expect(resolve('1121', '00020001000000').entry?.kind, 'tram');
      expect(resolve('1121', '00020002000000').entry?.kind, 'light_rail');
    },
  );

  test('native complete result and historical names keep priority over raw aliases', () {
    add('1121', '112100070018', '原生站名');
    add('1121', '00070018', '相冲突的新站名');
    expect(resolve('1121', '00070018000000').stationName, '原生站名');
    expect(
      resolve('1121', '00070018000000', time: DateTime.utc(2019)).stationName,
      '历史站名',
    );
  });

  test(
    'native ambiguity and unavailable data never downgrade to a raw match',
    () {
      add('1121', '112100070018', '原生候选甲');
      add('1121', '112100070018', '原生候选乙');
      add('1121', '00070018', '不能覆盖歧义');
      expect(
        resolve('1121', '00070018000000').confidence,
        StationMatchConfidence.ambiguous,
      );
      db.execute('DROP TABLE "region_天津_1121"');
      repository.invalidate();
      expect(
        resolve('1121', '00070018000000').confidence,
        StationMatchConfidence.unavailable,
      );
    },
  );

  test(
    'longest consumed position prefix wins without city-length advantage',
    () {
      add('3010', '30100007', '', sourceField: 'M0.W.a');
      add('3010', '00070018', '长前缀站', sourceField: 'M0.W.a');
      expect(resolve('3010', '00070018000000').stationName, '长前缀站');
    },
  );

  test('equal bare and city-prefixed position lengths retain ambiguity', () {
    add('3010', '301000070018', '', sourceField: 'M0.W.a');
    add('3010', '00070018', '裸原码乙', sourceField: 'M0.W.a');
    final hit = resolve('3010', '00070018000000');
    expect(hit.confidence, StationMatchConfidence.ambiguous);
    expect(hit.candidates.map((e) => e.sourceKey).toSet(), {
      '301000070018',
      '00070018',
    });
  });

  test(
    'same-line native prefix gains station while retaining both sources',
    () {
      add('1121', '11210007', '');
      add('1121', '00070018', '丽江道');
      final hit = resolve('1121', '00070018000000');
      expect(hit.stationName, '丽江道');
      expect(
        hit.evidence.map((e) => e.sourceKey),
        containsAll(['11210007', '00070018']),
      );
    },
  );

  test(
    'a different-line raw candidate cannot replace a native line prefix',
    () {
      add('1121', '11210007', '');
      add('1121', '00070018', '异线站点', line: '8号线');
      final hit = resolve('1121', '00070018000000');
      expect(hit.lineName, '7号线');
      expect(hit.stationName ?? '', isEmpty);
      expect(hit.entry?.sourceKey, '11210007');
    },
  );
}
