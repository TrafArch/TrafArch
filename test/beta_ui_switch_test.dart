import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/app/beta_ui_scope.dart';
import 'package:transit_card_analyzer/app/internal_preview_app.dart';
import 'package:transit_card_analyzer/app/trafarch_app.dart';
import 'package:transit_card_analyzer/features/settings/presentation/settings_page.dart';
import 'package:transit_card_analyzer/features/updates/update_prompt.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_service.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';

import 'support/test_database.dart';
import 'support/gallery_scroll.dart';

AppDependencies createTestApp() => AppDependencies(
  database: testDatabase(),
  bundle: MissingTestAssets(),
  settingsStore: MemorySettingsStore(),
  logger: AppLogger(store: MemoryLogStore()),
  channel: _NoopNfcChannel(),
);

final _enableMainUi = find.widgetWithText(SwitchListTile, '启用 2.x 主界面');
final _useMainUi = find.widgetWithText(SwitchListTile, '使用 2.x 主界面');

void main() {
  testWidgets('legacy settings hides the switch outside a switching host', (
    tester,
  ) async {
    final app = createTestApp();
    addTearDown(app.dispose);
    await tester.pumpWidget(MaterialApp(home: SettingsPage(app: app)));
    await tester.scrollUntilVisible(find.text('莫奈取色'), 250);
    expect(_enableMainUi, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('preview switches between interfaces without a dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var created = 0;
    await tester.pumpWidget(
      InternalPreviewApp(
        previewSettingsStore: MemorySettingsStore(),
        createDependencies: () {
          created++;
          return createTestApp();
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TransitCardAnalyzerApp), findsOneWidget);
    expect(find.byType(UpdatePrompt), findsNothing);

    Future<void> openSwitch(Finder toggle) async {
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        toggle,
        250,
        scrollable: galleryVerticalScroll(),
      );
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
    }

    await openSwitch(_enableMainUi);
    expect(tester.widget<SwitchListTile>(_enableMainUi).value, isFalse);
    await tester.tap(_enableMainUi);
    await tester.pumpAndSettle();
    expect(find.byType(GalleryApp), findsOneWidget);
    expect(find.byType(TransitCardAnalyzerApp), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(created, 1);

    await openSwitch(_useMainUi);
    expect(tester.widget<SwitchListTile>(_useMainUi).value, isTrue);
    await tester.tap(_useMainUi);
    await tester.pumpAndSettle();
    expect(find.byType(TransitCardAnalyzerApp), findsOneWidget);
    expect(find.byType(GalleryApp), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(created, 2);

    await openSwitch(_enableMainUi);
    await tester.tap(_enableMainUi);
    await tester.pumpAndSettle();
    expect(find.byType(GalleryApp), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'preview return preference survives UI switching and host recreation',
    (tester) async {
      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemorySettingsStore();
      Future<void> enterPreview() async {
        final scope = BetaUiScope.maybeOf(
          tester.element(find.byType(TransitCardAnalyzerApp)),
        )!;
        scope.onChanged(true);
        await tester.pumpAndSettle();
      }

      Future<void> openSettings() async {
        await tester.tap(find.byTooltip('设置'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('预测性返回手势'),
          250,
          scrollable: galleryVerticalScroll(),
        );
        await tester.pumpAndSettle();
      }

      Finder toggle() => find.widgetWithText(SwitchListTile, '预测性返回手势');
      await tester.pumpWidget(
        InternalPreviewApp(
          createDependencies: createTestApp,
          previewSettingsStore: store,
        ),
      );
      await tester.pumpAndSettle();
      await enterPreview();
      await openSettings();
      expect(tester.widget<SwitchListTile>(toggle()).value, isTrue);
      await tester.tap(toggle());
      await tester.pumpAndSettle();
      expect(store.values[SettingsKeys.galleryPredictiveBackEnabled], 'false');
      expect(tester.widget<SwitchListTile>(toggle()).value, isFalse);
      BetaUiScope.maybeOf(tester.element(find.byType(GalleryApp)))!
          .onChanged(false);
      await tester.pumpAndSettle();
      await enterPreview();
      await openSettings();
      expect(tester.widget<SwitchListTile>(toggle()).value, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(
        InternalPreviewApp(
          createDependencies: createTestApp,
          previewSettingsStore: store,
        ),
      );
      await tester.pumpAndSettle();
      await enterPreview();
      await openSettings();
      expect(tester.widget<SwitchListTile>(toggle()).value, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}

class _NoopNfcChannel implements NfcChannel {
  @override
  Future<NfcScanResult?> scanOnce() async => null;
  @override
  Future<void> stopScan() async {}
  @override
  Future<List<int>> transceive(List<int> apdu) async => const [0x6a, 0x82];
}
