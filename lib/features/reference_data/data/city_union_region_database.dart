import 'package:flutter/services.dart' show AssetBundle;
import 'package:sqlite3/sqlite3.dart';

import '../domain/reference_match.dart';
import 'reference_package.dart';
import '../domain/region_db_store.dart';
import '../domain/station_codes.dart';
import 'city_union_lookup_rules.dart';

class CuRegionRow {
  const CuRegionRow({required this.regionCode, required this.regionName});
  final String regionCode;
  final String regionName;
}

class CuTerminalRule {
  const CuTerminalRule({
    required this.regionCode,
    required this.matchKey,
    required this.isPrefix,
    required this.requiredTxnType,
    required this.priority,
    required this.entry,
  });
  final String regionCode;
  final String matchKey;
  final bool isPrefix;
  final int requiredTxnType;
  final int priority;
  final StationCodeEntry entry;
}

class CityUnionTerminalMatcher {
  const CityUnionTerminalMatcher(this._rules) : _live = null;
  const CityUnionTerminalMatcher.live(CityUnionRegionKnowledgeDb source)
    : _rules = const [],
      _live = source;
  static const empty = CityUnionTerminalMatcher([]);
  final List<CuTerminalRule> _rules;
  final CityUnionRegionKnowledgeDb? _live;
  int get length => _live?.terminalRuleCount ?? _rules.length;

  ReferenceMatch<StationCodeEntry> resolve(
    String? terminal,
    CuLookupContext context,
  ) {
    final live = _live;
    if (live != null) return live.resolveTerminal(terminal, context);
    final key = (terminal ?? '').replaceAll(' ', '').toUpperCase();
    if (key.isEmpty || context.regionCode.isEmpty) {
      return ReferenceMatch(ReferenceMatchStatus.unknown, const []);
    }
    final ranked = <(int, StationCodeEntry)>[];
    for (final rule in _rules) {
      if (rule.regionCode != context.regionCode ||
          (rule.requiredTxnType != -1 &&
              rule.requiredTxnType != context.decodedCarrierType)) {
        continue;
      }
      final exact = key == rule.matchKey;
      if (!exact &&
          !(rule.isPrefix &&
              rule.matchKey.length >= 4 &&
              key.startsWith(rule.matchKey))) {
        continue;
      }
      ranked.add((
        _rank(exact, rule.matchKey.length, rule.requiredTxnType, rule.priority),
        rule.entry,
      ));
    }
    return _choose(ranked);
  }

  StationCodeEntry? match(
    String? terminal, {
    String? cityCode,
    int? decodedCarrierType,
    DateTime? transactionTime,
    bool busLookupEnabled = false,
  }) => resolve(
    terminal,
    CuLookupContext(
      regionCode: cityCode ?? '',
      decodedCarrierType: decodedCarrierType,
      transactionTime: transactionTime,
      busLookupEnabled: busLookupEnabled,
    ),
  ).value;

  static int _rank(bool exact, int length, int type, int priority) =>
      ((exact ? 1 : 0) << 24) +
      (length << 16) +
      ((type == -1 ? 0 : 1) << 8) +
      priority.clamp(0, 255);

  static ReferenceMatch<StationCodeEntry> _choose(
    List<(int, StationCodeEntry)> ranked,
  ) {
    if (ranked.isEmpty) {
      return ReferenceMatch(ReferenceMatchStatus.unknown, const []);
    }
    ranked.sort((a, b) => b.$1.compareTo(a.$1));
    final entries = ranked
        .where((r) => r.$1 == ranked.first.$1)
        .map((r) => r.$2)
        .toList();
    final identities = entries
        .map((e) => (e.lineCode, e.stationCode, e.line, e.station))
        .toSet();
    return ReferenceMatch(
      identities.length == 1
          ? ReferenceMatchStatus.matched
          : ReferenceMatchStatus.ambiguous,
      entries,
    );
  }
}

class CityUnionRegionDatabaseContent {
  const CityUnionRegionDatabaseContent({
    required this.cities,
    this.live,
    this.terminalMatcher = CityUnionTerminalMatcher.empty,
    this.databaseVersion,
  });
  final List<CuRegionRow> cities;
  final CityUnionRegionKnowledgeDb? live;
  final CityUnionTerminalMatcher terminalMatcher;
  final int? databaseVersion;
  int get stationDatasetCount => live?.datasetCount ?? 0;
  int get stationEntryCount => live?.totalEntryCount ?? 0;
  List<StationDataset> get stationDatasets => live?.lazyDatasets() ?? const [];
}

class CityUnionRegionDatabase {
  static const assetPath = 'assets/data/TrafArch_Database_CU.sqlite';
  static Future<CityUnionRegionDatabaseContent> load({
    AssetBundle? bundle,
  }) async {
    final package = await ReferencePackage.open('CU', bundle: bundle);
    try {
      final live = CityUnionRegionKnowledgeDb(package);
      final cities = <String, String>{};
      for (final row in package.db.select(
        'SELECT region_code,region_name FROM region_codes',
      )) {
        cities[row['region_code'] as String] = row['region_name'] as String;
      }
      for (final row in package.db.select(
        'SELECT region_code,region_name FROM regions',
      )) {
        cities[row['region_code'] as String] = row['region_name'] as String;
      }
      return CityUnionRegionDatabaseContent(
        cities: [
          for (final e in cities.entries)
            CuRegionRow(regionCode: e.key, regionName: e.value),
        ],
        live: live,
        terminalMatcher: CityUnionTerminalMatcher.live(live),
        databaseVersion: 1,
      );
    } catch (_) {
      package.close();
      rethrow;
    }
  }
}

/// Direct queries against the complete independent CU package. No derived
/// runtime schema, terminal tails or internal station IDs are used as card keys.
class CityUnionRegionKnowledgeDb implements LiveRegionLines {
  CityUnionRegionKnowledgeDb(this.package);
  final ReferencePackage package;
  Database get db => package.db;
  int get terminalRuleCount => package.counts['terminal_index'] ?? 0;
  int get totalEntryCount => package.counts['station_registry'] ?? 0;
  int get datasetCount => package.counts['regions'] ?? 0;
  int get busRouteCount => package.counts['bus_routes'] ?? 0;
  int get routeCount => package.counts['routes'] ?? 0;
  int get prefixCount => package.counts['cu_prefix_dictionary'] ?? 0;

  ReferenceMatch<StationCodeEntry> resolveTerminal(
    String? terminal,
    CuLookupContext context,
  ) {
    final key = (terminal ?? '').replaceAll(' ', '').toUpperCase();
    if (context.regionCode.isEmpty || key.isEmpty) {
      return ReferenceMatch(
        ReferenceMatchStatus.unknown,
        const [],
        issue: '缺少地区或原始终端码',
      );
    }
    try {
      final rows = db.select(
        'SELECT * FROM station_lookup WHERE region_code=? '
        'AND (required_transaction_type=-1 OR required_transaction_type=?) '
        "AND ((match_mode='exact' AND match_key=?) OR "
        "(match_mode='prefix' AND length(match_key)>=4 AND substr(?,1,length(match_key))=match_key))",
        [context.regionCode, context.decodedCarrierType, key, key],
      );
      final ranked = <(int, StationCodeEntry)>[
        for (final r in rows)
          (
            CityUnionTerminalMatcher._rank(
              r['match_mode'] == 'exact',
              '${r['match_key']}'.length,
              r['required_transaction_type'] as int,
              r['priority'] as int,
            ),
            _entry(r, context),
          ),
      ];
      final station = CityUnionTerminalMatcher._choose(ranked);
      // Ambiguous station evidence must not silently become a bus route.
      if (station.status == ReferenceMatchStatus.ambiguous) return station;
      final prefix = lookupPrefix(regionCode: context.regionCode, key: key);
      if (prefix.status == ReferenceMatchStatus.unavailable) {
        return ReferenceMatch(
          ReferenceMatchStatus.unavailable,
          const [],
          issue: prefix.issue,
        );
      }
      final prefixRow = prefix.value;
      // Exact CU-to-station mappings are already resolved above. In the CU
      // prefix dictionary, a more specific placeholder can suppress a broader
      // station/line; a less specific operator must not replace a station.
      final usePrefix =
          prefixRow != null &&
          (station.value == null ||
              (rows.any(
                    (row) =>
                        row['match_mode'] == 'prefix' &&
                        row['match_key'] == station.value!.code,
                  ) &&
                  (prefixRow['match_key'] as String).length >
                      station.value!.code.length));
      final entry = usePrefix
          ? _prefixEntry(prefixRow, context)
          : station.value;
      if (entry?.station?.isNotEmpty == true) {
        return ReferenceMatch(ReferenceMatchStatus.matched, [entry!]);
      }
      // The original Shenzhen fallback requires a missing station, including
      // a readable operator/line-only prefix, and every explicit bus condition.
      final bus = _historicalBus(key, context, prefix: entry);
      if (bus.status != ReferenceMatchStatus.unknown) return bus;
      return entry == null
          ? ReferenceMatch(ReferenceMatchStatus.unknown, const [])
          : ReferenceMatch(ReferenceMatchStatus.matched, [entry]);
    } catch (e) {
      return ReferenceMatch(
        ReferenceMatchStatus.unavailable,
        const [],
        issue: '$e',
      );
    }
  }

  ReferenceMatch<StationCodeEntry> _historicalBus(
    String key,
    CuLookupContext context, {
    StationCodeEntry? prefix,
  }) {
    final time = context.transactionTime;
    if (context.regionCode != '5180' ||
        context.decodedCarrierType != 1 ||
        !context.busLookupEnabled ||
        time == null ||
        key.length < 8 ||
        time.millisecondsSinceEpoch >= 1735675200000) {
      return ReferenceMatch(ReferenceMatchStatus.unknown, const []);
    }
    final rows = db.select(
      'SELECT * FROM bus_routes WHERE region_code=? AND terminal_suffix=? '
      'AND required_transaction_type=? AND valid_before_unix_ms>? '
      'AND requires_station_missing=1 AND requires_bus_lookup_enabled=1',
      [
        context.regionCode,
        key.substring(key.length - 8),
        context.decodedCarrierType,
        time.millisecondsSinceEpoch,
      ],
    );
    final entries = [
      for (final r in rows)
        StationCodeEntry(
          code: key,
          type: '公交',
          line: prefix?.line?.isNotEmpty == true
              ? '${prefix!.line} · ${r['route_number']}'
              : '${r['route_number']}',
          system: 'cu',
          kind: 'bus',
          datasetFile: 'cu:5180:bus_routes',
          sourceKey: '${r['terminal_suffix']}',
          sourceField: '${r['source_field']}',
          rawValueJson: '${r['value_json']}',
          // route_number is a display route identifier, not an invented encoded line code.
        ),
    ];
    return ReferenceMatch(
      entries.isEmpty
          ? ReferenceMatchStatus.unknown
          : ReferenceMatchStatus.matched,
      entries,
    );
  }

  ReferenceMatch<Map<String, Object?>> lookupRoute({
    required String regionCode,
    required String lineCode,
  }) => _dictionary(
    'SELECT * FROM routes WHERE region_code=? AND (line_code=? OR line_key=?)',
    [regionCode, lineCode, lineCode],
    'line_name',
  );

  ReferenceMatch<Map<String, Object?>> lookupPrefix({
    required String regionCode,
    required String key,
  }) {
    // Prefix records intentionally include operator/line/placeholder entries.
    // Return the original record_kind and raw fields, never re-label all as stations.
    return _dictionary(
      'SELECT * FROM cu_prefix_dictionary WHERE region_code=? '
          'AND length(match_key)>=5 AND substr(?,1,length(match_key))=match_key '
          'ORDER BY length(match_key) DESC LIMIT 1',
      [regionCode, key.replaceAll(' ', '').toUpperCase()],
      'value_json',
    );
  }

  ReferenceMatch<Map<String, Object?>> _dictionary(
    String sql,
    List<Object?> args,
    String identity,
  ) {
    if (args.any((v) => v == null || v == '')) {
      return ReferenceMatch(ReferenceMatchStatus.unknown, const []);
    }
    try {
      final rows = [
        for (final r in db.select(sql, args))
          Map<String, Object?>.unmodifiable(r),
      ];
      final values = rows.map((r) => r[identity]).toSet();
      return ReferenceMatch(
        rows.isEmpty
            ? ReferenceMatchStatus.unknown
            : values.length == 1
            ? ReferenceMatchStatus.matched
            : ReferenceMatchStatus.ambiguous,
        rows,
      );
    } catch (e) {
      return ReferenceMatch(
        ReferenceMatchStatus.unavailable,
        const [],
        issue: '$e',
      );
    }
  }

  static StationCodeEntry _entry(Row r, CuLookupContext context) {
    final sourceKey = '${r['source_key']}';
    final required = r['required_transaction_type'] as int;
    final carrier = required == -1
        ? CityUnionLookupRules.carrierForKey(sourceKey)
        : required;
    final presentation = CityUnionLookupRules.presentation(carrier);
    final labels = CityUnionLookupRules.labelsAt(
      sourceKey,
      context.transactionTime,
      r['line_name'] as String?,
      r['station_name'] as String?,
    );
    return StationCodeEntry(
      code: '${r['match_key']}',
      system: 'cu',
      kind: presentation?.$1 ?? r['transport_type'] as String?,
      type:
          presentation?.$2 ??
          switch (r['transport_type']) {
            'metro' => '地铁',
            'bus' => '公交',
            'brt' => 'BRT',
            'intercity_rail' => '铁路',
            _ => null,
          },
      line: labels.$1,
      station: labels.$2,
      lineCode: r['line_code'] as String?,
      stationCode: r['station_code'] as String?,
      lineKey: r['line_key'] as String?,
      sourceField: r['source_field'] as String?,
      sourceKey: r['source_key'] as String?,
      rawValueJson: r['raw_value_json'] as String?,
      datasetFile: 'cu:${r['region_code']}:station_lookup',
    );
  }

  StationCodeEntry? _prefixEntry(
    Map<String, Object?> row,
    CuLookupContext context,
  ) {
    final system = row['system_name'] as String;
    final line = row['line_name'] as String;
    final station = row['station_name'] as String;
    // Empty triples are intentional stopping rules, not invented locations.
    if (system.isEmpty && line.isEmpty && station.isEmpty) return null;
    final key = row['match_key'] as String;
    final labels = CityUnionLookupRules.labelsAt(
      key,
      context.transactionTime,
      line.isEmpty ? null : line,
      station.isEmpty ? null : station,
    );
    final carrier = CityUnionLookupRules.carrierForKey(key);
    final presentation = CityUnionLookupRules.presentation(carrier);
    final route = lookupRoute(
      regionCode: context.regionCode,
      lineCode: key,
    ).value;
    return StationCodeEntry(
      code: key,
      system: 'cu',
      kind: presentation?.$1,
      type: presentation?.$2,
      line: [
        if (system.isNotEmpty) system,
        if (labels.$1?.isNotEmpty == true) labels.$1!,
      ].join(' · '),
      station: labels.$2,
      lineKey: route?['line_key'] as String?,
      lineCode: route?['line_code'] as String?,
      sourceKey: key,
      sourceField: row['source_field'] as String?,
      rawValueJson: row['value_json'] as String?,
      datasetFile: 'cu:${context.regionCode}:cu_prefix_dictionary',
    );
  }

  @override
  List<RegionOverview> queryOverviews() => [
    for (final r in db.select(
      'SELECT r.region_code,r.region_name,COUNT(s.station_id) AS entries,'
      "COUNT(DISTINCT COALESCE(NULLIF(s.line_name,''),'未标注线路')) AS lines "
      'FROM regions r LEFT JOIN stations s ON s.region_code=r.region_code '
      'GROUP BY r.region_code,r.region_name ORDER BY r.region_code',
    ))
      RegionOverview(
        system: 'cu',
        code: '${r['region_code']}',
        name: '${r['region_name']}',
        lineCount: r['lines'] as int,
        stationCount: r['entries'] as int,
      ),
  ];

  @override
  Future<List<RegionLineCoverage>> linesForRegion(
    String cityKey,
    String system,
  ) async {
    if (system != 'cu') return const [];
    final lines = <String, Set<String>>{};
    for (final r in db.select(
      'SELECT line_name,station_name FROM stations WHERE region_code=?',
      [cityKey],
    )) {
      final line = r['line_name'] as String?;
      final station = r['station_name'] as String?;
      if (station == null || station.isEmpty) continue;
      (lines[line == null || line.isEmpty ? '未标注线路' : line] ??= {}).add(
        station,
      );
    }
    final names = lines.keys.toList()..sort();
    return [
      for (final line in names)
        RegionLineCoverage(line, lines[line]!.toList()..sort()),
    ];
  }

  List<StationDataset> lazyDatasets() => [
    for (final r in queryOverviews()) LiveRegionDataset(this, r),
  ];
  void close() => package.close();
}
