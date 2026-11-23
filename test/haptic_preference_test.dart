import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/settings/application/settings_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';

import 'support/test_database.dart';

SettingsController _controller(SettingsStore store) =>
    SettingsController(store, AppLogger(store: MemoryLogStore()));

void main() {
  group('SettingsController 震动偏好', () {
    test('未保存过设置时默认开启，初始化不会关闭', () async {
      final store = MemorySettingsStore();
      final controller = _controller(store);
      addTearDown(controller.dispose);

      expect(controller.hapticEnabled, isTrue);
      await controller.initialize();
      expect(controller.hapticEnabled, isTrue);
      expect(
        store.values.containsKey(SettingsKeys.hapticEnabled),
        isFalse,
        reason: '缺省开启的键不应被写成 false',
      );
    });

    test('关闭后持久化，重新 initialize 仍保持关闭', () async {
      final store = MemorySettingsStore();
      final controller = _controller(store);
      addTearDown(controller.dispose);
      await controller.initialize();

      await controller.setHapticEnabled(false);
      expect(controller.hapticEnabled, isFalse);
      expect(store.values[SettingsKeys.hapticEnabled], 'false');

      final reloaded = _controller(store);
      addTearDown(reloaded.dispose);
      await reloaded.initialize();
      expect(reloaded.hapticEnabled, isFalse);
    });

    test('显式开启后持久化，重新 initialize 仍保持开启', () async {
      final store = MemorySettingsStore({SettingsKeys.hapticEnabled: 'false'});
      final controller = _controller(store);
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.hapticEnabled, isFalse);

      await controller.setHapticEnabled(true);
      expect(controller.hapticEnabled, isTrue);
      expect(store.values[SettingsKeys.hapticEnabled], 'true');

      final reloaded = _controller(store);
      addTearDown(reloaded.dispose);
      await reloaded.initialize();
      expect(reloaded.hapticEnabled, isTrue);
    });

    test('快速连续切换以最后一次意图为准，且每次乐观发布一次', () async {
      final store = MemorySettingsStore();
      final controller = _controller(store);
      addTearDown(controller.dispose);
      await controller.initialize();

      var notifications = 0;
      void listener() => notifications++;
      controller.addListener(listener);

      final first = controller.setHapticEnabled(false);
      final second = controller.setHapticEnabled(true);
      final third = controller.setHapticEnabled(false);
      expect(controller.hapticEnabled, isFalse);
      expect(notifications, 3, reason: '每次切换都在等待写盘前发布');

      await Future.wait([first, second, third]);
      expect(controller.hapticEnabled, isFalse);
      expect(store.values[SettingsKeys.hapticEnabled], 'false');
      expect(notifications, 3, reason: '写盘完成不应再额外重建界面');
      controller.removeListener(listener);
    });
  });

  group('震动偏好 live 接线', () {
    testWidgets('切换同帧生效、恰好发布一次并持久化到设置', (tester) async {
      final store = MemorySettingsStore();
      final app = _App(store: store);
      addTearDown(app.dispose);
      await tester.runAsync(app.init);
      expect(app.hapticEnabled, isTrue);

      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(GalleryApp(liveApp: app));
      await tester.pumpAndSettle();

      final live = _liveAdapter(tester);
      final controller = live.controller;
      var publishes = 0;
      live.notifier.addListener(() => publishes++);
      expect(controller.hapticEnabled, isTrue);
      final trips = controller.trips;

      controller.setHaptic(false);
      await tester.pump();
      expect(controller.hapticEnabled, isFalse, reason: '开关视觉状态必须在写盘前同一帧更新');
      expect(app.hapticEnabled, isFalse);
      expect(publishes, 1, reason: '一次切换只发布一次，不重复重建');
      expect(identical(controller.trips, trips), isTrue);
      await tester.pumpAndSettle();
      expect(store.values[SettingsKeys.hapticEnabled], 'false');

      // 快速反向：最终值仍然正确，且每次意图各发布一次。
      controller.setHaptic(true);
      await tester.pump();
      expect(controller.hapticEnabled, isTrue);
      controller.setHaptic(false);
      await tester.pump();
      expect(controller.hapticEnabled, isFalse);
      expect(publishes, 3);
      await tester.pumpAndSettle();
      expect(app.hapticEnabled, isFalse);
      expect(store.values[SettingsKeys.hapticEnabled], 'false');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('启动时读取已保存的关闭状态', (tester) async {
      final store = MemorySettingsStore({SettingsKeys.hapticEnabled: 'false'});
      final app = _App(store: store);
      addTearDown(app.dispose);
      await tester.runAsync(app.init);
      expect(app.hapticEnabled, isFalse);

      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(GalleryApp(liveApp: app));
      await tester.pumpAndSettle();
      expect(_liveAdapter(tester).controller.hapticEnabled, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  test('样例模式只改会话状态，reset 恢复默认开启', () {
    final json = jsonDecode(
      File('assets/gallery/fixtures.json').readAsStringSync(),
    ) as GalleryRecord;
    final controller = GalleryController(GalleryData(json));
    addTearDown(controller.dispose);
    expect(controller.hapticEnabled, isTrue);

    var notifications = 0;
    void listener() => notifications++;
    controller.addListener(listener);
    controller.setHaptic(false);
    expect(controller.hapticEnabled, isFalse);
    expect(notifications, 1);
    controller.removeListener(listener);

    controller.reset();
    expect(controller.hapticEnabled, isTrue);
  });
}

/// live 外壳由 [GalleryApp] 创建；其适配器暴露控制器与设置页监听的 notifier。
({Listenable notifier, GalleryController controller}) _liveAdapter(
  WidgetTester tester,
) {
  final notifier = tester
      .widgetList<InheritedNotifier>(
        find.byWidgetPredicate((widget) => widget is InheritedNotifier),
      )
      .map((widget) => widget.notifier)
      .firstWhere((candidate) => '$candidate'.contains('GalleryLiveRead'))!;
  return (
    notifier: notifier,
    controller: (notifier as dynamic).navigation as GalleryController,
  );
}

class _App extends AppDependencies {
  _App({required SettingsStore store})
    : super(
        bundle: MissingTestAssets(),
        database: testDatabase(),
        settingsStore: store,
        logger: AppLogger(store: MemoryLogStore()),
      );
}
