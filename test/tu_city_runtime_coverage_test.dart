import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tu_region_live_source.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tu_station_repository.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/station_codes.dart';

// Exhaustive package-to-live-query checks. SQL supplies the independent raw
// row oracle; all lookups below invoke production Dart APIs. Package validation
// separately owns all_records/original-table consistency. No database writes.
// Optional evidence: TRAFARCH_TU_AUDIT_REPORT=/absolute/path/report.json.
void main() {
  final asset = File('assets/data/TrafArch_Database_TU.sqlite');
  final assetHash = sha256.convert(asset.readAsBytesSync()).toString();
  final db = sqlite3.open(asset.path, mode: OpenMode.readOnly);
  final repository = TuStationRepository(db);
  final live = TuRegionLiveSource(repository);
  final table = StationCodeTable.empty.withLiveSources([live]);
  final regions = db.select('SELECT * FROM regions ORDER BY region_code');
  final reports = <Map<String, Object?>>[];
  var allAssertionsCompleted = false;

  tearDownAll(() {
    expect(sha256.convert(asset.readAsBytesSync()).toString(), assetHash);
    db.close();
    final output = Platform.environment['TRAFARCH_TU_AUDIT_REPORT'];
    if (output != null) {
      File(output).writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert({'asset_sha256': assetHash, 'all_city_assertions_completed': allAssertionsCompleted, 'scope': 'All raw package rows through actual Repository + LiveSource + StationCodeTable; synthetic field probes are observations, not device evidence.', 'cities': reports})}\n',
      );
    }
  });

  for (final region in regions) {
    final city = region['region_code'] as String;
    final cityName = region['region_name'] as String;
    final tableName = region['table_name'] as String;
    test('TU packaged city $city $cityName: every field, row and full key', () {
      final quoted = '"${tableName.replaceAll('"', '""')}"';
      final raw = db.select('SELECT * FROM $quoted ORDER BY station_id');
      expect(raw, isNotEmpty, reason: tableName);
      final byKey = <String, List<Row>>{};
      final fields = <String, Map<String, Object?>>{};
      final probes = <Map<String, Object?>>[];
      for (final row in raw) {
        final key = row['source_key'] as String;
        final field = row['source_field'] as String;
        final reason = '$city $field $key station_id=${row['station_id']}';
        (byKey[key] ??= []).add(row);
        final stats = fields.putIfAbsent(
          field,
          () => {
            'rows': 0,
            'repository_rows_reached': 0,
            'live_unique_key_groups': 0,
            'live_ambiguous_key_groups': 0,
          },
        );
        stats['rows'] = (stats['rows'] as int) + 1;
        final hits = repository.findStations(
          regionCode: city,
          sourceField: field,
          sourceKey: key,
        );
        final same = hits.where((r) => r.stationId == row['station_id']);
        expect(same, hasLength(1), reason: reason);
        final hit = same.single;
        expect(hit.sourceKey, key, reason: reason);
        expect(hit.sourceField, field, reason: reason);
        expect(hit.regionCode, city, reason: reason);
        expect(hit.rawTransportType, row['transport_type'], reason: reason);
        expect(hit.lineName, _nullable(row['line_name']), reason: reason);
        expect(hit.stationName, _nullable(row['station_name']), reason: reason);
        expect(
          hit.rawValueJson,
          _nullable(row['raw_value_json']),
          reason: reason,
        );
        stats['repository_rows_reached'] =
            (stats['repository_rows_reached'] as int) + 1;
        // A source field is an actual constraint, never a broad-match hint.
        expect(
          repository.findStations(
            regionCode: city,
            sourceField: '__tu_audit_absent_field__',
            sourceKey: key,
          ),
          isEmpty,
          reason: reason,
        );
      }
      final ambiguities = <Map<String, Object?>>[];
      for (final item in byKey.entries) {
        final key = item.key;
        final sourceRows = item.value;
        final identities = sourceRows.map(_identity).toSet();
        final actual = live.lookupEntry(city, key);
        final publicActual = table.lookup(code: key, cityCode: city);
        final reason = '$city full source key $key';
        if (identities.length == 1) {
          expect(actual, isNotNull, reason: reason);
          expect(publicActual, isNotNull, reason: reason);
          final identity = identities.single;
          expect(
            (actual!.line, actual.station, actual.kind),
            identity,
            reason: reason,
          );
          expect(actual.system, 'tu', reason: reason);
          expect(actual.sourceKey, key, reason: reason);
          expect(
            (publicActual!.line, publicActual.station, publicActual.kind),
            identity,
            reason: reason,
          );
        } else {
          expect(actual, isNull, reason: '$reason must preserve ambiguity');
          expect(
            publicActual,
            isNull,
            reason: '$reason must preserve ambiguity',
          );
          ambiguities.add({
            'source_key': key,
            'candidates': [
              for (final row in sourceRows)
                {
                  'source_field': row['source_field'],
                  'line': row['line_name'],
                  'station': row['station_name'],
                  'transport': row['transport_type'],
                },
            ],
          });
        }
        for (final field in sourceRows.map((r) => r['source_field']).toSet()) {
          final metric = identities.length == 1
              ? 'live_unique_key_groups'
              : 'live_ambiguous_key_groups';
          final stats = fields[field]!;
          stats[metric] = (stats[metric] as int) + 1;
        }
      }
      // Original m756j(type=3) accepts city+field and longest prefixes. These
      // reproducible vectors derive from every packaged native rail source
      // key. Observe the current 1E and lineValue entry points without turning
      // known application integration gaps into false passing assertions.
      const nativeRailFields = {'M0.i0.a', 'M0.W.a', 'M0.a0.a', 'M0.e0.a'};
      for (final row in raw) {
        final key = row['source_key'] as String;
        if (!nativeRailFields.contains(row['source_field']) ||
            !key.startsWith(city) ||
            key.length < 6 ||
            key.length > 18) {
          continue;
        }
        final field = key.substring(4).padRight(14, '0');
        final match = table.matchLineStationField(field: field, cityCode: city);
        final record = repository
            .findStations(
              regionCode: city,
              sourceKey: key,
              sourceField: row['source_field'] as String,
            )
            .first;
        final segments = record.segments;
        final lineValue = int.tryParse(segments.$1 ?? '', radix: 16);
        final station = segments.$2;
        final withLine = station == null
            ? null
            : table.matchTuStationByCardId(
                cityCode: city,
                rawStationId: station.padLeft(16, '0'),
                lineValue: lineValue,
              );
        probes.add({
          'source_key': key,
          'source_field': row['source_field'],
          'expected_line': row['line_name'],
          'expected_station': row['station_name'],
          'synthetic_original_prefix_field': field,
          'field_result': _result(match, row),
          if (withLine != null) 'line_value_result': _result(withLine, row),
          if (withLine != null) 'line_value': lineValue,
          if (withLine != null) 'station_segment': station,
        });
      }
      expect(live.lookupEntry(city, '__tu_audit_absent_key__'), isNull);
      expect(
        live.lookupEntry('__tu_audit_absent_city__', byKey.keys.first),
        isNull,
      );
      expect(repository.queryIssue, isNull);
      reports.add({
        'city_code': city,
        'city_name': cityName,
        'rows': raw.length,
        'key_groups': byKey.length,
        'fields': fields,
        'ambiguities': ambiguities,
        'native_rail_probes': probes,
      });
    });
  }
  test('TU coverage completed every packaged city', () {
    expect(reports, hasLength(regions.length));
    expect(reports, isNotEmpty);
    allAssertionsCompleted = true;
  });
}

String? _nullable(Object? value) {
  final text = '${value ?? ''}'.trim();
  return text.isEmpty ? null : text;
}

(String?, String?, String) _identity(Row row) => (
  _nullable(row['line_name']),
  _nullable(row['station_name']),
  switch (row['transport_type']) {
    'metro' || 'subway' || 'rail' => 'metro',
    'bus' || 'coach' => 'bus',
    'brt' => 'brt',
    'bike' || 'bicycle' => 'bike',
    'intercity_rail' || 'railway' => 'intercity_rail',
    _ => 'other',
  },
);

Map<String, Object?> _result(StationMatch match, Row expected) => {
  'confidence': match.confidence.name,
  'source_key': match.entry?.sourceKey,
  'source_field': match.entry?.sourceField,
  'line': match.lineName,
  'station': match.stationName,
  'correct_identity':
      match.confidence == StationMatchConfidence.exact &&
      match.lineName == _nullable(expected['line_name']) &&
      match.stationName == _nullable(expected['station_name']),
};
