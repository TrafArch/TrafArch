import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_transfer_controller.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/archive_export_options.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_document.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/platform/storage/archive_document_store.dart';

void main() {
  for (final incomingIsNewer in [false, true]) {
    test(
      'displaced scalar stays visible after merge and reopen (newer=$incomingIsNewer)',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'trafarch-summary-',
        );
        final file = File('${directory.path}/archive.sqlite');
        var db = AppDatabase(NativeDatabase(file));
        ArchiveTransferController? controller;
        addTearDown(() async {
          controller?.dispose();
          await controller?.finishWrites();
          await db.close();
          await directory.delete(recursive: true);
        });
        var repository = CardRepository(db);
        final local = _document('local', incomingIsNewer ? 100 : 300, 1);
        final incoming = _document('remote', 200, 2);
        await repository.importDocuments([local]);
        await repository.importDocuments([incoming]);
        final merged = (await repository.exportDocuments()).single;
        expect(merged.retainedSummaries, hasLength(1));
        expect(merged.batches, isEmpty);
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        repository = CardRepository(db);
        final history = await ArchiveHistory(repository).load('local');
        expect(
          history.records.map((record) => record.fields['terminalId']).toSet(),
          {'000001', '000002'},
        );
        final retained = history.batches.singleWhere(
          (item) => item.origin == 'imported_summary',
        );
        expect(retained.id, startsWith('retained-summary:'));
        expect(retained.timeSource, 'summary.lastReadAt');
        expect(
          retained.decoded.rawJson,
          incomingIsNewer
              ? local.card.sessionDataJson
              : incoming.card.sessionDataJson,
        );
        final originalId = retained.id;
        final documents = _Documents();
        controller = ArchiveTransferController(repository, documents);
        await controller.export(
          options: ArchiveExportOptions(
            fields: {ArchiveExportField.terminal, ArchiveExportField.amount},
          ),
        );
        final rows = (jsonDecode(documents.saved!) as Map)['records'] as List;
        expect(rows.map((row) => row['terminal']).toSet(), {
          '000001',
          '000002',
        });
        expect(rows.map((row) => row['amount']).toSet(), {'-1.00', '-2.00'});
        await controller.export(
          options: ArchiveExportOptions(mode: ArchiveExportMode.fullBackup),
        );
        documents.next = PickedArchiveDocument(
          name: 'backup.json',
          content: documents.saved!,
        );
        final preview = (await controller.pickImport())!;
        expect(preview.recordCount, 2);
        expect(preview.batchCount, 0);
        await controller.confirmImport(preview);
        final replayed = await ArchiveHistory(repository).load('local');
        expect(replayed.records, hasLength(2));
        expect(
          replayed.batches
              .singleWhere((item) => item.origin == 'imported_summary')
              .id,
          originalId,
        );
        expect((await repository.exportDocuments()).single.batches, isEmpty);
      },
    );
  }
}

CardArchiveDocument _document(String id, int at, int sequence) =>
    CardArchiveDocument(
      card: SavedCard(
        id: id,
        cardFingerprint: 'same-card',
        cardType: 'china_tunion',
        identificationSource: 'unknown',
        createdAt: at,
        updatedAt: at,
        lastReadAt: at,
        sessionDataJson: CardSessionSnapshot(
          context: const ArchiveContext(
            currencyCode: 'CNY',
            minorUnitDigits: 2,
          ),
          trips: [
            TransitTrip(
              time: DateTime.utc(2026, 10, 26, 8, sequence),
              amountFen: sequence * 100,
              overdraftLimitFen: 0,
              isConsume: true,
              typeName: '消费',
              sequence: sequence,
              terminalId: sequence.toString().padLeft(6, '0'),
            ),
          ],
        ).encode(),
      ),
      batches: [],
      fieldObservationTimes: {},
    );

class _Documents implements ArchiveDocumentStore {
  String? saved;
  PickedArchiveDocument? next;
  @override
  Future<PickedArchiveDocument?> openJson() async => next;
  @override
  Future<String?> saveJson(String fileName, String content) async {
    saved = content;
    return fileName;
  }
}
