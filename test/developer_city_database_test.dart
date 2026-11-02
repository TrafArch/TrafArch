import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tu_station_repository.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/station_codes.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/tu_lookup_service.dart';

// Expectations are frozen from the supplied developer database, independently
// of the published assets. This verifies data retention and query reachability;
// it does not claim that every key has a verified physical-card field layout.
void main() {
  late Database tu;
  late TuStationRepository repository;
  late List<Map<String, dynamic>> rows;

  setUpAll(() {
    tu = sqlite3.open(
      'assets/data/TrafArch_Database_TU.sqlite',
      mode: OpenMode.readOnly,
    );
    repository = TuStationRepository(tu);
    final fixture = jsonDecode(
      File('test/fixtures/developer_tu_city_rows.json').readAsStringSync(),
    );
    rows = ((fixture is Map ? fixture['rows'] : fixture) as List)
        .cast<Map<String, dynamic>>();
  });
  tearDownAll(() => tu.close());

  test(
    'conflicting developer keys do not silently replace complete locations',
    () {
      final lookup = TuLookupService(repository);
      final tianjin = lookup.resolveCycle(
        city: '1121',
        field: '00060032000000',
        appType: 1,
      );
      expect(tianjin.stationName, '黑牛城道');
      expect(tianjin.entry?.sourceKey, '112100060032');
      expect(
        repository
            .findStations(regionCode: '1121', sourceKey: '00060032')
            .map((r) => r.stationName),
        contains('医大二院'),
      );
      final dongguan = lookup.resolveCycle(
        city: '6020',
        field: '00020208000000',
        appType: 1,
      );
      expect(dongguan.confidence, StationMatchConfidence.ambiguous);
      expect(
        dongguan.candidates.map((r) => r.station).toSet(),
        containsAll(['鸿福路', '市民中心']),
      );
    },
  );

  test('both published protocols contain no shared community table', () {
    for (final protocol in ['TU', 'CU']) {
      final db = sqlite3.open(
        'assets/data/TrafArch_Database_$protocol.sqlite',
        mode: OpenMode.readOnly,
      );
      try {
        expect(
          db.select(
            "SELECT name FROM sqlite_master WHERE name LIKE 'community_%'",
          ),
          isEmpty,
        );
        expect(db.select('PRAGMA integrity_check').single.values, ['ok']);
        expect(db.select('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        db.close();
      }
    }
  });

  test('all 427 developer additions remain in their owning city tables', () {
    expect(rows, hasLength(427));
    for (final expected in rows) {
      final city = expected['city'] as String;
      final table = expected['table'] as String;
      final key = expected['source_key'] as String;
      final source = expected['source_field'] as String;
      final reason = '$city/$source/$key';
      expect(repository.findRegion(regionCode: city)?.tableName, table);
      final found = repository
          .findStations(regionCode: city, sourceKey: key, sourceField: source)
          .where((r) => r.stationId == expected['station_id'])
          .toList();
      expect(found, hasLength(1), reason: reason);
      final actual = found.single;
      expect(actual.lineName, expected['line_name'], reason: reason);
      expect(actual.stationName, expected['station_name'], reason: reason);
      expect(actual.rawValueJson, expected['raw_value_json'], reason: reason);
      expect(
        tu.select(
          'SELECT station_id FROM all_records '
          'WHERE region_code=? AND station_id=? AND source_field=? AND source_key=?',
          [city, expected['station_id'], source, key],
        ),
        hasLength(1),
        reason: '$reason is visible in the original view',
      );
    }
    expect(repository.queryIssue, isNull);
  });

  test(
    'developer city counts and deliberate Nanjing removals are retained',
    () {
      expect(
        tu.select('SELECT COUNT(*) AS c FROM all_records').single['c'],
        8004,
      );
      expect(
        tu.select('SELECT COUNT(*) AS c FROM "region_南京_3010"').single['c'],
        273,
      );
      expect(
        tu.select(
          'SELECT station_id FROM "region_南京_3010" WHERE source_field=?',
          ['M0.E.a'],
        ),
        isEmpty,
      );
    },
  );

  test('TU synchronization preserves the approved CU Jinan package', () {
    expect(
      sha256
          .convert(
            File('assets/data/TrafArch_Database_CU.sqlite').readAsBytesSync(),
          )
          .toString(),
      '77ba3ad4310782f7625f7b1b1f87a7bc99fee2420cf9060477b614f1580c6ed3',
    );
    final manifest = jsonDecode(
      File('assets/data/reference_manifest.json').readAsStringSync(),
    ) as Map;
    expect(manifest.keys.where((k) => '$k'.startsWith('community_')), isEmpty);
    expect(
      (manifest['sources'] as List).where(
        (s) => '${s['id']}'.startsWith('tripreader_community_'),
      ),
      isEmpty,
    );
  });
}
