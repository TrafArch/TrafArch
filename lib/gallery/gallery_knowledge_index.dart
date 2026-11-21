import 'dart:collection';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';

import '../features/reference_data/data/reference_package.dart';

enum GalleryKnowledgeKind { city, line, station, code }

class GalleryKnowledgeCity {
  GalleryKnowledgeCity(this.system, this.name, this.code, this.province);

  final String system, name, code, province;
  final _lines = <String, GalleryKnowledgeLine>{};
  final _aliases = <String>{};
  int _codeCount = 0;

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
    final codes = <GalleryKnowledgeResult>{};
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
        cities.addAll(regions.values);
        final byCode = {for (final city in regions.values) city.code: city};
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
        void addRecord(GalleryKnowledgeCity? city, Row row) {
          if (city == null) return;
          final lineName = _field(row, 'line_name');
          final stationName = _field(row, 'station_name');
          final code = _field(row, 'source_key');
          final source = _field(row, 'source_field');
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

        for (final row in db.select(
          tu
              ? 'SELECT region_id, line_name, station_name, source_key, '
                    'source_field FROM all_records ORDER BY station_id'
              : 'SELECT region_code, line_name, station_name, source_key, '
                    'source_field FROM stations ORDER BY station_id',
        )) {
          addRecord(
            tu ? regions[row['region_id']] : byCode[row['region_code']],
            row,
          );
        }
        if (!tu) {
          for (final row in db.select(
            'SELECT region_code, line_name, NULL AS station_name, '
            'line_key AS source_key, source_field, line_code FROM routes '
            'ORDER BY region_code, source_entry_index',
          )) {
            final city = byCode[row['region_code']];
            addRecord(city, row);
            final code = _field(row, 'line_code');
            if (code.isNotEmpty) {
              city?._lines[_field(row, 'line_name')]?._codes.add(code);
            }
          }
          for (final row in db.select(
            'SELECT station.region_code, station.line_name, station.station_name, '
            'terminal.match_key AS source_key, station.source_field '
            'FROM terminal_index AS terminal JOIN stations AS station '
            'ON station.station_id = terminal.station_id '
            'ORDER BY terminal.region_code, terminal.match_key',
          )) {
            addRecord(byCode[row['region_code']], row);
          }
        }
      } finally {
        db.close();
      }
    }
    return GalleryKnowledgeIndex._(cities, codes);
  }

  static String _field(Row row, String key) => row[key]?.toString() ?? '';

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
