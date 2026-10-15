// 新建文件：lib/features/card_archive/services/card_identification_service.dart
import '../../../core/analysis/tunion_analysis_models.dart';
import '../../../core/card/card_parser.dart';
import '../../../core/data/tunion_knowledge_base.dart';
import '../../../core/transit/city_union/city_union_models.dart';
import '../models/card_archive_identity.dart';
import '../models/card_fingerprint.dart';
import '../models/card_types.dart';

/// 卡片识别引擎：按解析器分派卡种 → 匹配城市 / 发行方 / 正式卡名，
/// 产出可供归档的识别结果（正式名称与自定义名称分离，见 CardRepository）。
///
/// 原则：识别规则集中在本模块（勿写在 UI 中）；没有可靠证据时不猜测
/// 具体卡名 / 城市 / 发行方，由展示层回退通用名称。
class CardIdentificationService {
  /// 交通知识库（卡种目录 = 卡号前缀库、发卡机构指纹、城市码表）。
  final KnowledgeBase knowledge;

  const CardIdentificationService(this.knowledge);

  /// 按解析器分派识别（新增卡型解析器时在此登记识别逻辑）；
  /// 无法确定卡型或无法生成稳定指纹（关键标识未读到）时返回 null，
  /// 调用方跳过建档（不猜测）。
  IdentifiedCard? identify(
    ParsedCard card, {
    CardIdentity? analysisIdentity,
  }) {
    switch (card.parserId) {
      case CardParserIds.tunion:
        return _identifyTUnion(card, analysisIdentity);
      case CardParserIds.cityUnion:
        return _identifyCityUnion(card);
      default:
        return null;
    }
  }

  /// 统一结果构建器：校验并规范化各字段（空串 / 空白视为未知，保持
  /// null 交由展示层回退通用名称），不猜测具体卡名。
  CardArchiveIdentity resolve({
    required String cardType,
    String? officialName,
    String? issuerName,
    String? cityName,
    String source = CardIdentificationSources.unknown,
    double? confidence,
  }) {
    String? normalize(String? value) {
      final trimmed = value?.trim();
      return trimmed == null || trimmed.isEmpty ? null : trimmed;
    }

    return CardArchiveIdentity(
      cardType: cardType,
      officialName: normalize(officialName),
      issuerName: normalize(issuerName),
      cityName: normalize(cityName),
      identificationSource: source,
      confidence: confidence,
    );
  }

  /// 交通联合（JT/T 978.2）：正式卡名与发卡地取自维护的卡种目录
  /// （卡号前缀库：卡号 IIN 优先，回退发卡机构标识）；发行方与城市
  /// 回退发卡机构指纹库与城市码表识别结果。均未命中时保持未知。
  IdentifiedCard? _identifyTUnion(
    ParsedCard card,
    CardIdentity? analysisIdentity,
  ) {
    final info = card.info;
    final catalog = knowledge.cardPrefixes.lookup(info.displayCardNumber) ??
        knowledge.cardPrefixes.lookupByIssuerId(info.issuerId);
    final officialName = catalog?.cardName;
    final issuerName = analysisIdentity?.operatorName;
    final cityName =
        catalog?.city ?? _cityNameOf(info.cityCode) ?? analysisIdentity?.cityName;
    final source = officialName != null
        ? CardIdentificationSources.cardCatalog
        : issuerName != null
            ? CardIdentificationSources.issuerFingerprint
            : cityName != null
                ? CardIdentificationSources.cityCode
                : CardIdentificationSources.parserOnly;
    // 置信度仅采用识别引擎的规则化证据权重（无证据时不记录，不做主观评分）。
    final rawConfidence = analysisIdentity?.confidence;
    final confidence = rawConfidence == null || rawConfidence <= 0
        ? null
        : rawConfidence;
    final identity = resolve(
      cardType: _refineTUnionType(officialName),
      officialName: officialName,
      issuerName: issuerName,
      cityName: cityName,
      source: source,
      confidence: confidence,
    );
    final fingerprint = CardFingerprint.build(
      system: CardParserIds.tunion,
      issuerId: info.issuerId,
      cardNumber: info.displayCardNumber,
    );
    if (fingerprint == null) return null;
    return IdentifiedCard(
      fingerprint: fingerprint,
      identity: identity,
      cardNumber: info.displayCardNumber,
    );
  }

  /// 城市一卡通（CJ/T 331-2016）：卡片标识取自公共应用基本信息文件
  /// （SFI 0x15）；正式卡名与发卡地取自 CU 卡片识别库（城市代码 =
  /// 邮编前四位 / CU 城市项目代码 → 本地卡名称参考 / 城市），识别库
  /// 未收录城市时回退交通联合城市码表；均未命中时保持未知（不猜测）。
  IdentifiedCard? _identifyCityUnion(ParsedCard card) {
    CjT331PublicInfo? publicInfo;
    for (final view in card.cityUnionFiles) {
      if (view is CjT331PublicInfo) {
        publicInfo = view;
        break;
      }
    }
    final catalog = knowledge.cityUnionCards.lookup(publicInfo?.cityCode);
    final officialName = catalog?.cardName;
    final cityName = catalog?.city ?? _cityNameOf(publicInfo?.cityCode);
    final source = officialName != null
        ? CardIdentificationSources.cardCatalog
        : cityName != null
            ? CardIdentificationSources.cityCode
            : CardIdentificationSources.parserOnly;
    final identity = resolve(
      cardType: CardTypes.cityUnion,
      officialName: officialName,
      cityName: cityName,
      source: source,
    );
    final fingerprint = CardFingerprint.build(
      system: CardParserIds.cityUnion,
      issuerId: publicInfo?.issuerCode,
      cardNumber: publicInfo?.applicationSerialNumber,
    );
    if (fingerprint == null) return null;
    return IdentifiedCard(
      fingerprint: fingerprint,
      identity: identity,
      cardNumber: publicInfo?.applicationSerialNumber,
    );
  }

  /// 城市代码 → 城市名（城市码表；大小写归一后查询）；未收录返回 null。
  String? _cityNameOf(String? code) {
    final trimmed = code?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return knowledge.cities.lookup(trimmed.toUpperCase())?.name ??
        knowledge.cities.lookup(trimmed)?.name;
  }

  /// 卡种目录细化规则：按已验证的卡种目录（卡名特征）细化交通联合卡型；
  /// 未命中保持通用卡型 [CardTypes.chinaTunion]。新增卡种时在此维护。
  static const _tunionTypeRefinements = <String, String>{
    '八达通': CardTypes.octopusTunion,
  };

  static String _refineTUnionType(String? officialName) {
    if (officialName != null) {
      for (final entry in _tunionTypeRefinements.entries) {
        if (officialName.contains(entry.key)) return entry.value;
      }
    }
    return CardTypes.chinaTunion;
  }
}

/// 识别输出：待归档的卡片档案快照。
class IdentifiedCard {
  /// 稳定的本地卡片指纹（构建规则见 [CardFingerprint]）。
  final String fingerprint;

  /// 识别结果（卡型 / 正式名称 / 发行方 / 城市 / 依据）。
  final CardArchiveIdentity identity;

  /// 卡号（完整，不脱敏）：交通联合为逻辑卡号（应用序列号去前导 0），
  /// 城市一卡通为 0x15 公共应用基本信息的应用序列号；未读到时为 null。
  final String? cardNumber;

  const IdentifiedCard({
    required this.fingerprint,
    required this.identity,
    this.cardNumber,
  });

  /// 展示名称：正式卡名优先，未识别时回退卡型通用名称（不猜测）。
  String get displayName =>
      identity.officialName ?? cardTypeLabel(identity.cardType);
}
