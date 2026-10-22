import '../../../protocols/transit/card_parser.dart';
import '../../../protocols/bank/domain/models/bank_card_result.dart';
import '../../archive/domain/card_types.dart';

String bankFamilyText(String family) => switch (family) {
  BankCardProtocolFamily.mixed => 'EMV + PBOC（按应用分别解析）',
  BankCardProtocolFamily.pboc => 'PBOC（JR/T 0025 系列规则）',
  _ => 'EMV（通用规范规则）',
};

String transitTypeLabel(String? parserId) => cardTypeLabel(switch (parserId) {
  CardParserIds.shanghaiTunion => CardTypes.shanghaiTransitUnion,
  CardParserIds.cityUnion => CardTypes.cityUnion,
  _ => CardTypes.chinaTunion,
});

String transitDisplayName({
  required String? parserId,
  String? identifiedName,
  String? localName,
}) =>
    identifiedName ??
    (parserId == null
        ? '未识别卡片'
        : parserId == CardParserIds.localCard
        ? localName ?? '地方交通卡'
        : transitTypeLabel(parserId));
String bankStatusText(BankCardResult bank, {bool detailed = false}) =>
    switch (bank.status) {
      BankCardStatus.noCard => '未读到应用数据',
      BankCardStatus.enumerationFailed => bankEnumerationText(
        bank,
        detailed: detailed,
      ),
      BankCardStatus.partial => '部分解析成功（仅公开可读数据）',
      BankCardStatus.success => '解析完成',
    };

/// 银行卡枚举失败文案：优先展示具体原因码，避免统一盖成「PPSE 不支持」。
String bankEnumerationText(BankCardResult bank, {bool detailed = false}) {
  for (final issue in bank.issues) {
    if (issue.stage == 'enumeration' || issue.stage == 'ppse') {
      return '应用枚举未完成（${issue.code}）${detailed ? '：${issue.message}' : ''}';
    }
  }
  return '应用枚举未完成';
}

String bankEmptyReason(BankCardResult bank) {
  for (final issue in bank.issues) {
    if (issue.stage == 'ppse') return issue.message;
  }
  return bank.status == BankCardStatus.enumerationFailed
      ? '卡片未返回应用目录（PPSE），或读取被访问条件拒绝'
      : '未读到可展示的应用数据';
}
