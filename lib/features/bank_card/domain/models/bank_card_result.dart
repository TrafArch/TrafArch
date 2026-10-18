import '../../../../core/transit/local_card/bank_card_probe.dart';
import 'apdu_trace.dart';
import 'card_application.dart';
import 'parse_issue.dart';

/// 银行卡协议族标识（不表示"识别成功支付网络"，仅表示所用解析规则来源）。
abstract final class BankCardProtocolFamily {
  static const String emv = 'emv';
  static const String pboc = 'pboc';
}

/// 读取整体状态。
enum BankCardStatus {
  /// 未读到 ISO-DEP 应用。
  noCard,

  /// 应用枚举失败（如 PPSE 不支持）。
  enumerationFailed,

  /// 至少读取到一个应用的部分数据。
  partial,

  /// 全部命中应用解析成功。
  success,
}

/// 一次银行卡只读分析的统一结果（结构对齐后续落库表字段）。
/// 实现核心标记接口 [BankCardOutcome]，从而可作为统一识读流程的一等产物回传。
class BankCardResult implements BankCardOutcome {
  final String protocolFamily;
  final DateTime analyzedAt;
  final String parserVersion;
  final BankCardStatus status;
  final List<ParsedApplication> applications;
  final List<ApduTrace> traces;
  final List<ParseIssue> issues;

  const BankCardResult({
    required this.protocolFamily,
    required this.analyzedAt,
    required this.parserVersion,
    required this.status,
    this.applications = const [],
    this.traces = const [],
    this.issues = const [],
  });

  Map<String, dynamic> toJson() => {
        'protocolFamily': protocolFamily,
        'analyzedAt': analyzedAt.toIso8601String(),
        'parserVersion': parserVersion,
        'status': status.name,
        'issues': issues.map((e) => e.toJson()).toList(),
        'traces': traces.map((e) => e.toJson()).toList(),
        // 记录与标签含原始值，序列化仅用于本地展示 / 后续受控存储，
        // 不写入普通运行日志。
      };
}