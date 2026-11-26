import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/home/presentation/result_labels.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_service.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/protocols/transport/transport_failure.dart';

import 'support/test_database.dart';

const _unknownLabel = '暂无可识别卡种';
const _pseName = '315041592E5359532E4444463031';
const _ppseName = '325041592E5359532E4444463031';
const _mastercardAid = 'A0000000041010';
const _unionPayAid = 'A000000333010101';
const _tagLost = TransportFailure(
  kind: TransportFailureKind.tagLost,
  code: 'TAG_LOST',
  message: 'synthetic tag loss',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('unsupported transit uses the unrecognized card label', () {
    expect(transitDisplayName(parserId: null), _unknownLabel);
  });

  for (final scenario in ['metadata', 'unsupported', 'transit-io']) {
    test('$scenario does not publish or save a parsed card', () async {
      final channel = _UnknownChannel(
        isoDepConnected: scenario != 'metadata',
        failOnExchange: scenario == 'transit-io',
      );
      final app = _createApp(channel);
      await app.init();
      await app.scanOnceForGallery();
      expect(app.parsedCard, isNull);
      expect(app.pendingCardSave, isNull);
      if (scenario == 'transit-io') {
        expect(app.error, contains('TAG_LOST'));
        expect(channel.commands, hasLength(1));
      } else {
        expect(app.scan.outcome, isA<UnsupportedReadOutcome>());
        expect(app.error, isNull);
        if (scenario == 'metadata') expect(channel.commands, isEmpty);
      }
    });
  }

  test('a card with only bank applications is unsupported and unsaved', () async {
    final channel = _UnknownChannel(
      selectResponse: (name) => switch (name) {
        _pseName || _ppseName => _hexBytes(
          '6F1CA51ABF0C1761094F07${_mastercardAid}610A4F08${_unionPayAid}9000',
        ),
        _mastercardAid => _hexBytes('6F098407${_mastercardAid}9000'),
        _unionPayAid => _hexBytes('6F0A8408${_unionPayAid}9000'),
        _ => null,
      },
    );
    final app = _createApp(channel);
    await app.init();
    expect(app.autoSaveEnabled, isTrue);
    await app.scanOnce();

    expect(app.scan.outcome, isA<UnsupportedReadOutcome>());
    expect(app.error, isNull);
    expect(app.pendingCardSave, isNull);
    expect(await app.cardRepository.getAllCards(), isEmpty);
    expect(channel.commands, isNotEmpty);
    expect(
      channel.commands.map(_selectedName).toSet().intersection({
        _pseName,
        _ppseName,
        _mastercardAid,
        _unionPayAid,
      }),
      isEmpty,
    );
  });
}

AppDependencies _createApp(NfcChannel channel) {
  final app = AppDependencies(
    database: testDatabase(),
    channel: channel,
    bundle: MissingTestAssets(),
    logger: AppLogger(store: MemoryLogStore()),
    settingsStore: MemorySettingsStore({SettingsKeys.autoSaveEnabled: 'true'}),
  );
  addTearDown(app.dispose);
  return app;
}

String? _selectedName(List<int> command) {
  if (command.length < 5 || command[1] != 0xA4 || command[2] != 0x04) {
    return null;
  }
  final end = 5 + command[4];
  if (command.length < end) return null;
  return command
      .sublist(5, end)
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
}

List<int> _hexBytes(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

class _UnknownChannel implements NfcChannel {
  _UnknownChannel({
    this.isoDepConnected = true,
    this.failOnExchange = false,
    this.selectResponse,
  });

  final bool isoDepConnected;
  final bool failOnExchange;
  final List<int>? Function(String? name)? selectResponse;
  final List<List<int>> commands = [];

  @override
  Future<NfcScanResult?> scanOnce() async => NfcScanResult(
    isoDepConnected: isoDepConnected,
    uid: '00112233',
    technologies: const ['IsoDep'],
    timestamp: DateTime.utc(2026, 11, 10),
  );

  @override
  Future<List<int>> transceive(List<int> apdu) async {
    commands.add(List<int>.of(apdu));
    if (failOnExchange) throw _tagLost;
    return selectResponse?.call(_selectedName(apdu)) ?? const [0x6A, 0x82];
  }

  @override
  Future<void> stopScan() async {}
}
