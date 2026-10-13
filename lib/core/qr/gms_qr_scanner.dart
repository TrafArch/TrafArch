import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Google Play 服务（GMS）扫码通道（Android 侧见 MainActivity：
/// transit_card_analyzer/gms_scan）。
///
/// 使用 Google Code Scanner API：扫码界面与相机由 Google Play 服务提供，
/// 应用无需申请相机权限；设备不具备 GMS 时不可用。
const MethodChannel gmsQrScannerChannel =
    MethodChannel('transit_card_analyzer/gms_scan');

/// 当前设备是否具备 Google Play 服务扫码能力。
/// 非 Android 平台、通道不可用或探测失败时返回 false（仅用于设置页提示
/// 与预热决策；是否屏蔽应用内相机扫码由「使用系统扫码」开关决定）。
Future<bool> isGmsQrScanAvailable() async {
  try {
    final available = await gmsQrScannerChannel
        .invokeMethod<bool>('isAvailable')
        .timeout(const Duration(seconds: 5));
    return available ?? false;
  } catch (_) {
    return false;
  }
}

/// 调起 Google Play 服务扫码界面扫描二维码，返回二维码原始载荷字节。
///
/// 用户取消或未识别到二维码时返回 null；扫码服务不可用 / 调用失败时抛出
/// [PlatformException]、等待超时抛出 [TimeoutException]，由调用方处理
/// （调用方在开关开启时已整体屏蔽应用内相机组件，失败仅提示不回退）。
Future<List<int>?> scanQrWithGms() async {
  final bytes = await gmsQrScannerChannel
      .invokeMethod<Uint8List>('scan')
      .timeout(const Duration(minutes: 5));
  if (bytes == null || bytes.isEmpty) return null;
  return bytes;
}

/// 后台预热 Google Play 服务扫码：原生侧提前创建并缓存扫码器、
/// 预装 barcode_ui 扫码模块，缩短首次调起扫码界面的等待时间。
///
/// 应用启动探测到 GMS 后调用（fire-and-forget）；预热失败静默处理，
/// 不影响扫码主流程（首次扫码仍会按需加载）。
Future<void> warmUpGmsQrScanner() async {
  try {
    await gmsQrScannerChannel.invokeMethod<void>('warmUp');
  } catch (_) {
    // 预热失败不影响扫码主流程
  }
}
