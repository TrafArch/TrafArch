import 'emv_date_codec.dart';
import 'tlv_node.dart';

/// 单个提炼出的关键字段：标签号 + 中文名 + 值（已按 decoder 解码，失败回退 HEX）。
class CardField {
  final String tag;
  final String label;
  final String value;

  /// 原始编码用于提取 PAN，避免展示字典丢弃非法 BCD 半字节后制造卡号。
  final String? rawValueHex;

  /// 该标签在字典中标记为敏感（PAN/磁道/姓名等）。
  final bool sensitive;

  const CardField({
    required this.tag,
    required this.label,
    required this.value,
    this.rawValueHex,
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

  /// 优先取 5A，其次取 57 / 9F6B 二磁道数据中的 PAN。
  /// 不把磁道中的有效期、服务代码或自由数据拼到卡号后面。
  String? get pan => _panEvidence?.$2;

  String? get panSourceTag => _panEvidence?.$1;

  (String, String)? get _panEvidence {
    for (final tag in ['5A', '57', '9F6B']) {
      final field = byTag(tag);
      if (field == null) continue;
      final number = extractPan(tag, field.rawValueHex ?? field.value);
      if (number != null) return (tag, number);
    }
    return null;
  }

  /// 解码原始压缩数字；仅去除尾部填充，非法的中间半字节不做猜测修复。
  static String? extractPan(String tag, String raw) {
    final value = raw.toUpperCase();
    if (tag == '5A') {
      if (value.length > 20 || !RegExp(r'^[0-9]{1,19}F*$').hasMatch(value)) {
        return null;
      }
      return value.replaceFirst(RegExp(r'F+$'), '');
    }
    if (tag != '57' && tag != '9F6B') return null;
    if (value.length > 38) return null;
    // Track 2: PAN + D + YYMM (4) + service code (3) + discretionary digits.
    return RegExp(r'^([0-9]{1,19})D[0-9]{7,}F?$').firstMatch(value)?.group(1);
  }

  /// 卡号尾 4 位（列表页缩略展示）。
  String? get panTail {
    final p = pan;
    if (p == null) return null;
    final digits = p.replaceAll(RegExp(r'\D'), '');
    return digits.length <= 4 ? digits : digits.substring(digits.length - 4);
  }

  String? get cardholder => _v('5F20');

  /// 有效期：优先 5F24（兼容 BCD / ASCII 变体），缺失时从二磁道 YYMM 提取。
  /// 仅磁道可得年月时返回 `YYYY-MM`，不虚构具体日。
  String? get expiry => _expiryEvidence?.$2;

  String? get expirySourceTag => _expiryEvidence?.$1;

  (String, String)? get _expiryEvidence {
    final field = byTag('5F24');
    if (field != null) {
      final date =
          EmvDateCodec.decodeHex(field.rawValueHex ?? '') ??
          EmvDateCodec.normalize(field.value);
      if (date != null) return ('5F24', date);
    }
    for (final tag in ['57', '9F6B']) {
      final trackField = byTag(tag);
      if (trackField == null) continue;
      final track = _parseTrack2(trackField.rawValueHex ?? trackField.value);
      if (track != null) return (tag, track.expiry);
    }
    return null;
  }

  String? get effectiveDate {
    final field = byTag('5F25');
    if (field == null) return null;
    return EmvDateCodec.decodeHex(field.rawValueHex ?? '') ??
        EmvDateCodec.normalize(field.value);
  }

  /// 5F30 缺失或被解成 4 位时，用二磁道中的 3 位服务代码补齐。
  String? get serviceCode {
    final direct = _v('5F30')?.trim();
    if (direct != null && RegExp(r'^[0-9]{3}$').hasMatch(direct)) return direct;
    for (final tag in ['57', '9F6B']) {
      final field = byTag(tag);
      if (field == null) continue;
      final track = _parseTrack2(field.rawValueHex ?? field.value);
      if (track != null) return track.serviceCode;
    }
    return direct;
  }

  String? get atc => _v('9F36');

  /// 二磁道：PAN + D + YYMM + 3 位服务代码 + 自由数据。
  static _Track2? _parseTrack2(String raw) {
    final value = raw.trim().toUpperCase();
    final match = RegExp(r'^([0-9]{1,19})D([0-9]{4})([0-9]{3})')
        .firstMatch(value);
    if (match == null) return null;
    final yymm = match.group(2)!;
    final year = int.parse(yymm.substring(0, 2));
    final month = int.parse(yymm.substring(2, 4));
    if (month < 1 || month > 12) return null;
    final fullYear = year <= 69 ? 2000 + year : 1900 + year;
    return _Track2(
      expiry: '$fullYear-${month.toString().padLeft(2, '0')}',
      serviceCode: match.group(3)!,
    );
  }
}

class _Track2 {
  final String expiry;
  final String serviceCode;

  const _Track2({required this.expiry, required this.serviceCode});
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
