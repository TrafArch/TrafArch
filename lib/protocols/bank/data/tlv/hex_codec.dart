import 'dart:typed_data';

/// HEX 编解码工具：银行卡模块统一使用大写十六进制字符串展示原始字节。
class HexCodec {
  HexCodec._();

  static String encode(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();

  /// 分组编码（每 [group] 字节一组、空格分隔），用于 PAN 等长值展示。
  static String encodeGrouped(List<int> bytes, {int group = 4}) {
    final sb = StringBuffer();
    for (var i = 0; i < bytes.length; i++) {
      if (i > 0 && i % group == 0) sb.write(' ');
      sb.write(bytes[i].toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    return sb.toString();
  }

  static Uint8List decode(String hex) {
    final normalized = hex.replaceAll(RegExp(r'\s+'), '');
    if (normalized.length.isOdd ||
        !RegExp(r'^[0-9A-Fa-f]*$').hasMatch(normalized)) {
      throw const FormatException('无效的 HEX 字符串');
    }
    final bytes = <int>[];
    for (var i = 0; i < normalized.length; i += 2) {
      bytes.add(int.parse(normalized.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }
}
