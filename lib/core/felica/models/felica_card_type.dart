library;

/// FeliCa 卡产品类型。
///
/// 八达通全国通卡与双钱包产品是不同业务模型：
/// - [octopusTUnion]：只有港币钱包，内地/澳门交通支付按发卡方汇率折算；
/// - [octopusLingnanDual] / [octopusShenzhenTongDual]：港币钱包 + 人民币钱包。
///
/// [octopus] 只表示已确认八达通族、尚无法验证具体产品；不得为了展示
/// 把未确认的卡归入上述任一产品。
enum FelicaCardType {
  suica,
  octopus,
  octopusTUnion,
  octopusLingnanDual,
  octopusShenzhenTongDual,
  unknown,
}

/// 卡产品所属家族（用于识别与展示分组，不用于读取权限判断）。
enum FelicaCardFamily { suica, octopus, unknown }

extension FelicaCardTypeInfo on FelicaCardType {
  FelicaCardFamily get family => switch (this) {
        FelicaCardType.suica => FelicaCardFamily.suica,
        FelicaCardType.octopus ||
        FelicaCardType.octopusTUnion ||
        FelicaCardType.octopusLingnanDual ||
        FelicaCardType.octopusShenzhenTongDual =>
          FelicaCardFamily.octopus,
        FelicaCardType.unknown => FelicaCardFamily.unknown,
      };

  bool get isOctopusFamily => family == FelicaCardFamily.octopus;
}

/// 钱包类型：一个钱包对应一种货币与一套独立服务，不按汇率换算推导。
enum FelicaWalletKind {
  suicaJpy,
  octopusHkd,
  lingnanRmb,
  shenzhenTongRmb,
  unknown,
}

extension FelicaWalletKindInfo on FelicaWalletKind {
  /// 稳定的钱包标识（用于记录与钱包匹配，展示层不解析该值）。
  String get walletId => switch (this) {
        FelicaWalletKind.suicaJpy => 'suica.sf',
        FelicaWalletKind.octopusHkd => 'octopus.main',
        FelicaWalletKind.lingnanRmb => 'lingnan.rmb',
        FelicaWalletKind.shenzhenTongRmb => 'shenzhen_tong.rmb',
        FelicaWalletKind.unknown => 'unknown.wallet',
      };

  String get displayName => switch (this) {
        FelicaWalletKind.suicaJpy => 'Suica 电子货币',
        FelicaWalletKind.octopusHkd => '八达通钱包',
        FelicaWalletKind.lingnanRmb => '岭南通钱包',
        FelicaWalletKind.shenzhenTongRmb => '深圳通钱包',
        FelicaWalletKind.unknown => '未知钱包',
      };

  String get currency => switch (this) {
        FelicaWalletKind.suicaJpy => 'JPY',
        FelicaWalletKind.octopusHkd => 'HKD',
        FelicaWalletKind.lingnanRmb ||
        FelicaWalletKind.shenzhenTongRmb =>
          'CNY',
        FelicaWalletKind.unknown => '',
      };

  int get fractionDigits => switch (this) {
        FelicaWalletKind.suicaJpy => 0,
        FelicaWalletKind.octopusHkd ||
        FelicaWalletKind.lingnanRmb ||
        FelicaWalletKind.shenzhenTongRmb =>
          2,
        FelicaWalletKind.unknown => 0,
      };
}

/// 单个钱包的读取状态。
///
/// 产品定义存在某钱包（如双钱包产品的人民币钱包）不等于第三方应用
/// 能读取该钱包：[notDetected] / [accessDenied] / [unsupported] 都
/// 必须展示为「暂不可读取」，不能折算成 0 余额。
enum FelicaWalletReadState {
  success,
  unsupported,
  accessDenied,
  notDetected,
  failed,
}

extension FelicaWalletReadStateLabel on FelicaWalletReadState {
  String get label => switch (this) {
        FelicaWalletReadState.success => '读取成功',
        FelicaWalletReadState.unsupported => '不支持',
        FelicaWalletReadState.accessDenied => '无访问权限',
        FelicaWalletReadState.notDetected => '未检测到',
        FelicaWalletReadState.failed => '读取失败',
      };

  bool get isFailure => this != FelicaWalletReadState.success;
}