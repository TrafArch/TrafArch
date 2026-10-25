library;

import '../../../protocols/transit/card_parser.dart';
import '../../../protocols/transit/city_union/city_union_reader.dart';
import '../../../protocols/transit/tunion/tunion_models.dart';
import '../../../protocols/transit/local/apdu_exchange.dart';
import 'bank_card_probe.dart';
import '../../../protocols/bank/domain/models/bank_card_result.dart';
import '../../../protocols/transit/local/cards/beijing_local_card.dart';
import '../../../protocols/transit/local/cards/common_card_info.dart';
import '../../../protocols/transit/local/cards/macau_pass_card.dart';
import '../../../protocols/transit/local/cards/shenzhentong.dart';
import '../../../protocols/transit/local/cards/shanghai_transit_union_card.dart';
import '../../../protocols/transit/local/cards/shanghai_transit_union_models.dart';
import '../../../protocols/transit/local/cards/suzhou_card.dart';
import '../../../protocols/transit/local/cards/suzhou_cika.dart';
import '../../../protocols/transit/local/cards/tft_local_card.dart';
import '../../../protocols/transit/local/cards/wuhan_tong_card.dart';
import '../../../protocols/transit/local/cards/yangchengtong.dart';
import '../../../protocols/transit/local/local_card_models.dart';
import '../../../protocols/transit/local/trips/trip_dedup.dart';
import '../../../protocols/transit/local/trips/trip_extras.dart';
import '../../../protocols/transit/local/trips/trip_records.dart';
import '../../../protocols/transport/transport_failure.dart';

/// 进度 / 错误回调（轻量抽象，对应原重写工程的 CardReaderCallback）。
/// 会话 APDU 日志由上层 [LocalTransceive]（ScanController._exchange）统一记录，
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
/// 也可能是银行卡（[BankCardResult]）。[parsedCard] 的 parserId 为
/// tunion / cityUnion / localCard，供上层展示与分析链路按其分派；
/// [bank] 非空时表示本次识读命中银行卡（EMV / PBOC）只读流程。
class LocalReadOutcome {
  const LocalReadOutcome.transit({
    required this.readResult,
    required this.parsedCard,
    this.shanghai,
  }) : bank = null;

  const LocalReadOutcome.bankCard(BankCardResult outcome)
    : readResult = null,
      parsedCard = null,
      bank = outcome,
      shanghai = null;

  final ReadResult? readResult;
  final ParsedCard? parsedCard;
  final BankCardResult? bank;

  /// 上海交通卡（交通联合版）双路识读详情：仅命中该独立卡种时非空，
  /// 携带 TU / CU 两路各自的应用确认 / 读取成功 / 数据完整状态、原始
  /// 记录与解析错误。
  final ShanghaiTransitUnionResult? shanghai;

  /// 是否为银行卡识读产物（交通应用链路未命中时的一等阶段结果）。
  bool get isBankCard => bank != null;
}

/// 交通卡 / 银行卡统一识读编排主体（新模块为主）：按优先级串联各读法，
/// 命中即返回。
/// 0) [ShanghaiTransitUnionCardParser] 先读 TU，仅确认上海 TU 才读 CU，
///    命中上海时返回合并结果；
/// 1) 普通 TU 复用已读结果直接返回，不探测 CU；
/// 2) TU 无可返回结果时独立回退普通 CU，不冒认上海 TU、不重复探测；
/// 3) 地方交通卡逐城市探测（武汉通 / 北京 / 羊城通 / 深圳通 /
///    苏州(苏薪·计次) / 天府通），命中后读取共用卡信息与行程 / 扩展记录，
///    最后余额重建 + 换乘去重；
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
    } catch (e) {
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

      // 1) 先读取 TU，上海 TU 确认后才探测 CU；复用产物避免二次读取。
      callback.onProgress(10);
      final shanghai = await ShanghaiTransitUnionCardParser(
        _transceive,
        onStage: onStage,
        onProgress: (p) => callback.onProgress(10 + (p * 40).round()),
      ).read();
      final tuCard = shanghai.tu.card;
      final cuCard = shanghai.cu.card;

      if (shanghai.isShanghaiTransitUnion && shanghai.mergedCard != null) {
        callback.onProgress(95);
        return LocalReadOutcome.transit(
          readResult: shanghai.readResult,
          parsedCard: shanghai.mergedCard,
          shanghai: shanghai,
        );
      }

      // 2) 普通 TU 直接复用（含部分数据），不再探测 CU。
      if (tuCard != null) {
        callback.onProgress(95);
        return _outcome(
          shanghai.tu.cardInfo,
          shanghai.tu.records,
          extras,
          tuCard,
        );
      }

      // TU 无可返回结果时独立尝试普通 CU；上海分支已探测过则不重读。
      if (!shanghai.cu.probed) {
        onStage?.call(CommonUnitCu.moduleName);
        final cu = CommonUnitCu(apdu);
        ParsedCard? card;
        try {
          if (await cu.select(info, records)) {
            card = await cu.read(info, records, readBalance: true);
          }
        } on Exception catch (e) {
          card = cu.parsedCard;
          callback.onError(_mapError(e));
        }
        if (card != null && card.cityUnionFiles.isNotEmpty) {
          callback.onProgress(95);
          return _outcome(info, records, extras, card);
        }
      } else if (cuCard != null) {
        callback.onProgress(95);
        return _outcome(
          shanghai.cu.cardInfo,
          shanghai.cu.records,
          extras,
          cuCard,
        );
      }

      // 3~7) 地方交通卡探测（通用单元均未命中时）
      callback.onProgress(25);

      // 澳门通以专属钱包应用名认领，不套用国内地方卡的金额及余额重建规则。
      final macauPass = MacauPassCard(apdu);
      if (await macauPass.select(info, records)) {
        callback.onProgress(35);
        await macauPass.readBalanceAndRecords(info, records);
        callback.onProgress(95);
        return _localOutcome(
          ReadResult(info: info, records: records, extras: extras),
        );
      }

      // 3) 老版武汉通（AP1.WHCTC）：先于 PBOC 探测完成应用确认；
      //    一旦确认，即使后续流水读取失败也按地方卡返回，不再回退银行卡。
      final whctc = WuhanTongCard(apdu);
      if (await whctc.probe(info, records)) {
        info.isWHCTC = true;
        callback.onProgress(35);
        await whctc.readLogs(info, records);
        callback.onProgress(80);
        return await _finishLocal(tripReader, info, records, extras);
      }

      // 4) 北京地方卡探测
      if (await BeijingLocalCard(apdu).probe(info, records)) {
        info.isBeijing = true;
        callback.onProgress(35);
        await extrasReader.readCommon(info, records, extras); // m790f
        callback.onProgress(55);
        await tripReader.readFile(
          info,
          records,
          extras,
          TripFile.metro,
        ); // m789e 196
        callback.onProgress(80);
        return await _finishLocal(tripReader, info, records, extras);
      }

      // 5) 羊城通 YCT (PAY.APPY -> m794k)
      final yct = YangchengTong(apdu);
      if (await yct.selectAppy(records)) {
        info.isYCT = true;
        callback.onProgress(35);
        await yct.readInfoAndBalance(info, records);
        callback.onProgress(50);
        await extrasReader.readCommon(info, records, extras); // m790f
        callback.onProgress(65);
        await tripReader.readFile(
          info,
          records,
          extras,
          TripFile.metro,
        ); // m789e 196
        callback.onProgress(80);
        return await _finishLocal(tripReader, info, records, extras);
      }

      // 6) SZT / SUXIN / SUZ CIKA / TFT
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

      // 7) 共用读取 m791g（条件：YCT/SUXIN/CIKA/SZT）
      if (info.isYCT || info.isSuxin || info.isCika || info.isSZT) {
        callback.onProgress(35);
        if (await CommonCardInfo(apdu).read(info, records)) {
          callback.onProgress(50);
          await _readNonTuTrips(
            extrasReader,
            tripReader,
            info,
            records,
            extras,
          );
          callback.onProgress(80);
          return await _finishLocal(tripReader, info, records, extras);
        }
      }

      return null; // 非地方卡且通用单元未命中
    } on Exception catch (e) {
      callback.onError(_mapError(e));
      if (info.isLocalCard) {
        // A confirmed application's late failure is not a protocol non-match.
        // Do not call _finish: its balance reconstruction can perform I/O.
        return _localOutcome(
          ReadResult(
            info: info,
            records: List.unmodifiable(records),
            extras: extras,
            readError: e,
            transportFailure: switch (e) {
              ApduTransportException(:final failure) => failure,
              TransportFailure() => e,
              _ => null,
            },
          ),
        );
      }
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
      await reader.readFile(
        info,
        records,
        extras,
        TripFile.suxinTx,
      ); // m789e 132
    }
    if (info.isSZT) {
      if (info.cityCode != 2000) {
        await reader.readFile(
          info,
          records,
          extras,
          TripFile.ferry,
        ); // m789e 52
      } else {
        await reader.readFile(
          info,
          records,
          extras,
          TripFile.other,
        ); // m789e 212
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
    final result = await _finish(
      reader,
      info,
      records,
      extras,
    ); // m785a + m786b
    if (!info.isLocalCard) return null;
    callback.onProgress(90);
    final outcome = _localOutcome(result);
    callback.onProgress(95);
    return outcome;
  }

  /// Pure construction shared by complete reads and interrupted local reads.
  LocalReadOutcome _localOutcome(ReadResult result) {
    final info = result.info;
    final parsed = ParsedCard(
      parserId: CardParserIds.localCard,
      parserName: '地方交通卡 · ${info.cardKindLabel}',
      info: TUnionCardInfo(
        applicationSerial: info.cardNumber.isEmpty ? null : info.cardNumber,
        balanceFen: info.observedBalance,
      ),
      transactions: const [],
      localCard: result,
    );
    return LocalReadOutcome.transit(readResult: result, parsedCard: parsed);
  }

  /// 通用单元（TU/CU）命中后封装：保留新架构 ReadResult 汇总。
  LocalReadOutcome _outcome(
    CardInfo info,
    List<ApduRecord> records,
    CardExtras extras,
    ParsedCard parsed,
  ) => LocalReadOutcome.transit(
    readResult: ReadResult(info: info, records: records, extras: extras),
    parsedCard: parsed,
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
