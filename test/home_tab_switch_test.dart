import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/app/trafarch_app.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_service.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';

import 'support/test_database.dart';

void main() {
  testWidgets('legacy home waits for NFC to be enabled before its first scan', (
    tester,
  ) async {
    final states = StreamController<NfcAdapterState>.broadcast(sync: true);
    addTearDown(states.close);
    final channel = _NoopNfcChannel();
    final app = AppDependencies(
      database: testDatabase(),
      settingsStore: MemorySettingsStore(),
      bundle: MissingTestAssets(),
      channel: channel,
      nfcAdapterStates: states.stream,
    );
    await tester.runAsync(app.init);
    states.add(NfcAdapterState.disabled);
    await tester.pumpWidget(
      TransitCardAnalyzerApp(
        createDependencies: () => app,
        enableUpdateChecks: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('请先打开系统 NFC'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '开始读取'))
          .onPressed,
      isNull,
    );
    expect(channel.discoveries, 0);

    states.add(NfcAdapterState.enabled);
    await tester.pumpAndSettle();
    expect(channel.discoveries, 1);
    expect(find.textContaining('请先打开系统 NFC'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  for (final width in [390.0, 800.0]) {
    testWidgets('switching tabs at ${width}dp does not setState during build', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
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

      await tester.tap(find.byIcon(Icons.directions_transit_outlined));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('暂无行程数据'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }
}

class _NoopNfcChannel implements NfcChannel {
  int discoveries = 0;
  @override
  Future<NfcScanResult?> scanOnce() async {
    discoveries++;
    return null;
  }

  @override
  Future<void> stopScan() async {}
  @override
  Future<List<int>> transceive(List<int> apdu) async => const [0x6A, 0x82];
}
