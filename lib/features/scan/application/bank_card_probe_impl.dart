import '../../../protocols/transit/local/apdu_exchange.dart';
import 'bank_card_probe.dart';
import 'nfc_card_transport.dart';
import '../../../protocols/bank/parsers/bank_card_analyzer.dart';

/// 统一识读流程的银行卡探测实现：把 [BankCardAnalyzer]（EMV / PBOC）适配为
/// 核心流程可注入的 [BankCardProbe]。字典惰性加载；应用证据和通信失败
/// 都作为类型化结果保留。只有明确无应用且没有通信失败时才视作未匹配。
class BankCardProbeImpl implements BankCardProbe {
  const BankCardProbeImpl(this.analyzerProvider);

  final Future<BankCardAnalyzer> Function() analyzerProvider;

  @override
  Future<BankCardResult?> probe(LocalTransceive transceive) async {
    final analyzer = await analyzerProvider();
    final result = await analyzer.analyze(NfcCardTransport(transceive));
    // 非支付 CPU 卡（PPSE 未命中 / 无应用数据）在此拦下，
    // 由核心流程统一收敛为「未发现受支持的卡片应用」。
    if (result.discoveredApplications.isEmpty &&
        result.transportFailure == null &&
        !result.traces.any((trace) => trace.errorCode != null) &&
        !result.issues.any(
          (issue) => issue.code == 'nfc_io_error' || issue.code == 'io_error',
        ) &&
        (result.status == BankCardStatus.noCard ||
            result.status == BankCardStatus.enumerationFailed)) {
      return null;
    }
    return result;
  }
}
