import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

/// Adapts existing fixture inputs to the published package contract. This is
/// test-only construction; production has no legacy JSON/CSV merge path.
Map<String, Uint8List> publishTuFixture(
  Uint8List? original,
  Map<String, String> texts,
) {
  final directory = Directory.systemTemp.createTempSync(
    'trafarch-reference-fixture-',
  );
  final file = File('${directory.path}/TU.sqlite');
  if (original != null) file.writeAsBytesSync(original);
  final db = sqlite3.open(file.path);
  late Map<String, int> counts;
  try {
    db.execute(
      'CREATE TABLE IF NOT EXISTS reference_package(key TEXT PRIMARY KEY,value TEXT NOT NULL)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS reference_documents(name TEXT PRIMARY KEY,json TEXT NOT NULL)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS regions(region_id INTEGER PRIMARY KEY,region_code TEXT,region_name TEXT,province TEXT,table_name TEXT,code_source TEXT)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS card_prefixes(prefix TEXT,issuer TEXT,region_code TEXT,card_name TEXT,city_name TEXT,province TEXT,currency TEXT)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS issuer_city_codes(region_code TEXT,city_name TEXT,issuer TEXT,card_name TEXT,prefix TEXT)',
    );
    // Minimal old fixtures are expanded only in test support. The runtime
    // requires the same column contract as the actual published package.
    final selects = <String>[];
    for (final region in db.select('SELECT * FROM regions')) {
      final table = (region['table_name'] as String).replaceAll('"', '""');
      final columns = db
          .select('PRAGMA table_info("$table")')
          .map((r) => r['name'])
          .toSet();
      for (final column in [
        'native_namespace',
        'copy_role',
        'record_kind',
        'lookup_key_namespace',
      ]) {
        if (!columns.contains(column)) {
          db.execute('ALTER TABLE "$table" ADD COLUMN $column TEXT');
        }
      }
      final id = (region['region_id'] as num).toInt();
      selects.add(
        'SELECT $id AS region_id,r.region_code,s.* FROM "$table" s JOIN regions r ON r.region_id=$id',
      );
    }
    final emptyColumns = [
      'region_id',
      'region_code',
      'station_id',
      'transport_type',
      'line_name',
      'station_name',
      'system_name',
      'source_field',
      'source_key',
      'source_region_code',
      'source_region_name',
      'raw_value_json',
      'confidence',
      'native_namespace',
      'copy_role',
      'record_kind',
      'lookup_key_namespace',
    ];
    final view = selects.isEmpty
        ? 'SELECT ${emptyColumns.map((c) => 'NULL AS $c').join(',')} WHERE 0'
        : selects.join(' UNION ALL ');
    db.execute('CREATE VIEW IF NOT EXISTS all_records AS $view');
    for (final item in {
      'format_version': '1',
      'protocol': 'TU',
      'content_version': 'fixture-v1',
      'tool_version': 'fixture-v1',
    }.entries) {
      db.execute('INSERT OR REPLACE INTO reference_package VALUES(?,?)', [
        item.key,
        item.value,
      ]);
    }
    Object? source(String name) =>
        jsonDecode(texts['assets/data/$name.json'] ?? '{}');
    final prefixes = source('tunion_card_prefixes');
    final meta = source('tunion_card_meta');
    // The production builder folds reviewed metadata into the published
    // prefix document. Reproduce that contract in these old JSON fixtures.
    if (prefixes is Map && prefixes['entries'] is List && meta is Map) {
      final currencies = meta['currencyByPrefix'];
      for (final row in prefixes['entries'] as List) {
        if (row is Map && currencies is Map) {
          final currency = currencies[row['prefix']];
          if (currency != null) row['currency'] = currency;
        }
      }
      if (meta['cardKinds'] is Map) prefixes['cardKinds'] = meta['cardKinds'];
    }
    final cities = <String, Map<String, Object?>>{};
    for (final r in db.select(
      'SELECT region_code,region_name,province FROM regions',
    )) {
      cities[r['region_code'] as String] = {
        'code': r['region_code'],
        'name': r['region_name'],
        'province': r['province'],
      };
    }
    if (prefixes is Map && prefixes['entries'] is List) {
      for (final row in prefixes['entries'] as List) {
        final issuer = row['issuer'] as String?;
        final city = row['city'] as String?;
        if (issuer != null && issuer.length >= 4 && city != null) {
          final code = issuer.substring(issuer.length - 4);
          cities.putIfAbsent(code, () => {'code': code, 'name': city});
        }
      }
    }
    final documents = {
      'cities': {'entries': cities.values.toList()},
      'card_prefixes': prefixes,
      'issuers': source('tunion_issuer_fingerprints'),
      'terminal_rules': source('tunion_terminal_rules'),
      'card_meta': meta,
    };
    for (final entry in documents.entries) {
      db.execute('INSERT OR REPLACE INTO reference_documents VALUES(?,?)', [
        entry.key,
        jsonEncode(entry.value),
      ]);
    }
    counts = {
      for (final table in [
        'regions',
        'all_records',
        'card_prefixes',
        'issuer_city_codes',
      ])
        table:
            (db.select('SELECT COUNT(*) AS n FROM $table').single['n'] as num)
                .toInt(),
    };
  } finally {
    db.close();
  }
  final bytes = file.readAsBytesSync();
  directory.deleteSync(recursive: true);
  final manifest = jsonEncode({
    'format_version': 1,
    'tool_version': 'fixture-v1',
    'sources': [],
    'packages': {
      'TU': {
        'file': 'TrafArch_Database_TU.sqlite',
        'sha256': sha256.convert(bytes).toString(),
        'bytes': bytes.length,
        'content_version': 'fixture-v1',
        'tables': counts,
      },
    },
  });
  return {
    'assets/data/TrafArch_Database_TU.sqlite': bytes,
    'assets/data/reference_manifest.json': Uint8List.fromList(
      utf8.encode(manifest),
    ),
  };
}
