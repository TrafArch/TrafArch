import '../data/terminal_decoder.dart';
import '../transit/tunion/tunion_models.dart';

/// 识别证据：来源、说明与权重（0 表示"出场但未命中"）。
class Evidence {
  final String source;
  final String detail;
  final double weight;

  const Evidence({
    required this.source,
    required this.detail,
    required this.weight,
  });
}

/// 卡片身份识别结果（多证据融合 + 置信度 + 证据链）。
class CardIdentity {
  final String? cityCode;
  final String? cityName;
  final String? provinceName;
  final String? operatorName;
  final String? cardFamily;
  final double confidence;
  final List<Evidence> evidence;

  const CardIdentity({
    this.cityCode,
    this.cityName,
    this.provinceName,
    this.operatorName,
    this.cardFamily,
    required this.confidence,
    this.evidence = const [],
  });

  bool get isKnown => cityName != null || operatorName != null;

  String get confidenceText => '${(confidence * 100).round()}%';
}

/// 钱包摘要。
class WalletSummary {
  final String? cardNumber;
  final int? balanceFen;
  final DateTime? effectiveDate;
  final DateTime? expireDate;
  final bool expired;
  final int? daysRemaining;

  const WalletSummary({
    this.cardNumber,
    this.balanceFen,
    this.effectiveDate,
    this.expireDate,
    required this.expired,
    this.daysRemaining,
  });

  factory WalletSummary.of(TUnionCardInfo info, DateTime now) {
    final exp = info.expireDate;
    return WalletSummary(
      cardNumber: info.displayCardNumber,
      balanceFen: info.balanceFen,
      effectiveDate: info.effectiveDate,
      expireDate: exp,
      expired: exp != null && exp.isBefore(now),
      daysRemaining: exp == null ? null : exp.difference(now).inDays,
    );
  }

  String? get balanceText =>
      balanceFen == null ? null : '¥${(balanceFen! / 100).toStringAsFixed(2)}';
}

/// 行程段（v0.1：一条交易记录 = 一段行程，含终端解码结果；
/// 未来可扩展为进/出站配对的完整行程）。
class TransitTrip {
  final DateTime time;
  final int amountFen;
  final int overdraftLimitFen;
  final bool isConsume;
  final String typeName;
  final int sequence;
  final String terminalId;
  final TerminalLocation? location;
  final String? cityName;
  final String? lineLabel;
  final String? stationLabel;

  /// 站点条目类型（如 "地铁" / "BRT" / "公交"）；
  /// 未命中站点代码表（回退原始编码或无位置数据）时为 null。
  final String? stationType;

  /// 应用分类名称（如 "城市轨道交通" / "公共汽电车"）；
  /// 由 0x1E 过程记录按"时间 + 金额"配对补充，未配对或未收录时为 null。
  final String? appTypeName;

  /// 交易后余额（分）；由 0x1E 过程记录配对补充，未配对时为 null。
  final int? balanceAfterFen;

  /// 是否为进站记录：0 元交易与 0x1E 入站类记录（EC 0x01 / EP 0x03）
  /// 按"时间 + 金额"配对命中时为 true；0x1E 未命中时按 0x1A 记录 1/2
  /// （城市轨道 / 公共汽电车应用信息记录）的进站时间兜底配对。
  /// 展示层据此改显进站时间与站点。
  final bool isEntry;

  const TransitTrip({
    required this.time,
    required this.amountFen,
    required this.overdraftLimitFen,
    required this.isConsume,
    required this.typeName,
    required this.sequence,
    required this.terminalId,
    this.location,
    this.cityName,
    this.lineLabel,
    this.stationLabel,
    this.stationType,
    this.appTypeName,
    this.balanceAfterFen,
    this.isEntry = false,
  });

  String get amountText =>
      '${isConsume ? '-' : '+'}¥${(amountFen / 100).toStringAsFixed(2)}';

  /// 交易后余额展示文本（如 "¥53.40"）；无 0x1E 配对时为 null。
  String? get balanceAfterText => balanceAfterFen == null
      ? null
      : '¥${(balanceAfterFen! / 100).toStringAsFixed(2)}';

  bool get hasLocation =>
      lineLabel != null || stationLabel != null || cityName != null;

  static String _two(int v) => v.toString().padLeft(2, '0');

  String get timeText => '${time.year}-${_two(time.month)}-${_two(time.day)} '
      '${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}';
}

/// JT/T 978 符合性单项状态。
enum ComplianceStatus { pass, warn, fail, info }

/// JT/T 978 符合性检查项。
class ComplianceItem {
  final String id;
  final String title;
  final ComplianceStatus status;
  final String detail;

  const ComplianceItem({
    required this.id,
    required this.title,
    required this.status,
    required this.detail,
  });

  double get weight => switch (status) {
        ComplianceStatus.pass => 1,
        ComplianceStatus.warn => 0.5,
        ComplianceStatus.fail => 0,
        ComplianceStatus.info => 0,
      };
}

/// JT/T 978 符合性报告（info 项不计入覆盖率）。
class ComplianceReport {
  final List<ComplianceItem> items;
  final int scorePercent;

  const ComplianceReport({required this.items, required this.scorePercent});

  int get passCount =>
      items.where((i) => i.status == ComplianceStatus.pass).length;
  int get warnCount =>
      items.where((i) => i.status == ComplianceStatus.warn).length;
  int get failCount =>
      items.where((i) => i.status == ComplianceStatus.fail).length;
}

/// 异常严重级别。
enum AnomalySeverity { info, warn, critical }

/// 异常数据项。
class Anomaly {
  final String code;
  final AnomalySeverity severity;
  final String message;

  const Anomaly({
    required this.code,
    required this.severity,
    required this.message,
  });
}

/// 分析引擎输出契约：UI 只消费这一个模型。
class CardAnalysisResult {
  final CardIdentity identity;
  final WalletSummary wallet;
  final List<TransitTrip> trips;
  final ComplianceReport compliance;
  final List<Anomaly> anomalies;
  final DateTime generatedAt;

  const CardAnalysisResult({
    required this.identity,
    required this.wallet,
    required this.trips,
    required this.compliance,
    required this.anomalies,
    required this.generatedAt,
  });
}