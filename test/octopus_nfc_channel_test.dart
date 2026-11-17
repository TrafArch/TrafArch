import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/platform/nfc/octopus_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('transit_card_analyzer/octopus_nfc');
  const nfc = MethodChannelOctopusNfcChannel();
  const sessionId = 'octopus-attempt';

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('scans on the dedicated channel and returns session metadata', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'scanOnce');
      expect(call.arguments, {'sessionId': sessionId});
      return {
        'sessionId': sessionId,
        'uid': '01 23 45 67 89 AB CD EF',
        'technologies': ['NfcF'],
        'isoDepConnected': false,
        'felicaConnected': true,
        'timestamp': '2026-11-17T01:02:03Z',
      };
    });

    final scan = await nfc.scanSession(sessionId);
    expect(scan?.sessionId, sessionId);
    expect(scan?.uid, '01 23 45 67 89 AB CD EF');
    expect(scan?.felicaConnected, isTrue);
  });

  test('preserves a null scan response', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await nfc.scanSession(sessionId), isNull);
  });

  test('exchanges the complete NFC-F frame with the same session ID', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'transceiveFelica');
      expect(call.arguments, {
        'sessionId': sessionId,
        'frame': [4, 0, 128, 255],
      });
      return Uint8List.fromList([4, 1, 255, 128]);
    });

    expect(await nfc.exchangeSession(sessionId, [4, 0, 128, 255]), [
      4,
      1,
      255,
      128,
    ]);
  });

  test('missing or empty native response fails the exchange', () async {
    for (final response in [null, Uint8List(0)]) {
      messenger.setMockMethodCallHandler(channel, (_) async => response);
      await expectLater(
        nfc.exchangeSession(sessionId, [2, 0]),
        throwsA(isA<PlatformException>()),
      );
    }
  });

  test(
    'close waits for the physical-retirement reply for the same ID',
    () async {
      final request = Completer<MethodCall>();
      final acknowledgement = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        request.complete(call);
        await acknowledgement.future;
        return null;
      });

      var closed = false;
      final close = nfc.closeSession(sessionId).then((_) => closed = true);
      final received = await request.future;
      expect(received.method, 'stopScan');
      expect(received.arguments, {'sessionId': sessionId});
      expect(closed, isFalse);
      acknowledgement.complete();
      await close;
      expect(closed, isTrue);
    },
  );

  test('native scan, exchange and close errors propagate', () async {
    const closeDetails = {'sessionId': sessionId, 'closing': true};
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'scanOnce':
          throw PlatformException(code: 'NFC_STOPPED');
        case 'transceiveFelica':
          throw PlatformException(code: 'STALE_SESSION');
        case 'stopScan':
          throw PlatformException(
            code: 'NFC_CLOSE_FAILED',
            details: closeDetails,
          );
        default:
          throw MissingPluginException();
      }
    });

    await expectLater(
      nfc.scanSession(sessionId),
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'NFC_STOPPED'),
      ),
    );
    await expectLater(
      nfc.exchangeSession(sessionId, [2, 0]),
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'STALE_SESSION'),
      ),
    );
    await expectLater(
      nfc.closeSession(sessionId),
      throwsA(
        isA<PlatformException>()
            .having((e) => e.code, 'code', 'NFC_CLOSE_FAILED')
            .having((e) => e.details, 'details', closeDetails),
      ),
    );
  });
}
