library;

/// 跨境支付信息：描述「用一种货币钱包支付另一种货币场景」的折算口径。
///
/// 仅用于八达通－全国通卡这类单钱包产品：[sourceCurrency] 为卡内实际
/// 钱包币种，[targetCurrency] 为交易场景币种。它不是第二个钱包，不能
/// 把折算后金额当作卡内 [targetCurrency] 余额。
///
/// 汇率字段只允许在卡片实际提供并通过校验后填写；缺失时必须保持 null，
/// 展示层不得自行推算或缓存外部汇率。
class CrossBorderPaymentInfo {
  final String sourceCurrency;
  final String targetCurrency;

  /// 汇率分子 / 分母：1 [sourceCurrency] =
  /// numerator / denominator [targetCurrency]。
  /// 仅当二者均为正数时视为可用。
  final int? exchangeRateNumerator;
  final int? exchangeRateDenominator;

  final DateTime? rateUpdatedAt;
  final DateTime? rateExpiresAt;

  const CrossBorderPaymentInfo({
    required this.sourceCurrency,
    required this.targetCurrency,
    this.exchangeRateNumerator,
    this.exchangeRateDenominator,
    this.rateUpdatedAt,
    this.rateExpiresAt,
  });

  /// 八达通－全国通卡：港币钱包支付内地/澳门交通，由发卡方折算人民币。
  /// 不包含任何汇率数据（官方未通过卡片提供可靠汇率时保持未知）。
  const CrossBorderPaymentInfo.octopusTUnion()
      : sourceCurrency = 'HKD',
        targetCurrency = 'CNY',
        exchangeRateNumerator = null,
        exchangeRateDenominator = null,
        rateUpdatedAt = null,
        rateExpiresAt = null;

  double? get exchangeRate {
    final numerator = exchangeRateNumerator;
    final denominator = exchangeRateDenominator;
    if (numerator == null || denominator == null) return null;
    if (numerator <= 0 || denominator <= 0) return null;
    return numerator / denominator;
  }

  bool get hasVerifiedExchangeRate => exchangeRate != null;

  /// 汇率展示文本（4 位小数）；未提供可靠汇率时返回 null。
  String? get exchangeRateText {
    final rate = exchangeRate;
    if (rate == null) return null;
    return rate.toStringAsFixed(4);
  }

  /// 展示时必须同时检查有效期；过期汇率不得继续用于金额解释。
  bool isExpiredAt(DateTime now) {
    final expiresAt = rateExpiresAt;
    return expiresAt != null && !now.isBefore(expiresAt);
  }
}