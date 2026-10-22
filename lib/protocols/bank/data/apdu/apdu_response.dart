import 'dart:typed_data';

/// APDU 响应模型：拆分数据域与状态字（SW1SW2）。
class ApduResponse {
  final Uint8List data;
  final int sw1;
  final int sw2;

  const ApduResponse({
    required this.data,
    required this.sw1,
    required this.sw2,
  });

  int get statusWord => (sw1 << 8) | sw2;

  bool get isSuccess => statusWord == 0x9000;

  factory ApduResponse.fromBytes(Uint8List bytes) {
    if (bytes.length < 2) {
      throw const FormatException('APDU 响应缺少状态字');
    }
    return ApduResponse(
      data: Uint8List.fromList(bytes.sublist(0, bytes.length - 2)),
      sw1: bytes[bytes.length - 2],
      sw2: bytes[bytes.length - 1],
    );
  }
}
