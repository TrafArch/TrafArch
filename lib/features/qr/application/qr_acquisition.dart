import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../platform/qr/gms_qr_scanner.dart';
import '../domain/qr_barcode_payload.dart';
import '../data/qr_dart_decoder.dart';
import '../../../platform/qr/qr_image_picker.dart';

enum QrPayloadOrigin { systemScanner, camera, galleryMlkit, galleryDart }

sealed class QrAcquisitionResult {
  const QrAcquisitionResult();
}

class AcquiredQrPayload extends QrAcquisitionResult {
  AcquiredQrPayload(List<int> bytes, this.origin)
    : bytes = List<int>.unmodifiable(bytes);
  final List<int> bytes;
  final QrPayloadOrigin origin;
}

class QrAcquisitionCancelled extends QrAcquisitionResult {
  const QrAcquisitionCancelled();
}

class QrAcquisitionFailed extends QrAcquisitionResult {
  const QrAcquisitionFailed(this.message);
  final String message;
}

/// Acquisition policy and decoder lifetime, independent of navigation/dialogs.
/// Bytes are passed through; encoding fallback remains in the existing decoders.
class QrAcquisition {
  const QrAcquisition();
  Future<QrAcquisitionResult> scan({
    required bool useSystemScanner,
    required bool systemAvailable,
    required Future<List<int>?> Function() openCamera,
  }) async {
    if (useSystemScanner) {
      if (!systemAvailable) {
        return const QrAcquisitionFailed('系统扫码失败：未检测到 Google Play 服务扫码能力');
      }
      try {
        return _payload(await scanQrWithGms(), QrPayloadOrigin.systemScanner);
      } on PlatformException catch (error) {
        return QrAcquisitionFailed('系统扫码失败：${error.message ?? error.code}');
      } catch (error) {
        return QrAcquisitionFailed('系统扫码失败：$error');
      }
      // System mode never falls through to the in-app camera route.
    }
    return _payload(await openCamera(), QrPayloadOrigin.camera);
  }

  Future<QrAcquisitionResult> gallery() async {
    try {
      final path = await pickQrImageFromGallery();
      if (path == null) return const QrAcquisitionCancelled();
      var mlkitUnavailable = false;
      MobileScannerController? controller;
      try {
        controller = MobileScannerController();
        final capture = await controller.analyzeImage(
          path,
          formats: const [BarcodeFormat.qrCode],
        );
        final bytes = qrPayloadOfBarcodes(
          capture?.barcodes ?? const <Barcode>[],
        );
        if (bytes != null && bytes.isNotEmpty) {
          return AcquiredQrPayload(bytes, QrPayloadOrigin.galleryMlkit);
        }
      } catch (_) {
        mlkitUnavailable = true;
      } finally {
        try {
          await controller?.dispose();
        } catch (_) {
          // Cleanup failure must not discard successfully acquired bytes.
        }
      }
      final bytes = await decodeQrFromImageFile(path);
      if (bytes != null && bytes.isNotEmpty) {
        return AcquiredQrPayload(bytes, QrPayloadOrigin.galleryDart);
      }
      return QrAcquisitionFailed(
        mlkitUnavailable
            ? 'MLKit 不可用（Google Play 服务缺失或无法联网），内置解码也未识别到二维码'
            : '未在该图片中识别到二维码',
      );
    } catch (error) {
      return QrAcquisitionFailed('从相册导入失败：$error');
    }
  }

  QrAcquisitionResult _payload(List<int>? bytes, QrPayloadOrigin origin) =>
      bytes == null || bytes.isEmpty
      ? const QrAcquisitionCancelled()
      : AcquiredQrPayload(bytes, origin);
}
