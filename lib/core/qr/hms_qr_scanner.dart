import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// 华为统一扫码（Scan Kit）通道（Android 侧见 MainActivity：
/// transit_card_analyzer/hms_scan）。
///
/// 使用 Scan Kit 默认扫码界面：扫码 UI、相机与相册导入入口由 HMS Core
/// 提供；鸿蒙 4.2 等无 GMS 的华为设备走此通道。Scan Kit 为纯端侧能力，
/// 无需 AGC 配置。
const MethodChannel hmsQrScannerChannel =
    MethodChannel('transit_card_analyzer/hms_scan');

/// 当前设备是否具备华为 HMS Core（Scan Kit）扫码能力。
/// 非 Android、通道不可用或探测失败时返回 false（仅用于设置页提示与
/// 扫码通道分流；是否屏蔽应用内相机扫码由「使用系统扫码」开关决定）。
Future<bool> isHmsQrScanAvailable() async {
  try {
    final available = await hmsQrScannerChannel
        .invokeMethod<bool>('isAvailable')
        .timeout(const Duration(seconds: 5));
    return available ?? false;
  } catch (_) {
    return false;
  }
}

/// 华为扫码结果：原始载荷字节与识别码图文件路径。
class HmsQrScanCapture {
  const HmsQrScanCapture({this.bytes, this.bitmapPath});

  /// 扫码文本按 ISO-8859-1 还原的载荷字节
  /// （8 bit byte 模式的高字节可能因 SDK 文本编码转换而损坏）。
  final List<int>? bytes;

  /// 原生侧保存的识别码图 PNG 路径，供纯解码器无损还原字节；
  /// SDK 未提供码图时为 null。
  final String? bitmapPath;
}

/// 调起华为 Scan Kit 默认扫码界面扫描二维码。
///
/// 用户取消或未识别到二维码时返回 null；扫码服务不可用 / 调用失败时
/// 抛出 [PlatformException]、等待超时抛出 [TimeoutException]，由调用方
/// 处理（调用方在开关开启时已整体屏蔽应用内相机组件，失败仅提示不回退）。
Future<HmsQrScanCapture?> scanQrWithHms() async {
  final map = await hmsQrScannerChannel
      .invokeMethod<Map<Object?, Object>>('scan')
      .timeout(const Duration(minutes: 5));
  if (map == null) return null;
  return HmsQrScanCapture(
    bytes: map['bytes'] as Uint8List?,
    bitmapPath: map['bitmapPath'] as String?,
  );
}