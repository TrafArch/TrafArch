import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/qr/gms_qr_scanner.dart';
import '../../core/qr/hms_qr_scanner.dart';
import '../../state/app_state.dart';
import 'qr_barcode_payload.dart';
import 'qr_dart_decoder.dart';
import 'qr_image_picker.dart';
import 'qr_scan_page.dart';

/// 扫描二维码 → 解析并写入 [app]，结果以 SnackBar 提示。
///
/// 「使用系统扫码」开关开启时（[AppState.useGmsScanner]），原有应用内
/// 相机扫码组件被整体屏蔽（就当不存在）：扫码只调用 Play 服务扫码界面
/// （Google Code Scanner，应用无需相机权限）；仅当开关关闭时才使用
/// 应用内相机扫码页（需要相机权限）。
Future<void> scanQrAndParse(BuildContext context, AppState app) async {
  final bytes = await _acquireQrBytesFromScanner(context, app);
  if (bytes == null || bytes.isEmpty || !context.mounted) return;
  _notifyResult(context, app.parseQrBytes(bytes));
}

/// 获取扫码字节。
///
/// [AppState.useGmsScanner]（开关开启）时，原有应用内相机扫码模块被
/// 整体屏蔽：优先调起 Play 服务扫码界面；无 GMS 的华为/鸿蒙设备
/// （鸿蒙 4.2 等）改走华为 Scan Kit 扫码界面——均属"系统扫码"，应用侧
/// 不申请相机权限（华为通道由 SDK 界面自行持有相机权限）。两者都
/// 不可用时失败仅提示，不回退相机页。开关关闭时进入应用内相机扫码页。
Future<List<int>?> _acquireQrBytesFromScanner(
  BuildContext context,
  AppState app,
) async {
  if (app.useGmsScanner) {
    if (app.gmsAvailable) {
      try {
        return await scanQrWithGms();
      } on PlatformException catch (e) {
        // GMS 调用失败（探测结果可能过时）且华为扫码可用：改走华为通道
        if (!app.hmsScanAvailable) {
          _notifySystemScanFailed(context, e.message ?? e.code);
          return null;
        }
      } catch (e) {
        _notifySystemScanFailed(context, '$e');
        return null;
      }
    }
    if (app.hmsScanAvailable) {
      try {
        final capture = await scanQrWithHms();
        if (capture == null) return null; // 用户取消
        // 优先用识别码图做字节级无损还原（JT/T 1179 为 8 bit byte 模式，
        // 扫码文本经 SDK 编码转换可能损坏高字节）；失败时回退文本还原字节
        final path = capture.bitmapPath;
        if (path != null) {
          final payload = await decodeQrFromImageFile(path);
          if (payload != null && payload.isNotEmpty) return payload;
        }
        return capture.bytes;
      } on PlatformException catch (e) {
        _notifySystemScanFailed(context, e.message ?? e.code);
        return null;
      } catch (e) {
        _notifySystemScanFailed(context, '$e');
        return null;
      }
    }
    _notifySystemScanFailed(
      context,
      '未检测到 Google Play 服务或华为 HMS Core 扫码能力',
    );
    return null;
  }
  if (!context.mounted) return null;
  return Navigator.of(context).push<List<int>>(
    MaterialPageRoute<List<int>>(builder: (_) => const QrScanPage()),
  );
}

/// 系统扫码失败提示：原有相机扫码组件已整体屏蔽（就当不存在），
/// 失败不回退相机页，仅提示原因。
void _notifySystemScanFailed(BuildContext context, String reason) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('系统扫码失败：$reason')),
  );
}

/// 从相册导入二维码图片 → 解析并写入 [app]，结果以 SnackBar 提示。
///
/// 导入方式与权限与扫码器保持一致：系统照片选择器选图（无需存储权限）→
/// MLKit 识别；MLKit 不可用（无 Google Play 服务 / 无法联网 / 模型未下载）
/// 或未识别时，降级为内置纯 Dart 解码。
Future<void> importQrFromGalleryAndParse(
  BuildContext context,
  AppState app,
) async {
  final List<int>? bytes;
  try {
    bytes = await _pickQrBytesFromGallery(context);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('从相册导入失败：$e')),
      );
    }
    return;
  }
  if (bytes == null || bytes.isEmpty || !context.mounted) return;
  _notifyResult(context, app.parseQrBytes(bytes));
}

/// 打开系统相册选图并解码二维码，返回原始载荷字节。
///
/// 导入方式与权限与扫码器相机链路一致：系统照片选择器选图（无需存储
/// 权限），优先 MLKit 识别；MLKit 不可用或未识别时降级为内置纯 Dart 解码。
/// 用户取消返回 null；识别失败以 SnackBar 提示原因后返回 null。
Future<List<int>?> _pickQrBytesFromGallery(BuildContext context) async {
  final path = await pickQrImageFromGallery();
  if (path == null) return null; // 用户取消

  var mlkitUnavailable = false;
  MobileScannerController? controller;
  try {
    controller = MobileScannerController();
    final capture = await controller.analyzeImage(
      path,
      formats: const [BarcodeFormat.qrCode],
    );
    final payload = qrPayloadOfBarcodes(capture?.barcodes ?? const <Barcode>[]);
    if (payload != null && payload.isNotEmpty) return payload;
  } catch (_) {
    mlkitUnavailable = true;
  } finally {
    try {
      await controller?.dispose();
    } catch (_) {
      // 控制器释放失败不影响本次导入结果
    }
  }

  final payload = await decodeQrFromImageFile(path);
  if (payload != null && payload.isNotEmpty) return payload;

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          mlkitUnavailable
              ? 'MLKit 不可用（Google Play 服务缺失或无法联网），内置解码也未识别到二维码'
              : '未在该图片中识别到二维码',
        ),
      ),
    );
  }
  return null;
}

void _notifyResult(BuildContext context, bool ok) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(ok ? '二维码解析成功' : '二维码解析失败，请查看二维码详情')),
  );
}