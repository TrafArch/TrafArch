import 'package:flutter/services.dart';

import 'nfc_models.dart';

/// NFC-F-only discovery and frame exchange for an explicitly identified session.
abstract class OctopusNfcChannel {
  Future<NfcScanResult?> scanSession(String sessionId);
  Future<List<int>> exchangeSession(String sessionId, List<int> frame);
  Future<void> closeSession(String sessionId);
}

class MethodChannelOctopusNfcChannel implements OctopusNfcChannel {
  static const _channel = MethodChannel('transit_card_analyzer/octopus_nfc');

  const MethodChannelOctopusNfcChannel();

  @override
  Future<NfcScanResult?> scanSession(String sessionId) async {
    final raw = await _channel.invokeMapMethod<Object?, Object?>('scanOnce', {
      'sessionId': sessionId,
    });
    return raw == null ? null : NfcScanResult.fromMap(raw);
  }

  @override
  Future<List<int>> exchangeSession(String sessionId, List<int> frame) async {
    final response = await _channel.invokeMethod<Uint8List>(
      'transceiveFelica',
      {'sessionId': sessionId, 'frame': frame.toList()},
    );
    if (response == null || response.isEmpty) {
      throw PlatformException(
        code: 'TRANSCEIVE_FAILED',
        message: 'NFC-F 未返回响应帧',
        details: {'sessionId': sessionId},
      );
    }
    return response;
  }

  @override
  Future<void> closeSession(String sessionId) async {
    await _channel
        .invokeMethod<void>('stopScan', {'sessionId': sessionId})
        .timeout(const Duration(seconds: 12));
  }
}
