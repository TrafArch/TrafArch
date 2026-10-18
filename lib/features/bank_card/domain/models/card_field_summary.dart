// D:\iteam\TrafArch\lib\features\bank_card\domain\models\card_field_summary.dart
import 'tlv_node.dart';

/// 单个提炼出的关键字段：标签号 + 中文名 + 值（已按 decoder 解码，失败回退 HEX）。
class CardField {
  final String tag;
  final String label;
  final String value;

  /// 该标签在字典中标记为敏感（PAN/磁道/姓名等）。
  final bool sensitive;

  const CardField({
    required this.tag,
    required this.label,
    required this.value,
    this.sensitive = false,
  });
}

/// 从一个应用的 FCI / GPO / 各记录标签树中提炼的卡号与交易信息汇总。
class CardFieldSummary {
  final List<CardField> fields;
  const CardFieldSummary(this.fields);

  bool get isEmpty => fields.isEmpty;

  CardField? byTag(String tag) {
    for (final f in fields) {
      if (f.tag == tag) return f;
    }
    return null;
  }

  String? _v(String tag) => byTag(tag)?.value;

  /// 完整卡号（PAN，tag 5A）。
  String? get pan => _v('5A');

  /// 卡号尾 4 位（列表页缩略展示）。
  String? get panTail {
    final p = pan;
    if (p == null) return null;
    final digits = p.replaceAll(RegExp(r'\D'), '');
    return digits.length <= 4 ? digits : digits.substring(digits.length - 4);
  }

  String? get cardholder => _v('5F20');
  String? get expiry => _v('5F24');
  String? get serviceCode => _v('5F30');
  String? get atc => _v('9F36');
}

/// 深度优先查找首个匹配 tag（5A 等常嵌在 70 模板内）。
TlvNode? findTag(List<TlvNode> nodes, String tag) {
  for (final n in nodes) {
    if (n.tagHex == tag && n.rawValue.isNotEmpty) return n;
    final c = findTag(n.children, tag);
    if (c != null) return c;
  }
  return null;
}