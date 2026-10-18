import 'dart:io';

import 'package:flutter/services.dart' show rootBundle, AssetBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'station_codes.dart';

/// 城市一卡通（CU）地区行：地区编码（4 位邮编前缀）→ 地区名。
class CuRegionRow {
  final String regionCode;
  final String regionName;

  const CuRegionRow({required this.regionCode, required this.regionName});
}

/// 城市站点行（region_* 表一行，station_id 非卡面编码，仅内部键）。
class _CuStation {
  final String transport;
  final String? line;
  final String? station;

  const _CuStation({
    required this.transport,
    this.line,
    this.station,
  });
}

/// 城市一卡通终端索引规则（terminal_index 一行）：卡面交易终端编号 → 站点。
///
/// [matchKey] 为归一化（仅数字）后的匹配键；[isPrefix] 为真表示前缀匹配
/// （卡面终端码以 [matchKey] 开头即命中），否则按精确匹配。
/// [requiredTxnType] 为限定交易类型（-1 表示不限）；[priority] 越大越优先。
/// [entry] 为命中站点（线路 / 站点名，system 'cu'）。
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

/// 城市一卡通终端匹配器：以 terminal_index 的精确 / 前缀规则把卡面交易
/// 终端编号解析到站点（线路 / 站点名）。多候选按「同地区优先 → 精确优先
/// 于前缀 → 匹配键更长（更具体）优先 → 交易类型精确匹配优先 → priority
/// 更大优先」择优；均未命中返回 null（保持未知，不猜测）。
class CityUnionTerminalMatcher {
  static const _anyTxnType = -1;

  /// 前缀匹配最小键长（防止 1~3 位短前缀过度命中，与末四端口径一致）。
  static const _minPrefixLength = 4;

  final List<CuTerminalRule> _rules;

  const CityUnionTerminalMatcher(this._rules);

  static const empty = CityUnionTerminalMatcher([]);

  int get length => _rules.length;

  /// 交易终端编号 → 站点条目。[terminalNumber] 为卡片 BCD 终端编号（12 位
  /// 数字）；[cityCode] 为卡片城市代码（CU 邮编前四位，用于同地区优先）；
  /// [transactionType] 为交易类型原始值（如 0x06 / 0x09，用于类型过滤）。
  StationCodeEntry? match(
    String? terminalNumber, {
    String? cityCode,
    int? transactionType,
  }) {
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
      // 交易类型过滤：规则限定类型（非 -1）且卡类型已知时须相等。
      if (rule.requiredTxnType != _anyTxnType &&
          transactionType != null &&
          rule.requiredTxnType != transactionType) {
        continue;
      }
      final score = _score(rule, city: city, exact: exact, txnGiven: transactionType != null);
      if (best == null || score > bestScore) {
        best = rule;
        bestScore = score;
      }
    }
    return best?.entry;
  }

  /// 候选评分（数值越大越优，按位打包一次性比较）：
  /// 同地区(bit16) > 精确(bit15) > 键长度(bit8-14) > 交易类型精确(bit7) > priority(bit0-6)。
  int _score(
    CuTerminalRule rule, {
    required String city,
    required bool exact,
    required bool txnGiven,
  }) {
    final regionHit = city.isNotEmpty && rule.regionCode == city ? 1 : 0;
    final txnHit = txnGiven && rule.requiredTxnType != _anyTxnType ? 1 : 0;
    final priority = rule.priority.clamp(0, 63);
    final keyLen = rule.matchKey.length.clamp(0, 127);
    return (regionHit << 16) |
        ((exact ? 1 : 0) << 15) |
        (keyLen << 8) |
        (txnHit << 7) |
        priority;
  }

  static String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');
}

/// 城市一卡通地区 / 站点数据库读取内容：地区识别（regions + region_codes
/// 城市字典）+ 线路站点（各 region_* 表，经 terminal_index 匹配卡面终端码）。
///
/// 只承载数据、不含查询逻辑；由 [KnowledgeBase] 合并进城市码表 /
/// 站点代码表（数据库优先、JSON 兜底）。
class CityUnionRegionDatabaseContent {
  final List<CuRegionRow> cities;
  final List<StationDataset> stationDatasets;

  /// 终端索引匹配器（terminal_index 精确 / 前缀，供 CU 行程站点名解析）。
  final CityUnionTerminalMatcher terminalMatcher;

  const CityUnionRegionDatabaseContent({
    required this.cities,
    required this.stationDatasets,
    this.terminalMatcher = CityUnionTerminalMatcher.empty,
  });

  int get stationDatasetCount => stationDatasets.length;
  int get stationEntryCount =>
      stationDatasets.fold(0, (a, d) => a + d.codes.length);
}

/// 城市一卡通（CU）地区 / 线路站点数据库（外部 SQLite，只读接入）。
///
/// 数据源：assets/data/TrafArch_Database_CU.sqlite（cu-standalone-2）。
/// 站点表以 station_id 为内部主键（非卡面编码），卡面终端 / 站点编码经
/// terminal_index（match_key exact / prefix → station_id）匹配到站点行；
/// 本读取器按「完整键 + 后四位键」两种口径登记命中站点，与交通联合站点
/// 查询层（[StationCodeTable]）末四位策略对齐。Android 资产只读，先提取
/// 到临时文件，经 [sqlite3] 打开，读取完毕删除临时文件。资产缺失、原生库
/// 不可用或读取异常时返回 null（调用方回退既有知识库，不阻断、不猜测）。
class CityUnionRegionDatabase {
  static const assetPath = 'assets/data/TrafArch_Database_CU.sqlite';

  CityUnionRegionDatabase._();

  static Future<CityUnionRegionDatabaseContent?> load({
    AssetBundle? bundle,
  }) async {
    final root = bundle ?? rootBundle;
    File? tmp;
    Database? db;
    try {
      final data = await root.load(assetPath);
      final dir = await getTemporaryDirectory();
      tmp = File('${dir.path}/trafarch_database_cu.sqlite');
      await tmp.writeAsBytes(data.buffer.asUint8List(), flush: true);

      db = sqlite3.open(tmp.path);

      // 地区主表（region_code / region_name / table_name）
      final regions = <CuRegionRow>[];
      final tableByCode = <String, String>{};
      for (final r in db.select(
        'SELECT region_code, region_name, table_name FROM regions',
      )) {
        final code = _digits('${r['region_code'] ?? ''}');
        final name = '${r['region_name'] ?? ''}'.trim();
        final table = '${r['table_name'] ?? ''}'.trim();
        if (code.isEmpty || name.isEmpty) continue;
        regions.add(CuRegionRow(regionCode: code, regionName: name));
        if (table.isNotEmpty) tableByCode[code] = table;
      }

      // 城市字典（region_codes：4 位 CU 邮编前缀 → 地区名，覆盖广）
      final dict = <String, String>{};
      try {
        for (final r in db.select(
          'SELECT region_code, region_name FROM region_codes',
        )) {
          final code = _digits('${r['region_code'] ?? ''}');
          final name = '${r['region_name'] ?? ''}'.trim();
          if (code.isEmpty || name.isEmpty) continue;
          dict.putIfAbsent(code, () => name);
        }
      } catch (_) {
        // 无 region_codes 表：仅用 regions
      }

      final cities = <CuRegionRow>[
        ...regions,
        for (final e in dict.entries)
          CuRegionRow(regionCode: e.key, regionName: e.value),
      ];

      // 站点数据集：每地区一张表，经 terminal_index 匹配卡面编码
      final datasets = <StationDataset>[];
      final terminalRules = <CuTerminalRule>[];
      // terminal_index 列名集合（match_mode / required_transaction_type /
      // priority 缺失时按精确 / 不限类型 / 0 优先级降级，不猜测）。
      final tcols = _tableColumns(db, 'terminal_index');
      for (final region in regions) {
        final table = tableByCode[region.regionCode];
        if (table == null) continue;
        final stationById = <int, _CuStation>{};
        final cols = _tableColumns(db, table);
        if (cols == null) continue;
        if (!cols.contains('station_id') || !cols.contains('station_name')) {
          continue;
        }
        for (final r in db.select('SELECT * FROM "$table"')) {
          final id = (r['station_id'] as num?)?.toInt();
          if (id == null) continue;
          stationById[id] = _CuStation(
            transport: _cell(r, cols, 'transport_type').trim(),
            line: _nullIfEmpty(_cell(r, cols, 'line_name')),
            station: _nullIfEmpty(_cell(r, cols, 'station_name')),
          );
        }

        final codes = <String, StationCodeEntry>{};
        // 优先经 terminal_index 匹配（卡面终端 / 站点编码 → station_id）
        try {
          for (final r in db.select(
            'SELECT * FROM terminal_index WHERE region_code = ?',
            [region.regionCode],
          )) {
            final id = (r['station_id'] as num?)?.toInt();
            final st = id == null ? null : stationById[id];
            if (st == null) continue;
            final matchKey = '${r['match_key'] ?? ''}'.trim();
            if (matchKey.isEmpty) continue;
            _register(codes, matchKey, region.regionCode, st);
            // 同步收集终端索引规则（CU 行程站点名的精确 / 前缀匹配用）
            final mk = _digits(matchKey);
            if (mk.isNotEmpty && (st.station != null || st.line != null)) {
              terminalRules.add(CuTerminalRule(
                regionCode: region.regionCode,
                matchKey: mk,
                isPrefix: tcols != null && tcols.contains('match_mode')
                    ? '${r['match_mode'] ?? ''}'.toLowerCase().contains('prefix')
                    : false,
                requiredTxnType:
                    tcols != null && tcols.contains('required_transaction_type')
                        ? ((r['required_transaction_type'] as num?)?.toInt() ??
                            -1)
                        : -1,
                priority: tcols != null && tcols.contains('priority')
                    ? ((r['priority'] as num?)?.toInt() ?? 0)
                    : 0,
                entry: _entry(region.regionCode, mk, st),
              ));
            }
          }
        } catch (_) {
          // 无 terminal_index 表：回退按 station_id 登记（尽力而为）
        }
        // terminal_index 未覆盖时，回退按 station_id 末位登记
        if (codes.isEmpty) {
          stationById.forEach((id, st) {
            _register(codes, '$id', region.regionCode, st);
          });
        }
        if (codes.isEmpty) continue;
        datasets.add(StationDataset(
          file: 'cu:${region.regionCode}',
          cityCode: region.regionCode,
          cityName: region.regionName,
          system: 'cu',
          kind: 'mixed',
          codes: codes,
        ));
      }

      return CityUnionRegionDatabaseContent(
        cities: cities,
        stationDatasets: datasets,
        terminalMatcher: CityUnionTerminalMatcher(terminalRules),
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

  /// 将站点条目登记到 codes：完整匹配键 + 末四位键各一份（与交通联合
  /// 站点查询层「末四位」口径对齐）；同键保留首条（不覆盖）。
  static void _register(
    Map<String, StationCodeEntry> out,
    String rawCode,
    String cityCode,
    _CuStation st,
  ) {
    if (st.station == null && st.line == null) return;
    void add(String key) {
      if (key.isEmpty) return;
      out.putIfAbsent(key, () => _entry(cityCode, key, st));
    }

    add(rawCode);
    final tail = StationCodeTable.tailFourDigits(rawCode);
    if (tail != null) add(tail);
  }

  /// 构造城市一卡通站点条目（system 'cu'）：[key] 作编码键，
  /// 类型 / 线路 / 站点取自站点行。
  static StationCodeEntry _entry(String cityCode, String key, _CuStation st) {
    return StationCodeEntry(
      code: key,
      type: _typeName(st.transport),
      line: st.line,
      station: st.station,
      system: 'cu',
      kind: _kind(st.transport),
      datasetFile: 'cu:$cityCode',
    );
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