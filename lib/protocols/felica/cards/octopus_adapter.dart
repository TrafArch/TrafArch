library;

import '../detection/octopus_detector.dart';
import '../models/cross_border_payment.dart';
import '../models/felica_card_type.dart';
import '../models/felica_models.dart';
import 'felica_card_adapter.dart';
import 'felica_card_profiles.dart';
import 'felica_wallet_factory.dart';

/// 证据采集器：把协议层已验证的特征交给 [OctopusDetector]。
typedef OctopusEvidenceBuilder = OctopusDetectionEvidence Function(
  FelicaCardContext context,
);

/// 默认证据：尚未接入任何已验证的八达通产品规则。
OctopusDetectionEvidence _noVerifiedProductEvidence(
  FelicaCardContext context,
) => const OctopusDetectionEvidence.unverified();

/// 八达通适配器（需实卡验证）。
///
/// 产品模型：
/// - 八达通－全国通卡：只有港币钱包，内地/澳门交通支付按发卡方汇率
///   折算，不存在独立人民币钱包；
/// - 八达通－岭南通 / 深港互通行：港币钱包 + 人民币钱包，两个钱包
///   必须分别验证服务与读取权限。
///
/// 本适配器不读取未公开的八达通服务、不猜测服务码、不绕过访问控制；
/// 未获得已验证产品证据时只展示港币钱包占位，不预设第二钱包。
class OctopusAdapter implements FelicaCardAdapter {
  const OctopusAdapter({
    this.detector = const OctopusDetector(),
    this.evidenceBuilder = _noVerifiedProductEvidence,
  });

  final OctopusDetector detector;
  final OctopusEvidenceBuilder evidenceBuilder;

  @override
  String get cardType => FelicaCardProfiles.octopus.cardType;

  @override
  Future<bool> matches(FelicaCardContext context) async =>
      context.systemCodes.contains(FelicaKnownSystemCodes.octopus);

  @override
  Future<FelicaScanResult> read(FelicaCardContext context) async {
    final product = detector.detect(evidenceBuilder(context));
    final profile = product ?? FelicaCardProfiles.octopus;

    final wallets = markWalletsUnsupported(
      createWalletPlaceholders(profile),
      product == null
          ? '$_serviceUnavailable；产品类型未确认，不预设第二钱包'
          : _serviceUnavailable,
    );

    return FelicaScanResult(
      cardType: profile.cardType,
      displayName: profile.displayName,
      cardProductType: profile.type,
      idm: context.idm,
      systemCodes: context.systemCodes,
      wallets: wallets,
      crossBorder: profile.type == FelicaCardType.octopusTUnion
          ? const CrossBorderPaymentInfo.octopusTUnion()
          : null,
      transitCapability: _transitCapabilityText(profile.type),
      statuses: [
        FelicaReadStatus(
          stage: product == null ? '八达通卡型识别' : '八达通产品识别',
          state: FelicaReadState.unsupported,
          message: _statusMessage(product),
        ),
      ],
      scannedAt: DateTime.now(),
    );
  }
}

const _serviceUnavailable = '本适配器尚未实现并验证该八达通产品的余额与交易记录读取';

String _statusMessage(FelicaCardProfile? product) {
  if (product == null) {
    return '已确认八达通族（系统码 0x8008），但未获得可验证的产品证据'
        '（全国通 / 岭南通 / 深港互通行）；仅建立港币钱包占位，'
        '不预设第二钱包。$_serviceUnavailable';
  }
  return switch (product.type) {
    FelicaCardType.octopusTUnion =>
      '已按已验证证据识别为八达通－全国通卡：'
          '只有港币钱包，内地及澳门交通支付由发卡方按汇率折算，'
          '不构成独立人民币钱包。$_serviceUnavailable',
    FelicaCardType.octopusLingnanDual =>
      '已按已验证证据识别为八达通－岭南通：'
          '产品定义含八达通港币与岭南通人民币两个独立钱包，'
          '两个钱包需分别验证服务与权限，当前均不可读。$_serviceUnavailable',
    FelicaCardType.octopusShenzhenTongDual =>
      '已按已验证证据识别为深港互通行：'
          '产品定义含八达通港币与深圳通人民币两个独立钱包，'
          '两个钱包需分别验证服务与权限，当前均不可读。$_serviceUnavailable',
    _ => _serviceUnavailable,
  };
}

String? _transitCapabilityText(FelicaCardType type) => switch (type) {
  FelicaCardType.octopusTUnion => '八达通及交通联合（内地/澳门按发卡方汇率折算）',
  FelicaCardType.octopusLingnanDual => '八达通及岭南通',
  FelicaCardType.octopusShenzhenTongDual => '八达通及深圳通',
  _ => null,
};
