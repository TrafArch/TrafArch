library;

import '../cards/felica_card_profiles.dart';

/// 八达通产品识别的协议层证据。
///
/// 每个 `matches...` 只能由经过官方资料或实卡样本验证的规则生成；
/// 识别器不读取 IDm 前缀、不假设固定系统码，也不把「八达通族」
/// 当作具体产品。
class OctopusDetectionEvidence {
  final bool isNfcF;

  /// 八达通－全国通卡（单港币钱包 + 跨境交通）。
  final bool matchesOctopusTUnionProfile;

  /// 八达通－岭南通（港币 + 岭南通人民币双钱包）。
  final bool matchesLingnanDualProfile;

  /// 深港互通行（港币 + 深圳通人民币双钱包）。
  final bool matchesShenzhenTongDualProfile;

  const OctopusDetectionEvidence({
    required this.isNfcF,
    this.matchesOctopusTUnionProfile = false,
    this.matchesLingnanDualProfile = false,
    this.matchesShenzhenTongDualProfile = false,
  });

  /// 尚未接入任何已验证产品规则时的证据：只表示通道为 NFC-F。
  const OctopusDetectionEvidence.unverified()
    : isNfcF = true,
      matchesOctopusTUnionProfile = false,
      matchesLingnanDualProfile = false,
      matchesShenzhenTongDualProfile = false;
}

/// 八达通产品识别器：只在证据唯一命中时返回产品档案。
///
/// 多个互斥产品规则同时命中（规则错误或卡片异常）时返回 null，
/// 由适配器回退到「已确认八达通族、产品未确认」的安全展示。
class OctopusDetector {
  const OctopusDetector();

  FelicaCardProfile? detect(OctopusDetectionEvidence evidence) {
    if (!evidence.isNfcF) return null;

    final matches = <FelicaCardProfile>[
      if (evidence.matchesOctopusTUnionProfile)
        FelicaCardProfiles.octopusTUnion,
      if (evidence.matchesLingnanDualProfile) FelicaCardProfiles.octopusLingnan,
      if (evidence.matchesShenzhenTongDualProfile)
        FelicaCardProfiles.octopusShenzhen,
    ];

    if (matches.length != 1) return null;
    return matches.single;
  }
}
