library;

import '../models/felica_card_type.dart';
import '../models/felica_models.dart';
import 'felica_card_profiles.dart';

/// 按产品档案建立钱包占位数据：只表达「产品定义应有哪些钱包」，
/// 不表示已经读取成功。
///
/// - 余额保持 null、状态为 [FelicaWalletReadState.notDetected]；
/// - 全国通卡只建立港币钱包，不建立人民币钱包；
/// - 双钱包产品建立两个独立钱包，读取状态需分别验证后替换。
List<FelicaWallet> createWalletPlaceholders(FelicaCardProfile profile) {
  final wallets = <FelicaWallet>[];
  final seen = <FelicaWalletKind>{};
  for (final kind in profile.expectedWallets) {
    if (!seen.add(kind)) continue;
    final unknown = kind == FelicaWalletKind.unknown;
    wallets.add(
      FelicaWallet(
        walletId: kind.walletId,
        kind: kind,
        name: kind.displayName,
        currency: kind.currency,
        fractionDigits: kind.fractionDigits,
        readState: unknown
            ? FelicaWalletReadState.unsupported
            : FelicaWalletReadState.notDetected,
        note: unknown ? '未知钱包类型，无法建立读取模型' : null,
      ),
    );
  }
  return wallets;
}

/// 已知服务不可读时，把占位钱包统一标记为
/// [FelicaWalletReadState.unsupported]。
///
/// 只改读取状态与原因，不写入任何余额，避免把「不可读」显示成 0。
List<FelicaWallet> markWalletsUnsupported(
  List<FelicaWallet> wallets,
  String reason,
) => [
  for (final wallet in wallets)
    wallet.copyWith(
      readState: FelicaWalletReadState.unsupported,
      errorMessage: reason,
    ),
];
