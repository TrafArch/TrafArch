/// PPSE 目录名称：2PAY.SYS.DDF01。
const String kEmvPpseName = '2PAY.SYS.DDF01';

/// 境内 PBOC 应用 AID：部分一芯双应用卡的 PPSE 只列出境外 EMV 应用，
/// 需要额外直接探测这些 AID 才能进入境内 PBOC 应用。
///
/// 除银联（A000000333）外，境内人民币清算网络使用各自的 RID：
/// - 万事网联（Mastercard Mainland China）：A0000000108888
/// - 连通 / 美国运通人民币卡（AMEX China）：A00000079001
const List<String> kPbocSupplementalAids = [
  // 银联借记 / 贷记 / 准贷记 / 纯电子现金（qPBOC）
  'A000000333010101',
  'A000000333010102',
  'A000000333010103',
  'A000000333010106',
  // 万事网联
  'A0000000108888',
  // 连通 / 美国运通人民币卡
  'A00000079001',
  // 部分 PBOC 应用只接受 7 字节基础 AID，由卡片以 tag 84 返回完整 AID
  'A0000003330101',
];

/// PBOC 应用族 RID / AID 前缀。
/// 覆盖银联、万事网联、连通（美国运通人民币卡）及少数 D156 前缀应用。
const List<String> kPbocAidPrefixes = [
  'A000000333', // UnionPay / PBOC
  'D156000101', // 部分 PBOC 应用
  'A0000000108888', // 万事网联
  'A000000790', // 连通 / AMEX China
];

/// 是否为境内 PBOC 应用族。
bool isPbocAid(String aidHex) {
  final aid = aidHex.toUpperCase();
  return kPbocAidPrefixes.any(aid.startsWith);
}

/// PPSE 不可用时按序尝试的候选 AID 回退表。
/// 说明：并非完整清单，发卡方可能使用其它 AID；本表合并了国际支付网络
/// 与境内 PBOC 常见 AID，命中任一即视为枚举成功。
const List<String> kEmvCandidateAids = [
  ...kPbocSupplementalAids,
  // Visa / Mastercard / American Express
  'A0000000031010',
  'A0000000041010',
  'A00000002501',
  'A0000000000101',
  // JCB / Discover / Diners（部署可能因卡而异）
  'A0000000651010',
  'A0000001523010',
  'A00000003614710',
  'A00000002771010',
];
