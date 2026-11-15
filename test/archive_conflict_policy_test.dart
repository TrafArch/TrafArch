import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_controller.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_identity.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_types.dart';
import 'package:transit_card_analyzer/features/archive/domain/pending_card_save.dart';
import 'package:transit_card_analyzer/features/home/presentation/pending_save_presenter.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/features/scan/domain/scan_presentation.dart';
import 'package:transit_card_analyzer/features/settings/presentation/settings_page.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/log_exporter.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/shared/domain/archive_conflict_policy.dart';

import 'support/test_database.dart';

void main() {
  test('已存在记录：跳过不写库，覆盖更新标量并替换旧批次', () async {
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
        replaceExistingHistory: true,
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
        replaceExistingHistory: true,
      ),
      isTrue,
    );
    card = (await repository.getAllCards()).single;
    history = await ArchiveHistory(repository).load(card.id);
    expect(card.balanceFen, 3000);
    expect(originalBatchCount, 1);
    expect(history.batches, hasLength(1));
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

  testWidgets('设置页可选择已存在记录策略并持久化', (tester) async {
    final store = MemorySettingsStore();
    final app = AppDependencies(
      database: testDatabase(),
      bundle: MissingTestAssets(),
      settingsStore: store,
      logger: AppLogger(store: MemoryLogStore()),
    );
    addTearDown(app.dispose);
    await tester.pumpWidget(MaterialApp(home: SettingsPage(app: app)));
    await tester.pumpAndSettle();

    expect(find.text('已经存在的记录'), findsOneWidget);
    await tester.tap(find.text('已经存在的记录'));
    await tester.pumpAndSettle();
    expect(find.text('跳过'), findsOneWidget);
    expect(find.text('每次询问'), findsOneWidget);

    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();
    expect(app.archiveConflictPolicy, ArchiveConflictPolicy.skip);
    expect(store.values[SettingsKeys.archiveConflictPolicy], 'skip');
    expect(find.text('跳过'), findsOneWidget);
  });

  testWidgets('保存冲突对话框提供跳过与覆盖两种选择', (tester) async {
    const pending = PendingCardSave(
      fingerprint: 'tunion:test',
      identity: CardArchiveIdentity(
        cardType: CardTypes.chinaTunion,
        officialName: '测试卡',
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: SaveCardDialog(
          pending: pending,
          conflict: true,
          askEachTime: true,
        ),
      ),
    );
    expect(find.text('记录已存在'), findsOneWidget);
    expect(find.text('跳过'), findsOneWidget);
    expect(find.text('覆盖'), findsOneWidget);
  });
}
