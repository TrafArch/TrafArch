library;

import '../models/felica_models.dart';
import '../models/felica_service_probe.dart';
import '../protocol/felica_protocol.dart';

/// 适配器上下文：由读取编排层提供 IDm、系统码与协议接口，
/// 不预先塞入全部卡片数据（按服务权限逐批读取）。
class FelicaCardContext {
  final String? idm;
  final List<int> idmBytes;
  final List<int> systemCodes;
  final FelicaProtocol protocol;

  /// Optional scan-local probe cache. Omitted by legacy/manual contexts.
  final Map<String, Future<FelicaServiceProbe>>? serviceProbes;

  const FelicaCardContext({
    required this.idm,
    required this.idmBytes,
    required this.systemCodes,
    required this.protocol,
    this.serviceProbes,
  });
}

/// 卡片适配器：负责识别卡种并解释数据（协议通信由 FelicaProtocol 完成）。
abstract interface class FelicaCardAdapter {
  String get cardType;

  /// 仅在匹配规则足够可靠时返回 true；不得仅凭 IDm 前缀判定。
  Future<bool> matches(FelicaCardContext context);

  Future<FelicaScanResult> read(FelicaCardContext context);
}
