import 'dart:typed_data';

/// 展示层标签节点：由 [RawTlv] + 标签字典结合生成，含含义、格式与解码值。
class TlvNode {
  final String tagHex;
  final int length;
  final Uint8List rawValue;
  final String? description;
  final String? decodedValue;

  /// 是否按敏感字段脱敏展示（依据字典 displayPolicy）。
  final bool masked;
  final List<TlvNode> children;

  const TlvNode({
    required this.tagHex,
    required this.length,
    required this.rawValue,
    this.description,
    this.decodedValue,
    this.masked = false,
    this.children = const [],
  });

  String get rawValueHex {
    final sb = StringBuffer();
    for (final b in rawValue) {
      sb.write(b.toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    return sb.toString();
  }
}
