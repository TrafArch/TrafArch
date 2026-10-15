import 'tlv_node.dart';

/// 一条已读取的应用记录（SFI + 记录号 + 原始字节 + 标签树）。
class CardRecord {
  final int sfi;
  final int recordNumber;
  final String rawHex;
  final List<TlvNode> tags;

  /// 记录未按 TLV 结构解析成功时保留原始数据并给出原因。
  final String? parseError;

  const CardRecord({
    required this.sfi,
    required this.recordNumber,
    required this.rawHex,
    required this.tags,
    this.parseError,
  });

  String get sfiHex => '0x${sfi.toRadixString(16).padLeft(2, '0').toUpperCase()}';
}