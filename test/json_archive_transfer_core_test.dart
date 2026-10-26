import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_document.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_identity.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  test(
    'backup restores exact captured evidence, provenance and unknown fields',
    () async {
      final source = _document(
        'card-1',
        'batch-1',
        payload: ' {"v":99,"future":{"001":"kept"}}\n',
      );
      final target = AppDatabase(NativeDatabase.memory());
      addTearDown(target.close);
      final bundle = CardArchiveBundle(
        cards: [source],
        exportedAt: DateTime.utc(2026, 10, 26),
      );
      final decoded = CardArchiveBundle.decode(bundle.encode());
      final repository = CardRepository(target);
      final result = await repository.importDocuments(decoded.cards);
      expect(result.insertedCards, 1);
      expect(result.addedBatches, 1);
      final restored = (await repository.exportDocuments()).single;
      expect(restored.toJson(), source.toJson());
      expect(restored.card.cardNumber, '000123');
      expect(restored.card.currencyCode, isNull);
      expect(
        restored.batches.single.payloadJson,
        source.batches.single.payloadJson,
      );
      final repeated = await repository.importDocuments(decoded.cards);
      expect(repeated.insertedCards, 0);
      expect(repeated.addedBatches, 0);
      expect(await target.select(target.cardReadBatches).get(), hasLength(1));
    },
  );

  test('preview and failing conflict leave all cards unchanged', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = CardRepository(db);
    final original = _document('card-1', 'batch-1');
    await repository.importDocuments([original]);
    final preview = await repository.previewImportDocuments([
      _document('card-2', 'batch-2'),
    ]);
    expect(preview.insertedCards, 1);
    expect(await repository.getAllCards(), hasLength(1));
    final conflict = _document(
      'card-1',
      'batch-1',
      payload: 'different immutable evidence',
    );
    await expectLater(
      repository.importDocuments([_document('card-2', 'batch-2'), conflict]),
      throwsA(isA<FormatException>()),
    );
    expect(await repository.getAllCards(), hasLength(1));
    expect(
      (await repository.exportDocuments()).single.toJson(),
      original.toJson(),
    );
  });

  test('merge retains local name and latest per-field observations', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = CardRepository(db);
    await repository.saveIdentity(
      fingerprint: 'fingerprint-card-1',
      identity: const CardArchiveIdentity(cardType: 'china_tunion'),
      cardNumber: '000123',
      balanceFen: 500,
      currencyCode: 'CNY',
      readAt: DateTime.fromMillisecondsSinceEpoch(400, isUtc: true),
    );
    final local = await db.select(db.savedCards).getSingle();
    await repository.renameCard(local.id, '本机名称');
    await repository.importDocuments([_document('card-1', 'incoming')]);
    final merged = (await repository.exportDocuments()).single;
    expect(merged.card.id, local.id);
    expect(merged.card.customName, '本机名称');
    expect(merged.card.balanceFen, 500);
    expect(merged.card.currencyCode, 'CNY');
    expect(merged.card.lastReadAt, 400);
    expect(merged.batches, hasLength(2));
    expect(
      merged.batches.firstWhere((b) => b.id == 'incoming').cardId,
      local.id,
    );
    await repository.saveIdentity(
      fingerprint: local.cardFingerprint,
      identity: const CardArchiveIdentity(cardType: 'china_tunion'),
      readAt: DateTime.fromMillisecondsSinceEpoch(600, isUtc: true),
    );
    await repository.saveIdentity(
      fingerprint: local.cardFingerprint,
      identity: const CardArchiveIdentity(cardType: 'china_tunion'),
      balanceFen: 300,
      currencyCode: 'HKD',
      readAt: DateTime.fromMillisecondsSinceEpoch(300, isUtc: true),
    );
    expect((await db.select(db.savedCards).getSingle()).balanceFen, 500);
  });

  test(
    'imported partial rows keep repeated identical rows and deduplicate replay',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repository = CardRepository(db);
      final source = _document('partial', 'unused').copyWith(
        card: _document(
          'partial',
          'unused',
        ).card.copyWith(sessionDataJson: const Value(null)),
        batches: [],
        importedRecords: [
          {'amount': 5, 'station_code': '0001'},
          {'amount': 5, 'station_code': '0001'},
        ],
      );
      final added = await repository.importDocuments([source]);
      expect(added.addedRecords, 2);
      expect(
        (await repository.getArchiveRows(source.card.id)).importedRecords,
        hasLength(2),
      );
      final repeated = await repository.importDocuments([source]);
      expect(repeated.addedRecords, 0);
      final restored = (await repository.exportDocuments()).single;
      expect(restored.importedRecords, source.importedRecords);
      expect(restored.batches, isEmpty);
    },
  );

  test('strict envelope validation does not reinterpret invalid or future snapshots', () {
    final valid = _document('one', 'one').toJson();
    expect(
      () => CardArchiveDocument.fromJson({...valid, 'version': 2}),
      throwsFormatException,
    );
    expect(
      () => CardArchiveDocument.fromJson({
        ...valid,
        'card': {...valid['card'] as Map, 'cardNumber': 123},
      }),
      throwsFormatException,
    );
    expect(
      () => CardArchiveDocument.fromJson({
        ...valid,
        'batches': [
          {...(valid['batches'] as List).single as Map, 'cardId': 'other'},
        ],
      }),
      throwsFormatException,
    );
    final raw = CardArchiveDocument.fromJson({
      ...valid,
      'batches': [
        {
          ...(valid['batches'] as List).single as Map,
          'payloadJson': '{corrupt raw',
        },
      ],
    });
    expect(raw.batches.single.payloadJson, '{corrupt raw');
    expect(() => CardArchiveBundle.decode('[1,2]'), throwsFormatException);
    final bundle = CardArchiveBundle(
      cards: [raw],
      exportedAt: DateTime.utc(2026),
    );
    expect((jsonDecode(bundle.encode()) as Map)['cards'], hasLength(1));
  });

  test(
    'reopening a canonical archive does not invent a scalar capture batch',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'trafarch-json-reopen-',
      );
      final file = File('${directory.path}/archive.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      final source = _document('canonical', 'original-capture').copyWith(
        card: _document('canonical', 'original-capture').card.copyWith(
          sessionDataJson: const Value(
            '{"v":99,"retainedBalanceSource":"scalar only"}',
          ),
        ),
      );
      try {
        await CardRepository(db).importDocuments([source]);
        final before = (await CardRepository(db).exportDocuments()).single;
        expect(before.batches, hasLength(1));
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        final reopened = (await CardRepository(db).exportDocuments()).single;
        expect(reopened.toJson(), before.toJson());
        expect(reopened.batches.single.id, 'original-capture');
      } finally {
        await db.close();
        directory.deleteSync(recursive: true);
      }
    },
  );

  for (final incomingIsNewer in [false, true]) {
    test(
      'merge preserves displaced scalar evidence when incoming is ${incomingIsNewer ? 'newer' : 'older'}',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final repository = CardRepository(db);
        const localRaw = ' {"v":99,"local":"scalar only"}\n';
        const incomingRaw = '{invalid incoming scalar';
        final local = _document('card-1', 'local-batch').copyWith(
          card: _document('card-1', 'local-batch').card.copyWith(
            lastReadAt: Value(incomingIsNewer ? 200 : 400),
            sessionDataJson: const Value(localRaw),
          ),
        );
        final incomingBase = _document('remote-card', 'incoming-batch');
        final incoming = incomingBase.copyWith(
          card: incomingBase.card.copyWith(
            cardFingerprint: local.card.cardFingerprint,
            lastReadAt: Value(incomingIsNewer ? 400 : 200),
            sessionDataJson: const Value(incomingRaw),
          ),
          batches: [
            incomingBase.batches.single.copyWith(
              cardFingerprint: local.card.cardFingerprint,
            ),
          ],
        );
        await repository.importDocuments([local]);
        await repository.importDocuments([incoming]);
        final merged = (await repository.exportDocuments()).single;
        final json = merged.toJson();
        final retained = json['retainedSummaries'] as List? ?? const [];
        final payloads = [
          merged.card.sessionDataJson,
          for (final batch in merged.batches) batch.payloadJson,
          for (final summary in retained)
            (summary as Map)['card']['sessionDataJson'],
        ];
        expect(payloads, containsAll([localRaw, incomingRaw]));
        expect(merged.batches, hasLength(2));
        expect(retained, hasLength(1));
        expect((retained.single as Map)['format'], 'trafarch.card-summary');
        expect((retained.single as Map)['version'], 1);
        expect(
          (retained.single as Map)['card']['id'],
          incomingIsNewer ? 'card-1' : 'remote-card',
        );
        expect(
          (retained.single as Map)['fieldObservationTimes'],
          local.fieldObservationTimes,
        );
        final replay = CardArchiveBundle.decode(
          CardArchiveBundle(
            cards: [incoming],
            exportedAt: DateTime.utc(2026),
          ).encode(),
        );
        await repository.importDocuments(replay.cards);
        await repository.renameCard(merged.card.id, '改名后仍保留证据');
        final refreshed = (await repository.exportDocuments()).single;
        expect(refreshed.toJson()['retainedSummaries'], retained);
        expect(refreshed.batches, hasLength(2));
        final restored = CardArchiveDocument.decode(refreshed.encode());
        expect(restored.toJson()['retainedSummaries'], retained);
      },
    );
  }

  test(
    'missing incoming summary fields cannot advance retained observation times',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repository = CardRepository(db);
      final baseline = _document('card-1', 'unused').copyWith(batches: []);
      final original = baseline.copyWith(
        card: baseline.card.copyWith(
          officialName: const Value('原名称'),
          balanceFen: const Value(100),
          currencyCode: const Value('CNY'),
          identificationSource: 'reference',
          identificationConfidence: const Value(0.8),
        ),
        fieldObservationTimes: {
          'officialName': 200,
          'balanceFen': 200,
          'currencyCode': 200,
          'identity': 200,
        },
      );
      await repository.importDocuments([original]);
      final missing = baseline.copyWith(
        card: baseline.card.copyWith(
          balanceFen: const Value(null),
          lastReadAt: const Value(500),
        ),
        fieldObservationTimes: {
          'officialName': 500,
          'balanceFen': 500,
          'currencyCode': 500,
          'identity': 500,
        },
      );
      await repository.importDocuments([missing]);
      final retained = (await repository.exportDocuments()).single;
      expect(retained.fieldObservationTimes['officialName'], 200);
      expect(retained.fieldObservationTimes['balanceFen'], 200);
      expect(retained.fieldObservationTimes['currencyCode'], 200);
      expect(retained.fieldObservationTimes['identity'], 200);
      expect(retained.card.officialName, '原名称');
      expect(retained.card.balanceFen, 100);
      final observed = baseline.copyWith(
        card: baseline.card.copyWith(
          officialName: const Value('新观察名称'),
          balanceFen: const Value(300),
          currencyCode: const Value('HKD'),
          identificationSource: 'new-reference',
          identificationConfidence: const Value(0.9),
          lastReadAt: const Value(300),
        ),
        fieldObservationTimes: {
          'officialName': 300,
          'balanceFen': 300,
          'currencyCode': 300,
          'identity': 300,
        },
      );
      await repository.importDocuments([observed]);
      final result = (await repository.exportDocuments()).single;
      expect(result.card.officialName, '新观察名称');
      expect(result.card.balanceFen, 300);
      expect(result.card.currencyCode, 'HKD');
      expect(result.card.identificationSource, 'new-reference');
      expect(result.card.lastReadAt, 500);
      expect(result.fieldObservationTimes['officialName'], 300);
      expect(result.fieldObservationTimes['balanceFen'], 300);
      expect(result.fieldObservationTimes['currencyCode'], 300);
      expect(result.fieldObservationTimes['identity'], 300);
    },
  );

  test(
    'unknown selected currency does not resurrect a previous currency clock',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repository = CardRepository(db);
      final baseline = _document('card-1', 'unused').copyWith(batches: []);
      await repository.importDocuments([
        baseline.copyWith(
          card: baseline.card.copyWith(
            balanceFen: const Value(100),
            currencyCode: const Value('CNY'),
          ),
          fieldObservationTimes: {'balanceFen': 200, 'currencyCode': 200},
        ),
      ]);
      await repository.importDocuments([
        baseline.copyWith(
          card: baseline.card.copyWith(
            balanceFen: const Value(300),
            currencyCode: const Value(null),
            lastReadAt: const Value(300),
          ),
          fieldObservationTimes: {'balanceFen': 300, 'currencyCode': 500},
        ),
      ]);
      await repository.renameCard(baseline.card.id, '刷新规范文档');
      final refreshed = (await repository.exportDocuments()).single;
      expect(refreshed.card.balanceFen, 300);
      expect(refreshed.card.currencyCode, isNull);
      expect(
        refreshed.fieldObservationTimes.containsKey('currencyCode'),
        isFalse,
      );
    },
  );
}

CardArchiveDocument _document(
  String cardId,
  String batchId, {
  String payload = '{"v":1,"trips":[],"rail":null,"bus":null}',
}) {
  final card = SavedCard(
    id: cardId,
    cardFingerprint: 'fingerprint-$cardId',
    cardType: 'china_tunion',
    identificationSource: 'unknown',
    cardNumber: '000123',
    customName: '来源名称',
    balanceFen: 0,
    currencyCode: null,
    sessionDataJson: payload,
    createdAt: 100,
    updatedAt: 200,
    lastReadAt: 200,
  );
  return CardArchiveDocument(
    card: card,
    batches: [
      CardReadBatch(
        id: batchId,
        cardId: cardId,
        cardFingerprint: card.cardFingerprint,
        readAt: 200,
        parseVersion: 1,
        payloadJson: payload,
      ),
    ],
    fieldObservationTimes: {'cardNumber': 200, 'balanceFen': 200},
    extensions: {
      'futureMetadata': {'unknown': 'retained'},
    },
  );
}
