library;

import 'dart:typed_data';

/// 通用 HEX / 字节工具（地方卡识读模块内聚使用）
class LocalHex {
  static String bytesToHex(List<int> bytes) => bytes
      .map((b) => (b & 0xFF).toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();

  static Uint8List hexToBytes(String hex) {
    final s = hex.replaceAll(' ', '');
    final out = Uint8List(s.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  /// '00A40400' + %02X(数据字节数) + dataHex
  static String wrapSelectCmd(String dataHex) {
    const header = '00A40400';
    final byteLen = dataHex.length ~/ 2;
    return '$header${byteLen.toRadixString(16).padLeft(2, '0').toUpperCase()}$dataHex';
  }

  static int bcdToInt(int b) {
    final v = b & 0xFF;
    return (v >> 4) * 10 + (v & 0xF);
  }

  static int readBEInt(List<int> bytes) {
    var n = 0;
    for (final b in bytes) {
      n = (n << 8) | (b & 0xFF);
    }
    return n;
  }
}
