library;

import '../../card/card_parser.dart';
import 'bank_card_probe.dart';
import 'local_card_reader.dart';

/// 卡片统一识读解析器（独立模块对外入口）。
///
/// 本模块以新架构为主，已把原先分散在 `AppState` 的老「交通联合
/// （JT/T 978.2）/ 城市一卡通（CJ/T 331-2016）」识读融入内部：编排主体
/// [LocalCardReader] 按「TU 富识读 → CU 富识读 → 地方交通卡探测 → 银行卡
/// （EMV / PBOC）」优先级串联，交通卡产出 [ParsedCard.parserId] 分别为
/// tunion / cityUnion / localCard，银行卡产出 [BankCardOutcome]，上层展示与
/// 分析链路据此分派。
/// 传输经应用侧 [ApduTransceive]（`AppState._transceive`）注入，模块不依赖
/// 任何上层状态，可独立复用与测试。
class LocalCardParser implements CardParser {
  LocalCardParser(
    this._transceive, {
    this.onStage,
    this.onProgress,
    this.bankProbe,
  });

  final ApduTransceive _transceive;

  /// 识读阶段回调（供上层写「== 尝试解析：xx ==」日志；可空）。
  final void Function(String stage)? onStage;

  /// 识读进度回调（0–100 百分比，供上层进度条展示；可空）。
  final void Function(int percent)? onProgress;

  /// 银行卡（EMV / PBOC）探测抽象；作为统一流程的一等阶段被 [LocalCardReader]
  /// 调用。为空时仅识读交通卡。
  final BankCardProbe? bankProbe;

  @override
  String get parserId => CardParserIds.localCard;

  @override
  String get parserName => '卡片统一识读';

  /// 统一识读入口：返回交通卡 / 银行卡的完整产物（供上层按类型分派）。
  Future<LocalReadOutcome?> read() => LocalCardReader(
        _transceive,
        onStage: onStage,
        bankProbe: bankProbe,
        callback: onProgress == null
            ? const NoopLocalCardReaderCallback()
            : _ProgressCallback(onProgress!),
      ).read();

  @override
  Future<ParsedCard?> parse() async => (await read())?.parsedCard;
}

/// 把上层进度函数适配为 [LocalCardReaderCallback]：错误信息仍由上层
/// APDU 日志 / 异常链路承载，这里不重复上报。
class _ProgressCallback implements LocalCardReaderCallback {
  const _ProgressCallback(this._onProgress);

  final void Function(int percent) _onProgress;

  @override
  void onProgress(int percent) => _onProgress(percent);

  @override
  void onError(String message) {}
}
