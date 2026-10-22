import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../domain/station_codes.dart';
import '../domain/region_db_store.dart' show RegionOverview;
import '../domain/tu_station_models.dart';
import '../domain/tu_lookup_service.dart';
export '../domain/tu_station_models.dart';

/// 交通联合（TU）原始地区表查询层。
///
/// 设计要点：
/// - `regions.table_name` 指向按地区拆分的站点表，所有站点查询都直查这些
///   原始表，不创建 `tu_stations` / `tu_lines` 之类的派生表；
/// - `source_key` 是站点映射键，`source_field` 是映射来源字段，二者不混用；
/// - 表名来自库内元数据，动态拼接前按 SQLite 标识符规则转义；
/// - 用户覆盖与未知站点上报写入两张 App 自有表，不改原始数据；
/// - 单地区表规模在数百到数千行量级，片段查询走原表扫描并做进程内缓存，
///   不物化整表。
class TuStationRepository implements TuLookupDataSource {
  TuStationRepository(this.db, {Database? userDatabase})
    : _userDb = userDatabase;

  final Database? _userDb;

  final Database db;
  @override
  String? queryIssue;

  static const _cacheLimit = 256;

  List<TuRegionRow>? _regions;
  Map<String, TuRegionRow>? _byCode;
  final Map<String, Set<String>> _columns = {};
  final Map<String, List<TuStationRecord>> _cache = {};
  final Map<String, String> _lineNames = {};
  final Set<String> _lineNameScanned = {};
  List<RegionOverview>? _overviews;
  Map<String, List<TuLookupValue>>? _lookupValues;

  Map<String, List<TuLookupValue>> get _lookup {
    if (_lookupValues != null) return _lookupValues!;
    final values = <String, List<TuLookupValue>>{};
    try {
      // Older test fixtures need only the original tables. A real SQLite read
      // error is reported, while a package without the optional document can
      // still use its original full rail keys and local terminals.
      if (db
          .select(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='reference_documents'",
          )
          .isNotEmpty) {
        final docs = db.select(
          'SELECT json FROM reference_documents WHERE name=?',
          ['tu_lookup'],
        );
        if (docs.isNotEmpty) {
          final document = jsonDecode(docs.single['json'] as String) as Map;
          if (document['format_version'] != 1 ||
              document['namespace'] != 'TU') {
            throw const FormatException('Unsupported TU lookup document');
          }
          for (final section in [
            'terminal_aliases',
            'rail_prefixes',
            'rail_history',
          ]) {
            for (final raw in document[section] as List) {
              final item = TuLookupValue(
                raw['source_field'] as String,
                raw['source_key'] as String,
                raw['raw_value'],
              );
              final index = section == 'rail_prefixes'
                  ? '$section|${item.sourceKey.substring(0, 4)}'
                  : '$section|${item.sourceKey}';
              (values[index] ??= []).add(item);
            }
          }
        }
      }
    } catch (error) {
      queryIssue = 'TU lookup 文档读取失败：$error';
      return const {};
    }
    return _lookupValues = values;
  }

  /// Native rail source maps only. Local terminals and bus/BRT maps never
  /// share this prefix namespace, even if their raw keys happen to collide.
  @override
  Iterable<StationCodeEntry> railCandidates(String city) sync* {
    for (final record in entriesOfRegion(city)) {
      if (record.sourceField == StationCodeTable.tuRailSourceField(city)) {
        yield entryForRecord(record);
      }
    }
    for (final value
        in _lookup['rail_prefixes|$city'] ?? const <TuLookupValue>[]) {
      final raw = value.rawValue! as List;
      yield StationCodeEntry(
        code: value.sourceKey,
        sourceKey: value.sourceKey,
        sourceField: value.sourceField,
        type: raw[0] as String,
        line: raw[1] as String,
        station: raw[2] as String,
        system: 'tu',
        kind: 'metro',
        datasetFile: 'tu:lookup',
        rawValueJson: jsonEncode(raw),
      );
    }
  }

  @override
  List<StationCodeEntry> localTerminalCandidates(
    String sourceField,
    String terminal,
  ) {
    final owner = switch (sourceField) {
      'M0.n0.a' => '1610',
      'M0.E.a' => '3010',
      'M0.b.a' => '6510',
      'M0.C.b' => '3370',
      _ => null,
    };
    if (owner == null) return const [];
    return findByKey(
      owner,
      terminal,
    ).where((r) => r.sourceField == sourceField).map(entryForRecord).toList();
  }

  @override
  List<TuLookupValue> terminalAliases(String terminal) => List.unmodifiable(
    _lookup['terminal_aliases|$terminal'] ?? const <TuLookupValue>[],
  );

  /// Original m762p: exact city + process terminal in M0.S.a. The key carries
  /// the full 16-character terminal, unlike basic-terminal maps.
  @override
  List<TuLookupValue> processTerminalCandidates(String city, String terminal) {
    return [
      for (final row in findByKey(city, '$city$terminal'))
        if (row.sourceField == 'M0.S.a')
          TuLookupValue(
            row.sourceField!,
            row.sourceKey,
            row.rawValueJson == null ? null : jsonDecode(row.rawValueJson!),
          ),
    ];
  }

  @override
  List<TuLookupValue> railHistory(String key) {
    for (var length = key.length; length >= 5; length--) {
      final rows = _lookup['rail_history|${key.substring(0, length)}'];
      if (rows != null) return List.unmodifiable(rows);
    }
    return const [];
  }

  StationMatch matchRailPrefix({
    required String city,
    required String key,
    DateTime? time,
  }) => TuLookupService(this).resolveRailKey(city: city, key: key, time: time);

  Database get _requireUserDb => _userDb ?? (throw StateError('用户站点存储不可用'));

  // ---------------------------------------------------------------- 建表

  /// App 自有表：用户覆盖 / 未知站点上报。
  ///
  /// `source_field` 统一以空串代替 NULL：SQLite 唯一约束对 NULL 不去重，
  /// 规范化后同一站点不会产生重复覆盖记录。
  static void ensureAppTables(Database db) {
    db.execute('''
CREATE TABLE IF NOT EXISTS tu_user_station_overrides(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  region_code TEXT NOT NULL,
  source_key TEXT NOT NULL,
  source_field TEXT NOT NULL DEFAULT '',
  station_name TEXT NOT NULL,
  line_name TEXT,
  transport_type TEXT NOT NULL DEFAULT 'other',
  updated_at TEXT NOT NULL,
  UNIQUE(region_code, source_key, source_field)
)''');
    db.execute('''
CREATE TABLE IF NOT EXISTS tu_unknown_station_reports(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  region_code TEXT NOT NULL DEFAULT '',
  source_key TEXT NOT NULL,
  source_field TEXT NOT NULL DEFAULT '',
  transport_type TEXT NOT NULL DEFAULT '',
  raw_value_json TEXT,
  first_seen_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL,
  hit_count INTEGER NOT NULL DEFAULT 1,
  UNIQUE(region_code, source_key, source_field)
)''');
  }

  // ---------------------------------------------------------------- 地区

  List<TuRegionRow> get regions {
    final cached = _regions;
    if (cached != null) return cached;
    final cols = _columnsOf('regions');
    if (cols == null) return _regions = const [];
    final order = cols.contains('region_id') ? ' ORDER BY region_id' : '';
    final out = <TuRegionRow>[];
    try {
      for (final row in db.select('SELECT * FROM regions$order')) {
        final code = _digits(_cell(row, 'region_code'));
        final name = _cell(row, 'region_name').trim();
        final table = _cell(row, 'table_name').trim();
        if (code.isEmpty || name.isEmpty || table.isEmpty) continue;
        out.add(
          TuRegionRow(
            regionId: _asIntCell(row, 'region_id'),
            regionCode: code,
            regionName: name,
            province: _nullable(_cell(row, 'province')),
            tableName: table,
            codeSource: _cell(row, 'code_source').trim(),
          ),
        );
      }
    } catch (error) {
      queryIssue = 'TU 地区查询失败：$error';
    }
    return _regions = List<TuRegionRow>.unmodifiable(out);
  }

  Map<String, TuRegionRow> get _regionsByCode =>
      _byCode ??= {for (final r in regions) r.regionCode: r};

  TuRegionRow? regionOf(String regionCode) =>
      _regionsByCode[regionCode.replaceAll(RegExp(r'\s+'), '')];

  /// 定位地区对应的实际站点表。
  ///
  /// 同时给出 `regionCode` 与 `regionName` 时按 AND 组合；多个地区命中时
  /// 返回 null（不擅自选择第一条）。
  TuRegionRow? findRegion({String? regionCode, String? regionName}) {
    if (regionCode == null && regionName == null) {
      throw ArgumentError('regionCode 和 regionName 至少提供一个');
    }
    final code = regionCode?.replaceAll(RegExp(r'\s+'), '');
    final name = regionName?.trim();
    final hits = <TuRegionRow>[];
    for (final r in regions) {
      if (code != null && code.isNotEmpty && r.regionCode != code) continue;
      if (name != null && name.isNotEmpty && r.regionName != name) continue;
      hits.add(r);
      if (hits.length > 1) break;
    }
    return hits.length == 1 ? hits.first : null;
  }

  // ---------------------------------------------------------------- 精确查询

  /// 在指定地区按 `source_key` 查找站点。
  ///
  /// [sourceField] / [transportType] 为可选收窄条件；传入时必须与库内值
  /// 精确相等（不做模糊匹配，不猜测）。
  List<TuStationRecord> findStations({
    required String sourceKey,
    String? sourceField,
    String? regionCode,
    String? regionName,
    String? transportType,
  }) {
    final key = _normalizeKey(sourceKey);
    if (key.isEmpty) return const [];
    final region = findRegion(regionCode: regionCode, regionName: regionName);
    if (region == null) return const [];
    final cols = _columnsOf(region.tableName);
    final col = _keyColumnOf(region);
    if (cols == null || col == null) return const [];

    final where = <String>['TRIM($col) = ?'];
    final args = <Object?>[key];
    final field = sourceField?.trim() ?? '';
    if (field.isNotEmpty) {
      // 表无该列时无法满足收窄条件：返回空，避免放大成宽匹配。
      if (!cols.contains('source_field')) return const [];
      where.add('source_field = ?');
      args.add(field);
    }
    final transport = transportType?.trim() ?? '';
    if (transport.isNotEmpty) {
      if (!cols.contains('transport_type')) return const [];
      where.add('transport_type = ?');
      args.add(transport);
    }
    return _selectRegion(region, where.join(' AND '), args);
  }

  /// 跨地区按 `source_key` 查找：用于解析记录没有地区线索的场景。
  ///
  /// 顺序遍历 `regions.table_name`，命中总数达到 [limit] 即停止；不给
  /// 城市兜底，也不按名称相似度猜测。
  List<TuStationRecord> findStationsAcrossRegions({
    required String sourceKey,
    String? sourceField,
    String? transportType,
    int limit = 200,
  }) {
    final key = _normalizeKey(sourceKey);
    if (key.isEmpty || limit <= 0) return const [];
    final field = sourceField?.trim() ?? '';
    final transport = transportType?.trim() ?? '';
    final out = <TuStationRecord>[];
    for (final region in regions) {
      final cols = _columnsOf(region.tableName);
      final col = _keyColumnOf(region);
      if (cols == null || col == null) continue;
      if (field.isNotEmpty && !cols.contains('source_field')) continue;
      if (transport.isNotEmpty && !cols.contains('transport_type')) continue;
      final where = <String>['TRIM($col) = ?'];
      final args = <Object?>[key];
      if (field.isNotEmpty) {
        where.add('source_field = ?');
        args.add(field);
      }
      if (transport.isNotEmpty) {
        where.add('transport_type = ?');
        args.add(transport);
      }
      out.addAll(
        _selectRegion(
          region,
          where.join(' AND '),
          args,
          limit: limit - out.length,
        ),
      );
      if (out.length >= limit) break;
    }
    return out;
  }

  // ---------------------------------------------------------------- 片段查询

  /// `source_key` 精确命中（供 [LiveStationSource.lookupEntry]）。
  List<TuStationRecord> findByKey(String regionCode, String key) {
    final normalized = _normalizeKey(key);
    if (normalized.isEmpty) return const [];
    return _memo('key|$regionCode|$normalized', () {
      final region = regionOf(regionCode);
      final col = region == null ? null : _keyColumnOf(region);
      if (region == null || col == null) return const [];
      return _selectRegion(region, 'TRIM($col) = ?', [normalized]);
    });
  }

  /// 线路片段 + 站点片段联合命中。
  ///
  /// 片段统一按十六进制文本口径比较（大写、去前导零），线路 / 站点按
  /// 「完整值 / 前两位 / 后两位」多口径对齐（兼容 12 位码左右补零），
  /// 同时覆盖 10 位（2 位线路 + 4 位站点）与 8 位（2 + 2）键。
  List<TuStationRecord> fragLineStation(
    String regionCode,
    String lineFragment,
    String stationFragment,
  ) {
    final line = _normalizeFragment(lineFragment);
    final station = _normalizeFragment(stationFragment);
    if (line.isEmpty || station.isEmpty) return const [];
    return _memo('ls|$regionCode|$line|$station', () {
      final region = regionOf(regionCode);
      final col = region == null ? null : _keyColumnOf(region);
      if (region == null || col == null) return const [];
      return _selectRegion(
        region,
        '${_lineCondition(col, 1)} AND ${_stationCondition(col, 2)}',
        [line, station],
      );
    });
  }

  /// 站点片段单独命中（候选可能跨线路）。
  List<TuStationRecord> fragStation(String regionCode, String stationFragment) {
    final station = _normalizeFragment(stationFragment);
    if (station.isEmpty) return const [];
    return _memo('st|$regionCode|$station', () {
      final region = regionOf(regionCode);
      final col = region == null ? null : _keyColumnOf(region);
      if (region == null || col == null) return const [];
      return _selectRegion(region, _stationCondition(col, 1), [station]);
    });
  }

  /// 线路片段单独命中。
  List<TuStationRecord> fragLine(String regionCode, String lineFragment) {
    final line = _normalizeFragment(lineFragment);
    if (line.isEmpty) return const [];
    return _memo('ln|$regionCode|$line', () {
      final region = regionOf(regionCode);
      final col = region == null ? null : _keyColumnOf(region);
      if (region == null || col == null) return const [];
      return _selectRegion(region, _lineCondition(col, 1), [line]);
    });
  }

  /// 线路号数字 + 编码末两位组合命中（线路名无数字时的兜底通道）。
  ///
  /// 与旧 `kb_entry.line_digits / code_tail2` 保持一致：两侧都按字符串
  /// 精确比较，尾码 `"00"`、线路数字 `"0"` 均为合法值，不做零值丢弃。
  List<TuStationRecord> lineStationTail(
    String regionCode,
    String lineDigits,
    String stationTail,
  ) {
    final line = _lineDigitsOf(lineDigits);
    final tail = stationTail.trim();
    if (line == null || tail.isEmpty) return const [];
    return _memo('tail|$regionCode|$line|$tail', () {
      final region = regionOf(regionCode);
      if (region == null) return const [];
      return [
        for (final r in entriesOfRegion(regionCode))
          if (_lineDigitsOf(r.lineName) == line &&
              _tailDigits(r.sourceKey, 2) == tail)
            r,
      ];
    });
  }

  /// 整地区条目（仅供知识库页 / 兜底扫描，规模受地区表行数约束）。
  List<TuStationRecord> entriesOfRegion(String regionCode) {
    return _memo('all|$regionCode', () {
      final region = regionOf(regionCode);
      if (region == null) return const [];
      return _selectRegion(region, '1 = 1', const [], limit: 20000);
    });
  }

  // ---------------------------------------------------------------- 线路名

  /// 线路号数字 → 线路名（`line_name` 首个数字段精确相等）。
  String? lookupLineName(String regionCode, String digits) {
    final key = '$regionCode|$digits';
    final cached = _lineNames[key];
    if (cached != null) return cached;
    if (_lineNameScanned.contains(regionCode)) return null;
    _lineNameScanned.add(regionCode);
    for (final r in entriesOfRegion(regionCode)) {
      final d = _lineDigitsOf(r.lineName);
      final name = r.lineName;
      if (d == null || name == null || name.isEmpty) continue;
      _lineNames.putIfAbsent('$regionCode|$d', () => name);
    }
    return _lineNames[key];
  }

  // ---------------------------------------------------------------- 统计

  /// 地区覆盖概况（线路数 / 条目数按原始表实时统计）。
  List<RegionOverview> queryOverviews() {
    final cached = _overviews;
    if (cached != null) return cached;
    final out = <RegionOverview>[];
    for (final region in regions) {
      final cols = _columnsOf(region.tableName);
      final col = _keyColumnOf(region);
      if (cols == null || col == null) continue;
      // 缺 line_name 的地区仍要计入站点数，不能让整条 SQL 失败。
      final lineExpr = cols.contains('line_name')
          ? "COUNT(DISTINCT NULLIF(TRIM(line_name), ''))"
          : '0';
      try {
        final row = db.select(
          'SELECT COUNT(*) AS c, $lineExpr AS l '
          'FROM ${_quote(region.tableName)} WHERE TRIM($col) <> ?',
          [''],
        ).first;
        out.add(
          RegionOverview(
            code: region.regionCode,
            name: region.regionName,
            province: region.province,
            lineCount: (row['l'] as num?)?.toInt() ?? 0,
            stationCount: (row['c'] as num?)?.toInt() ?? 0,
          ),
        );
      } catch (_) {}
    }
    return _overviews = List<RegionOverview>.unmodifiable(out);
  }

  /// 有站点表的地区数。
  int get datasetCount => queryOverviews().length;

  /// 站点条目总数（原始表实际行数，不采信 `source_metadata`）。
  int get stationCount =>
      queryOverviews().fold(0, (sum, o) => sum + o.stationCount);

  // ---------------------------------------------------------------- 覆盖 / 上报

  /// 查询用户覆盖（先于原始表返回）。
  TuStationOverride? queryOverride(
    String regionCode,
    String sourceKey, {
    String? sourceField,
  }) {
    try {
      final rows = _userDb?.select(
        'SELECT * FROM tu_user_station_overrides '
        'WHERE region_code = ?1 AND source_key = ?2 AND source_field = ?3 '
        'LIMIT 1',
        [regionCode, _normalizeKey(sourceKey), _normalizeField(sourceField)],
      );
      if (rows == null || rows.isEmpty) return null;
      final row = rows.first;
      return TuStationOverride(
        regionCode: '${row['region_code'] ?? ''}',
        sourceKey: '${row['source_key'] ?? ''}',
        sourceField: '${row['source_field'] ?? ''}',
        stationName: '${row['station_name'] ?? ''}',
        lineName: _nullable('${row['line_name'] ?? ''}'),
        transportType: '${row['transport_type'] ?? 'other'}',
        updatedAt:
            DateTime.tryParse('${row['updated_at'] ?? ''}') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
    } catch (_) {
      return null;
    }
  }

  /// Apply user edits at the live-query boundary, retaining the source evidence.
  StationCodeEntry entryForRecord(TuStationRecord record) {
    final original = record.toEntry();
    final edit =
        queryOverride(
          record.regionCode,
          record.sourceKey,
          sourceField: record.sourceField,
        ) ??
        queryOverride(record.regionCode, record.sourceKey);
    return edit?.toEntry(original: original) ?? original;
  }

  /// 写入 / 更新用户覆盖。
  void upsertOverride({
    required String regionCode,
    required String sourceKey,
    String? sourceField,
    required String stationName,
    String? lineName,
    required String transportType,
    DateTime? updatedAt,
  }) {
    final key = _normalizeKey(sourceKey);
    if (key.isEmpty) {
      throw ArgumentError.value(sourceKey, 'sourceKey', 'source_key 不能为空');
    }
    final at = (updatedAt ?? DateTime.now()).toIso8601String();
    _requireUserDb.execute(
      'INSERT INTO tu_user_station_overrides('
      'region_code, source_key, source_field, station_name, line_name, '
      'transport_type, updated_at) VALUES(?1,?2,?3,?4,?5,?6,?7) '
      'ON CONFLICT(region_code, source_key, source_field) DO UPDATE SET '
      'station_name = excluded.station_name, '
      'line_name = excluded.line_name, '
      'transport_type = excluded.transport_type, '
      'updated_at = excluded.updated_at',
      [
        regionCode.trim(),
        key,
        _normalizeField(sourceField),
        stationName,
        lineName,
        transportType,
        at,
      ],
    );
    invalidate();
  }

  /// 记录未识别站点：同键累加命中次数并刷新最后出现时间。
  ///
  /// 只记录原始编码与来源字段，不写入任何推测站名。
  void recordUnknownStation({
    String? regionCode,
    required String sourceKey,
    String? sourceField,
    String? transportType,
    String? rawValueJson,
    DateTime? seenAt,
  }) {
    final key = _normalizeKey(sourceKey);
    if (key.isEmpty) return;
    final at = (seenAt ?? DateTime.now()).toIso8601String();
    try {
      _requireUserDb.execute(
        'INSERT INTO tu_unknown_station_reports('
        'region_code, source_key, source_field, transport_type, '
        'raw_value_json, first_seen_at, last_seen_at, hit_count) '
        'VALUES(?1,?2,?3,?4,?5,?6,?6,1) '
        'ON CONFLICT(region_code, source_key, source_field) DO UPDATE SET '
        'last_seen_at = excluded.last_seen_at, '
        'hit_count = tu_unknown_station_reports.hit_count + 1, '
        'raw_value_json = COALESCE(excluded.raw_value_json, '
        '  tu_unknown_station_reports.raw_value_json)',
        [
          (regionCode ?? '').trim(),
          key,
          _normalizeField(sourceField),
          (transportType ?? '').trim(),
          rawValueJson,
          at,
        ],
      );
    } catch (_) {}
  }

  // ---------------------------------------------------------------- 解析

  /// 站点解析：用户覆盖 → 原始地区表 → 唯一 / 歧义 / 未匹配。
  ///
  /// 未匹配时不会伪造站名；调用方可按 [recordUnknown] 决定是否落库上报。
  TuStationResolution resolve({
    required String sourceKey,
    String? sourceField,
    String? regionCode,
    String? regionName,
    String? transportType,
  }) {
    final key = _normalizeKey(sourceKey);
    if (key.isEmpty ||
        ((regionCode ?? '').isEmpty && (regionName ?? '').isEmpty)) {
      return TuStationResolution.unmatched;
    }
    final region = findRegion(regionCode: regionCode, regionName: regionName);
    if (region == null) {
      return queryIssue == null
          ? TuStationResolution.unmatched
          : TuStationResolution(
              confidence: TuStationMatchConfidence.unavailable,
              issue: queryIssue,
            );
    }

    final override = queryOverride(
      region.regionCode,
      key,
      sourceField: sourceField,
    );
    if (override != null) {
      return TuStationResolution(
        override: override,
        confidence: TuStationMatchConfidence.overridden,
      );
    }

    final candidates = findStations(
      sourceKey: key,
      sourceField: sourceField,
      regionCode: region.regionCode,
      transportType: transportType,
    );
    if (queryIssue != null) {
      return TuStationResolution(
        confidence: TuStationMatchConfidence.unavailable,
        issue: queryIssue,
      );
    }
    if (candidates.isEmpty) return TuStationResolution.unmatched;

    final identities = candidates
        .map((c) => (c.lineName, c.stationName, c.transportType))
        .toSet();
    return TuStationResolution(
      candidates: candidates,
      confidence: identities.length > 1
          ? TuStationMatchConfidence.ambiguous
          : TuStationMatchConfidence.exact,
    );
  }

  /// 清空进程内缓存（写入用户覆盖 / 数据库内容变化后调用）。
  void invalidate() {
    queryIssue = null;
    _cache.clear();
    _lineNames.clear();
    _lineNameScanned.clear();
    _overviews = null;
    _regions = null;
    _byCode = null;
    _columns.clear();
  }

  // ---------------------------------------------------------------- 内部

  List<TuStationRecord> _memo(
    String key,
    List<TuStationRecord> Function() build,
  ) {
    final hit = _cache[key];
    if (hit != null) return hit;
    final rows = List<TuStationRecord>.unmodifiable(build());
    if (_cache.length >= _cacheLimit) _cache.clear();
    _cache[key] = rows;
    return rows;
  }

  List<TuStationRecord> _selectRegion(
    TuRegionRow region,
    String whereSql,
    List<Object?> args, {
    int limit = 200,
  }) {
    if (limit <= 0) return const [];
    final cols = _columnsOf(region.tableName);
    final keyCol = _keyColumnOf(region);
    if (cols == null || keyCol == null) return const [];
    final sql =
        'SELECT ${_selectList(cols, keyCol)} '
        'FROM ${_quote(region.tableName)} '
        'WHERE $whereSql ORDER BY $_orderBy LIMIT $limit';
    try {
      return db.select(sql, args).map((row) => _recordOf(row, region)).toList();
    } catch (error) {
      queryIssue = 'TU 查询失败：$error';
      return const [];
    }
  }

  static const _orderBy = '''
CASE WHEN station_name IS NULL OR TRIM(station_name) = '' THEN 100 ELSE 0 END,
CASE transport_type
  WHEN 'metro' THEN 0
  WHEN 'brt' THEN 1
  WHEN 'bus' THEN 2
  WHEN 'bike' THEN 3
  WHEN 'intercity_rail' THEN 4
  ELSE 5 END,
station_id''';

  String _selectList(Set<String> cols, String keyColumn) {
    String col(String name, String fallback) =>
        cols.contains(name) ? _quote(name) : '$fallback AS ${_quote(name)}';
    return [
      col('station_id', '0'),
      col('transport_type', "''"),
      col('line_name', 'NULL'),
      col('station_name', 'NULL'),
      col('system_name', 'NULL'),
      col('source_field', 'NULL'),
      col('source_key', 'NULL'),
      col('source_region_code', 'NULL'),
      col('source_region_name', 'NULL'),
      col('raw_value_json', 'NULL'),
      col('confidence', 'NULL'),
      // 实际映射键列可能与 source_key 不同（旧库 code_source 回退）。
      '${cols.contains(keyColumn) ? _quote(keyColumn) : 'NULL'} AS "__key"',
    ].join(', ');
  }

  TuStationRecord _recordOf(Row row, TuRegionRow region) {
    final keyRaw = _cell(row, '__key').trim();
    final field = _cell(row, 'source_field');
    final transport = _cell(row, 'transport_type');
    return TuStationRecord(
      regionCode: region.regionCode,
      regionName: region.regionName,
      stationId: _asIntCell(row, 'station_id'),
      rawTransportType: transport.trim(),
      transportType: _kindOf(transport),
      lineName: _nullable(_cell(row, 'line_name')),
      stationName: _nullable(_cell(row, 'station_name')),
      systemName: _nullable(_cell(row, 'system_name')),
      sourceField: _nullable(field),
      sourceKey: keyRaw.isNotEmpty ? keyRaw : field.trim(),
      sourceRegionCode: _nullable(_cell(row, 'source_region_code')),
      sourceRegionName: _nullable(_cell(row, 'source_region_name')),
      rawValueJson: _nullable(_cell(row, 'raw_value_json')),
      confidence: _nullable(_cell(row, 'confidence')),
    );
  }

  /// 线路片段条件：12 位码按完整 / 前两位 / 后两位三口径；
  /// 10 / 8 位码的线路固定为 5-6 位。
  /// 统一用「大写 + 去前导零」文本比较，避免 CAST 把 "5E" 解析成 5。
  String _lineCondition(String col, int index) =>
      '''
(
  (length(TRIM($col)) >= 12 AND (
     LTRIM(UPPER(substr(TRIM($col), 5, 4)), '0') = ?$index
     OR LTRIM(UPPER(substr(TRIM($col), 5, 2)), '0') = ?$index
     OR LTRIM(UPPER(substr(TRIM($col), 7, 2)), '0') = ?$index))
  OR (length(TRIM($col)) BETWEEN 7 AND 11 AND (
     LTRIM(UPPER(substr(TRIM($col), 5, 2)), '0') = ?$index))
)''';

  /// 站点片段条件：
  /// - 12 位码：9-12 位，完整 / 前两位 / 后两位三口径；
  /// - 10 位码：7-10 位的 4 位站点（北京 HEX，如 `0013` / `001B`）；
  /// - 8 位码：7-8 位。
  String _stationCondition(String col, int index) =>
      '''
(
  (length(TRIM($col)) >= 12 AND (
     LTRIM(UPPER(substr(TRIM($col), 9, 4)), '0') = ?$index
     OR LTRIM(UPPER(substr(TRIM($col), 9, 2)), '0') = ?$index
     OR LTRIM(UPPER(substr(TRIM($col), 11, 2)), '0') = ?$index))
  OR (length(TRIM($col)) = 10 AND (
     LTRIM(UPPER(substr(TRIM($col), 7, 4)), '0') = ?$index
     OR LTRIM(UPPER(substr(TRIM($col), 7, 2)), '0') = ?$index
     OR LTRIM(UPPER(substr(TRIM($col), 9, 2)), '0') = ?$index))
  OR ((length(TRIM($col)) BETWEEN 7 AND 9 OR length(TRIM($col)) = 11) AND (
     LTRIM(UPPER(substr(TRIM($col), 7, 2)), '0') = ?$index))
)''';

  Set<String>? _columnsOf(String table) {
    final cached = _columns[table];
    if (cached != null) return cached;
    try {
      final cols = {
        for (final row in db.select('PRAGMA table_info(${_quote(table)})'))
          '${row['name'] ?? ''}',
      };
      if (cols.isEmpty) {
        queryIssue = 'TU 缺少数据表：$table';
        return null;
      }
      return _columns[table] = cols;
    } catch (error) {
      queryIssue = 'TU 表结构读取失败：$table：$error';
      return null;
    }
  }

  /// `source_key` 列名：新库为 source_key，旧库回退 source_field。
  String? _keyColumnOf(TuRegionRow region) {
    final cols = _columnsOf(region.tableName);
    if (cols == null) return null;
    if (cols.contains('source_key')) return 'source_key';
    if (cols.contains('source_field')) return 'source_field';
    // 旧库兼容：部分地区用 regions.code_source 指向实际编码列。
    final fallback = region.codeSource.trim();
    if (fallback.isNotEmpty && cols.contains(fallback)) return fallback;
    return null;
  }

  static String _quote(String identifier) =>
      '"${identifier.replaceAll('"', '""')}"';

  static String _normalizeKey(String raw) =>
      raw.replaceAll(RegExp(r'\s+'), '').trim();

  static String _normalizeField(String? raw) =>
      (raw ?? '').replaceAll(RegExp(r'\s+'), '').trim();

  /// 数值列读取：TEXT 存储的 station_id 不会触发类型转换异常。
  static int _asIntCell(Row row, String name) {
    try {
      final raw = row[name];
      if (raw is num) return raw.toInt();
      return int.tryParse('${raw ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '')) ??
          0;
    } catch (_) {
      return 0;
    }
  }

  static String _kindOf(String raw) => switch (raw.trim().toLowerCase()) {
    'metro' || 'subway' || 'rail' => 'metro',
    'brt' => 'brt',
    'bus' || 'coach' => 'bus',
    'bike' || 'bicycle' => 'bike',
    'intercity_rail' || 'railway' => 'intercity_rail',
    _ => 'other',
  };

  static String? _lineDigitsOf(String? line) {
    if (line == null) return null;
    final m = RegExp(r'(\d+)').firstMatch(line);
    if (m == null) return null;
    final t = m.group(1)!.replaceFirst(RegExp(r'^0+'), '');
    return t.isEmpty ? '0' : t;
  }

  static String? _tailDigits(String code, int n) {
    final m = RegExp(r'(\d+)$').firstMatch(code);
    if (m == null) return null;
    final digits = m.group(1)!;
    return digits.length >= n ? digits.substring(digits.length - n) : null;
  }

  static String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  static String _cell(Row row, String name) {
    try {
      final v = row[name];
      return v == null ? '' : '$v';
    } catch (_) {
      return '';
    }
  }

  static String? _nullable(String raw) {
    final t = raw.trim();
    return t.isEmpty ? null : t;
  }

  /// 片段归一化：大写、保留 A-F、去前导零；空 / 全零（未写入）返回空串。
  static String _normalizeFragment(String raw) {
    final text = raw.trim().toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');
    return text.replaceFirst(RegExp(r'^0+'), '');
  }
}
