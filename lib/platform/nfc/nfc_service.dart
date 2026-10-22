import 'dart:async';

import 'package:flutter/services.dart';

import 'nfc_models.dart';

/// NFC 硬件通道层（原 NfcService 拆分后的纯通道，无任何业务状态）。
///
/// 仅负责：发起扫描 / 停止扫描 / 收发 APDU。
/// 会话世代管理由 ScanController 持有，解析编排由 CardReadCoordinator 负责，
/// 本接口便于在测试中注入假通道（FakeChannel）驱动完整解析管道。
abstract class NfcChannel {
  /// 扫描一次标签；未发现标签返回 null；
  /// 原生错误以 PlatformException 抛出（NFC_DISABLED / NFC_STOPPED 等）。
  Future<NfcScanResult?> scanOnce();

  /// 停止扫描并释放原生连接。
  Future<void> stopScan();

  /// 发送 APDU 并返回响应（含 SW1SW2），失败以 PlatformException 抛出。
  Future<List<int>> transceive(List<int> apdu);
}

/// 原生（Android MethodChannel）通道实现。
abstract interface class SessionNfcChannel implements NfcChannel {
  Future<NfcScanResult?> scanSession(String sessionId);
  Future<void> closeSession(String sessionId);
  Future<List<int>> exchangeSession(String sessionId, List<int> apdu);
}

class MethodChannelNfcChannel implements NfcChannel, SessionNfcChannel {
  static const _channel = MethodChannel('transit_card_analyzer/nfc');

  const MethodChannelNfcChannel();

  @override
  Future<NfcScanResult?> scanSession(String sessionId) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('scanOnce', {
      'sessionId': sessionId,
    });
    return raw == null ? null : NfcScanResult.fromMap(raw);
  }

  @override
  Future<void> closeSession(String sessionId) async {
    await _channel
        .invokeMethod('stopScan', {'sessionId': sessionId})
        .timeout(const Duration(seconds: 12));
  }

  @override
  Future<List<int>> exchangeSession(String sessionId, List<int> apdu) async {
    final raw = await _channel.invokeMethod<List<dynamic>>('transceive', {
      'sessionId': sessionId,
      'apdu': apdu.toList(),
    });
    return raw?.map((e) => (e as num).toInt() & 0xFF).toList() ?? const [];
  }

  @override
  Future<NfcScanResult?> scanOnce() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('scanOnce');
    return raw == null ? null : NfcScanResult.fromMap(raw);
  }

  @override
  Future<void> stopScan() async {
    // Native reports failed retirement after ten seconds. The fallback must
    // exceed that deadline and propagate failure instead of pretending success.
    await _channel
        .invokeMethod('stopScan')
        .timeout(const Duration(seconds: 12));
  }

  @override
  Future<List<int>> transceive(List<int> apdu) async {
    // 保留普通 List<int> 的旧调用格式；原生同时支持 ByteArray。
    final raw = await _channel.invokeMethod<List<dynamic>>(
      'transceive',
      apdu is Uint8List ? apdu.toList() : apdu,
    );
    // 兼容两种原生返回形态：ByteArray（Uint8List，0~255）或 List<Byte>（-128~127）。
    // 统一 & 0xFF 归一化为无符号字节，防止 SW1SW2 判断与解析出错。
    return raw?.map((e) => (e as num).toInt() & 0xFF).toList() ?? const [];
  }
}
