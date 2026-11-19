library;

import '../felica_failure_mapping.dart';
import '../felica_hex.dart';
import '../models/amusement_ic_data.dart';
import '../models/felica_card_type.dart';
import '../models/felica_models.dart';
import '../parsers/amusement_ic_parser.dart';
import '../protocol/felica_command.dart';
import '../protocol/felica_protocol.dart';
import 'felica_card_adapter.dart';

/// Reads the public Amusement IC identity and encrypted Access Code block.
/// FeliCa Lite does not implement Request Service or Request System Code.
class AmusementIcAdapter implements FelicaCardAdapter {
  const AmusementIcAdapter({this.parser = const AmusementIcParser()});

  final AmusementIcParser parser;

  static const _systemCode = 0x88B4;
  static const _readService = 0x000B;
  static const _identityBlock = 0x82;
  static const _spad0Block = 0x00;

  @override
  String get cardType => 'amusement_ic';

  /// A system code only selects a candidate; the DFC confirms the product.
  /// No probe is sent to unrelated cards, nor while selecting an adapter.
  @override
  Future<bool> matches(FelicaCardContext context) async =>
      context.systemCodes.contains(_systemCode) &&
      context.idmBytes.length == FelicaCommand.idmLength;

  @override
  Future<FelicaScanResult> read(FelicaCardContext context) async {
    final statuses = <FelicaReadStatus>[];
    final rawBlocks = <FelicaRawBlock>[];
    List<int>? identity;
    List<int>? spad0;
    int? dataFormatCode;
    String? issuer;
    String? accessCode;
    String? note;

    FelicaScanResult snapshot() {
      final idBlock = identity;
      final codeBlock = spad0;
      return FelicaScanResult(
        cardType: issuer == null ? 'felica_generic' : cardType,
        displayName: issuer == null ? '通用 FeliCa 卡' : 'Amusement IC（$issuer）',
        cardProductType: issuer == null
            ? FelicaCardType.unknown
            : FelicaCardType.amusementIc,
        idm: context.idm,
        systemCodes: context.systemCodes,
        statuses: statuses,
        rawBlocks: rawBlocks,
        frames: context.protocol.frames,
        amusementIc: idBlock == null
            ? null
            : AmusementIcData(
                accessCode: accessCode,
                issuer: issuer,
                dataFormatCode: dataFormatCode,
                idBlockHex: FelicaHex.bytesToHex(idBlock),
                spad0Hex: codeBlock == null
                    ? null
                    : FelicaHex.bytesToHex(codeBlock),
                note: note,
              ),
        scannedAt: DateTime.now(),
      );
    }

    if (!await matches(context)) {
      statuses.add(
        const FelicaReadStatus(
          stage: 'Amusement IC 识别',
          state: FelicaReadState.unsupported,
          message: '未检测到 Amusement IC 候选系统，未读取数据块',
        ),
      );
      return snapshot();
    }

    final idBlock = await _readBlock(
      context,
      blockNumber: _identityBlock,
      stage: 'Amusement IC 身份块',
      statuses: statuses,
      rawBlocks: rawBlocks,
    );
    identity = idBlock;
    if (idBlock == null) return snapshot();

    // Bytes 0..7 are IDd, retained as evidence rather than substituted for the
    // session's RF IDm. DFC uses big-endian order in the identity block.
    final dfc = (idBlock[8] << 8) | idBlock[9];
    dataFormatCode = dfc;
    issuer = switch (dfc) {
      0x0078 => 'Aime',
      0x0068 => 'e-amusement',
      0x002A || 0x003A => 'Banapass',
      0x0079 => 'NESiCA',
      _ => null,
    };
    if (issuer == null) {
      final message =
          '身份块数据格式码 ${FelicaHex.wordCode(dfc)} '
          '尚未支持，未读取 SPAD0';
      note = message;
      statuses.add(
        FelicaReadStatus(
          stage: 'Amusement IC 识别',
          state: FelicaReadState.unsupported,
          message: message,
        ),
      );
      return snapshot();
    }
    statuses.add(
      FelicaReadStatus(
        stage: 'Amusement IC 识别',
        state: FelicaReadState.success,
        message:
            '身份块数据格式码 ${FelicaHex.wordCode(dfc)} '
            '匹配 $issuer',
      ),
    );

    final codeBlock = await _readBlock(
      context,
      blockNumber: _spad0Block,
      stage: 'Amusement IC Access Code',
      statuses: statuses,
      rawBlocks: rawBlocks,
    );
    spad0 = codeBlock;
    if (codeBlock == null) return snapshot();

    final decoded = parser.parseAccessCode(codeBlock);
    if (decoded == null || !_matchesIssuer(decoded, dfc)) {
      final message = decoded == null
          ? 'SPAD0 未通过 Access Code 格式校验，保留原始数据'
          : 'Access Code 前缀与身份块数据格式码不一致，未确认代码';
      note = message;
      statuses.add(
        FelicaReadStatus(
          stage: 'Amusement IC Access Code',
          state: FelicaReadState.malformed,
          message: message,
        ),
      );
      return snapshot();
    }
    accessCode = decoded;
    statuses.add(
      const FelicaReadStatus(
        stage: 'Amusement IC Access Code',
        state: FelicaReadState.success,
        message: '已读取 Access Code（格式校验通过）',
      ),
    );
    return snapshot();
  }

  Future<List<int>?> _readBlock(
    FelicaCardContext context, {
    required int blockNumber,
    required String stage,
    required List<FelicaReadStatus> statuses,
    required List<FelicaRawBlock> rawBlocks,
  }) async {
    final label = '$stage（${FelicaHex.byteCode(blockNumber)}）';
    try {
      final result = await context.protocol.readWithoutEncryption(
        idm: context.idmBytes,
        serviceCodes: const [_readService],
        blockListElements: [FelicaCommand.blockListElement(0, blockNumber)],
      );
      if (!result.ok) {
        final message =
            '数据块读取被拒绝（状态 '
            '${FelicaHex.wordCode(result.statusCode)}）';
        statuses.add(
          FelicaReadStatus(
            stage: stage,
            state: FelicaReadState.accessDenied,
            message: message,
            rawResponse: result.raw,
          ),
        );
        rawBlocks.add(FelicaRawBlock(label: label, error: message));
        return null;
      }
      // FelicaProtocol validates block count, size and response IDm first.
      final block = result.blocks.single;
      rawBlocks.add(FelicaRawBlock(label: label, bytes: block));
      return block;
    } on FelicaProtocolException catch (error) {
      statuses.add(
        FelicaReadStatus(
          stage: stage,
          state: error.readState,
          message: error.message,
          rawResponse: error.raw,
          transportFailure: error.transportFailure,
        ),
      );
      rawBlocks.add(FelicaRawBlock(label: label, error: error.message));
      return null;
    }
  }

  static bool _matchesIssuer(String code, int dataFormatCode) =>
      switch (dataFormatCode) {
        0x0078 => code.startsWith('500') || code.startsWith('501'),
        0x0068 => code.startsWith('520'),
        0x002A || 0x003A => code.startsWith('510'),
        0x0079 => code.startsWith('530'),
        _ => false,
      };
}
