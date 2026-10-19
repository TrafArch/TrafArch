import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'station_codes.dart';

/// 内建交通知识库 SQLite 的持久化存放。
///
/// - 资产仅在首次 / 内容变化时解包到 `<应用支持目录>/trafarch_db/<文件名>`；
/// - 派生索引按体系（tu / cu）分别构建，构建代标独立；
/// - 运行期全部走库内点查，不整表复制。
class RegionDatabaseStore {
  RegionDatabaseStore._();

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

  /// 构建代标键前缀；完整键按体系区分（`build.tu` / `build.cu`）。
  static const buildStampKey = 'build';

  static String stampKey(String system) => '$buildStampKey.$system';

  static void ensureMetaTable(Database db) => db.execute(
        'CREATE TABLE IF NOT EXISTS trafarch_meta('
        'key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );

  static String metaValue(Database db, String key) {
    try {
      final rows = db.select(
        'SELECT value FROM trafarch_meta WHERE key = ? LIMIT 1',
        [key],
      );
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

  static String _fingerprint(Uint8List bytes) {
    var h = 0xcbf29ce484222325;
    for (final b in bytes) {
      h = (h ^ b) * 0x100000001b3;
    }
    return '${bytes.length}-${h.toRadixString(16)}';
  }

  static void ensureSchema(Database db) {
    ensureMetaTable(db);
    db.execute(RegionKnowledgeDb.createTablesSql);
  }

  /// 重建前清空派生表（同时清理历史 `live_*` 表）。
  static void resetDerived(Database db) {
    for (final t in const [
      'kb_entry', 'kb_key', 'kb_frag_ls', 'kb_frag_st', 'kb_frag_ln',
      'kb_line_name', 'kb_region', 'kb_terminal_rule',
      'live_entry', 'live_key', 'live_frag_ls', 'live_frag_st',
      'live_frag_ln', 'live_line_name', 'live_region', 'live_cu_rule',
    ]) {
      try {
        db.execute('DROP TABLE IF EXISTS "$t"');
      } catch (_) {}
    }
    ensureSchema(db);
  }

  static int userVersion(Database db) {
    try {
      return (db.select('PRAGMA user_version').first['user_version'] as num?)
              ?.toInt() ??
          0;
    } catch (_) {
      return 0;
    }
  }

  static String normalizeCity(String cityCode) =>
      cityCode.replaceAll(' ', '').toUpperCase();

  static String? lineNameDigits(String? line) {
    if (line == null) return null;
    final m = RegExp(r'(\d+)').firstMatch(line);
    if (m == null) return null;
    final t = m.group(1)!.replaceFirst(RegExp(r'^0+'), '');
    return t.isEmpty ? '0' : t;
  }

  static Set<String> tuFragmentKeys(String? fragment) {
    if (fragment == null) return const {};
    final digits = fragment.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return const {};
    final keys = <String>{};
    void add(String part) {
      final s = part.replaceFirst(RegExp(r'^0+'), '');
      if (s.isNotEmpty) keys.add(s);
    }

    add(digits);
    if (digits.length > 2) {
      add(digits.substring(0, 2));
      add(digits.substring(digits.length - 2));
    }
    return keys;
  }

  /// 写入某体系的规模计数（entries 按「城市 + 编码」去重）。
  static void refreshCounts(Database db, String system) {
    try {
      final entries = (db.select(
        "SELECT COUNT(DISTINCT city_key || '|' || code) AS c "
        'FROM kb_entry WHERE system = ?1',
        [system],
      ).first['c'] as num?)?.toInt() ??
          0;
      final datasets = (db.select(
        'SELECT COUNT(*) AS c FROM kb_region WHERE system = ?1',
        [system],
      ).first['c'] as num?)?.toInt() ??
          0;
      setMetaValue(db, 'entries.$system', '$entries');
      setMetaValue(db, 'datasets.$system', '$datasets');
    } catch (_) {}
  }
}

/// 流式写入会话：单事务 + 预编译语句。
///
/// 调用方逐行 `addEntry`，最后 `commit`；任一步抛异常时 `rollback`，
/// 不会留下半成品索引。语句在提交 / 回滚时统一释放。
class RegionIngestSession {
  RegionIngestSession._(this.db, this.system);

  final Database db;
  final String system;

  PreparedStatement? _insEntry;
  PreparedStatement? _insKey;
  PreparedStatement? _insLineName;
  PreparedStatement? _insFragLs;
  PreparedStatement? _insFragSt;
  PreparedStatement? _insFragLn;
  PreparedStatement? _insRule;
  PreparedStatement? _insRegion;
  bool _closed = false;

  static RegionIngestSession? begin(Database db, String system) {
    try {
      db.execute('BEGIN IMMEDIATE');
    } catch (e) {
      // ignore: avoid_print
      print('[RegionIngestSession] 开启事务失败($system): $e');
      return null;
    }
    final session = RegionIngestSession._(db, system);
    try {
      session._prepare();
      return session;
    } catch (e) {
      // ignore: avoid_print
      print('[RegionIngestSession] 预编译失败($system): $e');
      session.rollback();
      return null;
    }
  }

  void _prepare() {
    _insEntry = db.prepare(
      'INSERT INTO kb_entry('
      'system, city_key, code, type, line, station, kind, weight, '
      'line_digits, code_tail2) '
      'VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10)',
    );
    _insKey = db.prepare(
      'INSERT INTO kb_key(system, city_key, key, entry_id) '
      'VALUES(?1,?2,?3,?4)',
    );
    _insLineName = db.prepare(
      'INSERT OR IGNORE INTO kb_line_name(system, city_key, digits, name) '
      'VALUES(?1,?2,?3,?4)',
    );
    _insFragLs = db.prepare(
      'INSERT INTO kb_frag_ls(system, city_key, line_num, station_num, entry_id) '
      'VALUES(?1,?2,?3,?4,?5)',
    );
    _insFragSt = db.prepare(
      'INSERT INTO kb_frag_st(system, city_key, station_num, entry_id) '
      'VALUES(?1,?2,?3,?4)',
    );
    _insFragLn = db.prepare(
      'INSERT INTO kb_frag_ln(system, city_key, line_num, entry_id) '
      'VALUES(?1,?2,?3,?4)',
    );
    _insRule = db.prepare(
      'INSERT INTO kb_terminal_rule('
      'region_code, match_key, is_prefix, txn_type, priority, entry_id) '
      'VALUES(?1,?2,?3,?4,?5,?6)',
    );
    _insRegion = db.prepare(
      'INSERT OR IGNORE INTO kb_region(system, city_key, name, province) '
      'VALUES(?1,?2,?3,?4)',
    );
  }

  void addRegion(String cityKey, String name, {String? province}) {
    final stmt = _insRegion;
    if (_closed || stmt == null) return;
    stmt.execute([system, cityKey, name, province]);
  }

  /// 写入一条站点编码；返回条目 ID（失败 / 已关闭返回 null）。
  int? addEntry(String cityKey, StationCodeEntry entry) {
    final insEntry = _insEntry;
    final insKey = _insKey;
    final insLineName = _insLineName;
    if (_closed || insEntry == null || insKey == null || insLineName == null) {
      return null;
    }
    final lineDigits = StationCodeTable.lineNameDigitsOf(entry.line);
    final tail2 = StationCodeTable.tailDigitsOf(entry.code, 2);
    final hasStation = (entry.station ?? '').trim().isNotEmpty;
    final weight =
        StationCodeTable.kindPriority(entry.kind) + (hasStation ? 0 : 100);
    insEntry.execute([
      system,
      cityKey,
      entry.code,
      entry.type,
      entry.line,
      entry.station,
      entry.kind ?? 'other',
      weight,
      lineDigits,
      tail2,
    ]);
    final id = db.lastInsertRowId;
    insKey.execute([system, cityKey, entry.code, id]);
    final line = entry.line;
    if (lineDigits != null && line != null && line.trim().isNotEmpty) {
      insLineName.execute([system, cityKey, lineDigits, line]);
    }
    if (system == 'tu') {
      final lineKeys = RegionDatabaseStore.tuFragmentKeys(entry.lineCode);
      final stationKeys =
          RegionDatabaseStore.tuFragmentKeys(entry.stationCode);
      final insFragLs = _insFragLs;
      final insFragSt = _insFragSt;
      final insFragLn = _insFragLn;
      if (insFragLs != null && insFragSt != null && insFragLn != null) {
        for (final sk in stationKeys) {
          insFragSt.execute([system, cityKey, sk, id]);
        }
        for (final lk in lineKeys) {
          insFragLn.execute([system, cityKey, lk, id]);
          for (final sk in stationKeys) {
            insFragLs.execute([system, cityKey, lk, sk, id]);
          }
        }
      }
    }
    return id;
  }

  void addTerminalRule({
    required String regionCode,
    required String matchKey,
    required bool isPrefix,
    required int txnType,
    required int priority,
    required int entryId,
  }) {
    final stmt = _insRule;
    if (_closed || stmt == null) return;
    stmt.execute([
      regionCode,
      matchKey,
      isPrefix ? 1 : 0,
      txnType,
      priority,
      entryId,
    ]);
  }

  bool commit() {
    if (_closed) return false;
    _disposeStatements();
    try {
      db.execute('COMMIT');
      _closed = true;
      return true;
    } catch (e) {
      try {
        db.execute('ROLLBACK');
      } catch (_) {}
      _closed = true;
      // ignore: avoid_print
      print('[RegionIngestSession] 提交失败(已回滚): $e');
      return false;
    }
  }

  void rollback() {
    if (_closed) return;
    _disposeStatements();
    try {
      db.execute('ROLLBACK');
    } catch (_) {}
    _closed = true;
  }

  void _disposeStatements() {
    for (final s in [
      _insEntry, _insKey, _insLineName, _insFragLs,
      _insFragSt, _insFragLn, _insRule, _insRegion,
    ]) {
      try {
        s?.dispose();
      } catch (_) {}
    }
    _insEntry = _insKey = _insLineName = _insFragLs = null;
    _insFragSt = _insFragLn = _insRule = _insRegion = null;
  }
}

/// 地区覆盖概况（知识库页地区列表一行）。
class RegionOverview {
  final String system;
  final String code;
  final String name;
  final String? province;
  final int lineCount;
  final int stationCount;

  const RegionOverview({
    this.system = 'tu',
    required this.code,
    required this.name,
    this.province,
    required this.lineCount,
    required this.stationCount,
  });
}

/// 一条线路及其站点集合（知识库页线路行）。
class RegionLineCoverage {
  final String line;
  final List<String> stations;

  const RegionLineCoverage(this.line, this.stations);
}

/// 地区线路覆盖查询契约：知识库页的惰性瓦片只依赖这两个方法。
/// TU 走原始地区表直查，CU 走派生索引，互不耦合。
abstract class LiveRegionLines {
  List<RegionOverview> queryOverviews();

  Future<List<RegionLineCoverage>> linesForRegion(
      String cityKey, String system);
}

/// 持久化知识库 + 库内派生索引点查基类（CU 使用）。
///
/// 派生表：
/// - `kb_region(system, city_key, name, province)`；
/// - `kb_entry(system, city_key, code, type, line, station, kind, weight,
///   line_digits, code_tail2)`；
/// - `kb_key(system, city_key, key, entry_id)`：登记键（同键允许多条目）；
/// - `kb_frag_ls / kb_frag_st / kb_frag_ln`：TU 多口径数字片段索引；
/// - `kb_line_name(system, city_key, digits, name)`；
/// - `kb_terminal_rule(region_code, match_key, is_prefix, txn_type, priority,
///   entry_id)`：CU 终端索引。
abstract class RegionKnowledgeDb implements LiveStationSource, LiveRegionLines {
  RegionKnowledgeDb(this.db, this.system);

  final Database db;

  @override
  final String system;

  PreparedStatement? _keyQ;
  PreparedStatement? _lineNameQ;
  PreparedStatement? _fragLsQ;
  PreparedStatement? _fragStQ;
  PreparedStatement? _fragLnQ;
  PreparedStatement? _tailQ;
  PreparedStatement? _ruleExactQ;
  PreparedStatement? _rulePrefixQ;
  int? _terminalRuleCount;

  @override
  StationCodeEntry? lookupEntry(String cityKey, String key) {
    try {
      final rows = (_keyQ ??= db.prepare(
        'SELECT e.code, e.type, e.line, e.station, e.kind, e.system '
        'FROM kb_key k JOIN kb_entry e ON e.id = k.entry_id '
        'WHERE k.system = ?1 AND k.city_key = ?2 AND k.key = ?3 '
        'ORDER BY e.weight, e.id LIMIT 1',
      )).select([system, cityKey, key]);
      return rows.isEmpty ? null : _rowToEntry(rows.first);
    } catch (_) {
      return null;
    }
  }

  @override
  String? lookupLineNameDigits(String cityKey, String digits) {
    try {
      final rows = (_lineNameQ ??= db.prepare(
        'SELECT name FROM kb_line_name '
        'WHERE system = ?1 AND city_key = ?2 AND digits = ?3 LIMIT 1',
      )).select([system, cityKey, digits]);
      return rows.isEmpty ? null : '${rows.first['name']}';
    } catch (_) {
      return null;
    }
  }

  @override
  List<StationCodeEntry> fragLineStation(
      String cityKey, String lineNum, String stationNum) {
    try {
      return (_fragLsQ ??= db.prepare(
        'SELECT e.code, e.type, e.line, e.station, e.kind, e.system '
        'FROM kb_frag_ls f JOIN kb_entry e ON e.id = f.entry_id '
        'WHERE f.system = ?1 AND f.city_key = ?2 '
        'AND f.line_num = ?3 AND f.station_num = ?4 '
        'ORDER BY e.weight, e.id',
      ))
          .select([system, cityKey, lineNum, stationNum])
          .map(_rowToEntry)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  List<StationCodeEntry> fragStation(String cityKey, String stationNum) {
    try {
      return (_fragStQ ??= db.prepare(
        'SELECT e.code, e.type, e.line, e.station, e.kind, e.system '
        'FROM kb_frag_st f JOIN kb_entry e ON e.id = f.entry_id '
        'WHERE f.system = ?1 AND f.city_key = ?2 AND f.station_num = ?3 '
        'ORDER BY e.weight, e.id',
      ))
          .select([system, cityKey, stationNum])
          .map(_rowToEntry)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  List<StationCodeEntry> fragLine(String cityKey, String lineNum) {
    try {
      return (_fragLnQ ??= db.prepare(
        'SELECT e.code, e.type, e.line, e.station, e.kind, e.system '
        'FROM kb_frag_ln f JOIN kb_entry e ON e.id = f.entry_id '
        'WHERE f.system = ?1 AND f.city_key = ?2 AND f.line_num = ?3 '
        'ORDER BY e.weight, e.id',
      ))
          .select([system, cityKey, lineNum])
          .map(_rowToEntry)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Iterable<StationCodeEntry> lineNameEntryCandidates(String cityKey) {
    try {
      return db
          .select(
            'SELECT code, type, line, station, kind, system FROM kb_entry '
            'WHERE system = ?1 AND city_key = ?2 ORDER BY weight, id',
            [system, cityKey],
          )
          .map(_rowToEntry);
    } catch (_) {
      return const [];
    }
  }

  /// 线路号数字 + 编码末两位直查（替代整城扫描）。
  @override
  List<StationCodeEntry> lookupLineStationTail(
      String cityKey, String lineDigits, String stationTail) {
    try {
      return (_tailQ ??= db.prepare(
        'SELECT code, type, line, station, kind, system FROM kb_entry '
        'WHERE system = ?1 AND city_key = ?2 '
        'AND line_digits = ?3 AND code_tail2 = ?4 '
        'ORDER BY weight, id',
      ))
          .select([system, cityKey, lineDigits, stationTail])
          .map(_rowToEntry)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// CU 交易终端编号 → 站点：精确命中 + 前缀命中（键长 >= 4）两段索引查询，
  /// 再按「同地区 > 精确 > 键更长 > 交易类型精确 > priority」择优。
  StationCodeEntry? matchTerminal(
    String? terminalNumber, {
    String? cityCode,
    int? transactionType,
  }) {
    final digits =
        terminalNumber?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
    if (digits.isEmpty) return null;
    final city = cityCode?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
    try {
      final exactQ = _ruleExactQ ??= db.prepare(
        'SELECT r.match_key, r.is_prefix, r.region_code, r.txn_type, '
        'r.priority, e.code, e.type, e.line, e.station, e.kind, e.system '
        'FROM kb_terminal_rule r JOIN kb_entry e ON e.id = r.entry_id '
        'WHERE e.system = ?1 AND r.match_key = ?2',
      );
      final prefixQ = _rulePrefixQ ??= db.prepare(
        'SELECT r.match_key, r.is_prefix, r.region_code, r.txn_type, '
        'r.priority, e.code, e.type, e.line, e.station, e.kind, e.system '
        'FROM kb_terminal_rule r JOIN kb_entry e ON e.id = r.entry_id '
        'WHERE e.system = ?1 AND r.match_key = ?2 AND r.is_prefix = 1',
      );
      final rows = <Row>[
        ...exactQ.select([system, digits]),
        for (var len = 4; len < digits.length; len++)
          ...prefixQ.select([system, digits.substring(0, len)]),
      ];
      Row? best;
      var bestScore = -1;
      for (final row in rows) {
        final key = '${row['match_key'] ?? ''}';
        if (key.isEmpty || key.length > digits.length) continue;
        final exact = key == digits;
        final isPrefix = ((row['is_prefix'] as num?)?.toInt() ?? 0) == 1;
        if (!exact &&
            !(isPrefix && key.length >= 4 && digits.startsWith(key))) {
          continue;
        }
        final required = (row['txn_type'] as num?)?.toInt() ?? -1;
        if (required != -1 &&
            transactionType != null &&
            required != transactionType) {
          continue;
        }
        var priority = (row['priority'] as num?)?.toInt() ?? 0;
        if (priority < 0) priority = 0;
        if (priority > 63) priority = 63;
        var keyLen = key.length;
        if (keyLen > 127) keyLen = 127;
        final region = '${row['region_code'] ?? ''}';
        final regionHit = city.isNotEmpty && region == city ? 1 : 0;
        final txnHit =
            transactionType != null && required != -1 ? 1 : 0;
        final score = (regionHit << 16) |
            ((exact ? 1 : 0) << 15) |
            (keyLen << 8) |
            (txnHit << 7) |
            priority;
        if (score > bestScore) {
          bestScore = score;
          best = row;
        }
      }
      return best == null ? null : _rowToEntry(best);
    } catch (_) {
      return null;
    }
  }

  /// 终端规则条数（缓存；重建后实例已固定）。
  int get terminalRuleCount {
    final cached = _terminalRuleCount;
    if (cached != null) return cached;
    try {
      final c = (db
                  .select('SELECT COUNT(*) AS c FROM kb_terminal_rule')
                  .first['c'] as num?)
              ?.toInt() ??
          0;
      _terminalRuleCount = c;
      return c;
    } catch (_) {
      return 0;
    }
  }

  @override
  int get totalEntryCount =>
      int.tryParse(RegionDatabaseStore.metaValue(db, 'entries.$system')) ?? 0;

  @override
  int get datasetCount =>
      int.tryParse(RegionDatabaseStore.metaValue(db, 'datasets.$system')) ?? 0;

  /// 地区覆盖概况（按地区编码升序）。
  List<RegionOverview> queryOverviews() {
    final out = <RegionOverview>[];
    try {
      final rows = db.select(
        'SELECT r.city_key, r.name, r.province, '
        "  (SELECT COUNT(DISTINCT COALESCE(NULLIF(TRIM(e.line), ''), "
        "     '未标注线路')) FROM kb_entry e "
        '     WHERE e.system = r.system AND e.city_key = r.city_key) AS lines, '
        '  (SELECT COUNT(DISTINCT e.code) FROM kb_entry e '
        '     WHERE e.system = r.system AND e.city_key = r.city_key) AS entries '
        'FROM kb_region r WHERE r.system = ?1 ORDER BY r.city_key',
        [system],
      );
      for (final row in rows) {
        out.add(RegionOverview(
          system: system,
          code: '${row['city_key'] ?? ''}',
          name: '${row['name'] ?? ''}',
          province: _nul(row['province']),
          lineCount: (row['lines'] as num?)?.toInt() ?? 0,
          stationCount: (row['entries'] as num?)?.toInt() ?? 0,
        ));
      }
    } catch (_) {}
    return out;
  }

  @override
  Future<List<RegionOverview>> regionsOverview() async => queryOverviews();

  @override
  Future<List<RegionLineCoverage>> linesForRegion(
      String cityKey, String system) async {
    final out = <RegionLineCoverage>[];
    try {
      final rows = db.select(
        "SELECT COALESCE(line, '') AS line, "
        "COALESCE(station, '') AS station "
        'FROM kb_entry WHERE system = ?1 AND city_key = ?2',
        [system, cityKey],
      );
      final byLine = <String, Set<String>>{};
      for (final row in rows) {
        final line = '${row['line'] ?? ''}'.trim();
        final key = line.isEmpty ? '未标注线路' : line;
        final st = '${row['station'] ?? ''}'.trim();
        if (st.isEmpty) continue;
        (byLine[key] ??= <String>{}).add(st);
      }
      byLine.forEach((line, stations) {
        final list = stations.toList()..sort();
        out.add(RegionLineCoverage(line, list));
      });
      out.sort(_compareLineCoverage);
    } catch (_) {}
    return out;
  }

  /// 惰性地区数据集（知识库页按需展开，不整表物化）。
  @override
  List<StationDataset> lazyDatasets() => [
        for (final o in queryOverviews()) LiveRegionDataset(this, o),
      ];

  void close() {
    for (final s in [
      _keyQ, _lineNameQ, _fragLsQ, _fragStQ, _fragLnQ,
      _tailQ, _ruleExactQ, _rulePrefixQ,
    ]) {
      try {
        s?.dispose();
      } catch (_) {}
    }
    _keyQ = _lineNameQ = _fragLsQ = _fragStQ = _fragLnQ = null;
    _tailQ = _ruleExactQ = _rulePrefixQ = null;
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

  /// SQL NULL 必须返回 null；旧实现 `'$v'` 会得到字符串 "null"。
  static String? _nul(Object? v) {
    if (v == null) return null;
    final s = '$v';
    return s.isEmpty ? null : s;
  }

  static int _compareLineCoverage(
      RegionLineCoverage a, RegionLineCoverage b) {
    const unlabeled = '未标注线路';
    if (a.line == unlabeled && b.line != unlabeled) return 1;
    if (b.line == unlabeled && a.line != unlabeled) return -1;
    final an = _lineNumber(a.line);
    final bn = _lineNumber(b.line);
    if (an != null && bn != null && an != bn) return an.compareTo(bn);
    if (an != null && bn == null) return -1;
    if (an == null && bn != null) return 1;
    return a.line.compareTo(b.line);
  }

  static int? _lineNumber(String line) {
    final m = RegExp(r'(\d+)').firstMatch(line);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// 统一 DDL（重建方先 DROP 再执行）。
  static const createTablesSql = '''
CREATE TABLE IF NOT EXISTS kb_region(
  system TEXT NOT NULL, city_key TEXT NOT NULL,
  name TEXT NOT NULL, province TEXT,
  PRIMARY KEY(system, city_key));
CREATE TABLE IF NOT EXISTS kb_entry(
  id INTEGER PRIMARY KEY,
  system TEXT NOT NULL, city_key TEXT NOT NULL, code TEXT NOT NULL,
  type TEXT, line TEXT, station TEXT,
  kind TEXT NOT NULL DEFAULT 'other',
  weight INTEGER NOT NULL DEFAULT 4,
  line_digits TEXT, code_tail2 TEXT);
CREATE TABLE IF NOT EXISTS kb_key(
  system TEXT NOT NULL, city_key TEXT NOT NULL,
  key TEXT NOT NULL, entry_id INTEGER NOT NULL,
  PRIMARY KEY(system, city_key, key, entry_id));
CREATE TABLE IF NOT EXISTS kb_frag_ls(
  system TEXT NOT NULL, city_key TEXT NOT NULL,
  line_num TEXT NOT NULL, station_num TEXT NOT NULL, entry_id INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS kb_frag_st(
  system TEXT NOT NULL, city_key TEXT NOT NULL,
  station_num TEXT NOT NULL, entry_id INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS kb_frag_ln(
  system TEXT NOT NULL, city_key TEXT NOT NULL,
  line_num TEXT NOT NULL, entry_id INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS kb_line_name(
  system TEXT NOT NULL, city_key TEXT NOT NULL,
  digits TEXT NOT NULL, name TEXT NOT NULL,
  PRIMARY KEY(system, city_key, digits));
CREATE TABLE IF NOT EXISTS kb_terminal_rule(
  id INTEGER PRIMARY KEY,
  region_code TEXT NOT NULL, match_key TEXT NOT NULL,
  is_prefix INTEGER NOT NULL DEFAULT 0,
  txn_type INTEGER NOT NULL DEFAULT -1,
  priority INTEGER NOT NULL DEFAULT 0,
  entry_id INTEGER NOT NULL);
CREATE INDEX IF NOT EXISTS idx_kb_key
  ON kb_key(system, city_key, key);
CREATE INDEX IF NOT EXISTS idx_kb_frag_ls
  ON kb_frag_ls(system, city_key, line_num, station_num);
CREATE INDEX IF NOT EXISTS idx_kb_frag_st
  ON kb_frag_st(system, city_key, station_num);
CREATE INDEX IF NOT EXISTS idx_kb_frag_ln
  ON kb_frag_ln(system, city_key, line_num);
CREATE INDEX IF NOT EXISTS idx_kb_entry_city
  ON kb_entry(system, city_key);
CREATE INDEX IF NOT EXISTS idx_kb_entry_tail
  ON kb_entry(system, city_key, line_digits, code_tail2);
CREATE INDEX IF NOT EXISTS idx_kb_rule_key
  ON kb_terminal_rule(match_key);
''';
}

/// 惰性地区数据集：`codes` 恒为空，条目 / 线路数用构建期概况计数，
/// 线路与站点在首次展开时按地区点查（缓存 Future）。
class LiveRegionDataset extends StationDataset {
  LiveRegionDataset(LiveRegionLines db, RegionOverview overview)
      : _db = db,
        _overview = overview,
        super(
          file: '${overview.system}:${overview.code}',
          cityCode: overview.code,
          cityName: overview.name,
          province: overview.province,
          system: overview.system,
          kind: 'mixed',
          codes: const {},
        );

  final LiveRegionLines _db;
  final RegionOverview _overview;

  RegionOverview get overview => _overview;

  @override
  bool get isLazy => true;

  @override
  int get entryCountOverride => _overview.stationCount;

  @override
  int get lineCountOverride => _overview.lineCount;

  Future<List<RegionLineCoverage>>? _linesFuture;

  Future<List<RegionLineCoverage>> linesOnce() {
    final city = cityCode;
    if (city == null || city.isEmpty) {
      return Future<List<RegionLineCoverage>>.value(const []);
    }
    return _linesFuture ??= _db.linesForRegion(city, _overview.system);
  }

  @override
  Future<List<StationCodeEntry>> lazyEntries() async {
    final lines = await linesOnce();
    return [
      for (final l in lines)
        for (final s in l.stations)
          StationCodeEntry(
            code: '',
            line: l.line == '未标注线路' ? null : l.line,
            station: s,
            system: _overview.system,
          ),
    ];
  }
}
