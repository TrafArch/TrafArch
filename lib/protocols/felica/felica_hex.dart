library;

import 'dart:typed_data';

/// FeliCa 模块内部 HEX / 字节序工具：只做无符号字节读写，
/// 不解释任何业务字段（字段语义由各卡种解析器负责）。
class FelicaHex {
  static String bytesToHex(List<int> bytes) => bytes
      .map((b) => (b & 0xFF).toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();

  static Uint8List hexToBytes(String hex) {
    final cleaned = hex.replaceAll(' ', '');
    if (cleaned.isEmpty ||
        cleaned.length.isOdd ||
        !RegExp(r'^[0-9A-Fa-f]+$').hasMatch(cleaned)) {
      throw FormatException('HEX 长度或字符非法：$hex');
    }
    final out = Uint8List(cleaned.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(cleaned.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  /// 小端 16 位无符号。
  static int readLe16(List<int> bytes, [int offset = 0]) =>
      (bytes[offset] & 0xFF) | ((bytes[offset + 1] & 0xFF) << 8);

  /// 小端 16 位有符号（二进制补码）。
  static int readSignedLe16(List<int> bytes, [int offset = 0]) {
    final value = readLe16(bytes, offset);
    return value >= 0x8000 ? value - 0x10000 : value;
  }

  static bool isBcd(int byte) {
    final value = byte & 0xFF;
    return ((value >> 4) & 0x0F) <= 9 && (value & 0x0F) <= 9;
  }

  static int bcdToInt(int byte) {
    final value = byte & 0xFF;
    return ((value >> 4) & 0x0F) * 10 + (value & 0x0F);
  }

  /// 2 位 / 4 位 HEX 文本（状态码、终端码等展示用）。
  static String byteCode(int value) =>
      '0x${(value & 0xFF).toRadixString(16).toUpperCase().padLeft(2, '0')}';

  static String wordCode(int value) =>
      '0x${(value & 0xFFFF).toRadixString(16).toUpperCase().padLeft(4, '0')}';

  static String systemCodeText(List<int> codes) =>
      codes.map(wordCode).join(' / ');
}
