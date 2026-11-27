import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_service.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';

import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('zero wallet balance is valid and must not be replaced by another balance field', () async {
    final channel = _ShanghaiChannel()..balanceFen = 0;
    final logger = AppLogger(store: MemoryLogStore());
    final app = AppDependencies(
      database: testDatabase(),
      channel: channel,
      bundle: MissingTestAssets(),
      logger: logger,
      settingsStore: MemorySettingsStore({SettingsKeys.loggingEnabled: 'true'}),
    );
    addTearDown(app.dispose);
    await app.init();
    await app.scanOnce();
    expect(app.cardInfo!.balanceFen, 0);
    final session = (await logger.readSessions()).singleWhere((s) => s.isScan);
    expect(session.cardInfo?['cardNumber'], app.lastIdentified!.cardNumber);
    expect(session.cardInfo?['cardName'], app.lastIdentified!.displayName);
    expect(
      session.cardInfo?['cardType'],
      app.lastIdentified!.identity.cardType,
    );
    expect(session.cardInfo?['identificationState'], 'resolved');
    final decoded = session.events
        .where(
          (e) => e.type == 'response_fields' && e.data['parserId'] == 'tunion',
        )
        .toList();
    expect(
      decoded.any(
        (e) =>
            (e.data['fields'] as Map?)?.containsKey('applicationSerial') ==
            true,
      ),
      isTrue,
    );
    expect(
      decoded.any((e) => (e.data['fields'] as Map?)?['balanceFen'] == 0),
      isTrue,
    );
    expect(
      session.cardInfo?['applicationSerialRaw'],
      app.cardInfo!.applicationSerial,
    );
    expect(channel.balanceCommands, [
      [0x80, 0x5C, 0, 2, 4],
    ]);
  });

  test(
    'Shanghai TU updates its current balance without changing captured amount',
    () async {
      final channel = _ShanghaiChannel(shanghaiIdentity: true)
        ..balanceFen = 10800;
      final app = AppDependencies(
        database: testDatabase(),
        channel: channel,
        bundle: MissingTestAssets(),
        logger: AppLogger(store: MemoryLogStore()),
        settingsStore: MemorySettingsStore({
          SettingsKeys.includeShanghaiOverdraft: 'true',
        }),
      );
      addTearDown(app.dispose);
      await app.init();
      await app.scanOnceForGallery();
      expect(app.parsedCard!.parserId, CardParserIds.tunion);
      expect(app.lastIdentified!.identity.cardType, 'shanghai_transit_union');
      expect(app.cardInfo!.cityCode, '2900');
      expect(app.balanceDisplay.balanceFen(app.cardInfo!.balanceFen), 10800);
      channel.balanceFen = 10000;
      await app.scanOnceForGallery();
      expect(app.pendingCardSave!.balanceFen, 10000);
      expect(app.balanceDisplay.balanceFen(app.cardInfo!.balanceFen), 10000);
      await app.setIncludeShanghaiOverdraft(false);
      expect(app.balanceDisplay.balanceFen(app.cardInfo!.balanceFen), 9200);
      expect(
        app.applications.singleWhere((app) => app.appId == 'tu').balanceFen,
        10000,
      );
      expect(channel.balanceCommands, everyElement([0x80, 0x5C, 0, 2, 4]));
    },
  );
}

/// Only the 80 5C 00 response is from the user; all identity/other responses are
/// synthetic. No real card number or personal information is stored here.
class _ShanghaiChannel implements NfcChannel {
  _ShanghaiChannel({this.shanghaiIdentity = false});
  final bool shanghaiIdentity;
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
            shanghaiIdentity ? 0x02 : 0,
            0,
            shanghaiIdentity ? 0x29 : 0x30,
            shanghaiIdentity ? 0x00 : 0x50,
            0,
            0,
            0,
            0,
            1,
            1,
            shanghaiIdentity ? 0x00 : 0x03,
            shanghaiIdentity ? 0x31 : 0x10,
            shanghaiIdentity ? 0x04 : 0,
            shanghaiIdentity ? 0x77 : 0,
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
          final data = List.filled(60, 0)..[6] = shanghaiIdentity ? 0x29 : 0x30;
          data[7] = shanghaiIdentity ? 0x00 : 0x50;
          return [...data, 0x90, 0];
      }
    }
    return [0x6A, 0x83];
  }
}
