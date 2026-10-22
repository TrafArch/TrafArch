import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/settings/application/settings_controller.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';

void main() {
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
