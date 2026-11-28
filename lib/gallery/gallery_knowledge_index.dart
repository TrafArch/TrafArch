import 'dart:collection';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';

import '../features/reference_data/data/reference_package.dart';
import '../features/reference_data/data/tu_station_repository.dart';
import '../features/reference_data/domain/station_codes.dart';

enum GalleryKnowledgeKind { city, line, station, code }

class GalleryKnowledgeCity {
  GalleryKnowledgeCity(this.system, this.name, this.code, this.province);

  final String system, name, code, province;
  final _lines = <String, GalleryKnowledgeLine>{};
  final _aliases = <String>{};
  int _codeCount = 0;

  /// 设计快照（样例 fixtures）声明的线路数。发布包索引本身没有该字段，
  /// 样例模式由 [GalleryKnowledgeIndex.applyDeclaredLineCounts] 补齐；
  /// 缺失时为 null，线路数退回浏览列表长度。
  int? declaredLineCount;

  Iterable<GalleryKnowledgeLine> get lines => _lines.values;
  int get codeCount => _codeCount;
}

class GalleryKnowledgeLine {
  GalleryKnowledgeLine(this.name);

  final String name;
  final _stations = <String, GalleryKnowledgeStation>{};
  final _codes = <String>{};

  Iterable<GalleryKnowledgeStation> get stations => _stations.values;
  Set<String> get codes => UnmodifiableSetView(_codes);
}

class GalleryKnowledgeStation {
  GalleryKnowledgeStation(this.name);

  final String name;
  final _codes = <(String, String)>{};

  Set<(String, String)> get codes => UnmodifiableSetView(_codes);
}

/// 城市详情页的数据视图。样例（fixtures）与 live（已校验发布包）两条路径
/// 都先转换成这个结构再导航，详情页因此不依赖具体数据源。
class GalleryKnowledgeCityView {
  const GalleryKnowledgeCityView({
    required this.system,
    required this.name,
    required this.code,
    required this.province,
    required this.lineCount,
    required this.codeCount,
    required this.lines,
    required this.hasStationData,
  });

  final String system, name, code, province;

  /// 发布包声明的线路数；结构缺失时为 null（界面显示未知）。
  final int? lineCount;

  /// 城市编码条目数；结构缺失时为 null（界面显示未知）。
  final int? codeCount;

  final List<GalleryKnowledgeLineView> lines;

  /// 数据源是否提供了线路内站点列表；没有则为 null 而不是 0。
  final bool hasStationData;

  /// 同城同名站点只计一次。
  int? get stationCount {
    if (!hasStationData) return null;
    final names = <String>{};
    for (final line in lines) {
      for (final station in line.stations) {
        names.add(station.name);
      }
    }
    return names.length;
  }

  factory GalleryKnowledgeCityView.fromCity(GalleryKnowledgeCity city) {
    final lines = [
      for (final line in city.lines)
        GalleryKnowledgeLineView(
          name: line.name,
          stations: List.unmodifiable([
            for (final station in line.stations)
              GalleryKnowledgeStationView(
                name: station.name,
                codes: List.unmodifiable({
                  for (final (code, _) in station.codes) code,
                }),
              ),
          ]),
          codes: List.unmodifiable(line.codes),
        ),
    ];
    return GalleryKnowledgeCityView(
      system: city.system.toUpperCase(),
      name: city.name,
      code: city.code,
      province: city.province,
      lineCount: resolveKnowledgeLineCount(
        declared: city.declaredLineCount,
        listed: city.lines.length,
      ),
      codeCount: city.codeCount,
      lines: _orderedCityLines(lines),
      // 发布包可能只有线路行（如 CU 的 routes 表）而没有站点行；此时站点数
      // 不可得，不能当成 0。
      hasStationData: lines.any((line) => line.stations.isNotEmpty),
    );
  }

  /// 从样例快照的城市记录构造。
  factory GalleryKnowledgeCityView.fromRegion(
    String system,
    Map<String, dynamic> region,
  ) {
    final rawLines = region['lines'];
    final built = <GalleryKnowledgeLineView>[];
    // 线路存在但缺 stations 字段时，站点数不可得，不能当成 0。
    var hasStationData = rawLines is List;
    if (rawLines is List) {
      for (final raw in rawLines) {
        if (raw is! Map) {
          hasStationData = false;
          continue;
        }
        final name = '${raw['name'] ?? ''}'.trim();
        final rawStations = raw['stations'];
        if (rawStations is! List) hasStationData = false;
        built.add(
          GalleryKnowledgeLineView(
            name: name.isEmpty ? '未标注线路' : name,
            stations: List.unmodifiable([
              if (rawStations is List)
                for (final station in rawStations)
                  GalleryKnowledgeStationView(name: '$station'),
            ]),
            codes: const [],
          ),
        );
      }
    }
    return GalleryKnowledgeCityView(
      system: system.toUpperCase(),
      name: '${region['name'] ?? '未知城市'}',
      code: '${region['code'] ?? '未知'}',
      province: '${region['province'] ?? ''}',
      lineCount: knowledgeLineCountOfRegion(region),
      codeCount: region['entries'] as int?,
      lines: _orderedCityLines(built),
      hasStationData: hasStationData,
    );
  }
}

// 只识别显示名里的单个地铁号线。公交纯数字名、S1 线、1/2 号线和
// 松江有轨电车 1 号线等不参与排序。规范化仅用于比较，不改变原名。
final _metroLineNumber = RegExp(
  r'^(?:地[铁鐵]\s*)?([0-9]+)\s*[号號]\s*[线線]'
  r'(?:\s*(?:[东西南北東]?支[线線]|\([^()]+\)))?$',
);

List<GalleryKnowledgeLineView> _orderedCityLines(
  List<GalleryKnowledgeLineView> lines,
) {
  final slots = <int>[];
  final numbered =
      <({int number, int original, GalleryKnowledgeLineView line})>[];
  for (final (index, line) in lines.indexed) {
    final label = _metroLineNumber.firstMatch(_normalize(line.name))?.group(1);
    final number = label == null ? null : int.tryParse(label);
    if (number == null) continue;
    slots.add(index);
    numbered.add((number: number, original: index, line: line));
  }
  numbered.sort((a, b) {
    final byNumber = a.number.compareTo(b.number);
    return byNumber != 0 ? byNumber : a.original.compareTo(b.original);
  });
  // 只在原有号线的槽位内重排；公交和具名线路不移动，同号线路按源顺序。
  for (final (index, entry) in numbered.indexed) {
    lines[slots[index]] = entry.line;
  }
  return List.unmodifiable(lines);
}

/// 线路数的唯一口径：发布包／设计快照声明的值优先，只有缺失时才退回当前
/// 可浏览的线路列表长度。首页城市卡、数据概况、城市页 KV 与线路区标题、
/// 以及 [GalleryKnowledgeCityView.fromCity]／[GalleryKnowledgeCityView.fromRegion]
/// 两条进入路径都走这里，避免同一城市在不同位置出现两个数字。
///
/// 样例的 `lines` 只是浏览子集，`lineCount` 才是设计快照统计；因此区标题
/// 写「收录 N 条线路」时 N 也用这里的值，列表条数较少不算矛盾。
int? resolveKnowledgeLineCount({int? declared, int? listed}) =>
    declared ?? listed;

/// 从 region 记录解析线路数（声明值优先，缺失才用 lines 列表长度）。
/// 非 Map 的线路项不计入列表长度。
int? knowledgeLineCountOfRegion(Map<String, dynamic> region) {
  final declared = region['lineCount'];
  final rawLines = region['lines'];
  return resolveKnowledgeLineCount(
    declared: declared is int ? declared : null,
    listed: rawLines is List ? rawLines.whereType<Map>().length : null,
  );
}

class GalleryKnowledgeLineView {
  const GalleryKnowledgeLineView({
    required this.name,
    required this.stations,
    this.codes = const <String>[],
  });

  final String name;
  final List<GalleryKnowledgeStationView> stations;

  /// 线路编号（原始值，按数据源顺序）。样例快照不含线路编号，保持空列表，
  /// 界面显示「线路编号未知」而不猜测。
  final List<String> codes;

  /// 线路卡片展开状态的唯一标识：体系 + 城市编码 + 线路名。用线路名而不是
  /// 列表索引，线路顺序变化不会串状态（spec §9.4）。
  static String idFor(String system, String cityCode, String lineName) =>
      'knowledge-line:${system.toUpperCase()}:$cityCode:$lineName';
}

/// 城市页线路卡内的站点视图。样例快照只提供站点名，[codes] 为空表示数据源
/// 没有编码字段；有值时按原始字符串展示，不做格式猜测。
class GalleryKnowledgeStationView {
  const GalleryKnowledgeStationView({
    required this.name,
    this.codes = const <String>[],
  });

  final String name;
  final List<String> codes;
}

class GalleryKnowledgeResult {
  const GalleryKnowledgeResult(
    this.kind,
    this.city, {
    this.line,
    this.station,
    this.code,
    this.source,
  });

  final GalleryKnowledgeKind kind;
  final GalleryKnowledgeCity city;
  final GalleryKnowledgeLine? line;
  final GalleryKnowledgeStation? station;
  final String? code, source;

  String get title => switch (kind) {
    GalleryKnowledgeKind.city => city.name,
    GalleryKnowledgeKind.line => line!.name,
    GalleryKnowledgeKind.station => station!.name,
    GalleryKnowledgeKind.code => code!,
  };
}

class GalleryKnowledgeIndex {
  GalleryKnowledgeIndex._(
    Iterable<GalleryKnowledgeCity> regions,
    Iterable<GalleryKnowledgeResult> codes,
  ) : cities = List.unmodifiable(regions) {
    for (final city in cities) {
      _add(GalleryKnowledgeResult(GalleryKnowledgeKind.city, city), [
        city.code,
        ...city._aliases,
      ]);
      for (final line in city.lines) {
        _add(
          GalleryKnowledgeResult(GalleryKnowledgeKind.line, city, line: line),
          line.codes,
        );
        for (final station in line.stations) {
          _add(
            GalleryKnowledgeResult(
              GalleryKnowledgeKind.station,
              city,
              line: line,
              station: station,
            ),
            const [],
          );
        }
      }
    }
    for (final result in codes) {
      _add(result, const []);
    }
  }

  final _postings = <int, List<_SearchTerm>>{};
  final List<GalleryKnowledgeCity> cities;

  /// 补齐设计快照声明的线路数（`{system: {code: lineCount}}`，system 小写）。
  /// 发布包索引本身没有这个字段，样例模式由界面层从 fixtures 传入；重复调用
  /// 结果一致，缺失的城市保持 null（线路数退回浏览列表长度）。
  void applyDeclaredLineCounts(Map<String, Map<String, int>> bySystem) {
    for (final city in cities) {
      final declared = bySystem[city.system.toLowerCase()]?[city.code];
      if (declared != null) city.declaredLineCount = declared;
    }
  }

  static Future<GalleryKnowledgeIndex> loadPaths(Map<String, String> paths) {
    if (paths.isEmpty) throw StateError('本地参考数据包不可用');
    return Isolate.run(() => GalleryKnowledgeIndex.fromPaths(paths));
  }

  static Future<GalleryKnowledgeIndex> load() async {
    final paths = <String, String>{};
    for (final protocol in ['TU', 'CU']) {
      final package = await ReferencePackage.open(protocol);
      try {
        paths[protocol] = package.path;
      } finally {
        package.close();
      }
    }
    return loadPaths(paths);
  }

  factory GalleryKnowledgeIndex.fromPaths(Map<String, String> paths) {
    final cities = <GalleryKnowledgeCity>[];
    final codes = <GalleryKnowledgeResult>[];
    for (final entry in paths.entries) {
      final tu = entry.key == 'TU';
      final db = sqlite3.open(entry.value, mode: OpenMode.readOnly);
      try {
        final regions = {
          for (final row in db.select(
            'SELECT region_id, region_code, region_name, '
            '${tu ? 'province' : 'NULL AS province'} FROM regions '
            'ORDER BY region_code, region_id',
          ))
            row['region_id'] as int: GalleryKnowledgeCity(
              entry.key,
              _field(row, 'region_name'),
              _field(row, 'region_code'),
              _field(row, 'province'),
            ),
        };
        final byCode = {for (final city in regions.values) city.code: city};
        GalleryKnowledgeCity? routeCity(String code, String name) {
          if (name.trim().isEmpty) return byCode[code];
          return byCode.putIfAbsent(
            code,
            () => GalleryKnowledgeCity(entry.key, name, code, ''),
          );
        }

        if (tu) {
          for (final row in db.select(
            'SELECT region_id, source_region_name FROM region_aliases',
          )) {
            final city = regions[row['region_id']];
            final alias = _field(row, 'source_region_name').trim();
            if (alias.isNotEmpty && alias != city?.name)
              city?._aliases.add(alias);
          }
        }

        final seen = <(GalleryKnowledgeCity, String, String, String, String)>{};
        void addRecord(
          GalleryKnowledgeCity? city, {
          required String lineName,
          required String stationName,
          required String code,
          required String source,
        }) {
          if (city == null) return;
          if (!seen.add((city, lineName, stationName, code, source))) return;
          final line = lineName.trim().isEmpty && stationName.trim().isEmpty
              ? null
              : city._lines.putIfAbsent(
                  lineName,
                  () => GalleryKnowledgeLine(
                    lineName.trim().isEmpty ? '未标注线路' : lineName,
                  ),
                );
          final station = stationName.trim().isEmpty
              ? null
              : line?._stations.putIfAbsent(
                  stationName,
                  () => GalleryKnowledgeStation(stationName),
                );
          if (code.trim().isEmpty) return;
          if (station != null) {
            station._codes.add((code, source));
          } else {
            line?._codes.add(code);
          }
          city._codeCount++;
          codes.add(
            GalleryKnowledgeResult(
              GalleryKnowledgeKind.code,
              city,
              line: line,
              station: station,
              code: code,
              source: source,
            ),
          );
        }

        void addLineCode(
          GalleryKnowledgeCity? city,
          String line,
          String code,
          String source,
        ) {
          if (city == null ||
              line.trim().isEmpty ||
              code.trim().isEmpty ||
              city._lines[line]?._codes.contains(code) == true) {
            return;
          }
          addRecord(
            city,
            lineName: line,
            stationName: '',
            code: code,
            source: source,
          );
        }

        for (final row in db.select(
          tu
              ? 'SELECT * FROM all_records ORDER BY station_id'
              : 'SELECT region_code, line_name, station_name, source_key, '
                    'source_field FROM stations ORDER BY station_id',
        )) {
          final city = tu
              ? regions[row['region_id']]
              : byCode[row['region_code']];
          final line = _field(row, 'line_name');
          final station = _field(row, 'station_name');
          final code = _field(row, 'source_key');
          final source = _field(row, 'source_field');
          // TU 的 route_name 行把线路名称存放在 station_name 列。
          if (tu && row['record_kind'] == 'route_name') {
            addLineCode(
              city,
              line.trim().isEmpty ? station : line,
              code,
              source,
            );
          } else {
            addRecord(
              city,
              lineName: line,
              stationName: station,
              code: code,
              source: source,
            );
            if (tu && city != null && station.isNotEmpty) {
              final segment = _tuStationLineCode(city.code, row, code, source);
              if (segment != null) addLineCode(city, line, segment, source);
            }
          }
        }
        if (tu) {
          final repository = TuStationRepository(db);
          for (final prefix in repository.railPrefixes) {
            final key = prefix.sourceKey;
            if (prefix.rawValue case [_, final String line, '']
                when line.trim().isNotEmpty && key.length > 4) {
              final owner = key.substring(0, 4);
              final city =
                  byCode[owner] ?? routeCity(owner, _tuCityName(db, owner));
              addLineCode(city, line, key, prefix.sourceField);
              addLineCode(city, line, key.substring(4), prefix.sourceField);
            }
          }
          if (repository.queryIssue case final issue?) throw StateError(issue);
        } else {
          // 先取线路表的原码。济南等城市只在站点行明确登记线路键。
          final routes = db.select(
            'SELECT r.region_code, c.region_name, r.line_name, r.line_key, '
            'r.line_code, r.source_field FROM routes r '
            'LEFT JOIN region_codes c ON c.region_code = r.region_code '
            'ORDER BY r.region_code, r.source_entry_index',
          );
          final stationLines = db.select(
            'SELECT region_code, line_name, line_key, line_code, source_field '
            'FROM stations WHERE line_name_matches_prefix = 1 '
            'GROUP BY region_code, line_name, line_key, line_code, source_field '
            'ORDER BY MIN(station_id)',
          );
          for (final row in routes.followedBy(stationLines)) {
            final city = routeCity(
              _field(row, 'region_code'),
              _field(row, 'region_name'),
            );
            final line = _field(row, 'line_name');
            final source = _field(row, 'source_field');
            addLineCode(city, line, _field(row, 'line_key'), source);
            addLineCode(city, line, _field(row, 'line_code'), source);
          }
          for (final row in db.select(
            'SELECT station.region_code, station.line_name, station.station_name, '
            'terminal.match_key AS source_key, station.source_field '
            'FROM terminal_index AS terminal JOIN stations AS station '
            'ON station.station_id = terminal.station_id '
            'ORDER BY terminal.region_code, terminal.match_key',
          )) {
            addRecord(
              byCode[row['region_code']],
              lineName: _field(row, 'line_name'),
              stationName: _field(row, 'station_name'),
              code: _field(row, 'source_key'),
              source: _field(row, 'source_field'),
            );
          }
        }
        cities.addAll(
          byCode.values.toList()..sort((a, b) => a.code.compareTo(b.code)),
        );
      } finally {
        db.close();
      }
    }
    return GalleryKnowledgeIndex._(cities, codes);
  }

  static String _field(Row row, String key) => row[key]?.toString() ?? '';

  static final _hexCode = RegExp(r'^[0-9A-Fa-f]+$');

  /// 城市原表可以同时收录带城市前缀与不带前缀的站点键。
  static String? _tuStationLineCode(
    String city,
    Row row,
    String code,
    String source,
  ) {
    if (row['record_kind'] != 'station_mapping' ||
        row['lookup_key_namespace'] != 'TU' ||
        !const {'metro', 'tram', 'light_rail', 'intercity_rail'}
            .contains(row['transport_type']) ||
        !StationCodeTable.isTuRailSourceField(city, source) ||
        !_hexCode.hasMatch(code)) {
      return null;
    }
    final prefixed = code.startsWith(city);
    if (!prefixed && row['source_region_code'] != city) return null;
    final key = prefixed ? code : '$city$code';
    final (line, _) = tuSourceKeySegments(key);
    // 取原文片段，保留前导零和字母大小写。
    return line == null
        ? null
        : key.substring(city.length, city.length + line.length);
  }

  static String _tuCityName(Database db, String code) {
    final rows = db.select(
      r'''
      SELECT city.value ->> '$.name' AS name
      FROM reference_documents, json_each(reference_documents.json, '$.entries') AS city
      WHERE reference_documents.name = 'cities' AND city.value ->> '$.code' = ?
    ''',
      [code],
    );
    return rows.isEmpty ? '' : _field(rows.first, 'name');
  }

  void _add(GalleryKnowledgeResult result, Iterable<String> aliases) {
    final term = _SearchTerm(result, aliases);
    for (final character in {
      ...term.title.runes,
      for (final alias in term.aliases) ...alias.runes,
    }) {
      (_postings[character] ??= []).add(term);
    }
  }

  Map<GalleryKnowledgeKind, List<GalleryKnowledgeResult>> search(String input) {
    final query = _normalize(input);
    if (query.isEmpty) return const {};
    final matches =
        <GalleryKnowledgeKind, Map<int, List<GalleryKnowledgeResult>>>{};
    final candidates = query.runes
        .map((character) => _postings[character] ?? const <_SearchTerm>[])
        .reduce(
          (first, second) => first.length <= second.length ? first : second,
        );
    for (final term in candidates) {
      final rank = term.rank(query);
      if (rank == null) continue;
      ((matches[term.result.kind] ??= {})[rank] ??= []).add(term.result);
    }
    return {
      for (final kind in GalleryKnowledgeKind.values)
        if (matches[kind] case final ranks?)
          kind: [for (var rank = 0; rank <= 3; rank++) ...?ranks[rank]],
    };
  }
}

String _normalize(String value) => String.fromCharCodes(
  value.trim().runes.map(
    (character) => character >= 0xff01 && character <= 0xff5e
        ? character - 0xfee0
        : character,
  ),
).toLowerCase();

class _SearchTerm {
  _SearchTerm(this.result, Iterable<String> aliases)
    : title = _normalize(result.title),
      aliases = aliases
          .map(_normalize)
          .where((alias) => alias.isNotEmpty)
          .toList();

  final GalleryKnowledgeResult result;
  final String title;
  final List<String> aliases;

  int? rank(String query) {
    if (title == query) return 0;
    if (title.startsWith(query)) return 1;
    if (result.kind == GalleryKnowledgeKind.code) return null;
    if (title.contains(query)) return 2;
    if (aliases.any((alias) => alias.startsWith(query))) return 3;
    return null;
  }
}
