library;

import '../felica_hex.dart';
import '../models/felica_models.dart';
import 'felica_card_adapter.dart';
import 'felica_card_profiles.dart';

/// 通用模式：无法确认卡种时使用，只展示标签基础信息与读取状态，
/// 不读取未知服务、不猜测字段。
class GenericFelicaAdapter implements FelicaCardAdapter {
  const GenericFelicaAdapter();

  @override
  String get cardType => FelicaCardProfiles.generic.cardType;

  @override
  Future<bool> matches(FelicaCardContext context) async => true;

  @override
  Future<FelicaScanResult> read(FelicaCardContext context) async {
    final codes = FelicaHex.systemCodeText(context.systemCodes);
    return FelicaScanResult(
      cardType: cardType,
      displayName: FelicaCardProfiles.generic.displayName,
      idm: context.idm,
      systemCodes: context.systemCodes,
      statuses: [
        FelicaReadStatus(
          stage: 'FeliCa 卡型识别',
          state: FelicaReadState.unsupported,
          message: codes.isEmpty
              ? '未匹配已验证的 FeliCa 卡型，未读取未知服务'
              : '系统码 $codes 未匹配已验证卡型，未读取未知服务'
                  '（避免越权访问与误解析）',
        ),
      ],
      scannedAt: DateTime.now(),
    );
  }
}