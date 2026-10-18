import 'card_field_summary.dart';
import 'card_record.dart';
import 'parse_issue.dart';
import 'tlv_node.dart';

/// 应用目录条目（PPSE / 1PAY / 1RWA 枚举得到）：AID + 标签。
class CardApplication {
  final String aidHex;
  final String? label;

  /// 目录 FCI 中携带的原始标签（选择状态证据）。
  final List<TlvNode> directoryTags;

  /// 应用选择是否成功。
  final bool selected;

  const CardApplication({
    required this.aidHex,
    this.label,
    this.directoryTags = const [],
    this.selected = false,
  });

  String get displayLabel => (label == null || label!.isEmpty) ? aidHex : label!;
}

/// 一个应用解析后的结果：选择证据 + GPO + 记录 + 异常。
class ParsedApplication {
  final CardApplication application;
  final String parserId;

  /// 应用选择响应（FCI）解析出的标签树。
  final List<TlvNode> fciTags;

  /// GET PROCESSING OPTIONS 响应解析出的标签树（含 AIP / AFL）。
  final List<TlvNode> gpoTags;

  final String gpoHex;
  final List<CardRecord> records;
  final List<ParseIssue> issues;

  /// 从各标签树提炼的卡号 / 交易信息汇总（供列表与详情页醒目展示）。
  final CardFieldSummary summary;

  const ParsedApplication({
    required this.application,
    required this.parserId,
    this.fciTags = const [],
    this.gpoTags = const [],
    this.gpoHex = '',
    this.records = const [],
    this.issues = const [],
    this.summary = const CardFieldSummary([]),
  });

  bool get hasData =>
      fciTags.isNotEmpty || gpoTags.isNotEmpty || records.isNotEmpty;
}