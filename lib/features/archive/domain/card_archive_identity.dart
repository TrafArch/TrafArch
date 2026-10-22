/// 名称的识别依据（[CardArchiveIdentity.identificationSource] 取值）。
abstract final class CardIdentificationSources {
  /// 未声明来源。
  static const String unknown = 'unknown';

  /// 卡种目录：维护的卡号前缀库卡名（发卡机构号段 → 正式卡名）。
  static const String cardCatalog = 'card_catalog';

  /// 发卡机构指纹库（issuerId → 城市 / 运营方 / 卡系）。
  static const String issuerFingerprint = 'issuer_fingerprint';

  /// 城市代码表（卡片城市代码 → 城市名）。
  static const String cityCode = 'city_code';

  /// 仅解析器证据：卡型已确认，名称 / 城市 / 发行方均未知。
  static const String parserOnly = 'parser_only';
}

/// 识别状态（识别结果的可信度分级；不以主观评分替代证据）。
enum CardIdentificationStatus {
  /// 已确认：存在足够的发行方或卡片应用证据。
  confirmed,

  /// 部分识别：已确认卡种，但城市或正式卡名未知。
  partial,

  /// 未识别：只能确定是一张 NFC 卡，不能确认具体交通卡类型。
  unrecognized,
}

/// 卡片身份识别结果：卡种 + 正式名称 + 发行方 + 城市 + 识别依据。
///
/// 无法可靠识别时对应字段保持 null，由展示层回退通用名称
/// （如「交通联合卡」），不猜测具体卡名 / 城市 / 发行方。
class CardArchiveIdentity {
  /// 卡型（[CardTypes] 常量）。
  final String cardType;

  /// 自动识别的正式卡名（如「福路通」）；无可靠证据时为 null。
  final String? officialName;

  /// 发卡机构或运营方。
  final String? issuerName;

  /// 已确认的城市或地区。
  final String? cityName;

  /// 名称的识别依据（[CardIdentificationSources] 常量）。
  final String identificationSource;

  /// 识别置信度（仅在有明确规则依据时记录，如识别引擎的证据权重）。
  final double? confidence;

  const CardArchiveIdentity({
    required this.cardType,
    this.officialName,
    this.issuerName,
    this.cityName,
    this.identificationSource = CardIdentificationSources.unknown,
    this.confidence,
  });

  /// 识别状态：有正式卡名或发行方证据视为已确认；仅确认卡种时为部分识别。
  /// （已建档卡片均来自通过的解析器，因此不会出现 [unrecognized]。）
  CardIdentificationStatus get status {
    if (officialName != null || issuerName != null) {
      return CardIdentificationStatus.confirmed;
    }
    return CardIdentificationStatus.partial;
  }
}
