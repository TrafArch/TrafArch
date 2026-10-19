import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:transit_card_analyzer/core/data/station_codes.dart';
import 'package:transit_card_analyzer/core/data/tu_station_repository.dart';

void main() {
  late Database db;
  late TuStationRepository repo;

  setUp(() {
    db = sqlite3.openInMemory();
    db.execute('''
CREATE TABLE regions(
  region_id INTEGER PRIMARY KEY,
  region_code TEXT NOT NULL,
  region_name TEXT NOT NULL,
  province TEXT,
  table_name TEXT NOT NULL,
  code_source TEXT
)''');
    db.execute('''
CREATE TABLE "region_上海_2900"(
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
    db.execute('''
CREATE TABLE "region_北京_1000"(
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
      "INSERT INTO regions VALUES(1,'2900','上海','上海市','region_上海_2900','tu')",
    );
    db.execute(
      "INSERT INTO regions VALUES(2,'1000','北京','北京市','region_北京_1000','tu')",
    );

    // 上海：12 位 source_key，线路/站点片段右填充零
    db.execute(
      "INSERT INTO \"region_上海_2900\" VALUES"
      "(1,'metro','10号线','航中路','上海地铁','M0.i0.a','290000100018',"
      "'2900','上海',NULL,'high')",
    );
    db.execute(
      "INSERT INTO \"region_上海_2900\" VALUES"
      "(2,'metro','2号线','人民广场','上海地铁','M0.i1.a','290000200031',"
      "'2900','上海',NULL,'high')",
    );
    // 北京：8 位 source_key
    db.execute(
      "INSERT INTO \"region_北京_1000\" VALUES"
      "(3,'bus','1路','四惠枢纽','北京公交','M0.i0.a','10000118',"
      "'1000','北京',NULL,'high')",
    );

    TuStationRepository.ensureAppTables(db);
    repo = TuStationRepository(db);
  });

  tearDown(() {
    db.dispose();
  });

  group('地区定位', () {
    test('按编码唯一定位地区', () {
      final region = repo.findRegion(regionCode: '2900');
      expect(region, isNotNull);
      expect(region!.regionName, '上海');
      expect(region.tableName, 'region_上海_2900');
    });

    test('编码与名称同时给出时按 AND 组合', () {
      expect(repo.findRegion(regionCode: '2900', regionName: '上海'), isNotNull);
      expect(repo.findRegion(regionCode: '2900', regionName: '北京'), isNull);
    });

    test('两者都未提供时抛 ArgumentError', () {
      expect(() => repo.findRegion(), throwsArgumentError);
    });

    test('名称重复导致多命中时返回 null（不擅自选第一条）', () {
      db.execute(
        "INSERT INTO regions VALUES(3,'2901','上海','上海市','region_上海_2900','tu')",
      );
      repo.invalidate();
      expect(repo.findRegion(regionName: '上海'), isNull);
    });
  });

  group('source_key 精确查询', () {
    test('地区 + source_key 命中唯一站点', () {
      final rows = repo.findStations(
        sourceKey: '290000100018',
        regionCode: '2900',
      );
      expect(rows, hasLength(1));
      expect(rows.first.stationName, '航中路');
      expect(rows.first.lineName, '10号线');
      expect(rows.first.sourceField, 'M0.i0.a');
      expect(rows.first.transportType, 'metro');
      expect(rows.first.confidence, 'high');
    });

    test('source_field 收窄可区分同键多来源', () {
      db.execute(
        "INSERT INTO \"region_上海_2900\" VALUES"
        "(4,'metro','10号线','航中路','上海地铁','M0.i0.b','290000100018',"
        "'2900','上海',NULL,'medium')",
      );
      repo.invalidate();
      expect(
        repo.findStations(
          sourceKey: '290000100018',
          regionCode: '2900',
        ),
        hasLength(2),
      );
      final narrowed = repo.findStations(
        sourceKey: '290000100018',
        sourceField: 'M0.i0.a',
        regionCode: '2900',
      );
      expect(narrowed, hasLength(1));
      expect(narrowed.first.confidence, 'high');
    });

    test('transport_type 不匹配时不返回（不模糊匹配）', () {
      expect(
        repo.findStations(
          sourceKey: '290000100018',
          regionCode: '2900',
          transportType: 'bus',
        ),
        isEmpty,
      );
    });

    test('空编码 / 未知地区返回空', () {
      expect(repo.findStations(sourceKey: '  ', regionCode: '2900'), isEmpty);
      expect(repo.findStations(sourceKey: '290000100018', regionCode: '9999'),
          isEmpty);
    });

    test('片段切分：12 位取 5-8 / 9-12，8 位取 5-6 / 7-8', () {
      final sh = repo
          .findStations(sourceKey: '290000100018', regionCode: '2900')
          .first;
      expect(sh.segments, ('0010', '0018'));
      final bj = repo
          .findStations(sourceKey: '10000118', regionCode: '1000')
          .first;
      expect(bj.segments, ('01', '18'));
    });
  });

  group('跨地区查询', () {
    test('无地区线索时按 source_key 遍历各地区表', () {
      final rows = repo.findStationsAcrossRegions(sourceKey: '10000118');
      expect(rows, hasLength(1));
      expect(rows.first.regionCode, '1000');
    });

    test('limit 生效', () {
      expect(
        repo.findStationsAcrossRegions(sourceKey: '10000118', limit: 0),
        isEmpty,
      );
    });
  });

  group('片段查询（0x1A / 0x1E 通道）', () {
    test('线路 + 站点片段命中（右填充零）', () {
      final rows = repo.fragLineStation('2900', '10', '18');
      expect(rows, hasLength(1));
      expect(rows.first.stationName, '航中路');
    });

    test('左填充零同样命中', () {
      db.execute(
        "INSERT INTO \"region_上海_2900\" VALUES"
        "(5,'metro','3号线','测试站','上海地铁','M0.i2.a','290000030008',"
        "'2900','上海',NULL,'high')",
      );
      repo.invalidate();
      expect(repo.fragLineStation('2900', '3', '8'), hasLength(1));
    });

    test('8 位编码按 2 位线路 / 2 位站点命中', () {
      final rows = repo.fragLineStation('1000', '1', '18');
      expect(rows, hasLength(1));
      expect(rows.first.stationName, '四惠枢纽');
    });

    test('站点片段单独命中可跨线路', () {
      db.execute(
        "INSERT INTO \"region_上海_2900\" VALUES"
        "(6,'metro','11号线','另一个18号站','上海地铁','M0.i3.a','290000110018',"
        "'2900','上海',NULL,'high')",
      );
      repo.invalidate();
      expect(repo.fragStation('2900', '18'), hasLength(2));
    });

    test('未命中返回空（不猜测）', () {
      expect(repo.fragStation('2900', '99'), isEmpty);
      expect(repo.fragLineStation('9999', '1', '1'), isEmpty);
    });
  });

  group('线路号 + 站点尾码（0x1E 兜底通道）', () {
    test('line_name 数字 + source_key 末两位命中', () {
      final rows = repo.lineStationTail('2900', '10', '18');
      expect(rows, hasLength(1));
      expect(rows.first.stationName, '航中路');
    });

    test('尾码 "00" 参与匹配（不因零值被丢弃）', () {
      db.execute(
        "INSERT INTO \"region_上海_2900\" VALUES"
        "(8,'metro','5号线','零号站','上海地铁','M0.i4.a','290000050000',"
        "'2900','上海',NULL,'high')",
      );
      repo.invalidate();
      final rows = repo.lineStationTail('2900', '5', '00');
      expect(rows, hasLength(1));
      expect(rows.first.stationName, '零号站');
    });

    test('未命中返回空', () {
      expect(repo.lineStationTail('2900', '99', '18'), isEmpty);
    });
  });

  group('歧义不泄露站名', () {
    test('同键不同站名时 stationName / entry 均为 null', () {
      db.execute(
        "INSERT INTO \"region_上海_2900\" VALUES"
        "(10,'metro','10号线','另一个航中路','上海地铁','M0.i0.d','290000100018',"
        "'2900','上海',NULL,'low')",
      );
      repo.invalidate();
      final r = repo.resolve(sourceKey: '290000100018', regionCode: '2900');
      expect(r.confidence, TuStationMatchConfidence.ambiguous);
      expect(r.stationName, isNull);
      expect(r.entry, isNull);
      expect(r.candidates, hasLength(2));
    });
  });

  group('缺列与 code_source 回退', () {
    test('请求 source_field 收窄但表无该列时返回空（不放大结果）', () {
      db.execute('''
CREATE TABLE "region_缺列_3000"(
  station_id INTEGER PRIMARY KEY,
  transport_type TEXT,
  line_name TEXT,
  station_name TEXT,
  source_key TEXT
)''');
      db.execute(
        "INSERT INTO regions VALUES(4,'3000','缺列','X','region_缺列_3000','tu')",
      );
      db.execute(
        "INSERT INTO \"region_缺列_3000\" VALUES"
        "(1,'metro','1号线','甲','300000010001')",
      );
      repo.invalidate();
      expect(
        repo.findStations(
          sourceKey: '300000010001',
          regionCode: '3000',
          sourceField: 'M0.i0.a',
        ),
        isEmpty,
      );
      expect(
        repo.findStations(sourceKey: '300000010001', regionCode: '3000'),
        hasLength(1),
      );
      expect(
        repo.queryOverviews().firstWhere((o) => o.code == '3000').stationCount,
        1,
      );
    });

    test('无 source_key/source_field 时按 regions.code_source 指定列查询', () {
      db.execute('''
CREATE TABLE "region_回退_4000"(
  station_id INTEGER PRIMARY KEY,
  transport_type TEXT,
  line_name TEXT,
  station_name TEXT,
  raw_code TEXT
)''');
      db.execute(
        "INSERT INTO regions VALUES(5,'4000','回退','X','region_回退_4000','raw_code')",
      );
      db.execute(
        "INSERT INTO \"region_回退_4000\" VALUES"
        "(1,'metro','1号线','乙','400000010009')",
      );
      repo.invalidate();
      final rows = repo.findStations(
        sourceKey: '400000010009',
        regionCode: '4000',
      );
      expect(rows, hasLength(1));
      expect(rows.first.stationName, '乙');
    });
  });

  group('用户覆盖优先', () {
    test('覆盖命中时直接返回覆盖结果', () {
      repo.upsertOverride(
        regionCode: '2900',
        sourceKey: '290000100018',
        sourceField: 'M0.i0.a',
        stationName: '航中路（用户修正）',
        lineName: '10号线',
        transportType: 'metro',
      );
      final resolution = repo.resolve(
        sourceKey: '290000100018',
        sourceField: 'M0.i0.a',
        regionCode: '2900',
      );
      expect(resolution.confidence, TuStationMatchConfidence.overridden);
      expect(resolution.stationName, '航中路（用户修正）');
    });

    test('source_field 空值规范化后不产生重复覆盖', () {
      repo.upsertOverride(
        regionCode: '2900',
        sourceKey: '290000200031',
        stationName: '第一次',
        transportType: 'metro',
      );
      repo.upsertOverride(
        regionCode: '2900',
        sourceKey: '290000200031',
        sourceField: '',
        stationName: '第二次',
        transportType: 'metro',
      );
      final rows = db.select(
        'SELECT COUNT(*) AS c FROM tu_user_station_overrides '
        'WHERE source_key = ?',
        ['290000200031'],
      );
      expect((rows.first['c'] as num).toInt(), 1);
      expect(
        repo.queryOverride('2900', '290000200031')!.stationName,
        '第二次',
      );
    });
  });

  group('未知站点上报', () {
    test('同键累加命中次数并保留首次时间', () {
      repo.recordUnknownStation(
        regionCode: '2900',
        sourceKey: '290000999999',
        sourceField: 'M0.i9.a',
        transportType: 'metro',
        rawValueJson: '{"v":1}',
        seenAt: DateTime(2026, 1, 1),
      );
      repo.recordUnknownStation(
        regionCode: '2900',
        sourceKey: '290000999999',
        sourceField: 'M0.i9.a',
        transportType: 'metro',
        seenAt: DateTime(2026, 2, 1),
      );
      final row = db
          .select('SELECT * FROM tu_unknown_station_reports')
          .first;
      expect((row['hit_count'] as num).toInt(), 2);
      expect(row['first_seen_at'], startsWith('2026-01-01'));
      expect(row['last_seen_at'], startsWith('2026-02-01'));
      expect(row['raw_value_json'], '{"v":1}');
    });
  });

  group('解析与统计', () {
    test('唯一候选记精确；站名不一致记歧义', () {
      expect(
        repo.resolve(sourceKey: '290000100018', regionCode: '2900').confidence,
        TuStationMatchConfidence.exact,
      );
      db.execute(
        "INSERT INTO \"region_上海_2900\" VALUES"
        "(7,'metro','10号线','另一个航中路','上海地铁','M0.i0.c','290000100018',"
        "'2900','上海',NULL,'low')",
      );
      repo.invalidate();
      expect(
        repo.resolve(sourceKey: '290000100018', regionCode: '2900').confidence,
        TuStationMatchConfidence.ambiguous,
      );
    });

    test('地区覆盖概况按原始表实时统计', () {
      final overviews = repo.queryOverviews();
      expect(overviews, hasLength(2));
      final sh = overviews.firstWhere((o) => o.code == '2900');
      expect(sh.stationCount, 2);
      expect(sh.lineCount, 2);
      expect(repo.datasetCount, 2);
      expect(repo.stationCount, 3);
    });
  });

  group('表名转义', () {
    test('恶意表名不会破坏 SQL', () {
      db.execute(
        "INSERT INTO regions VALUES"
        "(9,'9999','恶意','X','region_\"bad', 'tu')",
      );
      repo.invalidate();
      // 表不存在 → 返回空，不抛异常
      expect(repo.findStations(sourceKey: '1', regionCode: '9999'), isEmpty);
    });
  });

  group('北京 10 位 HEX 编码（昌平线 0x5E）', () {
    setUp(() {
      db.execute(
        "INSERT INTO \"region_北京_1000\" VALUES"
        "(20,'metro','昌平线','昌平西山口','北京地铁','M0.i0.a','10005E0013',"
        "'1000','北京',NULL,'high')",
      );
      db.execute(
        "INSERT INTO \"region_北京_1000\" VALUES"
        "(21,'metro','昌平线','北邵洼','北京地铁','M0.i1.a','10005E001B',"
        "'1000','北京',NULL,'high')",
      );
      db.execute(
        "INSERT INTO \"region_北京_1000\" VALUES"
        "(22,'metro','昌平线','西二旗','北京地铁','M0.i2.a','10005E0029',"
        "'1000','北京',NULL,'high')",
      );
      // 5 号线同站号：验证 5E 不会再被当成 5
      db.execute(
        "INSERT INTO \"region_北京_1000\" VALUES"
        "(23,'metro','5号线','五号线测试站','北京地铁','M0.i3.a','1000050013',"
        "'1000','北京',NULL,'high')",
      );
      // 十进制撞码回归：0x1B 的十进制 27 等于真实站码 0x27，
      // 0x1D 的十进制 29 等于真实站码 0x29。
      db.execute(
        "INSERT INTO \"region_北京_1000\" VALUES"
        "(24,'metro','昌平线','南邵','北京地铁','M0.i4.a','10005E001D',"
        "'1000','北京',NULL,'high')",
      );
      db.execute(
        "INSERT INTO \"region_北京_1000\" VALUES"
        "(25,'metro','昌平线','生命科学园','北京地铁','M0.i5.a','10005E0027',"
        "'1000','北京',NULL,'high')",
      );
      repo.invalidate();
    });

    test('10 位键切分为 2 位线路 + 4 位站点', () {
      final row =
          repo.findStations(sourceKey: '10005E0013', regionCode: '1000').first;
      expect(row.segments, ('5E', '0013'));
    });

    test('线路 5E + 站点 13 命中昌平线，不落入 5 号线', () {
      final rows = repo.fragLineStation('1000', '5E', '13');
      expect(rows, hasLength(1));
      expect(rows.first.lineName, '昌平线');
      expect(rows.first.stationName, '昌平西山口');
    });

    test('含 A-F 的站点码 001B 可命中', () {
      final rows = repo.fragLineStation('1000', '5E', '1B');
      expect(rows, hasLength(1));
      expect(rows.first.stationName, '北邵洼');
    });

    test('线路 5 只命中 5 号线（5E 不参与 5 的匹配）', () {
      final rows = repo.fragLineStation('1000', '5', '13');
      expect(rows, hasLength(1));
      expect(rows.first.lineName, '5号线');
    });

    test('0x1E 字段 005E0029 命中昌平线西二旗', () {
      final table =
          StationCodeTable.empty.withLiveSources([TuRegionLiveSource(repo)]);
      final m = table.matchLineStationField(
        field: '005E0029000000',
        cityCode: '1000',
      );
      expect(m.confidence, StationMatchConfidence.exact);
      expect(m.lineName, '昌平线');
      expect(m.stationName, '西二旗');
    });

    test('0x1E 001B 不被十进制撞码 0027 干扰（北邵洼）', () {
      final table =
          StationCodeTable.empty.withLiveSources([TuRegionLiveSource(repo)]);
      final m = table.matchLineStationField(
        field: '005E001B000000',
        cityCode: '1000',
      );
      expect(m.confidence, StationMatchConfidence.exact);
      expect(m.stationName, '北邵洼');
    });

    test('0x1E 001D 命中南邵而非西二旗（十六进制 29 撞码）', () {
      final table =
          StationCodeTable.empty.withLiveSources([TuRegionLiveSource(repo)]);
      final m = table.matchLineStationField(
        field: '005E001D000000',
        cityCode: '1000',
      );
      expect(m.confidence, StationMatchConfidence.exact);
      expect(m.stationName, '南邵');
    });

    test('内存索引（fromDatasets）同样按 HEX 口径命中', () {
      final table = StationCodeTable.fromDatasets([
        StationDataset(
          file: 'tu:1000',
          cityCode: '1000',
          system: 'tu',
          kind: 'metro',
          codes: {
            '10005E001B': StationCodeEntry(
              code: '10005E001B',
              line: '昌平线',
              station: '北邵洼',
              system: 'tu',
              kind: 'metro',
              lineCode: '5E',
              stationCode: '001B',
            ),
            '10005E0027': StationCodeEntry(
              code: '10005E0027',
              line: '昌平线',
              station: '生命科学园',
              system: 'tu',
              kind: 'metro',
              lineCode: '5E',
              stationCode: '0027',
            ),
          },
        ),
      ]);
      final m = table.matchLineStationField(
        field: '005E001B000000',
        cityCode: '1000',
      );
      expect(m.confidence, StationMatchConfidence.exact);
      expect(m.stationName, '北邵洼');
    });
  });
}