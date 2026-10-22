library;

import '../../../protocols/transit/local/apdu_exchange.dart';
import '../../../protocols/bank/domain/models/bank_card_result.dart';

/// 银行卡探测抽象：作为统一识读流程的一等阶段执行 EMV / PBOC 只读枚举与分析。
///
/// 具体实现（`BankCardProbeImpl`）注入特性层的 `BankCardAnalyzer`，核心流程
/// 只依赖本抽象；传输复用统一的 [LocalTransceive]（与交通卡同一收发通道）。
abstract interface class BankCardProbe {
  /// 以统一传输执行一次银行卡只读探测；命中返回产物（含仅枚举失败的结果，
  /// 由上层按其状态展示），未装配 / 不适用时返回 null。
  Future<BankCardResult?> probe(LocalTransceive transceive);
}
