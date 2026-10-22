library;

import 'package:flutter/services.dart';

/// NFC-F（FeliCa）原始帧通道：发送完整帧（含 LEN），返回完整响应帧。
///
/// 与 [NfcChannel] 共用原生 NFC 连接（同一条 MethodChannel），
/// 仅新增 FeliCa 帧收发方法；连接关闭仍由 stopScan 统一处理。
abstract class FelicaChannel {
  Future<List<int>> transceive(List<int> frame);
}

/// 原生（Android MethodChannel）实现。
abstract interface class SessionFelicaChannel implements FelicaChannel {
  Future<List<int>> exchangeSession(String sessionId, List<int> frame);
}

class MethodChannelFelicaChannel
    implements FelicaChannel, SessionFelicaChannel {
  static const _channel = MethodChannel('transit_card_analyzer/nfc');

  const MethodChannelFelicaChannel();

  @override
  Future<List<int>> exchangeSession(String sessionId, List<int> frame) async {
    final raw = await _channel.invokeMethod<List<dynamic>>('transceiveFelica', {
      'sessionId': sessionId,
      'frame': frame.toList(),
    });
    return raw?.map((e) => (e as num).toInt() & 0xFF).toList() ?? const [];
  }

  @override
  Future<List<int>> transceive(List<int> frame) async {
    // 与既有 transceive 一致：Uint8List 会被编码成 ByteArray，
    // 统一 toList() 归一化为普通 List 再发送。
    final raw = await _channel.invokeMethod<List<dynamic>>(
      'transceiveFelica',
      frame is Uint8List ? frame.toList() : frame,
    );
    // 兼容 ByteArray（Uint8List，0~255）与 List<Byte>（-128~127）。
    return raw?.map((e) => (e as num).toInt() & 0xFF).toList() ?? const [];
  }
}
