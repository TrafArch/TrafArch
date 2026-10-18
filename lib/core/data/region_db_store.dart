import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// 内建交通知识库 SQLite 的持久化存放（替代"每次启动提取临时文件 →
/// 整表读出 → 删除"的旧逻辑）：
///
/// - 资产仅在首次 / 内容变化（应用升级带来新库）时解包到
///   `<应用支持目录>/trafarch_db/<文件名>`，此后跨启动复用；
/// - 解包依据资产字节的 FNV-1a(64) 指纹与旁标文件比对，不命中才覆写；
/// - 句柄以可写方式打开并长期持有（由 [KnowledgeBase] 保存），上层在库
///   内维护派生索引表（`trafarch_*`），运行期按需点查而非整表复制。
class RegionDatabaseStore {
  RegionDatabaseStore._();

  /// 解包（必要时）并打开数据库；资产缺失 / 原生库不可用时返回 null。
  /// 缓存文件损坏（缺 regions 表）时删除重建一次。
  static Future<Database?> openCached({
    required String assetPath,
    required String fileName,
    AssetBundle? bundle,
  }) async {
    try {
      final db = await _openOnce(assetPath, fileName, bundle);
      if (db == null) return null;
      if (_looksHealthy(db)) return db;
      try {
        db.dispose();
      } catch (_) {}
      final path = await _filePath(fileName);
      for (final f in [path, '$path.fingerprint']) {
        try {
          File(f).deleteSync();
        } catch (_) {}
      }
      return _openOnce(assetPath, fileName, bundle);
    } catch (_) {
      return null;
    }
  }

  static Future<Database?> _openOnce(
    String assetPath,
    String fileName,
    AssetBundle? bundle,
  ) async {
    final bytes =
        (await (bundle ?? rootBundle).load(assetPath)).buffer.asUint8List();
    final dir = await getApplicationSupportDirectory();
    final root = Directory('${dir.path}/trafarch_db');
    if (!await root.exists()) await root.create(recursive: true);
    final file = File('${root.path}/$fileName');
    final fp = _fingerprint(bytes);
    final tag = File('${root.path}/$fileName.fingerprint');
    final reuse = await file.exists() &&
        await tag.exists() &&
        (await tag.readAsString()).trim() == fp;
    if (!reuse) {
      // 覆盖后原库内的派生索引随之失效：打开方按构建代标检测并重建。
      await file.writeAsBytes(bytes, flush: true);
      await tag.writeAsString(fp, flush: true);
    }
    return sqlite3.open(file.path);
  }

  static Future<String> _filePath(String fileName) async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/trafarch_db/$fileName';
  }

  static bool _looksHealthy(Database db) {
    try {
      return db
          .select("SELECT name FROM sqlite_master WHERE type='table' "
              "AND name='regions' LIMIT 1")
          .isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// 派生索引构建代标键（值 = user_version + 索引模型版本，一致则跳过重建）。
  static const buildStampKey = 'build';

  /// 元数据表（记录派生索引构建代标与规模计数，随资产覆盖自然清空）。
  static void ensureMetaTable(Database db) => db.execute(
        'CREATE TABLE IF NOT EXISTS trafarch_meta('
        'key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );

  static String metaValue(Database db, String key) {
    try {
      final rows = db.select(
        'SELECT value FROM trafarch_meta WHERE key = ? LIMIT 1', [key]);
      return rows.isEmpty ? '' : '${rows.first['value'] ?? ''}';
    } catch (_) {
      return '';
    }
  }

  static void setMetaValue(Database db, String key, String value) => db.execute(
        'INSERT INTO trafarch_meta(key, value) VALUES(?, ?) '
        'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
        [key, value],
      );

  /// 资产指纹：长度 + FNV-1a 64 位（VM int 乘法自然 64 位回绕）。
  static String _fingerprint(Uint8List bytes) {
    var h = 0xcbf29ce484222325;
    for (final b in bytes) {
      h = (h ^ b) * 0x100000001b3;
    }
    return '${bytes.length}-${h.toRadixString(16)}';
  }
}

/// 地区覆盖概况（知识库页地区列表一行）。
class RegionOverview {
  final String code;
  final String name;
  final String? province;
  final int lineCount;
  final int stationCount;

  const RegionOverview({
    required this.code,
    required this.name,
    this.province,
    required this.lineCount,
    required this.stationCount,
  });
}

/// 一条线路及其站点集合（知识库页线路行；[stations] 可为空 = 无站点名）。
class RegionLineCoverage {
  final String line;
  final List<String> stations;

  const RegionLineCoverage(this.line, this.stations);
}

/// 内建知识库持久化数据库 + 库内派生索引（`live_*`）点查基类。
///
/// 替代旧"每次启动提取临时文件 → 整表 SELECT * → 物化成 Dart Map →
/// 删除"的逻辑：句柄跨启动复用、长期持有；仅在资产变化（构建代标
/// 不匹配）时重建一次派生表；运行期站点 / 线路查询全部走预编译点查。
///
/// 派生表口径（由 [StationCodeTable] 查询层消费，system：tu / cu）：
/// - `live_entry`：站点条目（city_key 规范化大写 + code/type/line/station/kind）；
/// - `live_key(key, city_key, entry_id)`：登记键点查（TU 站点片段与
///   线路+站点拼接键；CU 完整匹配键 + 末四位键）；
/// - `live_frag_ls / live_frag_st / live_frag_ln`：TU 多口径数字片段索引；
/// - `live_line_name`：线路号数字 → 线路名；
/// - `trafarch_meta`：构建代标（[RegionDatabaseStore.buildStampKey]）与
///   规模计数（entries / datasets）。
abstract class RegionKnowledgeDb {
  RegionKnowledgeDb(this.db);

  /// 长期持有的持久化数据库句柄（可写，库内含派生表）。
  final Database db;

  PreparedStatement? _keyQ;
  PreparedStatement? _lineNameQ;
  PreparedStatement? _fragLsQ;
  PreparedStatement? _fragStQ;
  PreparedStatement? _fragLnQ;

  /// 点查：规范化城市键 + 登记键；无命中返回 null。
  StationCodeEntry? lookupEntry(String cityKey, String key) {
    try {
      final rows = (_keyQ ??= db.prepare(
        'SELECT e.code, e.type, e.line, e.station, e.kind, e.system '
        'FROM live_key k JOIN live_entry e ON e.id = k.entry_id '
        'WHERE k.key = ?1 AND k.city_key = ?2 '
        'ORDER BY ${_scoreSql('e')} LIMIT 1',
      )).select([key, cityKey]);
      return rows.isEmpty ? null : _rowToEntry(rows.first);
    } catch (_) {
      return null;
    }
  }

  /// 线路号数字 → 线路名；未收录返回 null。
  String? lookupLineNameDigits(String cityKey, String digits) {
    try {
      final rows = (_lineNameQ ??= db.prepare(
        'SELECT name FROM live_line_name '
        'WHERE city_key = ?1 AND digits = ?2 LIMIT 1',
      )).select([cityKey, digits]);
      return rows.isEmpty ? null : '${rows.first['name']}';
    } catch (_) {
      return null;
    }
  }

  /// 「城市+线路+站点」三键片段候选（多口径数字键，择优排序）。
  List<StationCodeEntry> fragLineStation(
      String cityKey, String lineNum, String stationNum) {
    try {
      return (_fragLsQ ??= db.prepare(
        'SELECT e.code, e.type, e.line, e.station, e.kind, e.system '
        'FROM live_frag_ls f JOIN live_entry e ON e.id = f.entry_id '
        'WHERE f.city_key = ?1 AND f.line_num = ?2 AND f.station_num = ?3 '
        'ORDER BY ${_scoreSql('e')}',
      )).select([cityKey, lineNum, stationNum]).map(_rowToEntry).toList();
    } catch (_) {
      return const [];
    }
  }

  /// 「城市+站点」片段候选。
  List<StationCodeEntry> fragStation(String cityKey, String stationNum) {
    try {
      return (_fragStQ ??= db.prepare(
        'SELECT e.code, e.type, e.line, e.station, e.kind, e.system '
        'FROM live_frag_st f JOIN live_entry e ON e.id = f.entry_id '
        'WHERE f.city_key = ?1 AND f.station_num = ?2 '
        'ORDER BY ${_scoreSql('e')}',
      )).select([cityKey, stationNum]).map(_rowToEntry).toList();
    } catch (_) {
      return const [];
    }
  }

  /// 「城市+线路」片段候选。
  List<StationCodeEntry> fragLine(String cityKey, String lineNum) {
    try {
      return (_fragLnQ ??= db.prepare(
        'SELECT e.code, e.type, e.line, e.station, e.kind, e.system '
        'FROM live_frag_ln f JOIN live_entry e ON e.id = f.entry_id '
        'WHERE f.city_key = ?1 AND f.line_num = ?2 '
        'ORDER BY ${_scoreSql('e')}',
      )).select([cityKey, lineNum]).map(_rowToEntry).toList();
    } catch (_) {
      return const [];
    }
  }

  /// 可查询条目总数 / 覆盖地区数（构建期写入 trafarch_meta，O(1) 读取）。
  int get totalEntryCount =>
      int.tryParse(RegionDatabaseStore.metaValue(db, 'entries')) ?? 0;
  int get datasetCount =>
      int.tryParse(RegionDatabaseStore.metaValue(db, 'datasets')) ?? 0;

  /// 兜底通道候选流：城市前缀扫描（线路名数字 / 站点末两位过滤在查询侧）。
  Iterable<StationCodeEntry> lineNameEntryCandidates(String cityKey) {
    try {
      return db
          .select(
            "SELECT code, type, line, station, kind, system FROM live_entry "
            "WHERE city_key LIKE '${_likeEscape(cityKey)}%'",
          )
          .map(_rowToEntry);
    } catch (_) {
      return const [];
    }
  }

  /// 地区覆盖概况列表（按地区编码升序，供知识库页）。
  Future<List<RegionOverview>> regionsOverview();

  /// 单地区线路行（线路名 + 去重站点名，供知识库页）。
  Future<List<RegionLineCoverage>> linesForRegion(
      String cityKey, String system);

  /// 关闭句柄并释放预编译语句（幂等）。
  void close() {
    for (final s in [_keyQ, _lineNameQ, _fragLsQ, _fragStQ, _fragLnQ]) {
      try {
        s?.dispose();
      } catch (_) {}
    }
    _keyQ = _lineNameQ = _fragLsQ = _fragLnQ = null;
    try {
      db.dispose();
    } catch (_) {}
  }

  static StationCodeEntry _rowToEntry(Row r) => StationCodeEntry(
        code: '${r['code'] ?? ''}',
        type: _nul(r['type']),
        line: _nul(r['line']),
        station: _nul(r['station']),
        kind: _nul(r['kind']),
        system: _nul(r['system']),
      );

  static String? _nul(Object? v) {
    final s = '$v';
    return s.isEmpty ? null : s;
  }

  /// LIKE 模式转义（单引号）。
  static String _likeEscape(String s) => s.replaceAll("'", "''");

  /// 择优排序 SQL 片段（分值越小越优）：有站点名优先，其次类别优先级
  /// （metro > brt > bus > bike > 其它），与 StationCodeTable 口径一致。
  static String _scoreSql(String alias) =>
      "CASE WHEN COALESCE($alias.station,'')='' THEN 100 ELSE 0 END + "
      'CASE $alias.kind '
      "WHEN 'metro' THEN 0 WHEN 'brt' THEN 1 WHEN 'bus' THEN 2 "
      "WHEN 'bike' THEN 3 ELSE 4 END";

  /// 派生表统一 DDL（重建方先 DROP 再执行；含 SQLite 侧点查索引）。
  static const createTablesSql = '''
CREATE TABLE IF NOT EXISTS live_entry(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  city_key TEXT NOT NULL, code TEXT NOT NULL,
  type TEXT, line TEXT, station TEXT,
  kind TEXT NOT NULL DEFAULT 'other', system TEXT NOT NULL DEFAULT 'tu');
CREATE TABLE IF NOT EXISTS live_key(
  key TEXT NOT NULL, city_key TEXT NOT NULL, entry_id INTEGER NOT NULL,
  PRIMARY KEY(city_key, key));
CREATE TABLE IF NOT EXISTS live_frag_ls(
  city_key TEXT NOT NULL, line_num TEXT NOT NULL,
  station_num TEXT NOT NULL, entry_id INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS live_frag_st(
  city_key TEXT NOT NULL, station_num TEXT NOT NULL, entry_id INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS live_frag_ln(
  city_key TEXT NOT NULL, line_num TEXT NOT NULL, entry_id INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS live_line_name(
  city_key TEXT NOT NULL, digits TEXT NOT NULL, name TEXT NOT NULL,
  PRIMARY KEY(city_key, digits));
CREATE INDEX IF NOT EXISTS idx_live_key ON live_key(key, city_key);
CREATE INDEX IF NOT EXISTS idx_live_frag_ls ON live_frag_ls(city_key, line_num, station_num);
CREATE INDEX IF NOT EXISTS idx_live_frag_st ON live_frag_st(city_key, station_num);
CREATE INDEX IF NOT EXISTS idx_live_frag_ln ON live_frag_ln(city_key, line_num);
''';
}
