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

/// 交通联合（TU）地区 / 线路站点数据库读取器（外部 SQLite，持久化只读接入）。
///
/// 数据源：assets/data/TrafArch_Database_TU.sqlite。旧实现每次启动把整库文件
/// 写入临时目录、打开读取后再删除；现改为经 [RegionDatabaseStore] 持久化到应用
/// 支持目录并跨启动复用（仅资产指纹变化时覆盖重建），读取期按目标表定向查询，
/// 不再每次拷贝整库。站点行按 source_field 切出「线路片段 / 站点片段」并登记
/// **复合键（含线路信息）**，规避同末四位跨线路覆盖。资产缺失 / 原生库不可用 /
/// 读取异常时返回 null（调用方回退既有知识库，不阻断、不猜测）。
class TunionRegionDatabase {
  static const assetPath = 'assets/data/TrafArch_Database_TU.sqlite';
  static const _fileName = 'trafarch_database_tu.sqlite';

  static Future<TunionRegionDatabaseContent?> load({
    AssetBundle? bundle,
  }) async {
    Database? db;
    try {
      db = await RegionDatabaseStore.openCached(
        assetPath: assetPath,
        fileName: _fileName,
        bundle: bundle,
      );
      final handle = db;
      if (handle == null) return null;

      int? dbVersion;
      try {
        dbVersion =
            (handle.select('PRAGMA user_version').first['user_version'] as num?)
                ?.toInt();
        if (dbVersion == 0) dbVersion = null;
      } catch (_) {
        dbVersion = null;
      }

      // 地区主表（region_id / region_code / region_name / province /
      // table_name / code_source；列缺失按空值降级，不猜测）。
      final regions = <RegionInfo>[];
      final rcols = _tableColumns(handle, 'regions');
      for (final r in handle.select('SELECT * FROM regions')) {
        final code = _digits(_cell(r, rcols, 'region_code'));
        final name = _cell(r, rcols, 'region_name').trim();
        if (code.isEmpty || name.isEmpty) continue;
        regions.add(RegionInfo(
          regionId: (r['region_id'] as num?)?.toInt() ?? 0,
          regionCode: code,
          regionName: name,
          province: _nullIfEmpty(_cell(r, rcols, 'province')),
          tableName: _cell(r, rcols, 'table_name').trim(),
          codeSource: _cell(r, rcols, 'code_source').trim(),
        ));
      }

      // 发卡号段（issuer_city_codes：prefix / issuer / city_name / card_name /
      // region_code）。
      final issuerRows = <RegionIssuerRow>[];
      final icols = _tableColumns(handle, 'issuer_city_codes');
      try {
        for (final r in handle.select('SELECT * FROM issuer_city_codes')) {
          final cityName = _cell(r, icols, 'city_name').trim();
          final issuer = _digits(_cell(r, icols, 'issuer'));
          if (cityName.isEmpty && issuer.isEmpty) continue;
          issuerRows.add(RegionIssuerRow(
            regionCode: _digits(_cell(r, icols, 'region_code')),
            cityName: cityName,
            issuer: issuer,
            cardName: _nullIfEmpty(_cell(r, icols, 'card_name')),
            prefix: _digits(_cell(r, icols, 'prefix')),
          ));
        }
      } catch (_) {
        // 无该表：仅用 regions。
      }

      // 站点数据集：每地区一张 region_* 表。
      final datasets = <StationDataset>[];
      for (final region in regions) {
        if (region.tableName.isEmpty) continue;
        final ds = _readStationTable(handle, region.tableName, region);
        if (ds != null) datasets.add(ds);
      }

      return TunionRegionDatabaseContent(
        regions: regions,
        issuerCityCodes: issuerRows,
        stationDatasets: datasets,
        databaseVersion: dbVersion,
      );
    } catch (_) {
      return null;
    } finally {
      try {
        db?.dispose();
      } catch (_) {}
    }
  }

  /// 读取一张站点表并构建数据集：从编码字段（优先 source_field，回退
  /// source_key / code_source 指定列）取末尾数字串，按位数切出线路 / 站点片段
  /// （12 位：5-8 线路、9-12 站点；8 位：5-6 线路、7-8 站点），并登记复合键
  /// （站点片段 + 线路拼接键；非标准位数退化为「线路信息 + 末四位」，绝不
  /// 只用裸末四位，避免跨线路覆盖）。
  static StationDataset? _readStationTable(
    Database db,
    String table,
    RegionInfo region,
  ) {
    final cols = _tableColumns(db, table);
    if (cols == null) return null;
    final codeField = _firstPresent(cols, const ['source_field', 'source_key']) ??
        (cols.contains(region.codeSource) ? region.codeSource : null);
    if (codeField == null) return null;
    if (!cols.contains('station_name') && !cols.contains('line_name')) {
      return null;
    }
    final transportCol =
        _firstPresent(cols, const ['transport_type', 'kind', 'type']);

    final codes = <String, StationCodeEntry>{};
    for (final r in db.select('SELECT * FROM "$table"')) {
      final raw = _digits(_cell(r, cols, codeField));
      if (raw.isEmpty) continue;
      final line = _nullIfEmpty(_cell(r, cols, 'line_name'));
      final station = _nullIfEmpty(_cell(r, cols, 'station_name'));
      if (line == null && station == null) continue;
      final transport =
          transportCol == null ? '' : _cell(r, cols, transportCol).trim();
      final tail = RegExp(r'(\d+)$').firstMatch(raw)?.group(1) ?? raw;

      String? lineFrag;
      String? stationFrag;
      if (tail.length == 12) {
        lineFrag = tail.substring(4, 8);
        stationFrag = tail.substring(8, 12);
      } else if (tail.length == 8) {
        lineFrag = tail.substring(4, 6);
        stationFrag = tail.substring(6, 8);
      }

      final type = _typeName(transport);
      final kind = _kind(transport);
      for (final key in _stationKeys(tail, lineFrag, stationFrag, line)) {
        codes.putIfAbsent(
          key,
          () => StationCodeEntry(
            code: key,
            type: type,
            line: line,
            station: station,
            system: 'tu',
            kind: kind,
            datasetFile: 'tu:${region.regionCode}',
            lineCode: lineFrag,
            stationCode: stationFrag,
          ),
        );
      }
    }
    if (codes.isEmpty) return null;
    return StationDataset(
      file: 'tu:${region.regionCode}',
      cityCode: region.regionCode,
      cityName: region.regionName,
      province: region.province,
      system: 'tu',
      kind: 'mixed',
      codes: codes,
    );
  }

  /// 站点登记键（始终含线路信息）：12/8 位 → [站点片段, 线路片段+站点片段]；
  /// 其余 ≥4 位 → [末四位, 线路数字(或地区前缀)+末四位]。
  static List<String> _stationKeys(
    String tail,
    String? lineFrag,
    String? stationFrag,
    String? lineName,
  ) {
    final keys = <String>[];
    if ((tail.length == 12 || tail.length == 8) &&
        lineFrag != null &&
        stationFrag != null) {
      keys
        ..add(stationFrag)
        ..add('$lineFrag$stationFrag');
    } else if (tail.length >= 4) {
      final last4 = tail.substring(tail.length - 4);
      final linePart = _lineDigits(lineName) ??
          (tail.length > 4 ? tail.substring(0, tail.length - 4) : '');
      keys
        ..add(last4)
        ..add('$linePart$last4');
    }
    return keys.where((k) => k.isNotEmpty).toList();
  }

  static String? _lineDigits(String? line) {
    if (line == null) return null;
    final m = RegExp(r'(\d+)').firstMatch(line);
    if (m == null) return null;
    final t = m.group(1)!.replaceFirst(RegExp(r'^0+'), '');
    return t.isEmpty ? '0' : t;
  }

  static Set<String>? _tableColumns(Database db, String table) {
    try {
      return {
        for (final r in db.select('PRAGMA table_info("$table")')) '${r['name'] ?? ''}',
      };
    } catch (_) {
      return null;
    }
  }

  static String? _firstPresent(Set<String> cols, List<String> candidates) {
    for (final c in candidates) {
      if (cols.contains(c)) return c;
    }
    return null;
  }

  static String _cell(Row r, Set<String>? cols, String name) {
    if (cols == null || !cols.contains(name)) return '';
    return '${r[name] ?? ''}';
  }

  static String? _kind(String transport) => switch (transport) {
        'metro' => 'metro',
        'brt' => 'brt',
        'bus' => 'bus',
        'bike' => 'bike',
        'intercity_rail' => 'intercity_rail',
        _ => 'other',
      };

  static String? _typeName(String transport) => switch (transport) {
        'metro' => '地铁',
        'brt' => 'BRT',
        'bus' => '公交',
        'bike' => '自行车',
        'intercity_rail' => '城际铁路',
        _ => null,
      };

  static String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  static String? _nullIfEmpty(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }
}