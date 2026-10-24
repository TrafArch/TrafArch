library;

import '../../card_parser.dart';
import '../../city_union/city_union_models.dart';
import '../apdu_exchange.dart';
import '../local_card_models.dart';
import '../../city_union/city_union_reader.dart';
import '../../tunion/tunion_reader.dart';
import 'shanghai_transit_union_models.dart';

/// 上海交通卡（交通联合版）专用识别器。
///
/// 该卡种默认按 TU（JT/T 978.2）+ CU（CJ/T 331-2016）双标卡处理：
/// 1) 先独立执行交通联合应用识读（应用确认 → 读取 → 数据完整性判定）；
/// 2) 再独立执行城市一卡通应用识读（同一套三态判定）；
/// 3) 两路结果交给 [ShanghaiTransitUnionResult] 合并（含行程去重）。
///
/// 任一侧失败都不会跳过另一侧：两侧各自持有独立的 [CardInfo] /
/// [ApduRecord] / 错误列表，合并时只做数据汇聚，不互相覆盖。
/// 已确认 TU 的卡号前缀 31047700 / 已确认 CU 的 0x15 原始前四字节
/// 86982000 仅作各自来源的辅助线索（见 [ShanghaiTransitUnionResult]）。
class ShanghaiTransitUnionCardParser implements CardParser {
  ShanghaiTransitUnionCardParser(
    this._transceive, {
    this.onProgress,
    this.onStage,
  });

  final LocalTransceive _transceive;

  /// 模块内部识读进度（0.0–1.0）：TU 占前半程、CU 占后半程；可空。
  final void Function(double progress)? onProgress;

  /// 子阶段回调（供上层写「== 尝试解析：xx ==」日志；可空）。
  final void Function(String stage)? onStage;

  /// 展示 / 日志用的模块名。
  static const String moduleName = ShanghaiTransitUnionIds.moduleName;

  @override
  String get parserId => CardParserIds.shanghaiTunion;

  @override
  String get parserName => moduleName;

  void _report(double progress) => onProgress?.call(progress.clamp(0.0, 1.0));

  /// 双路识读入口：始终两路都执行，返回合并结果（不在此处判定卡种）。
  Future<ShanghaiTransitUnionResult> read() async {
    final apdu = ApduExchange(transceive: _transceive);
    _report(0);

    final tu = await _readTu(apdu);
    _report(0.5);

    final cu = await _readCu(apdu);
    _report(1);

    return ShanghaiTransitUnionResult.build(tu: tu, cu: cu);
  }

  @override
  Future<ParsedCard?> parse() async => (await read()).mergedCard;

  /// 交通联合应用识读（TU）。
  Future<ShanghaiTransitApplication> _readTu(ApduExchange apdu) async {
    onStage?.call('$moduleName · ${ShanghaiTransitUnionIds.tuSystem}');
    final info = CardInfo();
    final records = <ApduRecord>[];
    final errors = <String>[];
    final warnings = <String>[];
    final unit = CommonUnitTu(apdu, onProgress: (p) => _report(p * 0.45));

    var confirmed = false;
    ParsedCard? card;
    try {
      confirmed = await unit.select(info, records);
      if (!confirmed) {
        errors.add('TU 应用未确认（AID 选择失败）');
      } else {
        card = await unit.read(info, records);
        if (card == null) {
          errors.add('TU 应用已选中，但卡信息 / 应用序列号未通过校验');
        }
      }
    } on Exception catch (e) {
      card = unit.parsedCard;
      errors.add('TU 读取异常：$e');
    }

    final identity = unit.lastCardInfo ?? card?.info;
    final serial = card?.info.applicationSerial;
    final dataComplete =
        errors.isEmpty &&
        card != null &&
        serial != null &&
        serial.isNotEmpty &&
        card.info.balanceFen != null;
    if (card != null && card.info.balanceFen == null) {
      warnings.add('TU 钱包余额未读到');
    }

    return ShanghaiTransitApplication(
      system: ShanghaiTransitUnionIds.tuSystem,
      confirmed: confirmed,
      readSucceeded: card != null,
      dataComplete: dataComplete,
      card: card,
      identity: identity,
      cardInfo: info,
      records: records,
      errors: errors,
      warnings: warnings,
    );
  }

  /// 城市一卡通应用识读（CU）：读余额开关常开（该卡种 CU 侧为独立钱包）。
  Future<ShanghaiTransitApplication> _readCu(ApduExchange apdu) async {
    onStage?.call('$moduleName · ${ShanghaiTransitUnionIds.cuSystem}');
    final info = CardInfo();
    final records = <ApduRecord>[];
    final errors = <String>[];
    final warnings = <String>[];
    final unit = CommonUnitCu(apdu, onProgress: (p) => _report(0.5 + p * 0.45));

    var confirmed = false;
    ParsedCard? card;
    try {
      confirmed = await unit.select(info, records);
      if (!confirmed) {
        errors.add('CU 应用未确认（AID 选择失败）');
      } else {
        final parsed = await unit.read(info, records, readBalance: true);
        if (parsed == null) {
          errors.add('CU 应用已选中，但未读取到标准文件');
        } else if (parsed.cityUnionFiles.isEmpty) {
          errors.add('CU 标准文件为空（仅完成 AID 选择）');
        } else {
          card = parsed;
        }
      }
    } on Exception catch (e) {
      final partial = unit.parsedCard;
      if (partial != null && partial.cityUnionFiles.isNotEmpty) card = partial;
      errors.add('CU 读取异常：$e');
    }

    final public = card?.cityUnionFiles
        .whereType<CjT331PublicInfo>()
        .firstOrNull;
    final serial = public?.applicationSerialNumber;
    final hasWalletRecords =
        card?.cityUnionFiles.any(
          (view) =>
              view is CjT331WalletLocalConsumption ||
              view is CjT331WalletRecharge,
        ) ??
        false;
    final dataComplete =
        errors.isEmpty &&
        card != null &&
        public != null &&
        serial != null &&
        serial.isNotEmpty &&
        (card.info.balanceFen != null || hasWalletRecords);
    if (card != null && public == null) {
      warnings.add('CU 公共应用基本信息文件（0x15）未读到');
    }
    if (card != null && card.info.balanceFen == null) {
      warnings.add('CU 钱包余额未读到');
    }

    return ShanghaiTransitApplication(
      system: ShanghaiTransitUnionIds.cuSystem,
      confirmed: confirmed,
      readSucceeded: card != null,
      dataComplete: dataComplete,
      card: card,
      identity: card?.info,
      cardInfo: info,
      records: records,
      errors: errors,
      warnings: warnings,
    );
  }
}
