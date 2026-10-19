import 'package:flutter/services.dart' show AssetBundle;
import 'package:sqlite3/sqlite3.dart';

import 'station_codes.dart';
import 'tu_database.dart';
import 'tu_station_repository.dart';

/// 地区行（regions 表）。
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

/// 发卡号段行（issuer_city_codes 表）。
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

/// 线路站点库读取内容：地区识别 + 卡名识别 + 原始地区表直查源。
///
/// 不再持有 `kb_*` 派生索引：TU 站点查询一律经 [TuStationRepository]
/// 直查原始 `region_*` 表。
class TunionRegionDatabaseContent {
  final List<RegionInfo> regions;
  final List<RegionIssuerRow> issuerCityCodes;
  final int? databaseVersion;

  /// 原始地区表直查源（实现 [LiveStationSource]）。
  final LiveStationSource? live;

  /// 原始地区表仓储：供页面 / 诊断查询，不直接暴露 SQL。
  final TuStationRepository? repository;

  const TunionRegionDatabaseContent({
    required this.regions,
    required this.issuerCityCodes,
    this.databaseVersion,
    this.live,
    this.repository,
  });

  int get stationDatasetCount => live?.datasetCount ?? 0;
  int get stationEntryCount => live?.totalEntryCount ?? 0;
}

/// 交通联合（TU）地区 / 线路站点数据库读取器。
class TunionRegionDatabase {
  TunionRegionDatabase._();

  static const assetPath = TuDatabase.assetPath;

  static Future<TunionRegionDatabaseContent?> load({
    AssetBundle? bundle,
  }) async {
    final tu = await TuDatabase.open(bundle: bundle);
    if (tu == null) return null;
    final repository = tu.repository;
    final regions = repository.regions;
    if (regions.isEmpty) return null;
    return TunionRegionDatabaseContent(
      regions: [
        for (final r in regions)
          RegionInfo(
            regionId: r.regionId,
            regionCode: r.regionCode,
            regionName: r.regionName,
            province: r.province,
            tableName: r.tableName,
            codeSource: r.codeSource,
          ),
      ],
      issuerCityCodes: _IssuerReader.read(tu.db),
      databaseVersion: tu.userVersion,
      live: TuRegionLiveSource(repository),
      repository: repository,
    );
  }
}

/// `issuer_city_codes` 读取（列名自适应，缺失时返回空表）。
class _IssuerReader {
  _IssuerReader._();

  static List<RegionIssuerRow> read(Database db) {
    final out = <RegionIssuerRow>[];
    final cols = _tableColumns(db, 'issuer_city_codes');
    if (cols == null) return out;
    try {
      for (final row in db.select('SELECT * FROM issuer_city_codes')) {
        final cityName = _cell(row, cols, 'city_name');
        final issuer = _digits(_cell(row, cols, 'issuer'));
        if (cityName.isEmpty && issuer.isEmpty) continue;
        out.add(RegionIssuerRow(
          regionCode: _digits(_cell(row, cols, 'region_code')),
          cityName: cityName,
          issuer: issuer,
          cardName: _nullIfEmpty(_cell(row, cols, 'card_name')),
          prefix: _digits(_cell(row, cols, 'prefix')),
        ));
      }
    } catch (_) {}
    return out;
  }

  static Set<String>? _tableColumns(Database db, String table) {
    try {
      return {
        for (final row in db.select('PRAGMA table_info("$table")'))
          '${row['name'] ?? ''}',
      };
    } catch (_) {
      return null;
    }
  }

  static String _cell(Row row, Set<String> cols, String name) {
    if (!cols.contains(name)) return '';
    return '${row[name] ?? ''}'.trim();
  }

  static String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  static String? _nullIfEmpty(String s) => s.isEmpty ? null : s;
}