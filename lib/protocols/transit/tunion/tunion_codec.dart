/// 交通联合（T-Union）字节编解码工具（读取层与解析层共用）。
///
/// 集中 BCD / 大端整数 / HEX 转换逻辑，避免读取器（TUnionParser）与
/// 各解析器重复实现导致的口径不一致。
class TUnionCodec {
  TUnionCodec._();

  /// 是否为合法 BCD 字节（高/低半字节均 ≤ 9）。
  static bool isBcdByte(int b) => (b >> 4) <= 9 && (b & 0x0F) <= 9;

  /// BCD 字节数组转整数（如 [0x20, 0x24] -> 2024）。
  static int bcdToInt(List<int> bytes) =>
      bytes.fold(0, (acc, b) => acc * 100 + (b >> 4) * 10 + (b & 0x0F));

  /// BCD 字节数组转数字字符串（如 [0x12, 0x34] -> "1234"），
  /// 含非法 BCD 字节时返回 null。
  static String? bcdString(List<int> bytes) {
    if (bytes.isEmpty || !bytes.every(isBcdByte)) return null;
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b >> 4);
      sb.write(b & 0x0F);
    }
    return sb.toString();
  }

  /// 4 字节 BCD 日期（YYYYMMDD）转 DateTime，非法时返回 null。
  static DateTime? parseBcdDate(List<int> bytes) {
    if (bytes.length < 4 || !bytes.every(isBcdByte)) return null;
    final v = bcdToInt(bytes);
    final year = v ~/ 10000;
    final month = (v ~/ 100) % 100;
    final day = v % 100;
    if (year < 2000 ||
        year > 2100 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31) {
      return null;
    }
    return DateTime(year, month, day);
  }

  /// 7 字节 BCD 时间戳（YYYYMMDDhhmmss）转 DateTime，非法时返回 null。
  static DateTime? parseBcdDateTime(List<int> bytes) {
    if (bytes.length < 7 || !bytes.every(isBcdByte)) return null;
    final year = bcdToInt(bytes.sublist(0, 2));
    final month = bcdToInt(bytes.sublist(2, 3));
    final day = bcdToInt(bytes.sublist(3, 4));
    final hour = bcdToInt(bytes.sublist(4, 5));
    final minute = bcdToInt(bytes.sublist(5, 6));
    final second = bcdToInt(bytes.sublist(6, 7));
    if (year < 2000 ||
        year > 2100 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31 ||
        hour > 23 ||
        minute > 59 ||
        second > 59) {
      return null;
    }
    return DateTime(year, month, day, hour, minute, second);
  }

  /// 大端无符号整数（最多 4 字节），超界自动截断。
  static int beInt(List<int> data, int offset, int len) {
    var v = 0;
    for (var i = offset; i < offset + len && i < data.length; i++) {
      v = (v << 8) | data[i];
    }
    return v;
  }

  /// 字节数组转连续大写 HEX 字符串，空数组返回 null。
  static String? hexBytes(List<int> bytes) => bytes.isEmpty
      ? null
      : bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
            .join();

  /// 单字节转两位大写 HEX。
  static String hexByte(int b) =>
      b.toRadixString(16).padLeft(2, '0').toUpperCase();
}
