library;

import '../../card/card_parser.dart';
import '../tunion/tunion_models.dart';
import 'apdu_exchange.dart';
import 'bank_card_probe.dart';
import 'cards/beijing_local_card.dart';
import 'cards/common_card_info.dart';
import 'cards/common_unit_cu.dart';
import 'cards/common_unit_tu.dart';
import 'cards/shenzhentong.dart';
import 'cards/suzhou_card.dart';
import 'cards/suzhou_cika.dart';
import 'cards/tft_local_card.dart';
import 'cards/yangchengtong.dart';
import 'local_card_models.dart';
import 'trips/trip_dedup.dart';
import 'trips/trip_extras.dart';
import 'trips/trip_records.dart';

/// 进度 / 错误回调（轻量抽象，对应原重写工程的 CardReaderCallback）。
/// 会话 APDU 日志由上层 [LocalTransceive]（AppState._transceive）统一记录，
/// 这里仅承载“读取阶段进度 / 失败原因”信号。
abstract class LocalCardReaderCallback {
  void onProgress(int percent);
  void onError(String message);
}

/// 空实现回调（上层不关心进度时的默认值）。
class NoopLocalCardReaderCallback implements LocalCardReaderCallback {
  const NoopLocalCardReaderCallback();
  @override
  void onProgress(int percent) {}
  @override
  void onError(String message) {}
}

/// 一次识读的统一结果：既可能是交通卡（新架构汇总 + 对应卡型 [ParsedCard]），
/// 也可能是银行卡（[BankCardOutcome]）。[parsedCard] 的 parserId 为
/// tunion / cityUnion / localCard，供上层展示与分析链路按其分派；
/// [bank] 非空时表示本次识读命中银行卡（EMV / PBOC）只读流程。
class LocalReadOutcome {
  const LocalReadOutcome.transit({
    required this.readResult,
    required this.parsedCard,
  }) : bank = null;

  const LocalReadOutcome.bankCard(BankCardOutcome outcome)
      : readResult = null,
        parsedCard = null,
        bank = outcome;

  final ReadResult? readResult;
  final ParsedCard? parsedCard;
  final BankCardOutcome? bank;

  /// 是否为银行卡识读产物（交通应用链路未命中时的一等阶段结果）。
  bool get isBankCard => bank != null;
}

/// 交通卡 / 银行卡统一识读编排主体（新模块为主）：按优先级串联各读法，
/// 命中即返回。
/// 1) 交通联合（JT/T 978.2）富识读 [CommonUnitTu]；
/// 2) 城市一卡通（CJ/T 331-2016）富识读 [CommonUnitCu]；
///    交通联合命中后再独立探测城市一卡通应用，同一张物理卡上两个应用都读到
///    时合并为双应用结果（[ParsedCard.dualApplication]，见 _mergeDual）；
/// 3) 地方交通卡逐城市探测（北京 / 羊城通 / 深圳通 / 苏州(苏薪·计次) / 天府通），
///    命中后读取共用卡信息与行程 / 扩展记录，最后余额重建 + 换乘去重；
/// 4) 银行卡（EMV / PBOC）只读探测 [BankCardProbe]——与交通卡同为流程内的
///    一等阶段，而非上层单独触发的兜底分支。
/// 全部阶段均不命中时返回 null。
/// 传输经 [LocalTransceive] 注入（与 NfcChannel.transceive 同签名），
/// 模块不依赖任何上层状态，可独立复用与测试。
class LocalCardReader {
  LocalCardReader(
    this._transceive, {
    this.callback = const NoopLocalCardReaderCallback(),
    this.onStage,
    this.bankProbe,
  });

  final LocalTransceive _transceive;
  final LocalCardReaderCallback callback;

  /// 识读阶段回调（供上层写「== 尝试解析：xx ==」日志；可空）。
  final void Function(String stage)? onStage;

  /// 银行卡（EMV / PBOC）探测抽象；为空时流程只做交通卡识读。
  final BankCardProbe? bankProbe;

  Future<LocalReadOutcome?> read() async {
    final transit = await _readTransit();
    if (transit != null) return transit;
    // 交通应用链路未命中：作为统一识读流程的一等阶段执行银行卡只读探测。
    return _readBank();
  }

  Future<LocalReadOutcome?> _readBank() async {
    final probe = bankProbe;
    if (probe == null) return null;
    try {
      onStage?.call('银行卡（EMV / PBOC）');
      callback.onProgress(30);
      final outcome = await probe.probe(_transceive);
      if (outcome == null) return null;
      callback.onProgress(95);
      return LocalReadOutcome.bankCard(outcome);
    } on Exception catch (e) {
      callback.onError(_mapError(e));
      return null;
    }
  }

  Future<LocalReadOutcome?> _readTransit() async {
    final info = CardInfo();
    final records = <ApduRecord>[];
    final extras = CardExtras();
    final apdu = ApduExchange(transceive: _transceive);
    final extrasReader = CardExtrasReader(apdu);
    final tripReader = TripRecordReader(apdu);

    try {
      callback.onProgress(5);

      // 1) 交通联合富识读：命中后不立即返回——先记录结果，再在同一张卡上
      //    探测城市一卡通应用，双应用卡合并为一个结果（见 _mergeDual）。
      onStage?.call(CommonUnitTu.moduleName);
      callback.onProgress(10);
      // 模块内部进度（0–1）映射到本次识读的 15%–55% 区间
      final tu = CommonUnitTu(
        apdu,
        onProgress: (p) => callback.onProgress(15 + (p * 40).round()),
      );
      ParsedCard? tuParsed;
      if (await tu.select(info, records)) {
        tuParsed = await tu.read(info, records);
      }

      // 2) 城市一卡通富识读：交通联合未命中时按原优先级读取（命中即返回，
      //    标准文件视图）；已命中交通联合时，用独立的 CardInfo / records
      //    再探测一次住建部应用，避免污染交通联合汇总与行程分析链路。
      onStage?.call(CommonUnitCu.moduleName);
      // 双应用卡的 CU 为次应用（58%–88%）；单 CU 卡为主读法（20%–78%）
      final dual = tuParsed != null;
      final cuBase = dual ? 58 : 20;
      final cuSpan = dual ? 30 : 58;
      final cu = CommonUnitCu(
        apdu,
        onProgress: (p) => callback.onProgress(cuBase + (p * cuSpan).round()),
      );
      callback.onProgress(cuBase);
      ParsedCard? cuParsed;
      if (tuParsed != null) {
        // 双应用卡次应用探测：仅在确实读到 CU 标准文件时才认定为双应用，
        // 防止对纯 TU 卡的成功 SELECT 假阳性被误判为双应用。
        final cuInfo = CardInfo();
        final cuRecords = <ApduRecord>[];
        if (await cu.select(cuInfo, cuRecords)) {
          final secondary = await cu.read(cuInfo, cuRecords, readBalance: true);
          if (secondary != null && secondary.cityUnionFiles.isNotEmpty) {
            cuParsed = secondary;
          }
        }
      } else if (await cu.select(info, records)) {
        cuParsed = await cu.read(info, records);
      }

      if (tuParsed != null) {
        callback.onProgress(95);
        return _outcome(
          info,
          records,
          extras,
          cuParsed != null ? _mergeDual(tuParsed, cuParsed) : tuParsed,
        );
      }
      if (cuParsed != null) {
        callback.onProgress(95);
        return _outcome(info, records, extras, cuParsed);
      }

      // 3~7) 地方交通卡探测（通用单元均未命中时）
      callback.onProgress(25);
      // 3) 北京地方卡探测
      if (await BeijingLocalCard(apdu).probe(info, records)) {
        info.isBeijing = true;
        callback.onProgress(35);
        await extrasReader.readCommon(info, records, extras); // m790f
        callback.onProgress(55);
        await tripReader.readFile(info, records, extras, TripFile.metro); // m789e 196
        callback.onProgress(80);
        return await _finishLocal(tripReader, info, records, extras);
      }

      // 4) 羊城通 YCT (PAY.APPY -> m794k)
      final yct = YangchengTong(apdu);
      if (await yct.selectAppy(records)) {
        info.isYCT = true;
        callback.onProgress(35);
        await yct.readInfoAndBalance(info, records);
        callback.onProgress(50);
        await extrasReader.readCommon(info, records, extras); // m790f
        callback.onProgress(65);
        await tripReader.readFile(info, records, extras, TripFile.metro); // m789e 196
        callback.onProgress(80);
        return await _finishLocal(tripReader, info, records, extras);
      }

      // 5) SZT / SUXIN / SUZ CIKA / TFT
      if (await Shenzhentong(apdu).select(info, records)) {
        // isSZT 已置位
      } else if (await SuzhouCard(apdu).select(info, records)) {
        // isSuzhou / isSuxin 已置位
      } else if (await SuzhouCika(apdu).select(info, records)) {
        // isSuzhou / isCika 已置位
      } else {
        await TftLocalCard(apdu).select(info, records);
        // isTFT 已置位
      }

      // 8) 共用读取 m791g（条件：YCT/SUXIN/CIKA/SZT）
      if (info.isYCT || info.isSuxin || info.isCika || info.isSZT) {
        callback.onProgress(35);
        if (await CommonCardInfo(apdu).read(info, records)) {
          callback.onProgress(50);
          await _readNonTuTrips(extrasReader, tripReader, info, records, extras);
          callback.onProgress(80);
          return await _finishLocal(tripReader, info, records, extras);
        }
      }

      return null; // 非地方卡且通用单元未命中
    } on Exception catch (e) {
      callback.onError(_mapError(e));
      return null;
    }
  }

  /// 非 TU 分支的行程/扩展读取（对应 L8705-8755）。
  Future<void> _readNonTuTrips(
    CardExtrasReader ex,
    TripRecordReader reader,
    CardInfo info,
    List<ApduRecord> records,
    CardExtras extras,
  ) async {
    await ex.readCommon(info, records, extras); // m790f
    await reader.readFile(info, records, extras, TripFile.metro); // m789e 196

    if (info.isSZT || info.isCika) {
      await reader.readFile(info, records, extras, TripFile.suxinTx); // m789e 132
    }
    if (info.isSZT) {
      if (info.cityCode != 2000) {
        await reader.readFile(info, records, extras, TripFile.ferry); // m789e 52
      } else {
        await reader.readFile(info, records, extras, TripFile.other); // m789e 212
      }
    }
    if (info.isCika) {
      await reader.readFile(info, records, extras, TripFile.bus); // m789e 76
    }
  }

  /// 地方卡收尾：余额重建 + 换乘去重后，仅在命中地方卡种时封装产出；
  /// 通用 TU/CU 不走此路径（由富识读分支直接返回）。
  Future<LocalReadOutcome?> _finishLocal(
    TripRecordReader reader,
    CardInfo info,
    List<ApduRecord> records,
    CardExtras extras,
  ) async {
    final result = await _finish(reader, info, records, extras); // m785a + m786b
    if (!info.isLocalCard) return null;
    callback.onProgress(90);
    final parsed = ParsedCard(
      parserId: CardParserIds.localCard,
      parserName: '地方交通卡 · ${info.cardKindLabel}',
      info: TUnionCardInfo(
        applicationSerial: info.cardNumber.isEmpty ? null : info.cardNumber,
        balanceFen: info.balance,
      ),
      transactions: const [],
      localCard: result,
    );
    callback.onProgress(95);
    return LocalReadOutcome.transit(readResult: result, parsedCard: parsed);
  }

  /// 通用单元（TU/CU）命中后封装：保留新架构 ReadResult 汇总。
  LocalReadOutcome _outcome(
    CardInfo info,
    List<ApduRecord> records,
    CardExtras extras,
    ParsedCard parsed,
  ) =>
      LocalReadOutcome.transit(
        readResult: ReadResult(info: info, records: records, extras: extras),
        parsedCard: parsed,
      );

  /// 双应用卡合并：以交通联合（部互联互通）应用为主产出（parserId 保持
  /// [CardParserIds.tunion]，驱动既有分析与展示链路），并入城市一卡通
  /// （住建部）应用的标准文件视图与钱包余额，标记 [ParsedCard.dualApplication]。
  /// 两套钱包余额分属不同网络，互不覆盖。
  static ParsedCard _mergeDual(ParsedCard tu, ParsedCard cu) => ParsedCard(
        parserId: CardParserIds.tunion,
        parserName: '${tu.parserName} + ${cu.parserName}（双应用）',
        info: tu.info,
        transactions: tu.transactions,
        transitProcessRecords: tu.transitProcessRecords,
        cityUnionFiles: cu.cityUnionFiles,
        cityUnionBalanceFen: cu.info.balanceFen,
        dualApplication: true,
        selectedAidHex: tu.selectedAidHex,
      );

  /// 收尾（对应 L8911-8923）：余额重建 + 换乘去重 + 进度 100。
  Future<ReadResult> _finish(
    TripRecordReader reader,
    CardInfo info,
    List<ApduRecord> records,
    CardExtras extras,
  ) async {
    await reader.reconstructBalances(info, records); // m785a
    TripDeduper().process(info, records); // m786b
    return ReadResult(info: info, records: records, extras: extras);
  }

  static String _mapError(Object e) {
    final m = e.toString();
    if (m.contains('info')) return 'CardInfoFailed';
    if (m.contains('balance')) return 'BalanceFailed';
    return 'ReadingIncomplete';
  }
}