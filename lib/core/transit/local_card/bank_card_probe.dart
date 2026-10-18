library;

import 'apdu_exchange.dart';

/// 银行卡（EMV / PBOC）只读探测结果的标记接口。
///
/// 由特性层（`features/bank_card`）的具体结果类型 `BankCardResult` 实现，
/// 使核心识读流程 `LocalCardReader` 能在不反向依赖特性层的前提下，
/// 把银行卡产物作为统一识读流程的一等结果承载并回传给上层。
abstract interface class BankCardOutcome {}

/// 银行卡探测抽象：作为统一识读流程的一等阶段执行 EMV / PBOC 只读枚举与分析。
///
/// 具体实现（`BankCardProbeImpl`）注入特性层的 `BankCardAnalyzer`，核心流程
/// 只依赖本抽象；传输复用统一的 [LocalTransceive]（与交通卡同一收发通道）。
abstract interface class BankCardProbe {
  /// 以统一传输执行一次银行卡只读探测；命中返回产物（含仅枚举失败的结果，
  /// 由上层按其状态展示），未装配 / 不适用时返回 null。
  Future<BankCardOutcome?> probe(LocalTransceive transceive);
}