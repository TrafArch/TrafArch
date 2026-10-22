import '../../emv/data/aid_registry.dart';

/// PBOC（JR/T 0025 系列）应用族识别规则：以境内 PBOC RID / AID 前缀为据。
/// 仅用于"是否适用 PBOC 解析规则"的判定，不代表识别到具体发卡行。
class PbocVersionRules {
  PbocVersionRules._();

  /// 银联（A000000333）、万事网联（A0000000108888）、连通 / 美国运通
  /// 人民币卡（A000000790…）及部分 D156 前缀应用；未命中者由 EMV 规则兜底。
  static const List<String> pbocAidPrefixes = kPbocAidPrefixes;

  static bool matches(String aidHex) => isPbocAid(aidHex);
}
