import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/core/data/settings_store.dart';
import 'package:transit_card_analyzer/core/logging/app_logger.dart';
import 'package:transit_card_analyzer/core/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/core/nfc/nfc_service.dart';
import 'package:transit_card_analyzer/features/home/recent_scan_section.dart';
import 'package:transit_card_analyzer/state/app_state.dart';

import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Shanghai reported 000027109000 remains 100 CNY through UI and archive',
    (tester) async {
      final database = testDatabase();
      final channel = _ShanghaiChannel();
      final app = AppState(
        database: database,
        channel: channel,
        bundle: MissingTestAssets(),
        logger: AppLogger(store: MemoryLogStore()),
        settingsStore: MemorySettingsStore(),
      );
      addTearDown(app.dispose);
      await tester.runAsync(() async {
        await app.init();
        // A previous saved reading must be replaced, never added to a new one.
        channel.balanceFen = 10800;
        await app.scanOnce();
        expect(await app.acceptPendingSave(), isTrue);
        channel.balanceFen = 10000;
        await app.scanOnce();
        expect(app.cardInfo!.cityCode, '3050');
        expect(app.cardInfo!.balanceFen, 10000);
        expect(app.analysis!.wallet.balanceText, '¥100.00');
        expect(
          app.apduLog.join('\n'),
          contains('parsedFen=10000; display=¥100.00; archiveFen=10000; cuFen=null'),
        );
        expect(await app.acceptPendingSave(), isTrue);
        final cards = await database.select(database.savedCards).get();
        expect(cards, hasLength(1));
        expect(cards.single.balanceFen, 10000);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RecentScanSection(app: app)),
        ),
      );
      expect(find.text('¥100.00'), findsOneWidget);
      expect(find.text('¥108.00'), findsNothing);
      expect(channel.balanceCommands, everyElement([0x80, 0x5C, 0, 2, 4]));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  test('zero wallet balance is valid and must not be replaced by another balance field', () async {
    final channel = _ShanghaiChannel()..balanceFen = 0;
    final app = AppState(
      database: testDatabase(),
      channel: channel,
      bundle: MissingTestAssets(),
      logger: AppLogger(store: MemoryLogStore()),
      settingsStore: MemorySettingsStore(),
    );
    addTearDown(app.dispose);
    await app.init();
    await app.scanOnce();
    expect(app.cardInfo!.balanceFen, 0);
    expect(channel.balanceCommands, [
      [0x80, 0x5C, 0, 2, 4],
    ]);
  });
}

/// Only the 80 5C 00 response is from the user; all identity/other responses are
/// synthetic. No real card number or personal information is stored here.
class _ShanghaiChannel implements NfcChannel {
  int balanceFen = 10000;
  final balanceCommands = <List<int>>[];
  bool _tuSelected = false;

  @override
  Future<NfcScanResult?> scanOnce() async => NfcScanResult(
    uid: '04AABBCC',
    technologies: const ['IsoDep'],
    cardType: 'ISO-DEP',
    isoDepConnected: true,
    timestamp: DateTime(2026, 10, 20),
  );

  @override
  Future<void> stopScan() async {}

  @override
  Future<List<int>> transceive(List<int> apdu) async {
    if (apdu[1] == 0xA4) {
      final aid = apdu.skip(5).take(apdu[4]).toList();
      _tuSelected = listEquals(aid, [0xA0, 0, 0, 0x06, 0x32, 0x01, 0x01, 0x05]);
      return _tuSelected || apdu[2] == 0 ? [0x90, 0] : [0x6A, 0x82];
    }
    if (!_tuSelected) return [0x6A, 0x82];
    if (apdu[1] == 0x5C) {
      balanceCommands.add(List.of(apdu));
      final amount = apdu[2] == 0 ? balanceFen : 800;
      return [
        (amount >> 24) & 255,
        (amount >> 16) & 255,
        (amount >> 8) & 255,
        amount & 255,
        0x90,
        0,
      ];
    }
    if (apdu[1] == 0xB0) {
      switch (apdu[2] & 0x1F) {
        case 0x15:
          return [
            0,
            0,
            0x30,
            0x50,
            0,
            0,
            0,
            0,
            1,
            1,
            0x03,
            0x10,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            1,
            0x20,
            0x24,
            1,
            1,
            0x20,
            0x29,
            0x12,
            0x31,
            0,
            0,
            0x90,
            0,
          ];
        case 0x16:
          return [...List.filled(55, 0), 0x90, 0];
        case 0x17:
          final data = List.filled(60, 0)..[6] = 0x30;
          data[7] = 0x50;
          return [...data, 0x90, 0];
      }
    }
    return [0x6A, 0x83];
  }
}
