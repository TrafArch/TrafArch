/// PBOC（JR/T 0025 系列）应用族识别规则：以中国银联 RID 及常见 PBOC 前缀为据。
/// 仅用于"是否适用 PBOC 解析规则"的判定，不代表识别到具体发卡行。
class PbocVersionRules {
  PbocVersionRules._();

  /// 中国银联 RID（A000000333）—— 覆盖借记（…010101）/ 贷记（…010102）/
  /// 准贷记（…010103）/ 电子现金与 qPBOC 应用族；未命中者由 EMV 规则兜底。
  static const List<String> pbocAidPrefixes = [
    'A000000333', // UnionPay / PBOC
    'D156000101', // 部分 PBOC 应用
  ];

  static bool matches(String aidHex) {
    final aid = aidHex.toUpperCase();
    return pbocAidPrefixes.any(aid.startsWith);
  }
}