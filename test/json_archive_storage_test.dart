import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_identity.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  test('saving and renaming keep a versioned persisted JSON archive', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = CardRepository(db);
    await repository.saveIdentity(
      fingerprint: 'tu:00123',
      identity: const CardArchiveIdentity(cardType: 'china_tunion'),
      cardNumber: '00123',
      readAt: DateTime.fromMillisecondsSinceEpoch(100, isUtc: true),
    );
    final tables = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
        .get();
    expect(
      tables.map((r) => r.read<String>('name')),
      contains('archive_documents'),
    );
    final card = await db.select(db.savedCards).getSingle();
    await repository.renameCard(card.id, '通勤 001');
    final stored = await db
        .customSelect('SELECT payload_json,dirty FROM archive_documents')
        .getSingle();
    final document = jsonDecode(stored.read<String>('payload_json')) as Map;
    expect(document['format'], 'trafarch.card');
    expect(document['version'], 1);
    expect(document['card']['cardNumber'], '00123');
    expect(document['card']['customName'], '通勤 001');
    expect(document['batches'], hasLength(1));
    expect(stored.read<int>('dirty'), 0);
    expect(db.schemaVersion, 7);
    await repository.deleteCard(card.id);
    expect(
      await db.customSelect('SELECT * FROM archive_documents').get(),
      isEmpty,
    );
  });

  test(
    'v6 migration preserves raw malformed evidence and observation times',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'trafarch-json-v7-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/archive.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      final repository = CardRepository(db);
      await repository.saveIdentity(
        fingerprint: 'cu:0007',
        identity: const CardArchiveIdentity(cardType: 'city_union'),
        cardNumber: '0007',
        sessionDataJson: '{bad legacy raw',
        balanceFen: 0,
        currencyCode: null,
        readAt: DateTime.fromMillisecondsSinceEpoch(200, isUtc: true),
      );
      final card = await db.select(db.savedCards).getSingle();
      final batch = await db.select(db.cardReadBatches).getSingle();
      await db.customStatement('DROP TABLE IF EXISTS archive_documents');
      await db.customStatement('PRAGMA user_version=6');
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      try {
        final stored = await db
            .customSelect('SELECT payload_json FROM archive_documents')
            .getSingle();
        final document = jsonDecode(stored.read<String>('payload_json')) as Map;
        expect(document['card'], card.toJson());
        expect(document['batches'], [batch.toJson()]);
        expect(document['fieldObservationTimes']['balanceFen'], 200);
        expect(document['card']['sessionDataJson'], '{bad legacy raw');
        expect(document['card']['currencyCode'], isNull);
        final before = stored.read<String>('payload_json');
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        expect(
          (await db
                  .customSelect('SELECT payload_json FROM archive_documents')
                  .getSingle())
              .read<String>('payload_json'),
          before,
        );
      } finally {
        await db.close();
      }
    },
  );

  test(
    'legacy direct index writes refresh before canonical history reads',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repository = CardRepository(db);
      await repository.saveIdentity(
        fingerprint: 'tu:999',
        identity: const CardArchiveIdentity(cardType: 'china_tunion'),
      );
      final card = await db.select(db.savedCards).getSingle();
      await (db.update(db.savedCards)..where((t) => t.id.equals(card.id)))
          .write(const SavedCardsCompanion(customName: Value('外部旧写入')));
      final history = await repository.getArchiveRows(card.id);
      expect(history.card!.customName, '外部旧写入');
      final stored = await db
          .customSelect('SELECT payload_json,dirty FROM archive_documents')
          .getSingle();
      expect(
        (jsonDecode(stored.read<String>('payload_json'))
            as Map)['card']['customName'],
        '外部旧写入',
      );
      expect(stored.read<int>('dirty'), 0);
    },
  );
}
