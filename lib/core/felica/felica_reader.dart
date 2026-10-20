library;

import 'dart:async';

import 'package:flutter/services.dart';

import 'cards/card_adapter_registry.dart';
import 'cards/felica_card_adapter.dart';
import 'cards/felica_card_profiles.dart';
import 'models/felica_models.dart';
import 'protocol/felica_command.dart';
import 'protocol/felica_protocol.dart';
import 'transport.dart';

/// FeliCa 识读编排：协议探测 → 适配器选择 → 读取 → 统一结果。
///
/// 传输经 [FelicaTransceive] 注入；连接关闭由上层（AppState 的
/// stopScan 流程）统一负责，本模块不持有连接生命周期。
class FelicaReader {
  FelicaReader(
    this._transceive, {
    CardAdapterRegistry? registry,
    this.onStage,
    this.onProgress,
  }) : _registry = registry ?? CardAdapterRegistry.defaults();

  final FelicaTransceive _transceive;
  final CardAdapterRegistry _registry;

  /// 阶段回调（供上层写「== 尝试解析：xx ==」日志）。
  final void Function(String stage)? onStage;

  /// 进度回调（0–100）。
  final void Function(int percent)? onProgress;

  Future<FelicaScanResult> read({int? preferredSystemCode}) async {
    final protocol = FelicaProtocol(_transceive);
    final statuses = <FelicaReadStatus>[];
    String? idmHex;
    var systemCodes = <int>[];

    try {
      onStage?.call('FeliCa 协议探测');
      onProgress?.call(5);
      final polling = await protocol.polling(
        systemCode: preferredSystemCode ?? FelicaCommand.systemCodeWildcard,
      );
      idmHex = polling.idmHex;
      onProgress?.call(20);

      try {
        systemCodes = await protocol.requestSystemCode(polling.idm);
        statuses.add(FelicaReadStatus(
          stage: 'FeliCa 系统码',
          state: FelicaReadState.success,
          message: '卡片返回 ${systemCodes.length} 个系统码',
        ));
      } on FelicaProtocolException catch (e) {
        if (preferredSystemCode == null) rethrow;
        systemCodes = [preferredSystemCode];
        statuses.add(FelicaReadStatus(
          stage: 'FeliCa 系统码',
          state: FelicaReadState.partial,
          message: 'Request System Code 失败（${e.message}），'
              '回退 Android 探测到的系统码',
        ));
      }
      if (systemCodes.isEmpty) {
        systemCodes = [
          preferredSystemCode ?? FelicaCommand.systemCodeWildcard,
        ];
      }
      onProgress?.call(35);

      final context = FelicaCardContext(
        idm: idmHex,
        idmBytes: polling.idm,
        systemCodes: systemCodes,
        protocol: protocol,
      );
      final adapter = await _registry.select(context);
      onStage?.call('FeliCa 卡型匹配：${adapter.cardType}');
      onProgress?.call(45);

      final result = await adapter.read(context);
      onProgress?.call(95);
      return result.copyWith(statuses: [...statuses, ...result.statuses]);
    } on PlatformException catch (e) {
      return _failure(
        _mapPlatformCode(e.code),
        'FeliCa 通道',
        '${e.code}：${e.message ?? ''}',
        idmHex,
        statuses,
        systemCodes,
      );
    } on TimeoutException {
      return _failure(
        FelicaReadState.tagLost,
        'FeliCa 通道',
        '通信超时，卡片可能已离开',
        idmHex,
        statuses,
        systemCodes,
      );
    } on FelicaProtocolException catch (e) {
      return _failure(
        e.readState,
        e.stage,
        e.message,
        idmHex,
        statuses,
        systemCodes,
      );
    } catch (e) {
      return _failure(
        FelicaReadState.failed,
        'FeliCa 识读',
        '$e',
        idmHex,
        statuses,
        systemCodes,
      );
    }
  }

  static FelicaReadState _mapPlatformCode(String code) => switch (code) {
        'FELICA_NOT_CONNECTED' ||
        'TAG_NOT_CONNECTED' ||
        'TRANSCEIVE_FAILED' =>
          FelicaReadState.tagLost,
        'FELICA_UNAVAILABLE' => FelicaReadState.unsupported,
        _ => FelicaReadState.failed,
      };

  static FelicaScanResult _failure(
    FelicaReadState state,
    String stage,
    String message,
    String? idmHex,
    List<FelicaReadStatus> statuses,
    List<int> systemCodes,
  ) =>
      FelicaScanResult(
        cardType: FelicaCardProfiles.generic.cardType,
        displayName: 'FeliCa 卡',
        idm: idmHex,
        systemCodes: systemCodes,
        statuses: [
          ...statuses,
          FelicaReadStatus(stage: stage, state: state, message: message),
        ],
        scannedAt: DateTime.now(),
      );
}