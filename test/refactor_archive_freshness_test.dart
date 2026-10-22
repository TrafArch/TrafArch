import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_identity.dart';

void main() {
  test(
    'deduplicated field freshness survives database reopen and deletion',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'trafarch-freshness-',
      );
      final file = File('${directory.path}/archive.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      const identity = CardArchiveIdentity(cardType: 'tunion');
      Future<void> observe(int at, {int? balance}) =>
          CardRepository(db).saveIdentity(
            fingerprint: 'tunion:issuer:00123',
            identity: identity,
            balanceFen: balance,
            currencyCode: balance == null ? null : 'CNY',
            readAt: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
          );
      try {
        await observe(100, balance: 300);
        await observe(300, balance: 300);
        expect(await db.select(db.cardReadBatches).get(), hasLength(1));
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        await observe(400);
        await observe(200, balance: 200);
        var card = await db.select(db.savedCards).getSingle();
        expect(card.balanceFen, 300);
        expect(card.lastReadAt, 400);
        await observe(500, balance: 0);
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        await observe(600);
        await observe(450, balance: 450);
        card = await db.select(db.savedCards).getSingle();
        expect(card.balanceFen, 0);
        expect(card.lastReadAt, 600);
        final repository = CardRepository(db);
        final deletedId = card.id;
        expect(await repository.deleteCard(card.id), isTrue);
        expect(await db.select(db.cardReadBatches).get(), isEmpty);
        await observe(50, balance: 50);
        card = await db.select(db.savedCards).getSingle();
        expect(card.balanceFen, 50);
        expect(card.id, isNot(deletedId));
      } finally {
        await db.close();
        directory.deleteSync(recursive: true);
      }
    },
  );
}
