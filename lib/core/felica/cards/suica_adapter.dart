library;

import '../detection/suica_detector.dart';
import '../felica_hex.dart';
import '../models/felica_card_type.dart';
import '../models/felica_models.dart';
import '../parsers/suica_record_parser.dart';
import '../protocol/felica_command.dart';
import '../protocol/felica_protocol.dart';
import 'felica_card_adapter.dart';
import 'felica_card_profiles.dart';

/// Suica 适配器：服务验证通过后读取 SF 余额块与历史记录块。
///
/// 读取顺序与边界：
/// 1. Request Service 验证 SF 服务 0x090F，不通过则不读取任何块；
/// 2. 读取余额块 0：格式未通过校验时只展示「疑似 Suica」，不解析历史；
/// 3. 余额有效后按 [SuicaServiceCodes.historyChunk] 分批读取块 1..20，
///    某批失败只标记部分成功，不把缺失块补成 0；
/// 4. 记录解析失败保留原始字节，金额 / 时间字段保持 null。
class SuicaAdapter implements FelicaCardAdapter {
  const SuicaAdapter({
    this.detector = const SuicaDetector(),
    this.recordParser = const SuicaRecordParser(),
  });

  final SuicaDetector detector;
  final SuicaRecordParser recordParser;

  static const List<int> _sfServiceCodes = [SuicaServiceCodes.sf];

  @override
  String get cardType => FelicaCardProfiles.suica.cardType;

  @override
  Future<bool> matches(FelicaCardContext context) async {
    if (!context.systemCodes.contains(FelicaKnownSystemCodes.suica)) {
      return false;
    }
    if (context.idmBytes.length != FelicaCommand.idmLength) return false;
    return detector.verifyService(
      idmBytes: context.idmBytes,
      protocol: context.protocol,
    );
  }

  @override
  Future<FelicaScanResult> read(FelicaCardContext context) async {
    final statuses = <FelicaReadStatus>[];
    final rawBlocks = <FelicaRawBlock>[];
    final transactions = <FelicaTransaction>[];

    if (context.idmBytes.length != FelicaCommand.idmLength) {
      return _genericFallback(
        context,
        'IDm 长度异常（${context.idmBytes.length} 字节），未读取 SF 服务',
      );
    }

    final serviceVerified = await detector.verifyService(
      idmBytes: context.idmBytes,
      protocol: context.protocol,
    );
    statuses.add(FelicaReadStatus(
      stage: 'Suica 服务验证',
      state: serviceVerified
          ? FelicaReadState.success
          : FelicaReadState.accessDenied,
      message: serviceVerified
          ? 'SF 服务 0x090F 可用'
          : 'SF 服务 0x090F 不可用（卡内无该服务或访问被拒）',
    ));
    if (!serviceVerified) {
      return _unverifiedService(context, statuses);
    }

    int? balanceYen;
    var walletState = FelicaWalletReadState.notDetected;
    String? walletError;

    try {
      final result = await context.protocol.readWithoutEncryption(
        idm: context.idmBytes,
        serviceCodes: _sfServiceCodes,
        blockListElements: [
          FelicaCommand.blockListElement(0, SuicaServiceCodes.balanceBlock),
        ],
      );
      if (!result.ok) {
        walletState = FelicaWalletReadState.failed;
        walletError =
            '余额块读取失败（状态 ${FelicaHex.wordCode(result.statusCode)}）';
        statuses.add(FelicaReadStatus(
          stage: 'Suica 余额',
          state: FelicaReadState.failed,
          message: walletError,
        ));
        rawBlocks.add(FelicaRawBlock(label: '余额块 0', error: walletError));
      } else if (result.blocks.isEmpty) {
        walletState = FelicaWalletReadState.failed;
        walletError = '余额块读取成功但未返回数据';
        statuses.add(FelicaReadStatus(
          stage: 'Suica 余额',
          state: FelicaReadState.failed,
          message: walletError,
        ));
        rawBlocks.add(FelicaRawBlock(label: '余额块 0', error: walletError));
      } else {
        final block = result.blocks.first;
        rawBlocks.add(FelicaRawBlock(label: '余额块 0', bytes: block));
        if (block.length != FelicaCommand.blockSize) {
          walletState = FelicaWalletReadState.failed;
          walletError = '余额块长度异常：${block.length} 字节（期望 16）';
          statuses.add(FelicaReadStatus(
            stage: 'Suica 余额',
            state: FelicaReadState.partial,
            message: '$walletError，不解析余额与历史记录',
          ));
        } else {
          balanceYen = detector.verifiedBalanceYen(block);
          if (balanceYen == null) {
            walletState = FelicaWalletReadState.failed;
            walletError = '余额超出合理范围，未通过格式校验';
            statuses.add(FelicaReadStatus(
              stage: 'Suica 余额',
              state: FelicaReadState.partial,
              message: '$walletError（块 0），不解析历史记录',
            ));
          } else {
            walletState = FelicaWalletReadState.success;
            statuses.add(FelicaReadStatus(
              stage: 'Suica 余额',
              state: FelicaReadState.success,
              message: '余额 $balanceYen 日元（块 0）',
            ));
          }
        }
      }
    } on FelicaProtocolException catch (e) {
      walletState = FelicaWalletReadState.failed;
      walletError = '余额块读取异常：${e.message}';
      statuses.add(FelicaReadStatus(
        stage: 'Suica 余额',
        state: e.readState,
        message: walletError,
      ));
      rawBlocks.add(FelicaRawBlock(label: '余额块 0', error: walletError));
    }

    if (balanceYen != null) {
      await _readHistory(
        context,
        statuses: statuses,
        rawBlocks: rawBlocks,
        transactions: transactions,
      );
    }

    final detection = detector.detect(
      isNfcF: true,
      systemCode: FelicaHex.systemCodeText(context.systemCodes),
      idm: context.idm,
      hasVerifiedSuicaService: true,
      hasVerifiedSuicaRecord: balanceYen != null,
    );
    statuses.insert(1, detection.toStatus());

    return FelicaScanResult(
      cardType: cardType,
      displayName: detection.displayName,
      cardProductType: FelicaCardType.suica,
      idm: context.idm,
      systemCodes: context.systemCodes,
      wallets: [
        FelicaWallet(
          walletId: FelicaWalletKind.suicaJpy.walletId,
          kind: FelicaWalletKind.suicaJpy,
          name: FelicaWalletKind.suicaJpy.displayName,
          balanceMinorUnits: balanceYen,
          currency: FelicaCardProfiles.suica.currency,
          fractionDigits: FelicaCardProfiles.suica.fractionDigits,
          readState: walletState,
          note: balanceYen == null ? '余额暂不可读取' : null,
          errorMessage: walletError,
        ),
      ],
      transactions: transactions,
      statuses: statuses,
      rawBlocks: rawBlocks,
      scannedAt: DateTime.now(),
    );
  }

  /// 分批读取历史块；失败只标记部分成功，已读到的余额与记录不受影响。
  Future<void> _readHistory(
    FelicaCardContext context, {
    required List<FelicaReadStatus> statuses,
    required List<FelicaRawBlock> rawBlocks,
    required List<FelicaTransaction> transactions,
  }) async {
    const first = SuicaServiceCodes.historyFirstBlock;
    const last = SuicaServiceCodes.historyLastBlock;
    const chunk = SuicaServiceCodes.historyChunk;
    var ok = true;
    var recordCount = 0;

    for (var start = first; start <= last; start += chunk) {
      final end = start + chunk - 1 > last ? last : start + chunk - 1;
      final elements = [
        for (var block = start; block <= end; block++)
          FelicaCommand.blockListElement(0, block),
      ];
      try {
        final result = await context.protocol.readWithoutEncryption(
          idm: context.idmBytes,
          serviceCodes: _sfServiceCodes,
          blockListElements: elements,
        );
        if (!result.ok) {
          ok = false;
          statuses.add(FelicaReadStatus(
            stage: 'Suica 历史记录',
            state: FelicaReadState.partial,
            message: '块 $start-$end 读取失败'
                '（状态 ${FelicaHex.wordCode(result.statusCode)}），停止读取历史',
          ));
          break;
        }
        if (result.blocks.length != elements.length) {
          ok = false;
          statuses.add(FelicaReadStatus(
            stage: 'Suica 历史记录',
            state: FelicaReadState.partial,
            message: '块 $start-$end 返回 ${result.blocks.length} 块'
                '（期望 ${elements.length}），停止读取历史',
          ));
          break;
        }
        for (var i = 0; i < result.blocks.length; i++) {
          final blockNumber = start + i;
          final bytes = result.blocks[i];
          rawBlocks.add(FelicaRawBlock(
            label: '历史块 $blockNumber',
            bytes: bytes,
          ));
          final record = recordParser.parseBlock(
            blockNumber: blockNumber,
            bytes: bytes,
          );
          if (record.isBlank) continue;
          transactions.add(record.toTransaction());
          recordCount++;
        }
      } on FelicaProtocolException catch (e) {
        ok = false;
        statuses.add(FelicaReadStatus(
          stage: 'Suica 历史记录',
          state: e.readState == FelicaReadState.tagLost
              ? FelicaReadState.tagLost
              : FelicaReadState.partial,
          message: '块 $start-$end 读取异常：${e.message}',
        ));
        break;
      }
    }

    if (ok) {
      statuses.add(FelicaReadStatus(
        stage: 'Suica 历史记录',
        state: FelicaReadState.success,
        message: '已读取块 $first-$last，有效记录 $recordCount 条',
      ));
    }
  }

  /// 防御式回退：IDm 异常时不做任何服务访问，按通用 FeliCa 展示。
  static FelicaScanResult _genericFallback(
    FelicaCardContext context,
    String reason,
  ) =>
      FelicaScanResult(
        cardType: FelicaCardProfiles.generic.cardType,
        displayName: FelicaCardProfiles.generic.displayName,
        cardProductType: FelicaCardType.unknown,
        idm: context.idm,
        systemCodes: context.systemCodes,
        statuses: [
          FelicaReadStatus(
            stage: 'Suica 卡型识别',
            state: FelicaReadState.unsupported,
            message: reason,
          ),
        ],
        scannedAt: DateTime.now(),
      );

  /// 服务不可用：不读取块，也不把卡型标成 Suica。
  static FelicaScanResult _unverifiedService(
    FelicaCardContext context,
    List<FelicaReadStatus> statuses,
  ) =>
      FelicaScanResult(
        cardType: FelicaCardProfiles.generic.cardType,
        displayName: FelicaCardProfiles.generic.displayName,
        cardProductType: FelicaCardType.unknown,
        idm: context.idm,
        systemCodes: context.systemCodes,
        statuses: statuses,
        scannedAt: DateTime.now(),
      );
}
