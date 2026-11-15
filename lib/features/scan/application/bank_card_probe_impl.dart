import '../../../protocols/transit/local/apdu_exchange.dart';
import 'bank_card_probe.dart';
import 'nfc_card_transport.dart';
import '../../../protocols/bank/parsers/bank_card_analyzer.dart';

/// 统一识读流程的银行卡探测实现：把 [BankCardAnalyzer]（EMV / PBOC）适配为
/// 核心流程可注入的 [BankCardProbe]。字典惰性加载；应用证据和通信失败
/// 都作为类型化结果保留。已知目录应用被拒绝选择时保留诊断。
class BankCardProbeImpl implements BankCardProbe {
  const BankCardProbeImpl(this.analyzerProvider);

  final Future<BankCardAnalyzer> Function() analyzerProvider;

  @override
  Future<BankCardResult?> probe(LocalTransceive transceive) async {
    final analyzer = await analyzerProvider();
    final result = await analyzer.analyze(NfcCardTransport(transceive));
    // 未发现已选择的应用、目录拒绝或通信异常时，
    // 由核心流程统一收敛为「未发现受支持的卡片应用」。
    if (result.discoveredApplications.isEmpty &&
        result.transportFailure == null &&
        !result.traces.any((trace) => trace.errorCode != null) &&
        !result.issues.any(
          (issue) =>
              issue.code == 'nfc_io_error' ||
              issue.code == 'io_error' ||
              issue.code == 'directory_select_rejected',
        ) &&
        (result.status == BankCardStatus.noCard ||
            result.status == BankCardStatus.enumerationFailed)) {
      return null;
    }
    return result;
  }
}
