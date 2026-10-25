import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// A published, validated package. The owning controller closes this handle.
class ReferencePackage {
  ReferencePackage._(
    this.db,
    this.protocol,
    this.version,
    this.hash,
    this.counts,
  );

  final Database db;
  final String protocol;
  final String version;
  final String hash;
  final Map<String, int> counts;
  bool _closed = false;

  Object? document(String name) {
    final rows = db.select(
      'SELECT json FROM reference_documents WHERE name = ?',
      [name],
    );
    if (rows.isEmpty) {
      throw FormatException('Missing $protocol document: $name');
    }
    return jsonDecode(rows.single['json'] as String);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    db.close();
  }

  static Future<ReferencePackage> open(
    String protocol, {
    AssetBundle? bundle,
  }) async {
    final assets = bundle ?? rootBundle;
    final manifest = jsonDecode(
      await assets.loadString('assets/data/reference_manifest.json'),
    ) as Map<String, dynamic>;
    if (manifest['format_version'] != 1) {
      throw const FormatException('Unsupported reference manifest');
    }
    final spec = (manifest['packages'] as Map)[protocol] as Map;
    final name = spec['file'] as String;
    final hash = spec['sha256'] as String;
    if (!RegExp(r'^[A-Za-z0-9_.-]+\.sqlite$').hasMatch(name) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      throw const FormatException('Invalid reference package path or digest');
    }
    final data = await assets.load('assets/data/$name');
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (bytes.length != spec['bytes'] ||
        sha256.convert(bytes).toString() != hash) {
      throw FormatException('$protocol asset digest mismatch');
    }
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/trafarch_reference');
    await directory.create(recursive: true);
    final installed = File(
      '${directory.path}/${protocol.toLowerCase()}-$hash.sqlite',
    );
    if (!await installed.exists() ||
        sha256.convert(await installed.readAsBytes()).toString() != hash) {
      // Never replace the old mutable legacy database. A unique staging file
      // also keeps overlapping initializers from writing each other's bytes.
      final staging = await directory.createTemp('install-');
      final temporary = File('${staging.path}/package.sqlite');
      try {
        await temporary.writeAsBytes(bytes, flush: true);
        if (await installed.exists() &&
            sha256.convert(await installed.readAsBytes()).toString() != hash) {
          await installed.delete();
        }
        try {
          if (!await installed.exists()) await temporary.rename(installed.path);
        } on FileSystemException {
          if (!await installed.exists() ||
              sha256.convert(await installed.readAsBytes()).toString() !=
                  hash) {
            rethrow;
          }
        }
      } finally {
        if (await temporary.exists()) await temporary.delete();
        await staging.delete();
      }
    }
    final db = sqlite3.open(installed.path, mode: OpenMode.readOnly);
    try {
      final metadata = {
        for (final row in db.select('SELECT key, value FROM reference_package'))
          row['key'] as String: row['value'] as String,
      };
      if (metadata['protocol'] != protocol ||
          metadata['format_version'] != '1' ||
          metadata['content_version'] != spec['content_version']) {
        throw FormatException('$protocol package metadata mismatch');
      }
      final required = protocol == 'TU'
          ? <String, List<String>>{
              "regions": [
                "region_id",
                "region_code",
                "region_name",
                "province",
                "table_name",
                "code_source",
              ],
              "all_records": [
                "region_id",
                "region_code",
                "station_id",
                "transport_type",
                "line_name",
                "station_name",
                "system_name",
                "source_field",
                "source_key",
                "source_region_code",
                "source_region_name",
                "raw_value_json",
                "confidence",
                "native_namespace",
                "copy_role",
                "record_kind",
                "lookup_key_namespace",
              ],
              "card_prefixes": [
                "prefix",
                "issuer",
                "region_code",
                "card_name",
                "city_name",
                "province",
                "currency",
              ],
              "issuer_city_codes": [
                "region_code",
                "city_name",
                "issuer",
                "card_name",
                "prefix",
              ],
              "reference_package": ["key", "value"],
              "reference_documents": ["name", "json"],
            }
          : <String, List<String>>{
              "regions": [
                "region_id",
                "region_code",
                "postal_code",
                "region_name",
                "table_name",
                "record_count",
              ],
              "region_codes": ["region_code", "region_name"],
              "station_lookup": [
                "region_code",
                "match_key",
                "match_mode",
                "required_transaction_type",
                "priority",
                "station_id",
                "transport_type",
                "line_name",
                "station_name",
                "system_name",
                "source_field",
                "source_key",
                "source_region_code",
                "source_region_name",
                "raw_value_json",
                "line_key",
                "line_code",
                "line_number",
                "station_code",
                "line_prefix_name",
                "line_code_basis",
                "line_name_matches_prefix",
              ],
              "terminal_index": [
                "region_code",
                "match_key",
                "match_mode",
                "required_transaction_type",
                "station_id",
                "priority",
              ],
              "routes": [
                "region_code",
                "source_field",
                "source_entry_index",
                "line_key",
                "line_code",
                "line_number",
                "line_name",
                "lookup_namespace",
                "value_json",
              ],
              "bus_routes": [
                "region_code",
                "terminal_suffix",
                "route_number",
                "source_field",
                "source_entry_index",
                "required_transaction_type",
                "valid_before_unix_ms",
                "requires_station_missing",
                "requires_bus_lookup_enabled",
                "value_json",
              ],
              "cu_prefix_dictionary": [
                "region_code",
                "match_key",
                "record_kind",
                "system_name",
                "line_name",
                "station_name",
                "source_field",
                "source_entry_index",
                "value_json",
              ],
              "station_registry": ["region_code", "station_id"],
              "reference_package": ["key", "value"],
              "reference_documents": ["name", "json"],
            };
      for (final table in required.entries) {
        final columns = db
            .select('PRAGMA table_info("${table.key}")')
            .map((row) => row['name'] as String)
            .toSet();
        final missing = table.value
            .where((name) => !columns.contains(name))
            .toList();
        if (missing.isNotEmpty) {
          throw FormatException(
            '$protocol package missing ${table.key}: $missing',
          );
        }
      }
      if (protocol == 'TU') {
        for (final region in db.select('SELECT table_name FROM regions')) {
          final name = region['table_name'] as String;
          final escaped = name.replaceAll('"', '""');
          final columns = db
              .select('PRAGMA table_info("$escaped")')
              .map((row) => row['name'])
              .toSet();
          if (!columns.containsAll([
            'station_id',
            'source_key',
            'source_field',
            'line_name',
            'station_name',
            'raw_value_json',
            'transport_type',
          ])) {
            throw FormatException('TU invalid region schema: $name');
          }
        }
      }
      if (protocol == 'CU') {
        final rows = db.select(
          'SELECT json FROM reference_documents WHERE name = ?',
          ['card_catalog'],
        );
        final catalog = rows.isEmpty
            ? null
            : jsonDecode(rows.single['json'] as String);
        // These names are required by the runtime, even for otherwise valid
        // older packages. Overrides may legitimately be empty.
        if (catalog is! Map ||
            catalog['issuerNames'] is! List ||
            (catalog['issuerNames'] as List).isEmpty ||
            catalog['nameOverrides'] is! List) {
          throw const FormatException('CU invalid card_catalog naming contract');
        }
      }
      final counts = <String, int>{
        for (final item in (spec['tables'] as Map).entries)
          item.key as String: (item.value as num).toInt(),
      };
      return ReferencePackage._(
        db,
        protocol,
        spec['content_version'] as String,
        hash,
        Map.unmodifiable(counts),
      );
    } catch (_) {
      db.close();
      rethrow;
    }
  }
}
