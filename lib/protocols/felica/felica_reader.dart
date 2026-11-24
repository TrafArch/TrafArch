library;

import 'cards/card_adapter_registry.dart';
import 'cards/felica_card_adapter.dart';
import 'cards/felica_card_profiles.dart';
import 'cards/octopus_adapter.dart';
import '../octopus/octopus_balance_reader.dart';
import 'models/felica_models.dart';
import 'felica_failure_mapping.dart';
import 'protocol/felica_frame_evidence.dart';
import 'protocol/felica_command.dart';
import 'protocol/felica_protocol.dart';
import 'transport.dart';

/// FeliCa 识读编排：协议探测 → 适配器选择 → 读取 → 统一结果。
///
/// 传输经 [FelicaTransceive] 注入；连接关闭由上层（AppDependencies 的
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
      var polling = await protocol.polling(
        systemCode: preferredSystemCode ?? FelicaCommand.systemCodeWildcard,
      );
      idmHex = polling.idmHex;
      onProgress?.call(20);

      // Lite/Lite-S only support Polling and block access. Request System Code
      // would time out before an adapter can read these cards. Sony assigns IC
      // types F0/F1 and system 88B4; neither alone confirms an AIC product.
      var liteSelected = preferredSystemCode == FelicaKnownSystemCodes.lite;
      if (!liteSelected && (polling.pmm[1] == 0xF0 || polling.pmm[1] == 0xF1)) {
        polling = await protocol.polling(
          systemCode: FelicaKnownSystemCodes.lite,
        );
        idmHex = polling.idmHex;
        liteSelected = true;
      }
      if (liteSelected) {
        systemCodes = [FelicaKnownSystemCodes.lite];
        statuses.add(
          const FelicaReadStatus(
            stage: 'FeliCa 系统码',
            state: FelicaReadState.success,
            message: '已通过 Polling 选择 FeliCa Lite 系统 88B4',
          ),
        );
      } else {
        try {
          systemCodes = await protocol.requestSystemCode(polling.idm);
          statuses.add(
            FelicaReadStatus(
              stage: 'FeliCa 系统码',
              state: FelicaReadState.success,
              message: '卡片返回 ${systemCodes.length} 个系统码',
            ),
          );
        } on FelicaProtocolException catch (e) {
          if (preferredSystemCode == null || e.stopsSession) rethrow;
          systemCodes = [preferredSystemCode];
          statuses.add(
            FelicaReadStatus(
              stage: 'FeliCa 系统码',
              state: FelicaReadState.partial,
              message:
                  'Request System Code 失败（${e.message}），'
                  '回退 Android 探测到的系统码',
              rawResponse: e.raw,
              transportFailure: e.transportFailure,
            ),
          );
        }
      }
      if (systemCodes.isEmpty) {
        systemCodes = [preferredSystemCode ?? FelicaCommand.systemCodeWildcard];
      }
      onProgress?.call(35);

      final knownSystems = [
        for (final code in const [
          FelicaKnownSystemCodes.suica,
          FelicaKnownSystemCodes.octopus,
          FelicaKnownSystemCodes.lite,
        ])
          if (systemCodes.contains(code)) code,
      ];
      if (systemCodes.toSet().length > 1 && knownSystems.isNotEmpty) {
        return await _readSystems(
          protocol,
          knownSystems,
          systemCodes,
          statuses,
        );
      }

      var context = FelicaCardContext(
        idm: idmHex,
        idmBytes: polling.idm,
        systemCodes: systemCodes,
        protocol: protocol,
        serviceProbes: {},
      );
      final adapter = await _registry.select(context);
      if (adapter.cardType == 'amusement_ic' && !liteSelected) {
        // Discovery can list other systems than the one currently selected.
        // Read 88B4 only with the IDm returned by its own Polling response.
        polling = await protocol.polling(
          systemCode: FelicaKnownSystemCodes.lite,
        );
        idmHex = polling.idmHex;
        context = FelicaCardContext(
          idm: idmHex,
          idmBytes: polling.idm,
          systemCodes: systemCodes,
          protocol: protocol,
          serviceProbes: {},
        );
      }
      onStage?.call('FeliCa 卡型匹配：${adapter.cardType}');
      onProgress?.call(45);

      final result = await adapter.read(context);
      onProgress?.call(95);
      return result.copyWith(
        statuses: [...statuses, ...result.statuses],
        frames: protocol.frames,
      );
    } on FelicaProtocolException catch (e) {
      return _failure(
        e.readState,
        e.stage,
        e.message,
        idmHex,
        statuses,
        systemCodes,
        frames: protocol.frames,
        failure: e,
      );
    } catch (e) {
      return _failure(
        FelicaReadState.failed,
        'FeliCa 识读',
        '$e',
        idmHex,
        statuses,
        systemCodes,
        frames: protocol.frames,
      );
    }
  }

  Future<FelicaScanResult> _readSystems(
    FelicaProtocol protocol,
    List<int> knownSystems,
    List<int> advertised,
    List<FelicaReadStatus> discovery,
  ) async {
    final results = <int, FelicaScanResult>{};
    // Preserve the existing Suica / Octopus / Lite preference for the top-level
    // summary. Each adapter sees only what the current Polling selected.
    FelicaScanResult? primary;
    for (final code in knownSystems) {
      final start = protocol.frames.length;
      String? selectedIdm;
      FelicaScanResult result;
      try {
        onStage?.call(
          'FeliCa 系统 ${code.toRadixString(16).padLeft(4, '0').toUpperCase()}',
        );
        final octopus = code == FelicaKnownSystemCodes.octopus;
        final polling = await protocol.polling(
          systemCode: code,
          requestCode: octopus ? OctopusBalanceReader.pollingFrame[4] : 0,
          timeSlot: octopus ? OctopusBalanceReader.pollingFrame[5] : 0,
        );
        selectedIdm = polling.idmHex;
        final context = FelicaCardContext(
          idm: selectedIdm,
          idmBytes: polling.idm,
          systemCodes: [code],
          protocol: protocol,
          serviceProbes: {},
        );
        final adapter = await _registry.select(context);
        result = octopus && adapter is OctopusAdapter
            ? await adapter.read(context, readSelectedBalance: true)
            : await adapter.read(context);
      } on FelicaProtocolException catch (error) {
        result = _failure(
          error.readState,
          error.stage,
          error.message,
          selectedIdm,
          const [],
          [code],
          failure: error,
        );
      }
      result = result.copyWith(
        frames: List.unmodifiable(protocol.frames.skip(start)),
      );
      results[code] = result;
      if (primary == null ||
          (primary.cardType == FelicaCardProfiles.generic.cardType &&
              result.cardType != FelicaCardProfiles.generic.cardType)) {
        primary = result;
      }
      if (protocol.terminalFailure != null) break;
    }
    onProgress?.call(95);
    return primary!.copyWith(
      systemCodes: advertised,
      systemResults: Map.unmodifiable(results),
      frames: protocol.frames,
      statuses: [
        ...discovery,
        ...primary.statuses,
        for (final entry in results.entries)
          if (!identical(entry.value, primary))
            for (final status in entry.value.statuses)
              FelicaReadStatus(
                stage:
                    '${entry.key.toRadixString(16).toUpperCase().padLeft(4, '0')} / ${status.stage}',
                state: status.state,
                message: status.message,
                rawResponse: status.rawResponse,
                transportFailure: status.transportFailure,
              ),
      ],
    );
  }

  static FelicaScanResult _failure(
    FelicaReadState state,
    String stage,
    String message,
    String? idmHex,
    List<FelicaReadStatus> statuses,
    List<int> systemCodes, {
    List<FelicaFrameEvidence> frames = const [],
    FelicaProtocolException? failure,
  }) => FelicaScanResult(
    cardType: FelicaCardProfiles.generic.cardType,
    displayName: 'FeliCa 卡',
    idm: idmHex,
    systemCodes: systemCodes,
    frames: frames,
    statuses: [
      ...statuses,
      FelicaReadStatus(
        stage: stage,
        state: state,
        message: message,
        rawResponse: failure?.raw,
        transportFailure: failure?.transportFailure,
      ),
    ],
    scannedAt: DateTime.now(),
  );
}
