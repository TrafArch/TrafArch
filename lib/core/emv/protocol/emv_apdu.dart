// D:\iteam\TrafArch\lib\core\emv\protocol\emv_apdu.dart
library;

/// APDU 响应：数据 + 状态字（SW1/SW2），并提供 EMV 常用状态判定。
class EmvApduResponse {
  const EmvApduResponse(this.data, this.sw1, this.sw2);

  final List<int> data;
  final int sw1;
  final int sw2;

  int get statusWord => (sw1 << 8) | sw2;
  bool get isSuccess => statusWord == 0x9000;
  bool get hasMoreData => sw1 == 0x61; // 61XX：仍有数据，需 GET RESPONSE
  bool get wrongLe => sw1 == 0x6C; // 6CXX：Le 错误，SW2 为建议长度

  String get statusHex =>
      '${sw1.toRadixString(16).padLeft(2, '0')}'
      '${sw2.toRadixString(16).padLeft(2, '0')}'
          .toUpperCase();

  static EmvApduResponse parse(List<int> bytes) {
    if (bytes.length < 2) {
      throw const FormatException('APDU 响应少于 2 字节，缺少状态字');
    }
    return EmvApduResponse(
      bytes.sublist(0, bytes.length - 2),
      bytes[bytes.length - 2],
      bytes[bytes.length - 1],
    );
  }
}

/// APDU 组包工具。
class EmvApdu {
  /// SELECT by AID/DF Name：`00 A4 04 00 <len> <name> 00`。
  static List<int> selectByName(List<int> name) {
    if (name.isEmpty || name.length > 255) {
      throw ArgumentError('AID/DF Name 长度必须为 1..255 字节');
    }
    return [0x00, 0xA4, 0x04, 0x00, name.length, ...name, 0x00];
  }

  /// GET RESPONSE：`00 C0 00 00 <le>`。
  static List<int> getResponse(int le) => [0x00, 0xC0, 0x00, 0x00, le & 0xFF];
}