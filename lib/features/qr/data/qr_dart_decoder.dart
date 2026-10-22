import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:zxing2/qrcode.dart';

/// 纯 Dart 二维码解码结果。
///
/// 用于 MLKit 不可用（无 Google Play 服务 / 无法联网 / 模型未下载）时
/// 作为相册导入的兜底解码路径，全程无网络、无平台依赖。
class QrDartDecode {
  const QrDartDecode(this.payload);

  /// 二维码原始载荷字节（0x00-0xFF）。
  final List<int> payload;
}

/// 从 RGBA 像素数据解码二维码（同步、纯 Dart，可在后台 isolate 中运行）。
///
/// [rgba] 为每像素 4 字节（依次 R、G、B、A）的原始像素数据；
/// 返回 null 表示未识别到二维码或入参无效。
QrDartDecode? decodeQrFromRgba(Uint8List rgba, int width, int height) {
  if (width <= 0 || height <= 0 || rgba.length < width * height * 4) {
    return null;
  }
  try {
    final pixels = Int32List(width * height);
    for (var i = 0; i < pixels.length; i++) {
      final offset = i * 4;
      pixels[i] =
          0xFF000000 |
          (rgba[offset] << 16) |
          (rgba[offset + 1] << 8) |
          rgba[offset + 2];
    }
    final source = RGBLuminanceSource(width, height, pixels);
    final result = _tryDecode(source) ?? _tryDecode(source.invert());
    if (result == null) return null;

    // ZXing rawBytes contains QR codewords (mode/length/padding included).
    // Transit payloads live in the decoded byte segments instead.
    final byteSegments = result.resultMetadata[ResultMetadataType.byteSegments];
    if (byteSegments is List<Int8List> && byteSegments.isNotEmpty) {
      return QrDartDecode([
        for (final segment in byteSegments)
          for (final byte in segment) byte & 0xff,
      ]);
    }
    final text = result.text;
    if (text.isEmpty) return null;
    return QrDartDecode(utf8.encode(text));
  } catch (_) {
    return null;
  }
}

Result? _tryDecode(LuminanceSource source) {
  try {
    return QRCodeReader().decode(BinaryBitmap(HybridBinarizer(source)));
  } catch (_) {
    return null;
  }
}

/// 从图片文件解码二维码：主 isolate 将图片解码为 RGBA 像素，随后在后台
/// isolate 执行 ZXing 解码，避免阻塞 UI。
///
/// 返回二维码原始载荷字节；未识别到二维码或图片无法读取时返回 null。
Future<List<int>?> decodeQrFromImageFile(String path) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    final fileBytes = await File(path).readAsBytes();
    buffer = await ui.ImmutableBuffer.fromUint8List(fileBytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);

    var targetWidth = descriptor.width;
    var targetHeight = descriptor.height;
    const maxSide = 1800;
    final longest = targetWidth > targetHeight ? targetWidth : targetHeight;
    if (longest > maxSide) {
      final scale = maxSide / longest;
      targetWidth = (targetWidth * scale).round();
      targetHeight = (targetHeight * scale).round();
    }

    codec = await descriptor.instantiateCodec(
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final frame = await codec.getNextFrame();
    image = frame.image;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

    if (byteData == null) return null;
    final rgba = Uint8List.fromList(
      byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      ),
    );
    final decode = await Isolate.run(
      () => decodeQrFromRgba(rgba, targetWidth, targetHeight),
    );
    return decode?.payload;
  } catch (_) {
    return null;
  } finally {
    // 无论成功或中途抛异常，均已创建的原生资源必须全部释放，避免泄漏
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}
