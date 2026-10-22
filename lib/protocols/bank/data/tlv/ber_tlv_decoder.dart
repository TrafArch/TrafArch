import 'dart:typed_data';

import '../../../iso7816/ber_tlv.dart';

/// 原始 TLV 节点（协议层，不含业务语义）。
class RawTlv {
  final RawBerTlv? rawNode;
  List<TlvDiagnostic> get diagnostics => rawNode?.diagnostics ?? const [];
  final String tagHex;
  final Uint8List value;
  final bool isConstructed;
  final List<RawTlv> children;

  const RawTlv({
    this.rawNode,
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

  /// Child errors retain their raw container with diagnostics; exhausted
  /// depth/node/byte budgets are fatal and cannot be swallowed by a parent.
  static TlvParseResult decodeDetailed(Uint8List bytes) =>
      BerTlvParser.parse(bytes, policy: TlvPolicy.bank);

  static List<RawTlv> decode(Uint8List bytes) {
    final result = decodeDetailed(bytes);
    result.throwIfInvalid();
    return result.roots.map(_project).toList();
  }

  static RawTlv _project(RawBerTlv node) => RawTlv(
    tagHex: node.tagHex,
    value: node.value,
    isConstructed: node.isConstructed,
    children: node.children.map(_project).toList(),
    rawNode: node,
  );

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
}
