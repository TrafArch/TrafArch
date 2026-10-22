import 'dart:convert';
import 'dart:typed_data';

import '../../domain/interfaces/tag_dictionary.dart';
import '../../domain/models/emv_date_codec.dart';
import '../tlv/hex_codec.dart';

/// 通用 JSON 标签字典实现：EMV 与 PBOC 各自加载独立字典文件，
/// 语义互不混用；未收录标签也能被上层展示原始值。
class JsonTagDictionary implements TagDictionary {
  @override
  final String dictionaryId;
  @override
  final int schemaVersion;

  final Map<String, TagInfo> _entries;

  JsonTagDictionary._(this.dictionaryId, this.schemaVersion, this._entries);

  /// 从 JSON 字符串加载（[rawJson] 来自 assets/dictionaries/*.json）。
  factory JsonTagDictionary.fromJson(String rawJson) {
    final map = jsonDecode(rawJson) as Map<String, dynamic>;
    final id = '${map['dictionaryId'] ?? 'unknown'}';
    final version = (map['schemaVersion'] as num?)?.toInt() ?? 0;
    final entries = <String, TagInfo>{};
    for (final e in (map['entries'] as List? ?? const [])) {
      final m = e as Map<String, dynamic>;
      final tag = '${m['tag']}'.toUpperCase();
      entries[tag] = TagInfo(
        tag: tag,
        name: '${m['name'] ?? ''}',
        nameZh: '${m['nameZh'] ?? m['name'] ?? ''}',
        format: '${m['format'] ?? ''}',
        decoder: '${m['decoder'] ?? 'hex'}',
        sensitivity: '${m['sensitivity'] ?? 'low'}',
        displayPolicy: '${m['displayPolicy'] ?? 'normal'}',
      );
    }
    return JsonTagDictionary._(id, version, entries);
  }

  @override
  TagInfo? lookup(String tagHex) => _entries[tagHex.toUpperCase()];

  @override
  String describe(String tagHex) {
    final info = lookup(tagHex);
    if (info == null) return '未知标签';
    final parts = <String>[info.nameZh];
    if (info.name.isNotEmpty && info.name != info.nameZh) parts.add(info.name);
    if (info.format.isNotEmpty) parts.add('格式 ${info.format}');
    return parts.join(' · ');
  }

  @override
  bool shouldMask(String tagHex) => lookup(tagHex)?.displayPolicy == 'mask';

  @override
  String? decodeValue(String tagHex, List<int> raw) {
    final info = lookup(tagHex);
    final decoder = info?.decoder ?? 'hex';
    switch (decoder) {
      case 'numeric_bcd':
        return _decodeNumericBcd(raw);
      case 'date_yymmdd':
        return _decodeDateYymmdd(raw);
      case 'numeric':
        return _decodeNumeric(raw);
      case 'text':
        return _decodeText(raw);
      case 'hex':
      default:
        return null; // 原始 HEX 已由 TlvNode.rawValueHex 展示
    }
  }

  /// 右对齐半字节填充（'F' 补齐）的数字，用于 PAN 等。
  static String? _decodeNumericBcd(List<int> raw) {
    if (raw.isEmpty) return null;
    final sb = StringBuffer();
    for (final b in raw) {
      final hi = (b >> 4) & 0xF;
      final lo = b & 0xF;
      if (hi <= 9) sb.write(hi);
      if (lo <= 9) sb.write(lo);
    }
    return sb.isEmpty ? null : sb.toString();
  }

  static String? _decodeNumeric(List<int> raw) {
    if (raw.isEmpty) return null;
    final v = raw.fold<int>(0, (a, b) => (a << 8) | b);
    return v.toString();
  }

  static String? _decodeDateYymmdd(List<int> raw) {
    // 3 字节 BCD 是规范形式；同时兼容 4 字节 BCD YYYYMMDD 与 ASCII 数字，
    // 避免部分 Visa / 银联贷记卡的有效期恒解析失败。
    if (raw.isEmpty) return null;
    return EmvDateCodec.decodeHex(HexCodec.encode(raw));
  }

  static String? _decodeText(List<int> raw) {
    if (raw.isEmpty) return null;
    try {
      final s = String.fromCharCodes(raw).trim();
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }

  /// PAN 脱敏：仅保留末 4 位。
  static String maskPan(String pan) {
    if (pan.length <= 4) return pan;
    final tail = pan.substring(pan.length - 4);
    final hidden = '*' * (pan.length - 4);
    final grouped = <String>[];
    for (var i = 0; i < hidden.length; i += 4) {
      grouped.add(hidden.substring(i, (i + 4).clamp(0, hidden.length)));
    }
    final prefix = grouped.join(' ');
    return prefix.isEmpty ? '•••• $tail' : '$prefix $tail';
  }

  /// 供展示层把 [TlvNode] 的原始值按策略转换：解码 + 可选脱敏。
  static String? decodeForDisplay(
    TagDictionary dict,
    String tagHex,
    Uint8List raw,
  ) {
    final decoded = dict.decodeValue(tagHex, raw);
    if (decoded == null) return null;
    final info = dict.lookup(tagHex);
    if (info?.displayPolicy == 'mask' && info?.decoder == 'numeric_bcd') {
      return maskPan(decoded.replaceAll(RegExp(r'\D'), ''));
    }
    return decoded;
  }

  /// 暴露 HEX 工具避免上层重复实现（占位，保持编译依赖）。
  static String hexOf(List<int> b) => HexCodec.encode(b);
}
