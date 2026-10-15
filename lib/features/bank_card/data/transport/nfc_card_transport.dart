import 'dart:typed_data';

import '../../domain/interfaces/card_transport.dart';

/// 把现有 NFC 通道（AppState 的带日志 transceive）适配为 [CardTransport]。
///
/// 会话管理、卡片移除、超时与异常处理保留在通道层（由 AppState / 原生负责），
/// 本适配仅做类型映射，不重复实现。
class NfcCardTransport implements CardTransport {
  final Future<List<int>> Function(List<int> apdu) _transceive;

  NfcCardTransport(this._transceive);

  @override
  Future<Uint8List> transceive(Uint8List command) async {
    final resp = await _transceive(command);
    return Uint8List.fromList(resp);
  }

  @override
  Future<void> close() async {
    // 通道生命周期由 AppState 管理；此处无需处理。
  }
}