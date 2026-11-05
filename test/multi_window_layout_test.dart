import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/app/navigation/floating_nav_bar.dart';
import 'package:transit_card_analyzer/app/trafarch_app.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_service.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';

import 'support/test_database.dart';

void main() {
  testWidgets('主界面在小窗与分屏尺寸连续变化后保留页签及依赖，所有页签可切换', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = AppDependencies(
      database: testDatabase(),
      settingsStore: MemorySettingsStore(),
      bundle: MissingTestAssets(),
      channel: _NoopNfcChannel(),
    );
    await tester.runAsync(app.init);
    var creations = 0;
    await tester.pumpWidget(
      TransitCardAnalyzerApp(
        createDependencies: () {
          creations++;
          return app;
        },
      ),
    );
    await tester.pump();
    const icons = [
      Icons.directions_transit_outlined,
      Icons.credit_card_outlined,
      Icons.science_outlined,
      Icons.home_outlined,
    ];
    Finder tab(IconData icon) => find.descendant(
      of: find.byType(FloatingNavBar),
      matching: find.byIcon(icon),
    );
    await tester.tap(tab(icons.first));
    await tester.pumpAndSettle();
    for (final size in const [
      Size(360, 400),
      Size(320, 480),
      Size(280, 400),
      Size(240, 320),
      Size(600, 320),
      Size(390, 844),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('暂无行程数据'), findsOneWidget);
      for (final icon in icons.skip(1).followedBy([icons.first])) {
        expect(tab(icon).hitTestable(), findsOneWidget);
        await tester.tap(tab(icon));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(creations, 1);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}

class _NoopNfcChannel implements NfcChannel {
  @override
  Future<NfcScanResult?> scanOnce() async => null;
  @override
  Future<void> stopScan() async {}
  @override
  Future<List<int>> transceive(List<int> apdu) async => const [0x6A, 0x82];
}
