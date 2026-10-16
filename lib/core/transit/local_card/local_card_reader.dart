library;

import '../../card/card_parser.dart';
import '../tunion/tunion_models.dart';
import 'apdu_exchange.dart';
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

/// 一次识读的统一结果：新架构汇总 + 对应卡型的 [ParsedCard] 载荷。
/// [parsedCard] 的 parserId 为 tunion / cityUnion / localCard，
/// 供上层展示与分析链路按其分派。
class LocalReadOutcome {
  const LocalReadOutcome({required this.readResult, required this.parsedCard});
  final ReadResult readResult;
  final ParsedCard parsedCard;
}

/// 交通卡识读编排主体（新模块为主）：按优先级串联三类读法，命中即返回。
/// 1) 交通联合（JT/T 978.2）富识读 [CommonUnitTu]；
/// 2) 城市一卡通（CJ/T 331-2016）富识读 [CommonUnitCu]；
/// 3) 地方交通卡逐城市探测（北京 / 羊城通 / 深圳通 / 苏州(苏薪·计次) / 天府通），
///    命中后读取共用卡信息与行程 / 扩展记录，最后余额重建 + 换乘去重。
/// 三类均不命中时返回 null（交由上层银行卡兜底）。
/// 传输经 [LocalTransceive] 注入（与 NfcChannel.transceive 同签名），
/// 模块不依赖任何上层状态，可独立复用与测试。
class LocalCardReader {
  LocalCardReader(
    this._transceive, {
    this.callback = const NoopLocalCardReaderCallback(),
    this.onStage,
  });

  final LocalTransceive _transceive;
  final LocalCardReaderCallback callback;

  /// 识读阶段回调（供上层写「== 尝试解析：xx ==」日志；可空）。
  final void Function(String stage)? onStage;

  Future<LocalReadOutcome?> read() async {
    final info = CardInfo();
    final records = <ApduRecord>[];
    final extras = CardExtras();
    final apdu = ApduExchange(transceive: _transceive);
    final extrasReader = CardExtrasReader(apdu);
    final tripReader = TripRecordReader(apdu);

    try {
      callback.onProgress(10);

      // 1) 交通联合富识读：命中即返回（含交易 / 过程记录，供分析引擎）
      onStage?.call(CommonUnitTu.moduleName);
      final tu = CommonUnitTu(apdu);
      if (await tu.select(info, records)) {
        callback.onProgress(70);
        final parsed = await tu.read(info, records);
        if (parsed != null) return _outcome(info, records, extras, parsed);
      }

      // 2) 城市一卡通富识读：命中即返回（含标准文件视图）
      onStage?.call(CommonUnitCu.moduleName);
      final cu = CommonUnitCu(apdu);
      if (await cu.select(info, records)) {
        final parsed = await cu.read(info, records);
        if (parsed != null) return _outcome(info, records, extras, parsed);
      }

      // 3~7) 地方交通卡探测（通用单元均未命中时）
      // 3) 北京地方卡探测
      if (await BeijingLocalCard(apdu).probe(info, records)) {
        info.isBeijing = true;
        callback.onProgress(30);
        await extrasReader.readCommon(info, records, extras); // m790f
        await tripReader.readFile(info, records, extras, TripFile.metro); // m789e 196
        return await _finishLocal(tripReader, info, records, extras);
      }

      // 4) 羊城通 YCT (PAY.APPY -> m794k)
      final yct = YangchengTong(apdu);
      if (await yct.selectAppy(records)) {
        info.isYCT = true;
        await yct.readInfoAndBalance(info, records);
        callback.onProgress(30);
        await extrasReader.readCommon(info, records, extras); // m790f
        await tripReader.readFile(info, records, extras, TripFile.metro); // m789e 196
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
        if (await CommonCardInfo(apdu).read(info, records)) {
          callback.onProgress(30);
          await _readNonTuTrips(extrasReader, tripReader, info, records, extras);
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
    return LocalReadOutcome(readResult: result, parsedCard: parsed);
  }

  /// 通用单元（TU/CU）命中后封装：保留新架构 ReadResult 汇总。
  LocalReadOutcome _outcome(
    CardInfo info,
    List<ApduRecord> records,
    CardExtras extras,
    ParsedCard parsed,
  ) =>
      LocalReadOutcome(
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
    callback.onProgress(100);
    return ReadResult(info: info, records: records, extras: extras);
  }

  static String _mapError(Object e) {
    final m = e.toString();
    if (m.contains('info')) return 'CardInfoFailed';
    if (m.contains('balance')) return 'BalanceFailed';
    return 'ReadingIncomplete';
  }
}