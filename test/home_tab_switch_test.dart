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
  testWidgets('switching tabs does not setState during build', (tester) async {
    final app = AppDependencies(
      database: testDatabase(),
      settingsStore: MemorySettingsStore(),
      bundle: MissingTestAssets(),
      channel: _NoopNfcChannel(),
    );
    await tester.runAsync(app.init);
    await tester.pumpWidget(
      TransitCardAnalyzerApp(createDependencies: () => app),
    );
    await tester.pump();

    await tester.tap(
      find.descendant(
        of: find.byType(FloatingNavBar),
        matching: find.byIcon(Icons.directions_transit_outlined),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('暂无行程数据'), findsOneWidget);

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
