library;

import '../../../iso7816/ber_tlv.dart';

/// BER-TLV 节点。
class EmvTlv {
  const EmvTlv(this.tag, this.value, this.children, {this.rawNode});
  final RawBerTlv? rawNode;
  final String tag;
  final List<int> value;
  final List<EmvTlv> children;

  String get valueHex => value
      .map((b) => (b & 0xFF).toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();

  /// 可打印 ASCII 文本（不可打印字符以空格代替），用于标签名等。
  String get ascii {
    final decoded = String.fromCharCodes(
      value.map((b) => b >= 0x20 && b <= 0x7E ? b : 0x20),
    );
    return decoded.trim();
  }
}

/// 极简 BER-TLV 解析器（只读，防御式：越界 / 截断 / 非法长度抛 FormatException）。
class EmvTlvParser {
  /// Rich result retains offsets, original encoding and failure diagnostics.
  static TlvParseResult parseDetailed(List<int> bytes) =>
      BerTlvParser.parse(bytes, policy: TlvPolicy.discovery);

  static List<EmvTlv> parse(List<int> bytes) {
    final result = parseDetailed(bytes);
    result.throwIfInvalid();
    return result.roots.map(_project).toList();
  }

  static EmvTlv _project(RawBerTlv node) => EmvTlv(
    node.tagHex,
    node.value,
    node.children.map(_project).toList(),
    rawNode: node,
  );

  static Iterable<EmvTlv> flatten(Iterable<EmvTlv> nodes) sync* {
    for (final node in nodes) {
      yield node;
      yield* flatten(node.children);
    }
  }

  static String hex(List<int> bytes) => bytes
      .map((b) => (b & 0xFF).toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();

  static List<int> fromHex(String hex) {
    final cleaned = hex.replaceAll(RegExp(r'[\s:]'), '');
    if (cleaned.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(cleaned)) {
      throw const FormatException('十六进制字符串格式错误');
    }
    return [
      for (var i = 0; i < cleaned.length; i += 2)
        int.parse(cleaned.substring(i, i + 2), radix: 16),
    ];
  }
}
