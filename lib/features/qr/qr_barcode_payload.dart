import 'dart:convert';

import 'package:mobile_scanner/mobile_scanner.dart';

/// 从单个识别结果提取二维码原始载荷字节。
///
/// 优先取原始二进制（JT/T 1179 为 8 bit byte 模式，文本值会损坏数据），
/// 兜底按 ISO-8859-1 还原文本字节；无法提取时返回 null。
List<int>? qrPayloadOfBarcode(Barcode barcode) {
  final raw = barcode.rawDecodedBytes;
  if (raw is DecodedBarcodeBytes && raw.bytes.isNotEmpty) {
    return raw.bytes.toList();
  }
  final text = barcode.rawValue;
  if (text != null && text.isNotEmpty) {
    try {
      return latin1.encode(text);
    } catch (_) {
      // 文本含非 ISO-8859-1 字符：无法还原原始字节，忽略本次结果
    }
  }
  return null;
}

/// 遍历识别结果，返回首个可提取的二维码载荷；均不可提取时返回 null。
List<int>? qrPayloadOfBarcodes(List<Barcode> barcodes) {
  for (final barcode in barcodes) {
    final payload = qrPayloadOfBarcode(barcode);
    if (payload != null) return payload;
  }
  return null;
}