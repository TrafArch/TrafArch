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

AppDependencies createTestApp() => AppDependencies(
  database: testDatabase(),
  bundle: MissingTestAssets(),
  settingsStore: MemorySettingsStore(),
  logger: AppLogger(store: MemoryLogStore()),
  channel: _NoopNfcChannel(),
);

void main() {
  testWidgets(
    'current settings exposes beta switch only inside internal host',
    (tester) async {
      final app = createTestApp();
      addTearDown(app.dispose);
      var enabled = false;
      await tester.pumpWidget(
        BetaUiScope(
          enabled: false,
          onChanged: (value) => enabled = value,
          child: MaterialApp(home: SettingsPage(app: app)),
        ),
      );
      final tile = find.widgetWithText(SwitchListTile, '启用新界面（beta）');
      await tester.scrollUntilVisible(tile, 250);
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);
      await tester.tap(tile);
      await tester.pump();
      expect(enabled, isTrue);
      await tester.pumpWidget(MaterialApp(home: SettingsPage(app: app)));
      await tester.pump();
      expect(find.text('启用新界面（beta）'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('internal host disposes inactive UI and returns to current app', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var created = 0;
    await tester.pumpWidget(
      InternalPreviewApp(
        createDependencies: () {
          created++;
          return createTestApp();
        },
      ),
    );
    await tester.pump();
    expect(find.byType(TransitCardAnalyzerApp), findsOneWidget);
    expect(find.byType(UpdatePrompt), findsNothing);
    final scope = BetaUiScope.maybeOf(
      tester.element(find.byType(TransitCardAnalyzerApp)),
    )!;
    scope.onChanged(true);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(GalleryApp), findsOneWidget);
    expect(find.byType(TransitCardAnalyzerApp), findsNothing);
    expect(created, 1);
    BetaUiScope.maybeOf(tester.element(find.byType(GalleryApp)))!
        .onChanged(false);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(TransitCardAnalyzerApp), findsOneWidget);
    expect(find.byType(GalleryApp), findsNothing);
    expect(created, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

class _NoopNfcChannel implements NfcChannel {
  @override
  Future<NfcScanResult?> scanOnce() async => null;
  @override
  Future<void> stopScan() async {}
  @override
  Future<List<int>> transceive(List<int> apdu) async => const [0x6a, 0x82];
}
