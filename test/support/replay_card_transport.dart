import 'dart:typed_data';

import 'package:transit_card_analyzer/protocols/bank/data/tlv/hex_codec.dart';
import 'package:transit_card_analyzer/protocols/bank/domain/interfaces/card_transport.dart';

/// 测试回放通道：按预先准备的 HEX 样本序列返回响应，
/// 使解析流程测试无需依赖实体银行卡的完整敏感数据。
class ReplayCardTransport implements CardTransport {
  final List<Uint8List> _responses;
  final List<Uint8List> sent = [];
  int _index = 0;

  ReplayCardTransport(List<String> hexResponses)
    : _responses = hexResponses.map(HexCodec.decode).toList();

  /// 直接给定字节响应。
  ReplayCardTransport.bytes(this._responses);

  @override
  Future<Uint8List> transceive(Uint8List command) async {
    sent.add(command);
    if (_index >= _responses.length) {
      // 样本耗尽：返回 6A82（文件未找到）而非抛异常，贴近卡片行为
      return Uint8List.fromList([0x6A, 0x82]);
    }
    return _responses[_index++];
  }

  @override
  Future<void> close() async {}
}
