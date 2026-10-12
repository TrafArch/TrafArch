import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr/qr.dart';
import 'package:transit_card_analyzer/features/qr/qr_dart_decoder.dart';

void main() {
  group('decodeQrFromRgba', () {
    test('可识别二维码并还原原始字节', () {
      const text = 'TrafArch-qr-dart-fallback-2026';
      final image = _renderQr(text);
      final decoded = decodeQrFromRgba(image.rgba, image.side, image.side);
      expect(decoded, isNotNull);
      expect(decoded!.payload, utf8.encode(text));
    });

    test('纯色图片返回 null', () {
      const side = 200;
      final rgba = Uint8List(side * side * 4)
        ..fillRange(0, side * side * 4, 0xFF);
      expect(decodeQrFromRgba(rgba, side, side), isNull);
    });

    test('入参无效返回 null', () {
      expect(decodeQrFromRgba(Uint8List(0), 0, 0), isNull);
      expect(decodeQrFromRgba(Uint8List(4), 10, 10), isNull);
    });
  });
}

/// 将二维码渲染为 RGBA 像素：每模块 [scale] 像素，四周 [quietZone] 模块静区。
({Uint8List rgba, int side}) _renderQr(
  String text, {
  int scale = 8,
  int quietZone = 4,
}) {
  final qrImage = QrImage(
    QrCode(
      payload: QrPayload.fromString(text),
      errorCorrectLevel: QrErrorCorrectLevel.low,
    ),
  );
  final modules = qrImage.moduleCount;
  final side = (modules + quietZone * 2) * scale;
  final rgba = Uint8List(side * side * 4);
  for (var i = 0; i < rgba.length; i += 4) {
    rgba[i] = 0xFF;
    rgba[i + 1] = 0xFF;
    rgba[i + 2] = 0xFF;
    rgba[i + 3] = 0xFF;
  }
  for (var row = 0; row < modules; row++) {
    for (var col = 0; col < modules; col++) {
      if (!qrImage.isDark(row, col)) continue;
      final startX = (col + quietZone) * scale;
      final startY = (row + quietZone) * scale;
      for (var dy = 0; dy < scale; dy++) {
        var offset = ((startY + dy) * side + startX) * 4;
        for (var dx = 0; dx < scale; dx++) {
          rgba[offset] = 0;
          rgba[offset + 1] = 0;
          rgba[offset + 2] = 0;
          offset += 4;
        }
      }
    }
  }
  return (rgba: rgba, side: side);
}