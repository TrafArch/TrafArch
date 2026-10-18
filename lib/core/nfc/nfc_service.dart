import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'nfc_models.dart';

/// NFC 硬件通道层（原 NfcService 拆分后的纯通道，无任何业务状态）。
///
/// 仅负责：发起扫描 / 停止扫描 / 收发 APDU。
/// 会话世代管理、解析编排、状态存储与分析均上移至 state/app_state.dart，
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
class MethodChannelNfcChannel implements NfcChannel {
  static const _channel = MethodChannel('transit_card_analyzer/nfc');

  const MethodChannelNfcChannel();

  @override
  Future<NfcScanResult?> scanOnce() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('scanOnce');
    return raw == null ? null : NfcScanResult.fromMap(raw);
  }

  @override
  Future<void> stopScan() async {
    try {
      // 原生 stopScan 分支必须回传 result；若未回传（原生异常等），
      // 超时兜底，避免上层 await 永久挂起导致扫描状态无法复位
      await _channel.invokeMethod('stopScan').timeout(const Duration(seconds: 1));
    } on TimeoutException {
      // 超时视为已停止，交由上层继续收尾流程
    }
  }

  @override
  Future<List<int>> transceive(List<int> apdu) async {
    // Uint8List 会被 StandardMessageCodec 编码为 ByteArray，而原生 transceive
    // 仅接受 List<Number>（ByteArray 在 Kotlin 非 List，as? List<*> 得 null，
    // 触发「APDU 数据格式错误」）。统一 toList() 归一化为普通 List<int> 再发送。
    final raw = await _channel.invokeMethod<List<dynamic>>(
      'transceive',
      apdu is Uint8List ? apdu.toList() : apdu,
    );
    // 兼容两种原生返回形态：ByteArray（Uint8List，0~255）或 List<Byte>（-128~127）。
    // 统一 & 0xFF 归一化为无符号字节，防止 SW1SW2 判断与解析出错。
    return raw?.map((e) => (e as num).toInt() & 0xFF).toList() ?? const [];
  }
}
