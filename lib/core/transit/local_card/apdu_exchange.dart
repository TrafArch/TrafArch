library;

import 'dart:typed_data';
import 'local_card_models.dart';

/// 传输函数：发送 APDU（List<int>）返回响应（含 SW1SW2）。
/// 与 AppState._transceive / NfcChannel.transceive 同签名，便于直接注入。
typedef LocalTransceive = Future<List<int>> Function(List<int> apdu);

/// APDU 交换 + 6C/6700 续读 + 61XX 链式 GET RESPONSE + 9000 校验
class ApduExchange {
  ApduExchange({required this.transceive});
  final LocalTransceive transceive;

  static const List<int> okSw = [0x90, 0x00];
  static const List<int> sw6700 = [0x67, 0x00];

  Future<List<int>?> call(
    List<int> apdu,
    String label, {
    bool verbose = false,
    List<ApduRecord>? records,
    bool strict = false,
    int flags = 0xC0,
  }) async {
    final skipSwCheck = (flags & 0x40) == 0; // z4
    final cmd = Uint8List.fromList(apdu);
    final le = cmd.isNotEmpty ? cmd[cmd.length - 1] & 0xFF : 0;

    var response = await _follow(cmd[0], await transceive(cmd));
    var sw = _tail(response);
    if (sw == null) return null; // 空/短响应（上层出错兜底）

    // SW1 == 0x6C：用 SW2 作为正确 Le 重试
    if ((sw[0] & 0xFF) == 0x6C) {
      cmd[cmd.length - 1] = sw[1] & 0xFF;
      response = await _follow(cmd[0], await transceive(cmd));
      sw = _tail(response);
      if (sw == null) return null;
    } else if (_eq(sw, sw6700) && le != 0) {
      // SW == 6700 且 Le != 0：以 Le=0 重试
      cmd[cmd.length - 1] = 0;
      response = await _follow(cmd[0], await transceive(cmd));
      sw = _tail(response);
      if (sw == null) return null;
    }

    final enoughData = !strict || (response.length - 2 >= le);
    // 数据不足时按“长度错误”判失败（原先两个分支取值相同，strict 实际失效）
    final effectiveSw = enoughData ? sw : const [0x67, 0x00];

    if (verbose && (skipSwCheck || _eq(okSw, effectiveSw))) {
      records?.add(ApduRecord()
        ..commandHex = _hexStr(cmd)
        ..response = response
        ..label = label);
    }

    if (!_eq(okSw, effectiveSw)) return null;
    return response.sublist(0, response.length - 2);
  }

  /// 61XX 链式：读取剩余响应（支持多段，段数上限 32），
  /// 与现有 TUnionParser / CityUnionParser 的收发策略保持一致。
  Future<List<int>> _follow(int cla, List<int> first) async {
    var resp = first;
    var guard = 0;
    while (true) {
      final sw = _tail(resp);
      if (sw == null) break;
      final sw1 = sw[0] & 0xFF;
      final sw2 = sw[1] & 0xFF;
      if (sw1 != 0x61 || sw2 == 0 || guard++ >= 32) break;
      final data = resp.sublist(0, resp.length - 2);
      final chain = await transceive([cla, 0xC0, 0x00, 0x00, sw2]);
      if (chain.isEmpty) break;
      resp = [...data, ...chain];
    }
    return resp;
  }

  static List<int>? _tail(List<int> l) =>
      l.length < 2 ? null : l.sublist(l.length - 2);

  static bool _eq(List<int>? a, List<int> b) {
    if (a == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] & 0xFF) != (b[i] & 0xFF)) return false;
    }
    return true;
  }

  static String _hexStr(List<int> b) => b
      .map((x) => (x & 0xFF).toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
}