import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_transfer_controller.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/archive_export_options.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_identity.dart';
import 'package:transit_card_analyzer/platform/storage/archive_document_store.dart';

void main() {
  late AppDatabase db;
  late CardRepository repository;
  late _Documents store;
  late ArchiveTransferController controller;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = CardRepository(db);
    store = _Documents();
    controller = ArchiveTransferController(repository, store);
  });
  tearDown(() async {
    if (!controller.disposed) controller.dispose();
    await controller.finishWrites();
    await db.close();
  });

  test('selected JSON previews without writing, imports and reexports only selected fields', () async {
    store.next = PickedArchiveDocument(name: 'records.json', content: _rows());
    final preview = (await controller.pickImport())!;
    expect(preview.isPartial, isTrue);
    expect(preview.recordCount, 2);
    expect(await repository.getAllCards(), isEmpty);
    await controller.confirmImport(preview);
    final card = (await repository.getAllCards()).single;
    final history = await ArchiveHistory(repository).load(card.id);
    expect(history.importedRecords, hasLength(2));
    expect(history.importedRecords.first['card_number'], '000123');
    expect(history.batches, isEmpty);
    await controller.export(
      options: ArchiveExportOptions(
        fields: {ArchiveExportField.entryStation, ArchiveExportField.amount},
      ),
    );
    final output = jsonDecode(store.saved!) as Map<String, dynamic>;
    expect(output['format'], 'trafarch.records');
    final records = output['records'] as List;
    expect(records, hasLength(2));
    expect(records.first.keys.toSet(), {'entry_station', 'amount'});
    expect(records.first['entry_station'], '001号站');
    expect(store.saved, isNot(contains('000123')));
  });

  test(
    'repeat imports are idempotent while equal rows in one file survive',
    () async {
      for (var i = 0; i < 2; i++) {
        store.next = PickedArchiveDocument(name: 'same.json', content: _rows());
        await controller.confirmImport((await controller.pickImport())!);
      }
      final card = (await repository.getAllCards()).single;
      expect(
        (await ArchiveHistory(repository).load(card.id)).importedRecords,
        hasLength(2),
      );
    },
  );

  test('full backup restores imported rows into a clean database', () async {
    store.next = PickedArchiveDocument(name: 'rows.json', content: _rows());
    await controller.confirmImport((await controller.pickImport())!);
    await controller.export(
      options: ArchiveExportOptions(mode: ArchiveExportMode.fullBackup),
    );
    final target = AppDatabase(NativeDatabase.memory());
    final targetStore = _Documents()
      ..next = PickedArchiveDocument(
        name: 'backup.json',
        content: store.saved!,
      );
    final targetRepository = CardRepository(target);
    final restore = ArchiveTransferController(targetRepository, targetStore);
    try {
      final preview = (await restore.pickImport())!;
      expect(preview.isPartial, isFalse);
      await restore.confirmImport(preview);
      final restored = (await targetRepository.getAllCards()).single;
      expect(
        (await ArchiveHistory(targetRepository).load(restored.id))
            .importedRecords,
        hasLength(2),
      );
    } finally {
      restore.dispose();
      await restore.finishWrites();
      await target.close();
    }
  });

  test(
    'cancel, malformed JSON, future version and stale preview never write',
    () async {
      expect(await controller.pickImport(), isNull);
      store.next = const PickedArchiveDocument(name: 'bad.json', content: '{');
      await expectLater(controller.pickImport(), throwsFormatException);
      store.next = const PickedArchiveDocument(
        name: 'future.json',
        content: '{"format":"trafarch.archive","version":99,"cards":[]}',
      );
      await expectLater(controller.pickImport(), throwsFormatException);
      store.next = PickedArchiveDocument(name: 'good.json', content: _rows());
      final first = (await controller.pickImport())!;
      store.next = PickedArchiveDocument(name: 'good.json', content: _rows());
      final latest = (await controller.pickImport())!;
      await expectLater(controller.confirmImport(first), throwsStateError);
      expect(await repository.getAllCards(), isEmpty);
      await controller.confirmImport(latest);
      await expectLater(controller.confirmImport(latest), throwsStateError);
    },
  );

  test('busy and disposal cannot start a late database import', () async {
    final pending = Completer<PickedArchiveDocument?>();
    store.pending = pending.future;
    final opening = controller.pickImport();
    expect(controller.busy, isTrue);
    await expectLater(controller.pickImport(), throwsStateError);
    controller.dispose();
    pending.complete(
      PickedArchiveDocument(name: 'late.json', content: _rows()),
    );
    await expectLater(opening, throwsStateError);
    await controller.finishWrites();
    expect(await repository.getAllCards(), isEmpty);
  });

  test(
    'cards without records require full backup before opening save picker',
    () async {
      await repository.saveIdentity(
        fingerprint: 'empty-card',
        identity: const CardArchiveIdentity(cardType: 'china_tunion'),
      );
      await expectLater(
        controller.export(options: ArchiveExportOptions()),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('完整备份'),
          ),
        ),
      );
      expect(store.saved, isNull);
      await controller.export(
        options: ArchiveExportOptions(mode: ArchiveExportMode.fullBackup),
      );
      expect((jsonDecode(store.saved!) as Map)['cards'], hasLength(1));
    },
  );

  test(
    'unsupported backup envelope metadata is rejected without data loss',
    () async {
      await repository.saveIdentity(
        fingerprint: 'source',
        identity: const CardArchiveIdentity(cardType: 'china_tunion'),
      );
      await controller.export(
        options: ArchiveExportOptions(mode: ArchiveExportMode.fullBackup),
      );
      final json = jsonDecode(store.saved!) as Map<String, dynamic>;
      json['futureMetadata'] = {'001': 'kept'};
      store.next = PickedArchiveDocument(
        name: 'extended.json',
        content: jsonEncode(json),
      );
      await expectLater(
        controller.pickImport(),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('扩展'),
          ),
        ),
      );
      expect((await repository.getAllCards()).single.cardFingerprint, 'source');
    },
  );
}

String _rows() => jsonEncode({
  'format': 'trafarch.records',
  'version': 1,
  'exportedAt': '2026-10-26T12:00:00Z',
  'fields': ['card_number', 'entry_station', 'amount'],
  'records': List.generate(
    2,
    (_) => {
      'card_number': '000123',
      'entry_station': '001号站',
      'amount': '2.50',
    },
  ),
});

class _Documents implements ArchiveDocumentStore {
  PickedArchiveDocument? next;
  Future<PickedArchiveDocument?>? pending;
  String? saved;
  @override
  Future<PickedArchiveDocument?> openJson() async => pending ?? next;
  @override
  Future<String?> saveJson(String fileName, String content) async {
    saved = content;
    return 'content://exports/$fileName';
  }
}
