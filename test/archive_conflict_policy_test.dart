import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_controller.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/features/scan/domain/scan_presentation.dart';
import 'package:transit_card_analyzer/platform/storage/log_exporter.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/shared/domain/archive_conflict_policy.dart';

import 'support/test_database.dart';

void main() {
  test('已存在记录：跳过不写库，覆盖更新标量并保留旧批次', () async {
    final database = testDatabase();
    final repository = CardRepository(database);
    final controller = ArchiveController(
      repository,
      const MethodChannelLogExporter(),
      (_) {},
    );
    addTearDown(controller.dispose);
    addTearDown(database.close);

    void stage(int balance, int minute, String attempt) {
      controller.stage(
        ScanPresentation(
          TransitReadOutcome(
            ParsedCard(
              parserId: CardParserIds.tunion,
              parserName: '交通联合',
              info: TUnionCardInfo(
                applicationSerial: '03100000000000000001',
                issuerId: '1122334455667788',
                balanceFen: balance,
              ),
              transactions: const [],
              selectedAidHex: 'A000000632010105',
            ),
          ),
          KnowledgeBase.empty(),
        ),
        attempt,
        DateTime(2026, 11, 15, 10, minute),
        const [],
      );
    }

    stage(1000, 0, 'existing-a');
    expect(
      await controller.accept(
        'existing-a',
        conflictPolicy: ArchiveConflictPolicy.overwrite,
      ),
      isTrue,
    );
    var card = (await repository.getAllCards()).single;
    final originalReadAt = card.lastReadAt;
    var history = await ArchiveHistory(repository).load(card.id);
    final originalBatchCount = history.batches.length;
    expect(card.balanceFen, 1000);

    stage(2000, 1, 'existing-b');
    expect(
      await controller.accept(
        'existing-b',
        conflictPolicy: ArchiveConflictPolicy.skip,
      ),
      isTrue,
    );
    card = (await repository.getAllCards()).single;
    history = await ArchiveHistory(repository).load(card.id);
    expect(card.balanceFen, 1000);
    expect(card.lastReadAt, originalReadAt);
    expect(history.batches.length, originalBatchCount);
    expect(controller.autoSaveNotice, contains('已跳过'));

    stage(3000, 2, 'existing-c');
    expect(
      await controller.accept(
        'existing-c',
        conflictPolicy: ArchiveConflictPolicy.overwrite,
      ),
      isTrue,
    );
    card = (await repository.getAllCards()).single;
    history = await ArchiveHistory(repository).load(card.id);
    expect(card.balanceFen, 3000);
    expect(originalBatchCount, 1);
    expect(history.batches, hasLength(2));
    expect(
      history.batches.map(
        (batch) => batch.decoded.snapshot?.extensions['captureAttemptId'],
      ),
      containsAll(['existing-a', 'existing-c']),
    );
    expect(
      history.records.every((record) => record.sources.length == 1),
      isTrue,
    );
  });

  test('自动保存：每次询问保留待确认，跳过不写库', () async {
    final database = testDatabase();
    final repository = CardRepository(database);
    final controller = ArchiveController(
      repository,
      const MethodChannelLogExporter(),
      (_) {},
    );
    addTearDown(controller.dispose);
    addTearDown(database.close);

    void stage(int balance, int minute, String attempt) {
      controller.stage(
        ScanPresentation(
          TransitReadOutcome(
            ParsedCard(
              parserId: CardParserIds.tunion,
              parserName: '交通联合',
              info: TUnionCardInfo(
                applicationSerial: '03100000000000000001',
                issuerId: '1122334455667788',
                balanceFen: balance,
              ),
              transactions: const [],
            ),
          ),
          KnowledgeBase.empty(),
        ),
        attempt,
        DateTime(2026, 11, 15, 11, minute),
        const [],
      );
    }

    stage(1000, 0, 'auto-a');
    await controller.autoSave();
    expect(controller.pending, isNull);
    var card = (await repository.getAllCards()).single;
    expect(card.balanceFen, 1000);

    stage(2000, 1, 'auto-b');
    await controller.autoSave(policy: ArchiveConflictPolicy.ask);
    expect(controller.pending?.pendingSaveId, 'auto-b');
    card = (await repository.getAllCards()).single;
    expect(card.balanceFen, 1000);

    await controller.autoSave(policy: ArchiveConflictPolicy.skip);
    expect(controller.pending, isNull);
    card = (await repository.getAllCards()).single;
    expect(card.balanceFen, 1000);
    expect(controller.autoSaveNotice, contains('已跳过'));
  });
}
