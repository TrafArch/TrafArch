import 'dart:io';

import 'package:flutter/services.dart' show rootBundle, AssetBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'station_codes.dart';

/// 地区行（regions 表）：地区编码 → 地区名 / 省份 / 站点数据表名。
class RegionInfo {
  final int regionId;
  final String regionCode;
  final String regionName;
  final String? province;
  final String tableName;
  final String codeSource;

  const RegionInfo({
    required this.regionId,
    required this.regionCode,
    required this.regionName,
    this.province,
    required this.tableName,
    required this.codeSource,
  });
}

/// 发卡号段行（issuer_city_codes 表）：卡号前缀 / 发卡机构 → 城市 / 卡名。
class RegionIssuerRow {
  final String regionCode;
  final String cityName;
  final String issuer;
  final String? cardName;
  final String prefix;

  const RegionIssuerRow({
    required this.regionCode,
    required this.cityName,
    required this.issuer,
    this.cardName,
    required this.prefix,
  });
}

/// 线路站点库读取内容：地区识别（regions/城市）+ 卡片名称识别
/// （issuer_city_codes）+ 线路站点（各 region_* 表）。
///
/// 只承载数据、不含查询逻辑；由 [KnowledgeBase] 合并进卡号前缀库 /
/// 城市码表 / 站点代码表（1A：数据库优先、JSON 兜底）。
class TunionRegionDatabaseContent {
  final List<RegionInfo> regions;
  final List<RegionIssuerRow> issuerCityCodes;
  final List<StationDataset> stationDatasets;

  const TunionRegionDatabaseContent({
    required this.regions,
    required this.issuerCityCodes,
    required this.stationDatasets,
  });

  int get stationDatasetCount => stationDatasets.length;
  int get stationEntryCount =>
      stationDatasets.fold(0, (a, d) => a + d.codes.length);
}

/// 交通联合（TU）地区 / 卡名 / 线路站点数据库（外部 SQLite，只读接入）。
///
/// 数据源：assets/data/TrafArch_Database_TU.sqlite（schema_version 4，
/// 交通联合独立站点库）。Android 资产只读，先提取到临时文件，
/// 经 [sqlite3]（随 drift / sqlite3_flutter_libs 打包的原生库）打开；
/// 读取完毕删除临时文件。资产缺失、原生库不可用或读取异常时返回 null
/// （调用方回退既有 JSON 知识库，不阻断、不猜测）。
class TunionRegionDatabase {
  static const assetPath = 'assets/data/TrafArch_Database_TU.sqlite';

  /// 源字段尾码：取字符串末尾的连续数字（如 "M0.W.a306000010030"
  /// → "306000010030"）。
  static final _trailingDigits = RegExp(r'(\d+)$');

  /// 站点标识编码键：按位数切分源字段末尾数字，提取线路/站点片段并产出
  /// 匹配键集合（TU 匹配规则）：
  /// - 12 位：1-4 地区码、5-8 线路码、9-12 站点码；
  /// - 8 位：1-4 地区码、5-6 线路码、7-8 站点码；
  /// - 其他位数（≥4）：回退取末尾连续数字的后四位（旧口径，避免漏登记），
  ///   此时不产出 lineCode 片段。
  /// 匹配键含「站点码」与「线路码+站点码」两种，分别命中卡片侧站点查询与
  /// 线路+站点拼接查询；无有效切分时返回 null（不登记，避免误命中）。
  static ({String? line, String station, List<String> keys})? _stationKey(
      String raw) {
    final tail = _trailingDigits.firstMatch(raw.trim())?.group(1);
    if (tail == null) return null;
    if (tail.length == 12) {
      final line = tail.substring(4, 8);
      final station = tail.substring(8, 12);
      return (line: line, station: station, keys: [station, '$line$station']);
    }
    if (tail.length == 8) {
      final line = tail.substring(4, 6);
      final station = tail.substring(6, 8);
      return (line: line, station: station, keys: [station, '$line$station']);
    }
    if (tail.length >= 4) {
      final station = tail.substring(tail.length - 4);
      return (line: null, station: station, keys: [station]);
    }
    return null;
  }

  TunionRegionDatabase._();

  static Future<TunionRegionDatabaseContent?> load({
    AssetBundle? bundle,
  }) async {
    final root = bundle ?? rootBundle;
    File? tmp;
    Database? db;
    try {
      final data = await root.load(assetPath);
      final dir = await getTemporaryDirectory();
      tmp = File('${dir.path}/trafarch_database_tu.sqlite');
      await tmp.writeAsBytes(data.buffer.asUint8List(), flush: true);

      db = sqlite3.open(tmp.path);
      final regions = <RegionInfo>[];
      for (final r in db.select(
        'SELECT region_id, region_code, region_name, province, table_name, '
        'code_source FROM regions',
      )) {
        final info = RegionInfo(
          regionId: (r['region_id'] as num?)?.toInt() ?? 0,
          regionCode: '${r['region_code'] ?? ''}'.trim(),
          regionName: '${r['region_name'] ?? ''}'.trim(),
          province: _nullIfEmpty('${r['province'] ?? ''}'),
          tableName: '${r['table_name'] ?? ''}'.trim(),
          codeSource: '${r['code_source'] ?? ''}'.trim(),
        );
        if (info.regionCode.isEmpty || info.tableName.isEmpty) continue;
        regions.add(info);
      }

      final issuerRows = <RegionIssuerRow>[];
      for (final r in db.select(
        'SELECT region_code, city_name, issuer, card_name, prefix '
        'FROM issuer_city_codes',
      )) {
        final prefix = _digits('${r['prefix'] ?? ''}');
        final issuer = _digits('${r['issuer'] ?? ''}');
        final cityName = '${r['city_name'] ?? ''}'.trim();
        if (prefix.isEmpty && issuer.isEmpty) continue;
        if (cityName.isEmpty) continue;
        issuerRows.add(RegionIssuerRow(
          regionCode: _digits('${r['region_code'] ?? ''}'),
          cityName: cityName,
          issuer: issuer,
          cardName: _nullIfEmpty('${r['card_name'] ?? ''}'),
          prefix: prefix,
        ));
      }

      final aliasesByRegionId = <int, Set<String>>{};
      try {
        for (final r in db.select(
          'SELECT region_id, source_table FROM region_aliases',
        )) {
          final id = (r['region_id'] as num?)?.toInt();
          final table = '${r['source_table'] ?? ''}'.trim();
          if (id == null || table.isEmpty) continue;
          aliasesByRegionId.putIfAbsent(id, () => {}).add(table);
        }
      } catch (_) {
        // 无 region_aliases 表：忽略别名，仅用 regions.table_name
      }

      final stationsByRegion = <String, Map<String, StationCodeEntry>>{};
      final cityNameByRegion = <String, String>{};
      final provinceByRegion = <String, String?>{};
      for (final region in regions) {
        cityNameByRegion[region.regionCode] = region.regionName;
        provinceByRegion[region.regionCode] = region.province;
        final tables = <String>{region.tableName}
          ..addAll(aliasesByRegionId[region.regionId] ?? const {});
        for (final table in tables) {
          _readStationTable(
            db,
            table,
            region.regionCode,
            stationsByRegion
                .putIfAbsent(region.regionCode, () => <String, StationCodeEntry>{}),
          );
        }
      }

      final datasets = <StationDataset>[];
      stationsByRegion.forEach((regionCode, codes) {
        if (codes.isEmpty) return;
        datasets.add(StationDataset(
          file: 'sqlite:$regionCode',
          cityCode: regionCode,
          cityName: cityNameByRegion[regionCode],
          province: provinceByRegion[regionCode],
          system: 'tu',
          kind: 'mixed',
          codes: codes,
        ));
      });

      return TunionRegionDatabaseContent(
        regions: regions,
        issuerCityCodes: issuerRows,
        stationDatasets: datasets,
      );
    } catch (_) {
      // 资产缺失 / 原生库不可用 / 表结构异常：整体降级为空（调用方回退）
      return null;
    } finally {
      try {
        db?.close();
      } catch (_) {}
      try {
        if (tmp != null && tmp.existsSync()) tmp.deleteSync();
      } catch (_) {}
    }
  }

  /// 读取单张站点表（表名来自 regions/别名，仅取白名单命中的标准表；
  /// 表不存在或列缺失时跳过该表，不猜测）。
  ///
  /// 站点编码列自适应：新版地区表以 `source_key` 登记，兼容旧版
  /// `source_field`；两者皆无则跳过该表（不猜测）。
  static void _readStationTable(
    Database db,
    String table,
    String fallbackRegionCode,
    Map<String, StationCodeEntry> out,
  ) {
    final cols = _tableColumns(db, table);
    if (cols == null) return;
    final codeCol = _firstColumn(cols, const [
      'source_key',
      'source_field',
      'code',
      'station_code',
    ]);
    if (codeCol == null) return;
    final regionCol =
        _firstColumn(cols, const ['source_region_code', 'region_code']);
    List<Row> rows;
    try {
      rows = db.select('SELECT * FROM "$table"');
    } catch (_) {
      return;
    }
    for (final r in rows) {
      // 站点编码来源：source_key / source_field（按位数切分地区/线路/站点码，
      // 如 12 位 "306000010030" → 站点 "0030"、8 位 "39100631" → 站点 "31"）。
      final code = _cell(r, cols, codeCol).trim();
      final parsed = _stationKey(code);
      if (parsed == null) continue;
      final regionDigits =
          regionCol == null ? '' : _digits(_cell(r, cols, regionCol));
      final cityCode =
          regionDigits.isEmpty ? fallbackRegionCode : regionDigits;
      final transport = _cell(r, cols, 'transport_type').trim();
      final line = _nullIfEmpty(_cell(r, cols, 'line_name'));
      final station = _nullIfEmpty(_cell(r, cols, 'station_name'));
      if (station == null && line == null) continue;
      final entry = StationCodeEntry(
        code: parsed.station,
        type: _typeName(transport),
        line: line,
        station: station,
        system: 'tu',
        kind: _kind(transport),
        datasetFile: 'sqlite:$cityCode',
        lineCode: parsed.line,
        stationCode: parsed.station,
      );
      for (final key in parsed.keys) {
        out.putIfAbsent(key, () => entry);
      }
    }
  }

  /// 读取表的列名集合（PRAGMA table_info）；表不存在或异常返回 null。
  static Set<String>? _tableColumns(Database db, String table) {
    try {
      return {
        for (final r in db.select('PRAGMA table_info("$table")'))
          '${r['name'] ?? ''}',
      };
    } catch (_) {
      return null;
    }
  }

  /// 候选列名中首个存在于表中的列（均不存在返回 null）。
  static String? _firstColumn(Set<String> cols, List<String> candidates) {
    for (final c in candidates) {
      if (cols.contains(c)) return c;
    }
    return null;
  }

  /// 安全读取单元格：列不存在时返回空串（避免访问未知列抛异常）。
  static String _cell(Row r, Set<String> cols, String name) {
    if (!cols.contains(name)) return '';
    return '${r[name] ?? ''}';
  }

  static String? _kind(String transport) => switch (transport) {
        'metro' => 'metro',
        'brt' => 'brt',
        'bus' => 'bus',
        'intercity_rail' => 'intercity_rail',
        _ => 'other',
      };

  static String? _typeName(String transport) => switch (transport) {
        'metro' => '地铁',
        'brt' => 'BRT',
        'bus' => '公交',
        'intercity_rail' => '城际铁路',
        _ => null,
      };

  static String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  static String? _nullIfEmpty(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }
}