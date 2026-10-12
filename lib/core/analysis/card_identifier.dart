import '../data/knowledge_base.dart';
import '../transit/tunion/tunion_models.dart';
import 'analysis_models.dart';

/// 卡片识别器：多证据融合（发卡机构指纹为主证据，城市代码为辅证），
/// 输出置信度与完整证据链；宁可输出"未知"，不猜测。
class CardIdentifier {
  final KnowledgeBase knowledge;
  CardIdentifier(this.knowledge);

  CardIdentity identify(TUnionCardInfo info) {
    final evidence = <Evidence>[];
    var confidence = 0.0;
    String? cityCode;
    String? cityName;
    String? provinceName;
    String? operatorName;
    String? cardFamily;

    // 证据 1（主）：发卡机构标识 → 指纹库
    final issuerId = info.issuerId;
    if (issuerId != null) {
      final fp = knowledge.issuers.lookup(issuerId);
      if (fp != null) {
        confidence += 0.55;
        cityCode = fp.cityCode;
        cityName = fp.cityName;
        operatorName = fp.operatorName;
        cardFamily = fp.cardFamily;
        evidence.add(Evidence(
          source: 'issuerId',
          weight: 0.55,
          detail: '发卡机构指纹命中 $issuerId'
              '${fp.cityName == null && fp.operatorName == null ? '' : ' → ${fp.cityName ?? fp.operatorName}'}',
        ));
      } else {
        evidence.add(Evidence(
          source: 'issuerId',
          weight: 0,
          detail: '指纹库未收录 $issuerId（可在 assets/data/issuer_fingerprints.json 补充）',
        ));
      }
    }

    // 证据 2（辅）：城市代码 → 城市码表（由卡前缀库 issuer 后 4 位派生）
    final code = info.cityCode;
    if (code != null) {
      final city = knowledge.cities.lookup(code);
      if (city != null) {
        confidence += 0.30;
        cityCode ??= code;
        cityName ??= city.name;
        provinceName ??= city.province;
        evidence.add(Evidence(
          source: 'cityCode',
          weight: 0.30,
          detail: '城市代码 $code → ${city.name}',
        ));
      } else {
        evidence.add(Evidence(
          source: 'cityCode',
          weight: 0,
          detail: '城市代码 $code 未收录（可在 assets/data/card_prefixes.json 补充）',
        ));
      }
    }

    return CardIdentity(
      cityCode: cityCode,
      cityName: cityName,
      provinceName: provinceName,
      operatorName: operatorName,
      cardFamily: cardFamily,
      confidence: confidence > 0.95 ? 0.95 : confidence,
      evidence: evidence,
    );
  }
}