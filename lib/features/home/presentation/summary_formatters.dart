import '../../../protocols/felica/models/felica_models.dart';
import '../../../protocols/felica/models/felica_card_type.dart';

String summaryDate(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

/// 交通联合「互通卡种」推导的全国互联互通启用状态文案：与解析层
/// [TUnionCardInfo.isNationalInteropEnabled] 的 bool? 三态一一对应
/// （true 互通卡 / false 非互通卡 / null 未知），不猜测。
String tunionInteropText(bool? enabled) => switch (enabled) {
  true => '已启用（互通卡）',
  false => '未启用（非互通卡）',
  null => '未知（未读到管理信息文件或部标未定义取值）',
};
String felicaAmountText(FelicaTransaction tx, List<FelicaWallet> wallets) {
  final amount = tx.amountMinorUnits;
  if (amount == null) return '金额未解析';
  final wallet = walletForTransaction(tx, wallets);
  final text = wallet == null ? '$amount（币种未知）' : wallet.formatAmount(amount);
  // Suica 历史记录的金额字段是交易后残高，不能当作单笔交易额展示。
  return tx.amountIsBalance ? '$text（残高）' : text;
}

FelicaWallet? walletForTransaction(
  FelicaTransaction tx,
  List<FelicaWallet> wallets,
) {
  if (tx.walletKind != FelicaWalletKind.unknown) {
    for (final wallet in wallets) {
      if (wallet.kind == tx.walletKind) return wallet;
    }
  }
  final currency = tx.currency;
  if (currency != null) {
    for (final wallet in wallets) {
      if (wallet.currency == currency) return wallet;
    }
  }
  if (wallets.length == 1 && tx.walletKind == FelicaWalletKind.unknown) {
    return wallets.single;
  }
  return null;
}

String felicaTime(FelicaTransaction tx) {
  final time = tx.time;
  if (time == null) return '时间未解析';
  String pad2(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${pad2(time.month)}-${pad2(time.day)} '
      '${pad2(time.hour)}:${pad2(time.minute)}';
}
