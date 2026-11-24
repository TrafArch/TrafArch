library;

import '../../../protocols/transit/card_parser.dart';
import 'local_card_reader.dart';

/// 卡片统一识读解析器（独立模块对外入口）。
///
/// 传输经应用侧 [ApduTransceive]（ScanController）注入，模块不依赖
/// 任何上层状态，可独立复用与测试。
class LocalCardParser implements CardParser {
  LocalCardParser(this._transceive, {this.onStage, this.onProgress});

  final ApduTransceive _transceive;

  /// 识读阶段回调（供上层写「== 尝试解析：xx ==」日志；可空）。
  final void Function(String stage)? onStage;

  /// 识读进度回调（0–100 百分比，供上层进度条展示；可空）。
  final void Function(int percent)? onProgress;

  @override
  String get parserId => CardParserIds.localCard;

  @override
  String get parserName => '卡片统一识读';

  /// 统一识读入口：返回交通卡识读的完整产物。
  Future<IsoDepScan> scan() => LocalCardReader(
    _transceive,
    onStage: onStage,
    callback: onProgress == null
        ? const NoopLocalCardReaderCallback()
        : _ProgressCallback(onProgress!),
  ).scan();

  Future<LocalReadOutcome?> read() async => (await scan()).result;

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
