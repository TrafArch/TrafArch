import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tu_lookup_live_source.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tu_region_live_source.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tu_station_repository.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/station_codes.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/tu_lookup_service.dart';

void main() {
  late Database db;
  late TuStationRepository repository;
  late TuLookupService lookup;
  late Map<String, dynamic> supplement;

  setUpAll(() {
    db = sqlite3.open(
      'assets/data/TrafArch_Database_TU.sqlite',
      mode: OpenMode.readOnly,
    );
    repository = TuStationRepository(db);
    lookup = TuLookupService(repository);
    // Independent frozen source oracle, not a query over the published document.
    final sourceBytes = File('test/fixtures/reference/tu-lookup-20261021.json')
        .readAsBytesSync();
    final manifest = jsonDecode(
      File('assets/data/reference_manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final source = (manifest['sources'] as List).singleWhere(
      (entry) => entry['id'] == 'tu_lookup',
    ) as Map<String, dynamic>;
    expect(sha256.convert(sourceBytes).toString(), source['sha256']);
    supplement = jsonDecode(utf8.decode(sourceBytes)) as Map<String, dynamic>;
  });
  tearDownAll(() => db.close());

  test('original complete keys win over colliding byte fragments', () {
    const vectors = [
      ('2220', '08010000000000', '22200801', '河口'),
      ('3040', '01030000000000', '30400103', '南夏墅'),
      ('5510', '01000100000000', '5510010001', '尚双塘'),
      ('3610', '00010101000000', '361000010101', '合肥火车站'),
      ('6020', '00020202000000', '602000020202', '茶山'),
      ('2210', '000A0403000000', '2210000A0403', '塔湾街'),
    ];
    for (final (city, field, key, name) in vectors) {
      final result = lookup.resolveCycle(city: city, field: field, appType: 1);
      expect(result.confidence, StationMatchConfidence.exact, reason: key);
      expect(result.stationName, name, reason: key);
      expect(result.entry?.sourceKey, key);
      // The existing LiveSource path must also stop using byte fragments first.
      final table = StationCodeTable.empty.withLive(
        TuRegionLiveSource(repository),
      );
      expect(
        table.matchLineStationField(cityCode: city, field: field).stationName,
        name,
      );
    }
  });

  test('packaged city layouts and M0.S.a process terminals stay reachable', () {
    for (final (city, field, terminal, key, station) in [
      ('6510', '00001021000000', null, '65101021', '太平园'),
      ('3320', '01200000000000', null, '332000010020', '东环南路'),
      ('4520', '00000000000000', '4520000011210000', '45201121', '苗岭路'),
      ('7910', '00000000000000', '7910000001100000', '79100001000A', '陈杨寨'),
      ('3910', '00010011000000', null, '39100111', '象峰'),
      ('7010', '00010101000000', null, '70100101', '窦官'),
      (
        '3610',
        '00000101000000',
        '0000413106085352',
        '36100000413106085352',
        '铜陵新村',
      ),
    ]) {
      final match = lookup.resolveCycle(
        city: city,
        field: field,
        terminalId: terminal,
        appType: 1,
      );
      expect(match.stationName, station, reason: '$city/$key');
      expect(
        match.candidates.any((e) => (e.sourceKey ?? e.code) == key),
        isTrue,
        reason: '$city/$key',
      );
    }
  });

  test(
    'every native rail source key remains reachable at its longest prefix',
    () {
      final groups = <String, List<Row>>{};
      for (final row in db.select(
        "SELECT * FROM all_records WHERE source_field IN ('M0.i0.a','M0.W.a','M0.a0.a','M0.e0.a')",
      )) {
        (groups['${row['region_code']}|${row['source_key']}'] ??= []).add(row);
      }
      final cities = <String>{};
      final fields = <String>{};
      final table = StationCodeTable.empty.withLive(
        TuLookupLiveSource(repository),
      );
      for (final rows in groups.values) {
        final first = rows.first;
        final city = first['region_code'] as String;
        final key = first['source_key'] as String;
        cities.add(city);
        fields.add(first['source_field'] as String);
        // Filler cannot accidentally form another hexadecimal source key.
        final match = table.matchTuRailKey(
          cityCode: city,
          key: '${key}FFFFFFFF',
        );
        final identities = rows
            .map((r) => (r['line_name'], r['station_name']))
            .toSet();
        expect(
          match.confidence,
          identities.length == 1
              ? StationMatchConfidence.exact
              : StationMatchConfidence.ambiguous,
          reason: '$city/$key',
        );
        expect(match.candidates.map((e) => e.sourceKey).toSet(), {key});
        expect(
          match.candidates.map((e) => e.rawValueJson).toSet(),
          rows.map((r) => r['raw_value_json']).toSet(),
        );
      }
      expect(cities.length, greaterThan(30));
      expect(fields, {'M0.i0.a', 'M0.W.a', 'M0.a0.a', 'M0.e0.a'});
    },
  );

  test('all 270 verified line-only prefixes, including Nanning without a region table', () {
    final rows = supplement['rail_prefixes'] as List;
    expect(rows, hasLength(270));
    for (final row in rows) {
      final key = row['source_key'] as String;
      final raw = row['raw_value'] as List;
      final match = lookup.resolveRailKey(
        city: key.substring(0, 4),
        key: '${key}FFFFFFFF',
      );
      expect(match.confidence, StationMatchConfidence.exact, reason: key);
      expect(match.lineName, raw[1], reason: key);
      expect(match.stationName ?? '', raw[2], reason: key);
      expect(match.entry?.sourceField, row['source_field']);
      expect(jsonDecode(match.entry!.rawValueJson!), raw);
    }
    expect(
      lookup.resolveRailKey(city: '6110', key: '611000000001').lineName,
      isNotEmpty,
    );
  });

  test(
    'all local aliases route via the accepted city with source priority',
    () {
      final aliases = supplement['terminal_aliases'] as List;
      expect(aliases, hasLength(4014));
      final effective = <String, dynamic>{};
      for (final row in aliases) {
        effective.putIfAbsent(row['source_key'] as String, () => row);
      }
      for (final city in ['3310', '3350', '3370']) {
        for (final terminal in effective.keys) {
          final row = effective[terminal];
          final expected = lookup.resolveRailKey(
            city: city,
            key: '$city${row['raw_value']}',
          );
          final actual = lookup.resolveBasic(city: city, terminal: terminal);
          expect(
            actual.confidence,
            expected.confidence,
            reason: '$city/$terminal',
          );
          expect(actual.entry?.sourceKey, expected.entry?.sourceKey);
          expect(
            actual.evidence.any(
              (e) =>
                  e.sourceField == row['source_field'] &&
                  e.sourceKey == terminal,
            ),
            isTrue,
          );
        }
      }
      expect(
        lookup
            .resolveBasic(city: '3310', terminal: '413101784816')
            .entry
            ?.sourceKey,
        '331000040011',
      );
      expect(
        lookup.resolveBasic(city: '1000', terminal: '413101784816').isUnmatched,
        isTrue,
      );
    },
  );

  test('all exact native terminal rows use their original value shape', () {
    for (final (field, owner, cities) in [
      ('M0.n0.a', '1610', ['1610']),
      ('M0.E.a', '3010', ['3010']),
      ('M0.b.a', '6510', ['6510']),
      ('M0.C.b', '3370', ['3310', '3350', '3370']),
    ]) {
      for (final row in db.select(
        'SELECT * FROM all_records WHERE source_field=? AND region_code=?',
        [field, owner],
      )) {
        final raw = jsonDecode(row['raw_value_json'] as String) as List;
        final key = row['source_key'] as String;
        for (final city in cities) {
          final match = lookup.resolveBasic(city: city, terminal: key);
          expect(
            match.confidence,
            StationMatchConfidence.exact,
            reason: '$city/$field/$key',
          );
          final line = raw[raw.length == 2 ? 0 : 1] as String;
          expect(
            match.lineName,
            raw.length == 2 && RegExp(r'^\d+$').hasMatch(line)
                ? '$line号线'
                : line,
          );
          expect(match.stationName, raw.last);
          expect(match.entry?.sourceField, field);
          expect(match.entry?.rawValueJson, row['raw_value_json']);
          if (field == 'M0.n0.a') expect(match.entry?.kind, 'metro');
        }
      }
    }
  });

  test('all dated names apply before, but not at, the original cutoff', () {
    final histories = supplement['rail_history'] as List;
    expect(histories, hasLength(30));
    for (final history in histories) {
      final key = history['source_key'] as String;
      final rules = history['raw_value'] as List;
      final rule = rules.first as List;
      final cutoff = DateTime.parse(rule[0][r'$date_literal'] as String);
      final base = lookup.resolveRailKey(city: key.substring(0, 4), key: key);
      final old = lookup.resolveRailKey(
        city: key.substring(0, 4),
        key: key,
        time: cutoff.subtract(const Duration(microseconds: 1)),
      );
      final now = lookup.resolveRailKey(
        city: key.substring(0, 4),
        key: key,
        time: cutoff,
      );
      expect(base.confidence, StationMatchConfidence.exact, reason: key);
      expect(
        old.lineName,
        rule[2] == '*' ? base.lineName : rule[2],
        reason: key,
      );
      expect(
        old.stationName ?? '',
        rule[3] == '*' ? base.stationName ?? '' : rule[3],
        reason: key,
      );
      expect(now.lineName, base.lineName);
      expect(now.stationName, base.stationName);
      expect(old.entry?.rawValueJson, base.entry?.rawValueJson);
      expect(old.evidence.any((e) => e.sourceField == 'N0.e.a'), isTrue);
    }
  });

  test(
    'unknown app types and different namespaces never enter rail lookup',
    () {
      for (final type in [null, 0, 2, 0x39, 0xFF]) {
        expect(
          lookup
              .resolveCycle(
                city: '2220',
                field: '08010000000000',
                appType: type,
              )
              .isUnmatched,
          isTrue,
        );
      }
      expect(
        lookup
            .resolveCycle(city: null, field: '08010000000000', appType: 1)
            .isUnmatched,
        isTrue,
      );
      expect(
        lookup.resolveRailKey(city: '3040', key: '22200801').isUnmatched,
        isTrue,
      );
      expect(
        lookup
            .resolveBasic(city: '3310', terminal: '0000413101784816')
            .isUnmatched,
        isTrue,
      );
      expect(
        lookup
            .resolveCycle(
              city: '3310',
              field: '00000000000000',
              terminalId: '413101784816',
              appType: 1,
            )
            .isUnmatched,
        isTrue,
      );
    },
  );
}
