// D:\iteam\TrafArch\lib\core\emv\data\aid_registry.dart
/// PPSE 目录名称：2PAY.SYS.DDF01。
const String kEmvPpseName = '2PAY.SYS.DDF01';

/// PPSE 不可用时按序尝试的候选 AID 回退表。
/// 说明：并非完整清单，发卡方可能使用其它 AID；本表合并了国际支付网络
/// 与境内 PBOC 常见 AID，命中任一即视为枚举成功。
const List<String> kEmvCandidateAids = [
  // 银联借贷记 / 电子现金（PBOC 3.0）
  'A000000333010101',
  'A000000333010102',
  'A000000333010103',
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