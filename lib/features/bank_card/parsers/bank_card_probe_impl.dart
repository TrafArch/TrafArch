import '../../../core/transit/local_card/apdu_exchange.dart';
import '../../../core/transit/local_card/bank_card_probe.dart';
import '../data/transport/nfc_card_transport.dart';
import 'bank_card_analyzer.dart';

/// 统一识读流程的银行卡探测实现：把 [BankCardAnalyzer]（EMV / PBOC）适配为
/// 核心流程可注入的 [BankCardProbe]。解析器由 [analyzerProvider] 惰性提供
/// （字典随资产加载，上层缓存后一次读卡内复用），产物 [BankCardResult]
/// 同时实现核心标记接口 [BankCardOutcome]。
///
/// 命中门槛：仅当分析器至少读到一个应用的数据（[BankCardStatus.partial] /
/// [BankCardStatus.success]）时才回传产物；PPSE 不支持（[BankCardStatus.enumerationFailed]）
/// 或应用列表全空（[BankCardStatus.noCard]）时视为「非支付卡」，返回 null，
/// 让核心流程走「未发现受支持的卡片应用」，避免把非 EMV 规范的 CPU 卡
/// 误判为银行卡并渲染 EMV 结果视图。
class BankCardProbeImpl implements BankCardProbe {
  const BankCardProbeImpl(this.analyzerProvider);

  final Future<BankCardAnalyzer> Function() analyzerProvider;

  @override
  Future<BankCardOutcome?> probe(LocalTransceive transceive) async {
    final analyzer = await analyzerProvider();
    final result = await analyzer.analyze(NfcCardTransport(transceive));
    // 非支付 CPU 卡（PPSE 未命中 / 无应用数据）在此拦下，
    // 由核心流程统一收敛为「未发现受支持的卡片应用」。
    if (result.status == BankCardStatus.noCard ||
        result.status == BankCardStatus.enumerationFailed) {
      return null;
    }
    return result;
  }
}