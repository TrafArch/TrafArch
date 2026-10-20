library;

import '../felica_hex.dart';

/// FeliCa 块级工具：只提供与业务无关的字节读取，
/// 字段解释由卡种解析器负责。
class FelicaBlockParser {
  static const int blockSize = 16;

  static bool isValidBlock(List<int> bytes) => bytes.length == blockSize;

  /// 未写入块（全 0x00）。
  static bool isBlank(List<int> bytes) =>
      bytes.isNotEmpty && bytes.every((b) => (b & 0xFF) == 0x00);

  /// BCD 时间（YY MM DD hh mm ss）→ DateTime；任一段非法返回 null。
  static DateTime? bcdTime(List<int> bytes, int offset) {
    if (offset < 0 || offset + 6 > bytes.length) return null;
    for (var i = 0; i < 6; i++) {
      if (!FelicaHex.isBcd(bytes[offset + i])) return null;
    }
    final year = 2000 + FelicaHex.bcdToInt(bytes[offset]);
    final month = FelicaHex.bcdToInt(bytes[offset + 1]);
    final day = FelicaHex.bcdToInt(bytes[offset + 2]);
    final hour = FelicaHex.bcdToInt(bytes[offset + 3]);
    final minute = FelicaHex.bcdToInt(bytes[offset + 4]);
    final second = FelicaHex.bcdToInt(bytes[offset + 5]);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    if (hour > 23 || minute > 59 || second > 59) return null;
    final time = DateTime(year, month, day, hour, minute, second);
    // 排除 2 月 30 日等会被 DateTime 归一化的非法日期。
    if (time.month != month || time.day != day) return null;
    return time;
  }
}