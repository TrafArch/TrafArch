import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_document.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_identity.dart';
import 'package:transit_card_analyzer/features/archive/domain/suica_manual_number.dart';

import 'support/test_database.dart';

const _fingerprint = 'felica:suica:idm:0102030405060708';
const _rawCapture = '{"unknownOriginalField": "  preserve  ", "version": 99}';

Future<SavedCard> _save(
  CardRepository repository, {
  String fingerprint = _fingerprint,
  String type = 'suica',
  int at = 100,
}) async {
  await repository.saveIdentity(
    fingerprint: fingerprint,
    identity: CardArchiveIdentity(cardType: type, officialName: 'Suica'),
    balanceFen: 900,
    currencyCode: 'JPY',
    transactionCount: 1,
    sessionDataJson: _rawCapture,
    readAt: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
  );
  return (await repository.getAllCards()).single;
}

SuicaManualNumber? _number(Map<String, dynamic> extensions) =>
    SuicaManualNumber.fromJson(extensions['suicaManualNumber']);

void main() {
  test(
    'normalizes printed number whitespace and letter case without losing zeros',
    () {
      expect(
        normalizeSuicaManualNumber(' je000\t1234 5678\n9012 '),
        'JE000123456789012',
      );
      expect(
        normalizeSuicaManualNumber('AB123456789012345'),
        'AB123456789012345',
      );
      expect(normalizeSuicaManualNumber('  \n\t'), isNull);
      expect(normalizeSuicaManualNumber(null), isNull);
      for (final value in [
        '0102030405060708',
        'JE12345678901234',
        'JE1234567890123456',
        'JE123-4567-8901-2345',
        '1E123456789012345',
        'JE１２３４５６７８９０１２３４５',
      ]) {
        expect(
          () => normalizeSuicaManualNumber(value),
          throwsFormatException,
          reason: value,
        );
      }
    },
  );

  test(
    'only supported user metadata exposes a formatted manual card number',
    () {
      final json = <String, dynamic>{
        'version': 1,
        'source': 'user',
        'value': 'JE123456789012345',
        'updatedAt': 500,
      };
      final number = SuicaManualNumber.fromJson(json)!;
      expect(number.value, 'JE123456789012345');
      expect(number.formatted, 'JE123 4567 8901 2345');
      for (final value in [
        null,
        'JE123456789012345',
        {...json, 'version': 2},
        {...json, 'source': 'nfc'},
        {...json, 'value': null},
        {...json, 'value': '0102030405060708'},
        {...json, 'updatedAt': '500'},
      ]) {
        expect(SuicaManualNumber.fromJson(value), isNull);
      }
    },
  );

  test('manual saves and edits preserve observed identity and immutable capture bytes', () async {
    final repository = CardRepository(testDatabase());
    final saved = await _save(repository);
    await repository.renameCard(saved.id, '日本旅行');
    final before = (await repository.exportDocuments()).single;

    await repository.setSuicaManualNumber(saved.id, ' je123 4567 8901 2345 ');
    final after = (await repository.exportDocuments()).single;
    expect(_number(after.cardExtensions)!.value, 'JE123456789012345');
    expect(after.cardExtensions['suicaManualNumber'], {
      'version': 1,
      'source': 'user',
      'value': 'JE123456789012345',
      'updatedAt': after.card.updatedAt,
    });
    expect(after.card.updatedAt, greaterThan(before.card.updatedAt));
    expect(
      {...after.card.toJson()}..remove('updatedAt'),
      {...before.card.toJson()}..remove('updatedAt'),
    );
    expect(after.card.cardNumber, isNull);
    expect(after.card.cardFingerprint, _fingerprint);
    expect(after.card.lastReadAt, 100);
    expect(after.card.sessionDataJson, _rawCapture);
    expect(after.batches, before.batches);
    expect(after.fieldObservationTimes, before.fieldObservationTimes);

    await repository.setSuicaManualNumber(saved.id, 'JE000123456789012');
    final changed = (await repository.exportDocuments()).single;
    expect(_number(changed.cardExtensions)!.formatted, 'JE000 1234 5678 9012');
    expect(changed.card.updatedAt, greaterThan(after.card.updatedAt));
  });

  test('clearing leaves a user tombstone and rereading does not restore an old number', () async {
    final repository = CardRepository(testDatabase());
    final saved = await _save(repository);
    await repository.setSuicaManualNumber(saved.id, 'JE123456789012345');
    await repository.setSuicaManualNumber(saved.id, '  ');
    final cleared = (await repository.exportDocuments()).single;
    expect(_number(cleared.cardExtensions), isNull);
    expect(cleared.cardExtensions['suicaManualNumber'], {
      'version': 1,
      'source': 'user',
      'value': null,
      'updatedAt': cleared.card.updatedAt,
    });
    await _save(repository, at: 200);
    final reread = (await repository.exportDocuments()).single;
    expect(reread.cardExtensions, cleared.cardExtensions);
    expect(reread.card.cardNumber, isNull);
    expect(reread.card.lastReadAt, 200);
  });

  test('rereading and renaming preserve the saved manual number', () async {
    final repository = CardRepository(testDatabase());
    final saved = await _save(repository);
    await repository.setSuicaManualNumber(saved.id, 'JE123456789012345');
    final metadata = (await repository.exportDocuments()).single.cardExtensions;
    await _save(repository, at: 200);
    await repository.renameCard(saved.id, '东京通勤');
    final document = (await repository.exportDocuments()).single;
    expect(document.cardExtensions, metadata);
    expect(document.card.customName, '东京通勤');
    expect(document.card.lastReadAt, 200);
    expect(document.card.cardNumber, isNull);
  });

  test('rejects invalid values, missing cards and incompatible identities atomically', () async {
    final repository = CardRepository(testDatabase());
    final saved = await _save(repository);
    final before = (await repository.exportDocuments()).single.encode();
    await expectLater(
      repository.setSuicaManualNumber(saved.id, '1234'),
      throwsFormatException,
    );
    await expectLater(
      repository.setSuicaManualNumber('missing', 'JE123456789012345'),
      throwsStateError,
    );
    expect((await repository.exportDocuments()).single.encode(), before);
    for (final entry in [
      ('china_tunion', _fingerprint),
      ('suica', 'felica:suica:idm:0000000000000000'),
      ('suica', 'felica:suica:idm:0102'),
      ('suica', 'felica:suica:idm:010203040506070Z'),
      ('suica', 'felica:suica:idm:0102030405060708:extra'),
      ('suica', 'felica:octopus:idm:0102030405060708'),
    ]) {
      final invalidRepository = CardRepository(testDatabase());
      final invalidCard = await _save(
        invalidRepository,
        fingerprint: entry.$2,
        type: entry.$1,
      );
      final original = (await invalidRepository.exportDocuments()).single
          .encode();
      await expectLater(
        invalidRepository.setSuicaManualNumber(
          invalidCard.id,
          'JE123456789012345',
        ),
        throwsStateError,
      );
      expect(
        (await invalidRepository.exportDocuments()).single.encode(),
        original,
      );
    }
  });

  test('history and list streams publish manual changes without fabricating a reread', () async {
    final repository = CardRepository(testDatabase());
    final saved = await _save(repository);
    final history = StreamIterator(ArchiveHistory(repository).watch(saved.id));
    final list = StreamIterator(repository.watchAllArchiveRows());
    addTearDown(history.cancel);
    addTearDown(list.cancel);
    expect(await history.moveNext(), isTrue);
    expect(await list.moveNext(), isTrue);
    expect(_number(history.current.cardExtensions), isNull);
    expect(_number(list.current.single.cardExtensions), isNull);

    await repository.setSuicaManualNumber(saved.id, 'JE123456789012345');
    expect(
      await history.moveNext().timeout(const Duration(seconds: 5)),
      isTrue,
    );
    expect(await list.moveNext().timeout(const Duration(seconds: 5)), isTrue);
    expect(_number(history.current.cardExtensions)!.value, 'JE123456789012345');
    expect(
      _number(list.current.single.cardExtensions)!.value,
      'JE123456789012345',
    );
    expect(history.current.card!.lastReadAt, 100);
    expect(history.current.batches, hasLength(1));

    await repository.setSuicaManualNumber(saved.id, null);
    expect(
      await history.moveNext().timeout(const Duration(seconds: 5)),
      isTrue,
    );
    expect(await list.moveNext().timeout(const Duration(seconds: 5)), isTrue);
    expect(_number(history.current.cardExtensions), isNull);
    expect(_number(list.current.single.cardExtensions), isNull);
  });

  test(
    'manual metadata survives file reopen and complete JSON backup restoration',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'suica-manual-number-',
      );
      final file = File('${directory.path}/archive.sqlite');
      var database = AppDatabase(NativeDatabase(file));
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });
      var repository = CardRepository(database);
      final saved = await _save(repository);
      await repository.setSuicaManualNumber(saved.id, 'JE123456789012345');
      await repository.setSuicaManualNumber(saved.id, 'AB123456789012345');
      await database.close();
      database = AppDatabase(NativeDatabase(file));
      repository = CardRepository(database);
      final history = await ArchiveHistory(repository).load(saved.id);
      final number = _number(history.cardExtensions)!;
      expect(number.value, 'AB123456789012345');
      expect(number.formatted, 'AB123 4567 8901 2345');
      final json = CardArchiveBundle(
        cards: await repository.exportDocuments(),
        exportedAt: DateTime.utc(2026, 11, 16),
      ).encode();
      final target = CardRepository(testDatabase());
      await target.importDocuments(CardArchiveBundle.decode(json).cards);
      final restored = await ArchiveHistory(target).load(saved.id);
      expect(restored.cardExtensions, history.cardExtensions);
      expect(restored.card!.cardNumber, isNull);
      expect(restored.card!.cardFingerprint, _fingerprint);
      expect(restored.batches.single.decoded.rawJson, _rawCapture);
    },
  );

  test(
    'older backups cannot silently replace an edit or revive a cleared number',
    () async {
      final repository = CardRepository(testDatabase());
      final saved = await _save(repository);
      final noManualNumber = await repository.exportDocuments();
      await repository.setSuicaManualNumber(saved.id, 'JE123456789012345');
      final previousNumber = await repository.exportDocuments();
      for (final next in ['JE000123456789012', null]) {
        await repository.setSuicaManualNumber(saved.id, next);
        final latest = (await repository.exportDocuments()).single.encode();
        await expectLater(
          repository.previewImportDocuments(previousNumber),
          throwsFormatException,
        );
        await expectLater(
          repository.importDocuments(previousNumber),
          throwsFormatException,
        );
        expect((await repository.exportDocuments()).single.encode(), latest);
        await repository.importDocuments(noManualNumber);
        expect(
          _number((await repository.exportDocuments()).single.cardExtensions)
              ?.value,
          next,
        );
      }
    },
  );

  test('editing preserves unknown metadata and rejects unsupported existing versions', () async {
    for (final extension in <Object?>[
      {
        'version': 2,
        'source': 'user',
        'value': 'JE123456789012345',
        'updatedAt': 1,
      },
      {
        'version': 1,
        'source': 'nfc',
        'value': 'JE123456789012345',
        'updatedAt': 1,
      },
      {'version': 1, 'source': 'user', 'value': 'broken', 'updatedAt': 1},
      {'version': 1, 'source': 'user', 'value': null},
      null,
    ]) {
      final repository = CardRepository(testDatabase());
      final saved = await _save(repository);
      final document = (await repository.exportDocuments()).single;
      await repository.importDocuments([
        document.copyWith(cardExtensions: {'suicaManualNumber': extension}),
      ]);
      final before = (await repository.exportDocuments()).single.encode();
      await expectLater(
        repository.setSuicaManualNumber(saved.id, 'JE000123456789012'),
        throwsFormatException,
      );
      expect((await repository.exportDocuments()).single.encode(), before);
    }

    final repository = CardRepository(testDatabase());
    final saved = await _save(repository);
    final document = (await repository.exportDocuments()).single;
    await repository.importDocuments([
      document.copyWith(
        cardExtensions: {
          'futureCardMetadata': {'preserve': true},
          'suicaManualNumber': {
            'version': 1,
            'source': 'user',
            'value': 'JE123456789012345',
            'updatedAt': 1,
            'futureManualMetadata': {'preserve': true},
          },
        },
      ),
    ]);
    await repository.setSuicaManualNumber(saved.id, 'JE000123456789012');
    final updated = (await repository.exportDocuments()).single.cardExtensions;
    expect(updated['futureCardMetadata'], {'preserve': true});
    expect((updated['suicaManualNumber'] as Map)['futureManualMetadata'], {
      'preserve': true,
    });
  });
}
