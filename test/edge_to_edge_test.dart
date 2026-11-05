import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/app/navigation/floating_nav_bar.dart';
import 'package:transit_card_analyzer/app/trafarch_app.dart';
import 'package:transit_card_analyzer/features/recovery/recovery_result_panel.dart';
import 'package:transit_card_analyzer/features/recovery/recovery_state.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_details.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_presenter.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_service.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';

import 'support/test_database.dart';

void _window(WidgetTester tester, Size size, FakeViewPadding insets) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.viewPadding = insets;
  tester.view.padding = insets;
}

AppDependencies _app() => AppDependencies(
  database: testDatabase(),
  settingsStore: MemorySettingsStore(),
  bundle: MissingTestAssets(),
  channel: _NoopNfc(),
  logger: AppLogger(store: MemoryLogStore()),
);

void main() {
  testWidgets('系统栏图标跟随明暗主题，进入设置及返回后仍保持可读', (tester) async {
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    _window(
      tester,
      const Size(390, 844),
      const FakeViewPadding(top: 32, bottom: 24),
    );
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final app = _app();
    await tester.runAsync(app.init);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpWidget(
      TransitCardAnalyzerApp(createDependencies: () => app),
    );
    await tester.pumpAndSettle();

    Map<dynamic, dynamic> style() =>
        calls
                .lastWhere(
                  (call) =>
                      call.method == 'SystemChrome.setSystemUIOverlayStyle',
                )
                .arguments
            as Map<dynamic, dynamic>;

    expect(style()['systemNavigationBarIconBrightness'], 'Brightness.dark');
    expect(style()['statusBarIconBrightness'], 'Brightness.dark');
    expect(style()['systemNavigationBarColor'], Colors.transparent.toARGB32());
    expect(style()['systemNavigationBarContrastEnforced'], isTrue);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(style()['systemNavigationBarIconBrightness'], 'Brightness.light');
    expect(style()['statusBarIconBrightness'], 'Brightness.light');
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('读卡与数据'), findsOneWidget);
    expect(style()['systemNavigationBarIconBrightness'], 'Brightness.light');
    await tester.pageBack();
    await tester.pumpAndSettle();
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(style()['systemNavigationBarIconBrightness'], 'Brightness.dark');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('底栏、侧栏与标题避开手势条、三按钮栏和横屏刘海，安全区不叠加', (tester) async {
    addTearDown(tester.view.reset);
    final app = _app();
    await tester.runAsync(app.init);
    for (final (size, insets) in [
      (const Size(390, 844), const FakeViewPadding(top: 32, bottom: 24)),
      (const Size(390, 844), const FakeViewPadding(top: 32, bottom: 48)),
      (
        const Size(844, 390),
        const FakeViewPadding(left: 44, right: 24, bottom: 24),
      ),
      (const Size(1000, 800), const FakeViewPadding(top: 32, right: 48)),
    ]) {
      _window(tester, size, insets);
      await tester.pumpWidget(MaterialApp(home: AppShell(app: app)));
      await tester.pumpAndSettle();
      final title = tester.getRect(find.text('TrafArch'));
      expect(title.top, greaterThanOrEqualTo(insets.top));
      expect(title.left, greaterThanOrEqualTo(insets.left));
      if (size.height < 480 || size.width < 600) {
        final bar = tester.getRect(find.byType(FloatingNavBar));
        expect(bar.bottom, closeTo(size.height - insets.bottom - 20, 0.1));
        expect(bar.left, greaterThanOrEqualTo(insets.left));
        expect(bar.right, lessThanOrEqualTo(size.width - insets.right));
      } else {
        final rail = tester.getRect(find.byType(NavigationRail));
        expect(rail.top, greaterThanOrEqualTo(insets.top));
        expect(rail.bottom, lessThanOrEqualTo(size.height - insets.bottom));
      }
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    app.dispose();
  });

  for (final bottom in [24.0, 48.0]) {
    testWidgets('详情弹层在底部安全区 $bottom 下仍能滚动并点击最后操作', (tester) async {
      addTearDown(tester.view.reset);
      _window(
        tester,
        const Size(390, 844),
        FakeViewPadding(top: 32, bottom: bottom),
      );
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showTripEntryDetails(
                    context,
                    TripEntryInfo(
                      sourceLabel: '测试记录',
                      title: '记录详情',
                      isConsume: true,
                      fields: [
                        for (var i = 0; i < 35; i++) ('字段 $i', '原始值 $i'),
                      ],
                    ),
                    onDiagnostics: () => tapped = true,
                  ),
                  child: const Text('打开记录'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开记录'));
      await tester.pumpAndSettle();
      final list = find.descendant(
        of: find.byType(DraggableScrollableSheet),
        matching: find.byType(ListView),
      );
      expect(tester.getRect(list).bottom, closeTo(844 - bottom, 0.1));
      final lastAction = find.text('诊断与原始证据');
      await tester.scrollUntilVisible(
        lastAction,
        250,
        scrollable: find
            .descendant(of: list, matching: find.byType(Scrollable))
            .first,
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(lastAction).bottom,
        lessThanOrEqualTo(844 - bottom),
      );
      await tester.tap(lastAction);
      expect(tapped, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('恢复证据页正文在横屏避开侧边刘海和系统导航栏', (tester) async {
    addTearDown(tester.view.reset);
    _window(
      tester,
      const Size(844, 390),
      const FakeViewPadding(left: 44, right: 48, bottom: 24),
    );
    final app = _app();
    app.recoveredCapture = RecoveryCapture(
      readAt: DateTime(2026, 11, 5),
      summary: const {'cardName': '测试卡'},
      frames: const [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: RecoveryResultPanel(app: app)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看上次读取的原始数据'));
    await tester.pumpAndSettle();
    final body = tester.getRect(find.byType(SingleChildScrollView).last);
    expect(body.left, 44);
    expect(body.right, lessThanOrEqualTo(844 - 48));
    expect(body.bottom, lessThanOrEqualTo(390 - 24));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    app.dispose();
  });
}

class _NoopNfc implements NfcChannel {
  @override
  Future<NfcScanResult?> scanOnce() async => null;
  @override
  Future<void> stopScan() async {}
  @override
  Future<List<int>> transceive(List<int> apdu) async => const [0x6A, 0x82];
}
