import 'dart:typed_data';

import 'jt_t1179_qr_parser.dart';

/// JT/T 1179 二维码展示辅助：为 UI 层提供解析器未直接提供、
/// 且失败时不影响展示的安全解码视图。
extension JtT1179QrDisplay on JtT1179QrData {
  /// 证书发卡机构标识（cn8，压缩 BCD）→ 8 位数字字符串；
  /// 原始值包含非十进制半字节时返回 null（不中断展示）。
  String? get issuerIdText {
    try {
      return issuerCertificate.issuerId;
    } on FormatException {
      return null;
    }
  }

  /// 支付账户号（Cn 编码：数字 2 个一字节，右补十六进制 F）→ 数字字符串；
  /// 出现填充位之外的非法半字节时返回 null。
  String? get paymentAccountDigits => _cnDigits(paymentAccountNumber);

  /// 用户账户号按 Cn 编码解码的结果；无法解码时返回 null
  /// （公开实现样本多为 ASCII，展示层优先 [JtT1179QrData.userAccountNumberText]）。
  String? get userAccountDigits => _cnDigits(userAccountNumber);

  /// Cn（压缩数字）解码：逐半字节取十进制数字，遇 'F' 填充位截断；
  /// 出现其他非十进制半字节或填充位后仍有数字时返回 null。
  static String? _cnDigits(Uint8List bytes) {
    final digits = StringBuffer();
    var padding = false;
    for (final byte in bytes) {
      for (final nibble in [byte >> 4, byte & 0x0F]) {
        if (nibble <= 9) {
          if (padding) return null;
          digits.write(nibble);
        } else if (nibble == 0x0F) {
          padding = true;
        } else {
          return null;
        }
      }
    }
    return digits.isEmpty ? null : digits.toString();
  }
}