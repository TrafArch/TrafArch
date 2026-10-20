library;

import '../models/felica_card_type.dart';

/// 卡型档案：卡型标识、显示名、货币口径与产品定义的钱包集合。
///
/// [expectedWallets] 只表示该产品按官方定义应具备的钱包，不代表这些
/// 钱包都能被第三方 NFC 应用读取；实际可读性由适配器的服务发现结果
/// 决定，不能写死在档案里。
class FelicaCardProfile {
  /// 产品类型（区分单钱包全国通与双钱包产品）。
  final FelicaCardType type;

  /// 写入会话 / 档案的稳定卡型标识（与 CardTypes 常量对齐）。
  final String cardType;
  final String displayName;

  /// 主钱包币种（双钱包产品取港币钱包）。
  final String currency;
  final int fractionDigits;

  /// 产品定义是否为双独立钱包。
  final bool isDualWallet;

  /// 产品定义应具备的钱包（按展示顺序）。
  final List<FelicaWalletKind> expectedWallets;

  const FelicaCardProfile({
    required this.type,
    required this.cardType,
    required this.displayName,
    required this.currency,
    required this.fractionDigits,
    this.isDualWallet = false,
    this.expectedWallets = const [],
  });
}

/// 已验证的 FeliCa 系统码（仅作候选特征，不单独据此断言卡型）。
abstract final class FelicaKnownSystemCodes {
  /// Suica / PASMO 等日本铁路系 IC 卡。
  static const int suica = 0x0003;

  /// 八达通使用的 FeliCa 系统（服务码未公开）。
  /// 该码只用于路由到八达通族，不能用来区分全国通 / 岭南通 / 深港互通行。
  static const int octopus = 0x8008;
}

/// Suica SF 服务与块布局（仅使用公开可确认部分）。
abstract final class SuicaServiceCodes {
  /// SF 余额 / 历史记录服务（读属性，帧内小端 0F 09）。
  static const int sf = 0x090F;

  /// 余额块。
  static const int balanceBlock = 0;

  /// 历史记录块范围：块 0 为余额，块 1..20 为历史（从新到旧）。
  static const int historyFirstBlock = 1;
  static const int historyLastBlock = 20;

  /// 单次读取块数（FeliCa 同时访问块数有限，取保守值）。
  static const int historyChunk = 8;
}

abstract final class FelicaCardProfiles {
  static const suica = FelicaCardProfile(
    type: FelicaCardType.suica,
    cardType: 'suica',
    displayName: 'Suica（西瓜卡）',
    currency: 'JPY',
    fractionDigits: 0,
    expectedWallets: [FelicaWalletKind.suicaJpy],
  );

  /// 八达通族兜底档案：已确认是八达通，但尚未验证具体产品。
  static const octopus = FelicaCardProfile(
    type: FelicaCardType.octopus,
    cardType: 'octopus',
    displayName: '八达通卡（FeliCa）',
    currency: 'HKD',
    fractionDigits: 2,
    expectedWallets: [FelicaWalletKind.octopusHkd],
  );

  /// 八达通－全国通卡：单港币钱包 + 跨境交通功能。
  /// cardType 与 CardTypes.octopusTunion 对齐（core 不反向依赖 features）。
  static const octopusTUnion = FelicaCardProfile(
    type: FelicaCardType.octopusTUnion,
    cardType: 'octopus_tunion',
    displayName: '八达通－全国通卡',
    currency: 'HKD',
    fractionDigits: 2,
    expectedWallets: [FelicaWalletKind.octopusHkd],
  );

  /// 八达通－岭南通：港币钱包 + 岭南通人民币钱包。
  static const octopusLingnan = FelicaCardProfile(
    type: FelicaCardType.octopusLingnanDual,
    cardType: 'octopus_lingnan_dual',
    displayName: '八达通－岭南通',
    currency: 'HKD',
    fractionDigits: 2,
    isDualWallet: true,
    expectedWallets: [
      FelicaWalletKind.octopusHkd,
      FelicaWalletKind.lingnanRmb,
    ],
  );

  /// 深港互通行：港币钱包 + 深圳通人民币钱包。
  static const octopusShenzhen = FelicaCardProfile(
    type: FelicaCardType.octopusShenzhenTongDual,
    cardType: 'octopus_shenzhen_tong_dual',
    displayName: '深港互通行',
    currency: 'HKD',
    fractionDigits: 2,
    isDualWallet: true,
    expectedWallets: [
      FelicaWalletKind.octopusHkd,
      FelicaWalletKind.shenzhenTongRmb,
    ],
  );

  static const generic = FelicaCardProfile(
    type: FelicaCardType.unknown,
    cardType: 'felica_generic',
    displayName: '通用 FeliCa 卡',
    currency: '',
    fractionDigits: 0,
  );
}