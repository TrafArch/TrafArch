import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/app/trafarch_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_theme.dart';
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
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
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
    MaterialApp appWidget() => tester.widget(find.byType(MaterialApp));
    expect(appWidget().themeAnimationDuration, Duration.zero);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    await tester.pump();
    expect(appWidget().themeAnimationDuration, Duration.zero);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: false);
    await tester.pump();
    expect(appWidget().themeAnimationDuration, Duration.zero);

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
    final tokens = appWidget().theme!.extension<GalleryTokens>()!;
    expect(style()['systemNavigationBarColor'], tokens.canvas.toARGB32());

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(style()['systemNavigationBarIconBrightness'], 'Brightness.light');
    expect(style()['statusBarIconBrightness'], 'Brightness.light');
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('读卡与数据'), findsOneWidget);
    expect(style()['systemNavigationBarIconBrightness'], 'Brightness.light');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(style()['systemNavigationBarIconBrightness'], 'Brightness.dark');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
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
