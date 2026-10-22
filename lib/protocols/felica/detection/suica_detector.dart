library;

import '../cards/felica_card_profiles.dart';
import '../models/felica_card_type.dart';
import '../models/felica_models.dart';
import '../parsers/suica_record_parser.dart';
import '../protocol/felica_command.dart';
import '../protocol/felica_protocol.dart';
import '../models/felica_service_probe.dart';

/// 识别置信度：只有多项证据同时成立才允许进入 confirmed。
enum RecognitionConfidence { confirmed, probable, insufficient }

extension RecognitionConfidenceLabel on RecognitionConfidence {
  String get label => switch (this) {
    RecognitionConfidence.confirmed => '已确认',
    RecognitionConfidence.probable => '疑似',
    RecognitionConfidence.insufficient => '依据不足',
  };
}

/// 一次 FeliCa 识别的结论：卡型、置信度、证据与展示名。
class FelicaDetectionResult {
  final FelicaCardType type;
  final RecognitionConfidence confidence;
  final List<String> evidence;
  final String displayName;

  const FelicaDetectionResult({
    required this.type,
    required this.confidence,
    required this.evidence,
    required this.displayName,
  });

  bool get isSuica => type == FelicaCardType.suica;

  bool get isConfirmed => confidence == RecognitionConfidence.confirmed;

  bool get isProbable => confidence == RecognitionConfidence.probable;

  bool get isInsufficient => confidence == RecognitionConfidence.insufficient;

  String get evidenceText => evidence.join('；');

  /// 转为读取状态：confirmed → success，probable → partial，
  /// insufficient → unsupported。
  FelicaReadStatus toStatus({String stage = 'Suica 识别'}) {
    final suffix = evidence.isEmpty ? '' : '：$evidenceText';
    return FelicaReadStatus(
      stage: stage,
      state: switch (confidence) {
        RecognitionConfidence.confirmed => FelicaReadState.success,
        RecognitionConfidence.probable => FelicaReadState.partial,
        RecognitionConfidence.insufficient => FelicaReadState.unsupported,
      },
      message: '$displayName（${confidence.label}）$suffix',
    );
  }
}

/// Suica 独立识别器：只负责「是不是 Suica」，不解析卡片数据。
///
/// 证据分层：
/// 1. NFC-F 标签（读取编排层 polling 成功后进入，本类再做防御校验）；
/// 2. 系统码 / IDm 仅作为证据，不能单独认定卡型；
/// 3. Request Service 探测 SF 服务 0x090F；
/// 4. 余额块 16 字节长度 + 金额合理性校验；
/// 5. 服务 + 记录同时通过才 confirmed，仅服务通过为 probable，
///    其余 insufficient（由注册表回退通用 FeliCa 模式）。
class SuicaDetector {
  const SuicaDetector({this.recordParser = const SuicaRecordParser()});

  final SuicaRecordParser recordParser;

  static const List<int> _sfServiceCodes = [SuicaServiceCodes.sf];

  FelicaDetectionResult detect({
    required bool isNfcF,
    required String? systemCode,
    required String? idm,
    required bool hasVerifiedSuicaService,
    required bool hasVerifiedSuicaRecord,
  }) {
    if (!isNfcF) {
      return const FelicaDetectionResult(
        type: FelicaCardType.unknown,
        confidence: RecognitionConfidence.insufficient,
        evidence: ['不是 NFC-F 标签'],
        displayName: '未知卡片',
      );
    }

    final evidence = <String>[];

    if (systemCode != null && systemCode.isNotEmpty) {
      evidence.add('已获取系统代码');
    }

    if (idm != null && idm.isNotEmpty) {
      evidence.add('已获取 IDm');
    }

    if (hasVerifiedSuicaService) {
      evidence.add('匹配已验证的 Suica 服务');
    }

    if (hasVerifiedSuicaRecord) {
      evidence.add('匹配已验证的 Suica 记录格式');
    }

    if (hasVerifiedSuicaService && hasVerifiedSuicaRecord) {
      return FelicaDetectionResult(
        type: FelicaCardType.suica,
        confidence: RecognitionConfidence.confirmed,
        evidence: evidence,
        displayName: 'Suica',
      );
    }

    if (hasVerifiedSuicaService) {
      return FelicaDetectionResult(
        type: FelicaCardType.suica,
        confidence: RecognitionConfidence.probable,
        evidence: evidence,
        displayName: '疑似 Suica',
      );
    }

    return FelicaDetectionResult(
      type: FelicaCardType.unknown,
      confidence: RecognitionConfidence.insufficient,
      evidence: evidence.isEmpty ? ['缺少识别依据'] : evidence,
      displayName: '未知 FeliCa 卡片',
    );
  }

  /// Request Service 探测 SF 服务 0x090F。
  ///
  /// 返回空版本列表 → 服务不可用（false）；卡片无响应继续抛出，
  /// 由 FelicaReader 保留失败原因，不静默降级。
  Future<bool> verifyService({
    required List<int> idmBytes,
    required FelicaProtocol protocol,
  }) async =>
      (await probeService(idmBytes: idmBytes, protocol: protocol)).verified;

  Future<FelicaServiceProbe> probeService({
    required List<int> idmBytes,
    required FelicaProtocol protocol,
  }) async {
    if (idmBytes.length != FelicaCommand.idmLength) {
      return const FelicaServiceProbe(versions: [], frames: []);
    }
    final start = protocol.frames.length;
    try {
      final versions = await protocol.requestService(
        idm: idmBytes,
        serviceCodes: _sfServiceCodes,
      );
      return FelicaServiceProbe(
        versions: versions,
        frames: List.unmodifiable(protocol.frames.skip(start)),
      );
    } on FelicaProtocolException catch (error) {
      if (error.stopsSession) rethrow;
      return FelicaServiceProbe(
        versions: const [],
        error: error,
        frames: List.unmodifiable(protocol.frames.skip(start)),
      );
    }
  }

  /// 余额块校验：16 字节且金额在合理范围内才视为记录格式已验证。
  /// 返回 null 表示未通过（不把失败当 0）。
  int? verifiedBalanceYen(List<int> block) {
    if (block.length != FelicaCommand.blockSize) return null;
    return recordParser.parseBalanceYen(block);
  }
}
