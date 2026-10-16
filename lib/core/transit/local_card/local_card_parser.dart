library;

import '../../card/card_parser.dart';
import 'local_card_reader.dart';

/// 交通卡统一识读解析器（独立模块对外入口）。
///
/// 本模块以新架构为主，已把原先分散在 `AppState` 的老「交通联合
/// （JT/T 978.2）/ 城市一卡通（CJ/T 331-2016）」识读融入内部：编排主体
/// [LocalCardReader] 按「TU 富识读 → CU 富识读 → 地方交通卡探测」优先级
/// 串联，产出 [ParsedCard.parserId] 分别为 tunion / cityUnion / localCard，
/// 上层展示与分析链路据此分派，行为与拆分前完全一致（双标准卡以交通
/// 联合载荷为主）。
/// 传输经应用侧 [ApduTransceive]（`AppState._transceive`）注入，模块不依赖
/// 任何上层状态，可独立复用与测试。
class LocalCardParser implements CardParser {
  LocalCardParser(this._transceive, {this.onStage});

  final ApduTransceive _transceive;

  /// 识读阶段回调（供上层写「== 尝试解析：xx ==」日志；可空）。
  final void Function(String stage)? onStage;

  @override
  String get parserId => CardParserIds.localCard;

  @override
  String get parserName => '交通卡统一识读';

  @override
  Future<ParsedCard?> parse() async {
    final outcome = await LocalCardReader(_transceive, onStage: onStage).read();
    return outcome?.parsedCard;
  }
}