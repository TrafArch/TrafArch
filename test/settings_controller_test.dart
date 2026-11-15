import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/settings/application/settings_controller.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/shared/domain/archive_conflict_policy.dart';

void main() {
  group('SettingsController 已存在记录策略', () {
    test('默认覆盖，并持久化跳过与每次询问', () async {
      final store = MemorySettingsStore();
      final controller = SettingsController(
        store,
        AppLogger(store: MemoryLogStore()),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.archiveConflictPolicy, ArchiveConflictPolicy.overwrite);

      await controller.setArchiveConflictPolicy(ArchiveConflictPolicy.skip);
      expect(store.values[SettingsKeys.archiveConflictPolicy], 'skip');

      await controller.setArchiveConflictPolicy(ArchiveConflictPolicy.ask);
      expect(store.values[SettingsKeys.archiveConflictPolicy], 'ask');

      final reloaded = SettingsController(
        store,
        AppLogger(store: MemoryLogStore()),
      );
      addTearDown(reloaded.dispose);
      await reloaded.initialize();
      expect(reloaded.archiveConflictPolicy, ArchiveConflictPolicy.ask);
    });

    test('未知持久化值回退覆盖', () async {
      final controller = SettingsController(
        MemorySettingsStore({
          SettingsKeys.archiveConflictPolicy: 'not-a-policy',
        }),
        AppLogger(store: MemoryLogStore()),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.archiveConflictPolicy, ArchiveConflictPolicy.overwrite);
    });
  });

  group('SettingsController 上海交通卡可透支余额', () {
    test('未保存过设置时默认关闭，初始化不会开启', () async {
      final controller = SettingsController(
        MemorySettingsStore(),
        AppLogger(store: MemoryLogStore()),
      );
      addTearDown(controller.dispose);

      expect(controller.includeShanghaiOverdraft, isFalse);
      await controller.initialize();
      expect(controller.includeShanghaiOverdraft, isFalse);
    });

    test('开启后持久化，重新初始化仍包含可透支余额', () async {
      final store = MemorySettingsStore();
      final controller = SettingsController(
        store,
        AppLogger(store: MemoryLogStore()),
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      await controller.setIncludeShanghaiOverdraft(true);
      expect(controller.includeShanghaiOverdraft, isTrue);
      expect(store.values[SettingsKeys.includeShanghaiOverdraft], 'true');

      final reloaded = SettingsController(
        store,
        AppLogger(store: MemoryLogStore()),
      );
      addTearDown(reloaded.dispose);
      await reloaded.initialize();
      expect(reloaded.includeShanghaiOverdraft, isTrue);
    });

    test('关闭后持久化，再次打开应用保持扣除可透支额度', () async {
      final store = MemorySettingsStore({
        SettingsKeys.includeShanghaiOverdraft: 'true',
      });
      final controller = SettingsController(
        store,
        AppLogger(store: MemoryLogStore()),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.includeShanghaiOverdraft, isTrue);

      await controller.setIncludeShanghaiOverdraft(false);
      expect(controller.includeShanghaiOverdraft, isFalse);
      expect(store.values[SettingsKeys.includeShanghaiOverdraft], 'false');

      final reloaded = SettingsController(
        store,
        AppLogger(store: MemoryLogStore()),
      );
      addTearDown(reloaded.dispose);
      await reloaded.initialize();
      expect(reloaded.includeShanghaiOverdraft, isFalse);
    });
  });

  group('SettingsController 莫奈取色', () {
    test('未保存过设置时默认开启', () async {
      final controller = SettingsController(
        MemorySettingsStore(),
        AppLogger(store: MemoryLogStore()),
      );
      addTearDown(controller.dispose);

      expect(controller.monetEnabled, isTrue);
      await controller.initialize();
      expect(controller.monetEnabled, isTrue);
    });

    test('显式关闭后持久化，重新初始化仍保持关闭', () async {
      final store = MemorySettingsStore();
      final controller = SettingsController(
        store,
        AppLogger(store: MemoryLogStore()),
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      await controller.setMonetEnabled(false);
      expect(controller.monetEnabled, isFalse);
      expect(store.values[SettingsKeys.monetEnabled], 'false');

      final reloaded = SettingsController(
        store,
        AppLogger(store: MemoryLogStore()),
      );
      addTearDown(reloaded.dispose);
      await reloaded.initialize();
      expect(reloaded.monetEnabled, isFalse);
    });
  });
}
