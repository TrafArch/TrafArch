import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/card_read_batches.dart';
import 'tables/saved_cards.dart';
import 'archive_document_store.dart';

part 'app_database.g.dart';

/// 应用本地数据库（Drift + SQLite）：卡片档案及后续的交易 / 余额快照等表
/// 统一在本数据库管理（应用文档目录下 transit_card_analyzer.sqlite）。
///
/// 表结构变更时递增 [schemaVersion] 并在 [migration] 中为已安装用户编写
/// 迁移逻辑，避免升级后既有卡片档案丢失。
@DriftDatabase(tables: [SavedCards, CardReadBatches])
class AppDatabase extends _$AppDatabase {
  /// 测试可注入内存执行器：
  /// `AppDatabase(DatabaseConnection(NativeDatabase.memory()))`。
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      await transaction(() async {
        await _repairArchiveSchema();
        await backfillLegacySnapshots(onlyWithoutDocument: true);
        await ArchiveDocumentStore(this).backfill();
      });
    },
    // Also repairs files whose user_version was advanced by an older,
    // incomplete migration. Failure aborts opening; never replace the DB.
    beforeOpen: (_) => transaction(() async {
      await _repairArchiveSchema();
      await backfillLegacySnapshots(onlyWithoutDocument: true);
      await ArchiveDocumentStore(this).backfill();
    }),
  );

  Future<void> _repairArchiveSchema() async {
    final columns = await customSelect('PRAGMA table_info(saved_cards)').get();
    final names = columns.map((row) => row.read<String>('name')).toSet();
    // Literal historical SQL: no table rebuild and no masked -> full inference.
    const additions = <String, String>{
      'card_number': 'TEXT NULL',
      'card_number_masked': 'TEXT NULL',
      'balance_fen': 'INTEGER NULL',
      'currency_code': 'TEXT NULL',
      'transaction_count': 'INTEGER NULL',
      'session_data_json': 'TEXT NULL',
    };
    for (final entry in additions.entries) {
      if (!names.contains(entry.key)) {
        await customStatement(
          'ALTER TABLE saved_cards ADD COLUMN ${entry.key} ${entry.value}',
        );
      }
    }
    await customStatement('''
      CREATE TABLE IF NOT EXISTS card_read_batches (
        id TEXT NOT NULL PRIMARY KEY,
        card_id TEXT NOT NULL,
        card_fingerprint TEXT NOT NULL,
        read_at INTEGER NOT NULL,
        parse_version INTEGER NOT NULL DEFAULT 1,
        payload_json TEXT NOT NULL
      )
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS archive_batches_card_read
      ON card_read_batches (card_id, read_at DESC, id DESC)
    ''');
    // Summary freshness is independent of immutable, content-deduplicated
    // batches. Identical observations can happen at different capture times.
    await customStatement('''
      CREATE TABLE IF NOT EXISTS archive_field_observation_times (
        card_id TEXT NOT NULL,
        field_name TEXT NOT NULL,
        observed_at INTEGER NOT NULL,
        PRIMARY KEY (card_id, field_name)
      )
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS archive_documents (
        card_id TEXT NOT NULL PRIMARY KEY,
        payload_json TEXT NOT NULL,
        dirty INTEGER NOT NULL DEFAULT 0
      )
    ''');
    // A few legacy paths update the indexes directly. Mark their complete JSON
    // document dirty in that same SQLite transaction; reads materialize it
    // before exposing data, preserving any JSON-only imported rows/extensions.
    for (final table in [
      'saved_cards',
      'card_read_batches',
      'archive_field_observation_times',
    ]) {
      final key = table == 'saved_cards' ? 'id' : 'card_id';
      for (final operation in ['INSERT', 'UPDATE', 'DELETE']) {
        final name = 'archive_json_${table}_${operation.toLowerCase()}';
        final reference = operation == 'DELETE' ? 'OLD' : 'NEW';
        final statement = table == 'saved_cards' && operation == 'DELETE'
            ? 'DELETE FROM archive_documents WHERE card_id=OLD.id;'
            : 'UPDATE archive_documents SET dirty=1 WHERE card_id=$reference.$key;';
        await customStatement(
          'CREATE TRIGGER IF NOT EXISTS $name AFTER $operation ON $table BEGIN $statement END',
        );
      }
    }
  }

  /// Caller must hold the same transaction as any scalar replacement. Exact
  /// text equality makes retries idempotent, even for empty/malformed payloads.
  /// The reserved ID prefix records origin and timestamp provenance without
  /// changing captured JSON or the generated Drift table contract.
  Future<void> backfillLegacySnapshots({
    String? cardId,
    bool onlyWithoutDocument = false,
  }) async {
    final rows = await customSelect(
      '''
      SELECT s.id, s.card_fingerprint, s.session_data_json,
             COALESCE(s.last_read_at, s.updated_at, s.created_at) AS captured_at,
             CASE WHEN s.last_read_at IS NOT NULL THEN 'last_read_at'
                  WHEN s.updated_at IS NOT NULL THEN 'updated_at'
                  ELSE 'created_at' END AS time_source
      FROM saved_cards s
      WHERE s.session_data_json IS NOT NULL
        ${cardId == null ? '' : 'AND s.id = ?'}
        ${onlyWithoutDocument ? '''AND NOT EXISTS (
          SELECT 1 FROM archive_documents d WHERE d.card_id = s.id
        )''' : ''}
        AND NOT EXISTS (
          SELECT 1 FROM card_read_batches b
          WHERE b.card_id = s.id AND b.payload_json = s.session_data_json
        )
    ''',
      variables: [if (cardId != null) Variable<String>(cardId)],
    ).get();
    for (final row in rows) {
      final raw = row.read<String>('session_data_json');
      var parserVersion = 1;
      try {
        final value = jsonDecode(raw);
        if (value is Map<String, dynamic> &&
            value['parseVersion'] is int &&
            (value['parseVersion'] as int) > 0) {
          parserVersion = value['parseVersion'] as int;
        }
      } on FormatException {
        // The original text remains the authoritative evidence.
      }
      await customStatement(
        '''
        INSERT INTO card_read_batches
          (id, card_id, card_fingerprint, read_at, parse_version, payload_json)
        VALUES (? || lower(hex(randomblob(16))), ?, ?, ?, ?, ?)
      ''',
        [
          'legacy-scalar-v6:${row.read<String>('time_source')}:',
          row.read<String>('id'),
          row.read<String>('card_fingerprint'),
          row.read<int>('captured_at'),
          parserVersion,
          raw,
        ],
      );
    }
    if (rows.isNotEmpty) notifyUpdates({TableUpdate.onTable(cardReadBatches)});
  }

  static QueryExecutor _openConnection() =>
      driftDatabase(name: 'transit_card_analyzer');
}
