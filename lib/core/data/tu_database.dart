import 'package:flutter/services.dart' show AssetBundle;
import 'package:sqlite3/sqlite3.dart';

import 'region_db_store.dart';
import 'tu_station_repository.dart';

/// 交通联合（TU）站点数据库门面：资产解包、持久化与 App 自有表迁移。
///
/// 与旧实现的关键差异：
/// - 不再为 TU 构建 `kb_*` 派生索引表，站点查询一律直查原始 `region_*`
///   地区表，以 `source_key`（必要时叠加 `source_field` / `transport_type`）
///   作为查询入口；
/// - 原始 `regions` / `region_*` / `record_provenance` 等表结构完全不动；
/// - 只追加两张 App 自有表（用户覆盖 / 未知站点上报），与原始数据分离；
/// - 资产仅在首次或内容变化时解包（复用 [RegionDatabaseStore] 的指纹
///   机制），之后本地补充的数据不会被启动覆盖。
class TuDatabase {
  TuDatabase._(this.db) : repository = TuStationRepository(db);

  final Database db;

  /// 原始地区表直查仓储（页面 / 诊断统一入口，不直接暴露 SQL）。
  final TuStationRepository repository;

  static const assetPath = 'assets/data/TrafArch_Database_TU.sqlite';
  static const _fileName = 'trafarch_database_tu.sqlite';

  /// 旧版本 TU 派生索引清理标记（只清一次，避免每次启动写库）。
  static const _legacyPurgeKey = 'tu.legacy_purged';

  static TuDatabase? _instance;

  /// 打开（或复用）TU 数据库。
  ///
  /// 返回 null 表示资产缺失 / 文件损坏 / 迁移失败，调用方按「无库」降级，
  /// 不阻断其余知识库加载。
  static Future<TuDatabase?> open({AssetBundle? bundle}) async {
    final cached = _instance;
    if (cached != null) return cached;

    Database? handle;
    try {
      handle = await RegionDatabaseStore.openCached(
        assetPath: assetPath,
        fileName: _fileName,
        bundle: bundle,
      );
      if (handle == null) return null;
      if (!_hasRegions(handle)) {
        handle.dispose();
        return null;
      }
      // App 自有表失败（只读介质 / 磁盘满）不应阻断只读查询；
      // 覆盖与上报能力此时不可用，由 query/upsert 自行降级。
      try {
        TuStationRepository.ensureAppTables(handle);
      } catch (_) {}
      _purgeLegacyTuIndex(handle);
      return _instance = TuDatabase._(handle);
    } catch (_) {
      try {
        handle?.dispose();
      } catch (_) {}
      return null;
    }
  }

  /// 关闭单例（测试 / 热重载后重新解包用）。
  static void reset() {
    final cached = _instance;
    _instance = null;
    try {
      cached?.db.dispose();
    } catch (_) {}
  }

  /// `PRAGMA user_version`：数据库构建版本（未设置为 null）。
  int? get userVersion {
    try {
      final v = (db.select('PRAGMA user_version').first['user_version']
                  as num?)
              ?.toInt() ??
          0;
      return v == 0 ? null : v;
    } catch (_) {
      return null;
    }
  }

  /// `source_metadata` 原始统计（只读展示，不用于判断数据完整性）。
  Map<String, String> get sourceMetadata {
    final out = <String, String>{};
    try {
      final cols = _tableColumns(db, 'source_metadata');
      if (cols == null) return out;
      final keyCol = _firstPresent(cols, const ['key', 'meta_key', 'name']);
      final valueCol =
          _firstPresent(cols, const ['value', 'meta_value', 'content']);
      if (keyCol == null || valueCol == null) return out;
      for (final row in db.select('SELECT * FROM source_metadata')) {
        final key = '${row[keyCol] ?? ''}'.trim();
        if (key.isEmpty) continue;
        out[key] = '${row[valueCol] ?? ''}'.trim();
      }
    } catch (_) {}
    return out;
  }

  static bool _hasRegions(Database db) {
    try {
      return db
          .select(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name='regions' LIMIT 1",
          )
          .isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// 清理旧版本遗留的 TU 派生索引行（表结构保留给 CU 使用）。
  static void _purgeLegacyTuIndex(Database db) {
    try {
      RegionDatabaseStore.ensureMetaTable(db);
      if (RegionDatabaseStore.metaValue(db, _legacyPurgeKey) == '1') return;
    } catch (_) {
      return;
    }
    for (final table in const [
      'kb_entry',
      'kb_key',
      'kb_frag_ls',
      'kb_frag_st',
      'kb_frag_ln',
      'kb_line_name',
      'kb_region',
    ]) {
      try {
        db.execute('DELETE FROM "$table" WHERE system = ?', ['tu']);
      } catch (_) {}
    }
    try {
      db.execute(
        "DELETE FROM trafarch_meta WHERE key IN "
        "('build.tu', 'entries.tu', 'datasets.tu')",
      );
      RegionDatabaseStore.setMetaValue(db, _legacyPurgeKey, '1');
    } catch (_) {}
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

  static String? _firstPresent(Set<String> cols, List<String> candidates) {
    for (final c in candidates) {
      if (cols.contains(c)) return c;
    }
    return null;
  }
}