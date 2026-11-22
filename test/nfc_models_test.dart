import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_models.dart';

void main() {
  test('native UTC read timestamp becomes a device-local instant', () {
    final utc = DateTime.utc(2026, 11, 21, 2, 42, 30);
    final result = NfcScanResult.fromMap({
      'uid': '0102030405060708',
      'technologies': const ['IsoDep'],
      'isoDepConnected': true,
      'timestamp': utc.toIso8601String(),
    });

    expect(result.timestamp.isUtc, isFalse);
    expect(result.timestamp.millisecondsSinceEpoch, utc.millisecondsSinceEpoch);
  });
}
