import 'package:flutter/services.dart' show AssetBundle;
import 'package:sqlite3/sqlite3.dart';

import 'region_db_store.dart';
import 'station_codes.dart';

/// 城市一卡通（CU）地区行：地区编码（4 位邮编前缀）→ 地区名。
class CuRegionRow {
  final String regionCode;
  final String regionName;

  const CuRegionRow({required this.regionCode, required this.regionName});
}

/// 城市一卡通终端索引规则（内存形态；数据库形态见 `kb_terminal_rule`）。
class CuTerminalRule {
  final String regionCode;
  final String matchKey;
  final bool isPrefix;
  final int requiredTxnType;
  final int priority;
  final StationCodeEntry entry;

  const CuTerminalRule({
    required this.regionCode,
    required this.matchKey,
    required this.isPrefix,
    required this.requiredTxnType,
    required this.priority,
    required this.entry,
  });
}

/// 城市一卡通终端匹配器：优先委派持久化 `kb_terminal_rule` 索引查询；
/// 内存规则列表仅保留给测试 / 特殊数据源。
class CityUnionTerminalMatcher {
  static const _anyTxnType = -1;
  static const _minPrefixLength = 4;

  final List<CuTerminalRule> _rules;
  final RegionKnowledgeDb? _live;

  const CityUnionTerminalMatcher(this._rules) : _live = null;

  const CityUnionTerminalMatcher.live(RegionKnowledgeDb source)
      : _rules = const [],
        _live = source;

  static const empty = CityUnionTerminalMatcher([]);

  int get length => _live?.terminalRuleCount ?? _rules.length;

  StationCodeEntry? match(
    String? terminalNumber, {
    String? cityCode,
    int? transactionType,
  }) {
    final live = _live;
    if (live != null) {
      return live.matchTerminal(
        terminalNumber,
        cityCode: cityCode,
        transactionType: transactionType,
      );
    }
    final digits = _digits(terminalNumber ?? '');
    if (digits.isEmpty) return null;
    final city = _digits(cityCode ?? '');
    CuTerminalRule? best;
    var bestScore = 0;
    for (final rule in _rules) {
      final key = rule.matchKey;
      if (key.isEmpty || key.length > digits.length) continue;
      final exact = digits == key;
      final prefixHit = rule.isPrefix &&
          digits.length > key.length &&
          key.length >= _minPrefixLength &&
          digits.startsWith(key);
      if (!exact && !prefixHit) continue;
      if (rule.requiredTxnType != _anyTxnType &&
          transactionType != null &&
          rule.requiredTxnType != transactionType) {
        continue;
      }
      final score = _score(
        rule,
        city: city,
        exact: exact,
        txnGiven: transactionType != null,
      );
      if (best == null || score > bestScore) {
        best = rule;
        bestScore = score;
      }
    }
    return best?.entry;
  }

  int _score(
    CuTerminalRule rule, {
    required String city,
    required bool exact,
    required bool txnGiven,
  }) {
    final regionHit = city.isNotEmpty && rule.regionCode == city ? 1 : 0;
    final txnHit = txnGiven && rule.requiredTxnType != _anyTxnType ? 1 : 0;
    var priority = rule.priority;
    if (priority < 0) priority = 0;
    if (priority > 63) priority = 63;
    var keyLen = rule.matchKey.length;
    if (keyLen > 127) keyLen = 127;
    return (regionHit << 16) |
        ((exact ? 1 : 0) << 15) |
        (keyLen << 8) |
        (txnHit << 7) |
        priority;
  }

  static String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');
}

/// 城市一卡通地区 / 站点数据库读取内容。
class CityUnionRegionDatabaseContent {
  final List<CuRegionRow> cities;
  final CityUnionRegionKnowledgeDb? live;
  final CityUnionTerminalMatcher terminalMatcher;
  final int? databaseVersion;

  const CityUnionRegionDatabaseContent({
    required this.cities,
    this.live,
    this.terminalMatcher = CityUnionTerminalMatcher.empty,
    this.databaseVersion,
  });

  int get stationDatasetCount => live?.datasetCount ?? 0;
  int get stationEntryCount => live?.totalEntryCount ?? 0;

  /// 兼容旧字段：惰性数据集，仅按需点查。
  List<StationDataset> get stationDatasets =>
      live?.lazyDatasets() ?? const [];
}

/// 城市一卡通（CU）地区 / 线路站点数据库（持久化接入）。
class CityUnionRegionDatabase {
  static const assetPath = 'assets/data/TrafArch_Database_CU.sqlite';
  static const _fileName = 'trafarch_database_cu.sqlite';

  CityUnionRegionDatabase._();

  static Future<CityUnionRegionDatabaseContent?> load({
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
      final live = CityUnionRegionKnowledgeDb.open(handle);
      if (live == null) return null;
      db = null; // 句柄移交 live。

      final regions = _CuReader.readRegions(handle);
      final dict = _CuReader.readCityDict(handle);
      final cities = <CuRegionRow>[
        for (final r in regions)
          CuRegionRow(regionCode: r.code, regionName: r.name),
        for (final e in dict.entries)
          CuRegionRow(regionCode: e.key, regionName: e.value),
      ];
      return CityUnionRegionDatabaseContent(
        cities: cities,
        live: live,
        terminalMatcher: CityUnionTerminalMatcher.live(live),
        databaseVersion: live.databaseVersion,
      );
    } catch (_) {
      return null;
    } finally {
      try {
        db?.dispose();
      } catch (_) {}
    }
  }
}

class _CuRegion {
  final String code;
  final String name;
  final String? table;

  const _CuRegion(this.code, this.name, this.table);
}

class _CuReader {
  _CuReader._();

  static List<_CuRegion> readRegions(Database db) {
    final out = <_CuRegion>[];
    final cols = tableColumns(db, 'regions');
    if (cols == null) return out;
    final select = <String>[
      cols.contains('region_code') ? 'region_code' : "'' AS region_code",
      cols.contains('region_name') ? 'region_name' : "'' AS region_name",
      cols.contains('table_name') ? 'table_name' : 'NULL AS table_name',
    ];
    try {
      for (final r in db.select('SELECT ${select.join(', ')} FROM regions')) {
        final code = digits('${r['region_code'] ?? ''}');
        final name = '${r['region_name'] ?? ''}'.trim();
        final table = '${r['table_name'] ?? ''}'.trim();
        if (code.isEmpty || name.isEmpty) continue;
        out.add(_CuRegion(code, name, table.isEmpty ? null : table));
      }
    } catch (_) {}
    return out;
  }

  static Map<String, String> readCityDict(Database db) {
    final out = <String, String>{};
    try {
      for (final r in db.select(
        'SELECT region_code, region_name FROM region_codes',
      )) {
        final code = digits('${r['region_code'] ?? ''}');
        final name = '${r['region_name'] ?? ''}'.trim();
        if (code.isEmpty || name.isEmpty) continue;
        out.putIfAbsent(code, () => name);
      }
    } catch (_) {}
    return out;
  }

  static Set<String>? tableColumns(Database db, String table) {
    try {
      return {
        for (final r in db.select('PRAGMA table_info("$table")'))
          '${r['name'] ?? ''}',
      };
    } catch (_) {
      return null;
    }
  }

  static String digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  static String? nullIfEmpty(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }
}

/// CU 持久化知识库：站点与终端规则一次性流式写入 `kb_*`，运行期点查。
class CityUnionRegionKnowledgeDb extends RegionKnowledgeDb {
  CityUnionRegionKnowledgeDb._(Database db) : super(db, 'cu');

  static const _model = 'cu-idx-1';

  int? get databaseVersion => _version;
  int? _version;

  static CityUnionRegionKnowledgeDb? open(Database db) {
    try {
      RegionDatabaseStore.ensureSchema(db);
      final uv = RegionDatabaseStore.userVersion(db);
      final inst = CityUnionRegionKnowledgeDb._(db)
        .._version = uv == 0 ? null : uv;
      final stamp = '$uv:$_model';
      final key = RegionDatabaseStore.stampKey('cu');
      if (RegionDatabaseStore.metaValue(db, key) != stamp) {
        RegionDatabaseStore.setMetaValue(db, key, '');
        if (inst._rebuild()) {
          RegionDatabaseStore.setMetaValue(db, key, stamp);
        }
      }
      return inst;
    } catch (_) {
      return null;
    }
  }

  bool _rebuild() {
    RegionDatabaseStore.resetDerived(db);
    final regions = _CuReader.readRegions(db);
    final session = RegionIngestSession.begin(db, 'cu');
    if (session == null) return false;
    var totalRegions = 0;
    var ingested = 0;
    var skipped = 0;
    try {
      for (final region in regions) {
        totalRegions++;
        if (!_ingestRegion(db, region, session)) {
          skipped++;
          continue;
        }
        session.addRegion(
          RegionDatabaseStore.normalizeCity(region.code),
          region.name,
        );
        ingested++;
      }
      if (!session.commit()) {
        // ignore: avoid_print
        print('[CityUnionRegionKnowledgeDb] 提交失败，已回滚（下次启动重试）');
        return false;
      }
      RegionDatabaseStore.refreshCounts(db, 'cu');
      // ignore: avoid_print
      print('[CityUnionRegionKnowledgeDb] rebuild: regions=$totalRegions '
          'ingested=$ingested skipped=$skipped dbVersion=$_version');
      return true;
    } catch (e) {
      session.rollback();
      // ignore: avoid_print
      print('[CityUnionRegionKnowledgeDb] rebuild 失败(已回滚): $e');
      return false;
    }
  }

  /// 单地区：terminal_index JOIN 站点表流式写入；缺索引时回退按 station_id。
  static bool _ingestRegion(
    Database db,
    _CuRegion region,
    RegionIngestSession session,
  ) {
    final table = region.table;
    if (table == null) return false;
    final scols = _CuReader.tableColumns(db, table);
    if (scols == null ||
        !scols.contains('station_id') ||
        !scols.contains('station_name')) {
      return false;
    }
    final cityKey = RegionDatabaseStore.normalizeCity(region.code);

    final tcols = _CuReader.tableColumns(db, 'terminal_index');
    if (tcols != null && _hasTerminalRows(db, region.code)) {
      final select = <String>[
        't.match_key AS match_key',
        tcols.contains('match_mode')
            ? 't.match_mode AS match_mode'
            : 'NULL AS match_mode',
        tcols.contains('required_transaction_type')
            ? 't.required_transaction_type AS required_txn'
            : '-1 AS required_txn',
        tcols.contains('priority') ? 't.priority AS priority' : '0 AS priority',
        's.station_id AS station_id',
        scols.contains('transport_type')
            ? 's.transport_type AS transport_type'
            : 'NULL AS transport_type',
        scols.contains('line_name')
            ? 's.line_name AS line_name'
            : 'NULL AS line_name',
        's.station_name AS station_name',
      ];
      final stmt = db.prepare(
        'SELECT ${select.join(', ')} FROM terminal_index t '
        'JOIN "$table" s ON s.station_id = t.station_id '
        'WHERE t.region_code = ?',
      );
      var emitted = 0;
      try {
        final cursor = stmt.selectCursor([region.code]);
        while (cursor.moveNext()) {
          final row = cursor.current;
          final key = _CuReader.digits('${row['match_key'] ?? ''}');
          if (key.isEmpty) continue;
          final transport = '${row['transport_type'] ?? ''}'.trim();
          final line = _CuReader.nullIfEmpty('${row['line_name'] ?? ''}');
          final station =
              _CuReader.nullIfEmpty('${row['station_name'] ?? ''}');
          if (line == null && station == null) continue;
          final entryId = session.addEntry(
            cityKey,
            _entry(region.code, key, transport, line, station),
          );
          if (entryId == null) continue;
          final tail = StationCodeTable.tailFourDigits(key);
          if (tail != null && tail != key) {
            session.addEntry(
              cityKey,
              _entry(region.code, tail, transport, line, station),
            );
          }
          session.addTerminalRule(
            regionCode: region.code,
            matchKey: key,
            isPrefix:
                '${row['match_mode'] ?? ''}'.toLowerCase().contains('prefix'),
            txnType: (row['required_txn'] as num?)?.toInt() ?? -1,
            priority: (row['priority'] as num?)?.toInt() ?? 0,
            entryId: entryId,
          );
          emitted++;
        }
      } finally {
        stmt.dispose();
      }
      return emitted > 0;
    }

    // 无 terminal_index：回退按 station_id 登记（尽力而为）。
    final select = <String>[
      'station_id',
      scols.contains('transport_type')
          ? 'transport_type'
          : 'NULL AS transport_type',
      scols.contains('line_name') ? 'line_name' : 'NULL AS line_name',
      'station_name',
    ];
    final stmt = db.prepare('SELECT ${select.join(', ')} FROM "$table"');
    var emitted = 0;
    try {
      final cursor = stmt.selectCursor();
      while (cursor.moveNext()) {
        final row = cursor.current;
        final id = (row['station_id'] as num?)?.toInt();
        if (id == null) continue;
        final transport = '${row['transport_type'] ?? ''}'.trim();
        final line = _CuReader.nullIfEmpty('${row['line_name'] ?? ''}');
        final station =
            _CuReader.nullIfEmpty('${row['station_name'] ?? ''}');
        if (line == null && station == null) continue;
        if (session.addEntry(
              cityKey,
              _entry(region.code, '$id', transport, line, station),
            ) !=
            null) {
          emitted++;
        }
      }
    } finally {
      stmt.dispose();
    }
    return emitted > 0;
  }

  static bool _hasTerminalRows(Database db, String regionCode) {
    try {
      return db.select(
        'SELECT 1 FROM terminal_index WHERE region_code = ? LIMIT 1',
        [regionCode],
      ).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static StationCodeEntry _entry(
    String cityCode,
    String key,
    String transport,
    String? line,
    String? station,
  ) =>
      StationCodeEntry(
        code: key,
        type: _typeName(transport),
        line: line,
        station: station,
        system: 'cu',
        kind: _kind(transport),
        datasetFile: 'cu:$cityCode',
      );

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
}