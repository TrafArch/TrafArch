/// City Union（CJ/T 331-2016）字节编解码工具（读取层与解析层共用）。
///
/// 集中 BCD / HEX 转换逻辑，两种编码口径严格区分：
/// - BCD 按十进制半字节逐位解码为数字字符串（保留前导零，如
///   [0x00, 0x12] -> "0012"，[0x26] -> "26"）；
/// - HEX 按字节原样转大写（如 [0x26] -> "26"，其十进制值为 38）。
/// 调用方不得混用（0x26 作为 BCD 是十进制 26，作为 HEX 是十进制 38）。
class CityUnionCodec {
  CityUnionCodec._();

  /// 是否为合法 BCD 字节（高/低半字节均 ≤ 9）。
  static bool isBcdByte(int b) => (b >> 4) <= 9 && (b & 0x0F) <= 9;

  /// BCD 字节数组转数字字符串（保留前导零）；
  /// 含非法半字节（0x0A~0x0F）时无法解码，返回 null。
  static String? bcdString(List<int> bytes) {
    if (bytes.isEmpty) return null;
    final sb = StringBuffer();
    for (final b in bytes) {
      final high = b >> 4;
      final low = b & 0x0F;
      if (high > 9 || low > 9) return null;
      sb
        ..write(high)
        ..write(low);
    }
    return sb.toString();
  }

  /// 校验 8 位 BCD 数字串（YYYYMMDD）是否为真实日历日期。
  /// 以 DateTime 反向校验，防止 20240230 这类非法日期被自动进位。
  static bool isValidDateDigits(String digits) {
    if (digits.length != 8) return false;
    final year = int.parse(digits.substring(0, 4));
    final month = int.parse(digits.substring(4, 6));
    final day = int.parse(digits.substring(6, 8));
    if (year < 1) return false;
    final parsed = DateTime.utc(year, month, day);
    return parsed.year == year && parsed.month == month && parsed.day == day;
  }

  /// 8 位 BCD 数字串（YYYYMMDD）转 "YYYY-MM-DD" 展示格式。
  static String formatDateDigits(String digits) => '${digits.substring(0, 4)}-'
      '${digits.substring(4, 6)}-'
      '${digits.substring(6, 8)}';

  /// 校验 6 位 BCD 数字串（HHMMSS）是否为合法时刻
  /// （时 ≤ 23、分/秒 ≤ 59，与 [isValidDateDigits] 同口径）。
  static bool isValidTimeDigits(String digits) {
    if (digits.length != 6) return false;
    final hour = int.parse(digits.substring(0, 2));
    final minute = int.parse(digits.substring(2, 4));
    final second = int.parse(digits.substring(4, 6));
    return hour <= 23 && minute <= 59 && second <= 59;
  }

  /// 6 位 BCD 数字串（HHMMSS）转 "HH:MM:SS" 展示格式。
  static String formatTimeDigits(String digits) => '${digits.substring(0, 2)}:'
      '${digits.substring(2, 4)}:'
      '${digits.substring(4, 6)}';

  /// 字节数组转连续大写 HEX 字符串（如 [0x0A, 0x01] -> "0A01"）。
  static String hex(List<int> bytes) => bytes.map(hexByte).join();

  /// 字节数组转空格分隔大写 HEX（逐字节核对用，如 "0A 01"）。
  static String hexSpaced(List<int> bytes) => bytes.map(hexByte).join(' ');

  /// 单字节转两位大写 HEX（如 0x2D -> "2D"）。
  static String hexByte(int value) =>
      value.toRadixString(16).padLeft(2, '0').toUpperCase();

  /// SFI 展示标签（如 0x15）。
  static String sfiLabel(int sfi) => '0x${hexByte(sfi)}';
}