import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'tu_station_repository.dart';

/// User-authored data lives outside versioned reference packages.
class ReferenceUserStore {
  ReferenceUserStore._(this.db, this.migrationError);
  final Database db;
  final String? migrationError;
  bool _closed = false;

  static Future<ReferenceUserStore> open() async {
    final root = await getApplicationSupportDirectory();
    final db = sqlite3.open('${root.path}/reference_user.sqlite');
    try {
      TuStationRepository.ensureAppTables(db);
      db.execute(
        'CREATE TABLE IF NOT EXISTS reference_migrations('
        'source TEXT PRIMARY KEY, completed_at TEXT NOT NULL)',
      );
      db.execute(
        'CREATE TABLE IF NOT EXISTS reference_legacy_rows('
        'source TEXT NOT NULL, table_name TEXT NOT NULL, source_id TEXT NOT NULL,'
        'payload_json TEXT NOT NULL, PRIMARY KEY(source,table_name,source_id))',
      );
      String? error;
      try {
        _migrateLegacy(
          db,
          '${root.path}/trafarch_db/trafarch_database_tu.sqlite',
        );
      } catch (e) {
        // The legacy file remains intact, and the transaction has rolled back.
        // Keep new user edits available while surfacing migration failure.
        error = '旧站点数据迁移失败：$e';
      }
      return ReferenceUserStore._(db, error);
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  static void _migrateLegacy(Database target, String path) {
    const marker = 'legacy-tu-overrides-v1';
    if (target.select('SELECT 1 FROM reference_migrations WHERE source = ?', [
          marker,
        ]).isNotEmpty ||
        !File(path).existsSync()) {
      return;
    }
    final source = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      final tables = source
          .select("SELECT name FROM sqlite_master WHERE type='table'")
          .map((r) => r['name'])
          .toSet();
      target.execute('BEGIN IMMEDIATE');
      try {
        if (tables.contains('tu_user_station_overrides')) {
          for (final r in source.select(
            'SELECT * FROM tu_user_station_overrides',
          )) {
            _retainRow(target, marker, 'tu_user_station_overrides', r);
            final old = target.select(
              'SELECT updated_at FROM tu_user_station_overrides '
              'WHERE region_code=? AND source_key=? AND source_field=?',
              [r['region_code'], r['source_key'], r['source_field']],
            );
            if (old.isNotEmpty) {
              final incoming = DateTime.tryParse('${r['updated_at']}');
              final existing = DateTime.tryParse('${old.single['updated_at']}');
              if (incoming == null ||
                  existing == null ||
                  !incoming.isAfter(existing)) {
                continue;
              }
            }
            target.execute(
              'INSERT INTO tu_user_station_overrides '
              '(region_code,source_key,source_field,station_name,line_name,transport_type,updated_at) '
              'VALUES(?,?,?,?,?,?,?) ON CONFLICT(region_code,source_key,source_field) DO UPDATE SET '
              'station_name=excluded.station_name,line_name=excluded.line_name,'
              'transport_type=excluded.transport_type,updated_at=excluded.updated_at',
              [
                r['region_code'],
                r['source_key'],
                r['source_field'],
                r['station_name'],
                r['line_name'],
                r['transport_type'],
                r['updated_at'],
              ],
            );
          }
        }
        if (tables.contains('tu_unknown_station_reports')) {
          for (final r in source.select(
            'SELECT * FROM tu_unknown_station_reports',
          )) {
            _retainRow(target, marker, 'tu_unknown_station_reports', r);
            final existing = target.select(
              'SELECT * FROM tu_unknown_station_reports '
              'WHERE region_code=? AND source_key=? AND source_field=?',
              [r['region_code'], r['source_key'], r['source_field']],
            );
            final old = existing.isEmpty ? null : existing.single;
            String chooseTime(String field, bool earliest) {
              final incoming = '${r[field]}';
              if (old == null) return incoming;
              final previous = '${old[field]}';
              final left = DateTime.tryParse(incoming);
              final right = DateTime.tryParse(previous);
              if (left == null || right == null) return previous;
              return (earliest ? left.isBefore(right) : left.isAfter(right))
                  ? incoming
                  : previous;
            }

            final first = chooseTime('first_seen_at', true);
            final last = chooseTime('last_seen_at', false);
            target.execute(
              'INSERT INTO tu_unknown_station_reports '
              '(region_code,source_key,source_field,transport_type,raw_value_json,first_seen_at,last_seen_at,hit_count) '
              'VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(region_code,source_key,source_field) DO UPDATE SET '
              'transport_type=excluded.transport_type,raw_value_json=excluded.raw_value_json,'
              'first_seen_at=excluded.first_seen_at,last_seen_at=excluded.last_seen_at,'
              'hit_count=excluded.hit_count',
              [
                r['region_code'],
                r['source_key'],
                r['source_field'],
                old == null || last == r['last_seen_at']
                    ? r['transport_type']
                    : old['transport_type'],
                old == null || last == r['last_seen_at']
                    ? r['raw_value_json'] ??
                          (old == null ? null : old['raw_value_json'])
                    : old['raw_value_json'],
                first,
                last,
                (r['hit_count'] as int) + ((old?['hit_count'] as int?) ?? 0),
              ],
            );
          }
        }
        target.execute('INSERT INTO reference_migrations VALUES(?,?)', [
          marker,
          DateTime.now().toUtc().toIso8601String(),
        ]);
        target.execute('COMMIT');
      } catch (_) {
        target.execute('ROLLBACK');
        rethrow;
      }
    } finally {
      source.close();
    }
  }

  static void _retainRow(Database db, String source, String table, Row row) {
    db.execute('INSERT INTO reference_legacy_rows VALUES(?,?,?,?)', [
      source,
      table,
      '${row['id']}',
      jsonEncode(Map<String, Object?>.from(row)),
    ]);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    db.close();
  }
}
