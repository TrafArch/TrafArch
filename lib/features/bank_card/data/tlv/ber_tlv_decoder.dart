import 'dart:typed_data';

/// 原始 TLV 节点（协议层，不含业务语义）。
class RawTlv {
  final String tagHex;
  final Uint8List value;
  final bool isConstructed;
  final List<RawTlv> children;

  const RawTlv({
    required this.tagHex,
    required this.value,
    required this.isConstructed,
    this.children = const [],
  });

  int get length => value.length;
}

/// BER-TLV 解码器（第一版）。
///
/// 职责：解析标签、长度、值，并依据标签的 constructed 位递归解析子节点。
/// 不解释支付业务语义（由标签字典负责）。含最大嵌套深度与节点数上限，
/// 防御异常构造数据导致的无界递归 / 内存放大。
class BerTlvDecoder {
  BerTlvDecoder._();

  static const int _maxDepth = 8;
  static const int _maxNodes = 4096;

  /// 解码顶层对象；[bytes] 为空时返回空列表。
  static List<RawTlv> decode(Uint8List bytes) {
    var count = 0;
    return _decode(bytes, 0, bytes.length, 0, () => ++count > _maxNodes);
  }

  static List<RawTlv> _decode(
    Uint8List bytes,
    int start,
    int end,
    int depth,
    bool Function() overflow,
  ) {
    if (depth > _maxDepth) {
      throw const FormatException('TLV 嵌套深度超限');
    }
    final nodes = <RawTlv>[];
    var offset = start;

    while (offset < end) {
      // 跳过填充字节（0x00 / 0xFF 之间的高位 0 组成的占位）
      if (bytes[offset] == 0x00 || bytes[offset] == 0xFF) {
        offset++;
        continue;
      }
      if (overflow()) {
        throw const FormatException('TLV 节点数超限');
      }

      final tagStart = offset;
      final firstTagByte = bytes[offset++];
      // 单字节标签高 5 位为 11111 时为多字节标签
      if ((firstTagByte & 0x1F) == 0x1F) {
        var count = 0;
        var done = false;
        while (!done) {
          if (offset >= end || count >= 4) {
            throw const FormatException('TLV 标签不完整或过长');
          }
          final next = bytes[offset++];
          count++;
          done = (next & 0x80) == 0;
        }
      }
      final tagBytes = bytes.sublist(tagStart, offset);
      final tagHex = _toHex(tagBytes);
      // 标签前导无效率位为 0（非最短形式）拒绝，避免同义标签混用
      if ((tagBytes[0] & 0xFF) == 0) {
        throw const FormatException('TLV 标签编码不规范');
      }

      if (offset >= end) {
        throw const FormatException('TLV 缺少长度字段');
      }
      final firstLengthByte = bytes[offset++];
      final int length;
      if (firstLengthByte < 0x80) {
        length = firstLengthByte;
      } else {
        final lengthByteCount = firstLengthByte & 0x7F;
        if (lengthByteCount == 0 ||
            lengthByteCount > 3 ||
            offset + lengthByteCount > end) {
          throw const FormatException('TLV 长度编码无效');
        }
        length = bytes
            .sublist(offset, offset + lengthByteCount)
            .fold<int>(0, (v, b) => (v << 8) | b);
        offset += lengthByteCount;
        if (length < 0x80) {
          throw const FormatException('TLV 长度编码不规范（非最短形式）');
        }
      }

      if (length > end - offset) {
        throw const FormatException('TLV 值超出输入数据边界');
      }
      final value = Uint8List.fromList(bytes.sublist(offset, offset + length));
      offset += length;

      // constructed 位：首字节 bit6（0x20）
      final isConstructed = (tagBytes.first & 0x20) != 0;
      List<RawTlv> children = const [];
      if (isConstructed && value.isNotEmpty) {
        try {
          children = _decode(
            Uint8List.fromList(value),
            0,
            value.length,
            depth + 1,
            overflow,
          );
        } on FormatException {
          // 子结构非法时保留原始值，不丢弃数据（不猜测内部结构）
          children = const [];
        }
      }

      nodes.add(RawTlv(
        tagHex: tagHex,
        value: value,
        isConstructed: isConstructed,
        children: children,
      ));
    }
    return nodes;
  }

  /// 深度优先收集所有出现 [tagHex] 的节点（用于跨模板定位标签）。
  static List<RawTlv> findAll(List<RawTlv> roots, String tagHex) {
    final out = <RawTlv>[];
    void walk(List<RawTlv> list) {
      for (final n in list) {
        if (n.tagHex == tagHex) out.add(n);
        if (n.children.isNotEmpty) walk(n.children);
      }
    }
    walk(roots);
    return out;
  }

  /// 查找首个出现 [tagHex] 的节点。
  static RawTlv? findFirst(List<RawTlv> roots, String tagHex) {
    for (final n in roots) {
      if (n.tagHex == tagHex) return n;
      final child = findFirst(n.children, tagHex);
      if (child != null) return child;
    }
    return null;
  }

  static String _toHex(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
}