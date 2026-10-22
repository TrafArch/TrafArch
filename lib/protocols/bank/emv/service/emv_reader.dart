import '../discovery/application_enumerator.dart';
import '../models/emv_discovery_result.dart';
import '../transport.dart';

/// 独立 EMV 发现入口（对外公共 API）：给定传输通道执行一次只读应用发现。
/// 会话生命周期由调用方（AppDependencies / 上层编排）负责，本模块不管理连接。
class EmvReader {
  const EmvReader(this._transceive);
  final EmvTransceive _transceive;

  Future<EmvDiscoveryResult> discover() =>
      EmvApplicationEnumerator(_transceive).enumerate();
}
