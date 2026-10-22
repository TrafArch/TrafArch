/// EMV / PBOC 日期字段（5F24 / 5F25 / 9A）的统一解码。
///
/// 规范形式为 3 字节 BCD YYMMDD，但实际卡片存在 4 字节 BCD YYYYMMDD
/// 与 ASCII 数字等变体；统一输出 `YYYY-MM-DD`，仅有年月时输出 `YYYY-MM`，
/// 不补造具体日。
class EmvDateCodec {
  EmvDateCodec._();

  /// 解码原始 HEX：3/4 字节 BCD 或 2~4 字节 ASCII 数字。
  static String? decodeHex(String rawHex) {
    final hex = rawHex.trim().toUpperCase();
    if (hex.isEmpty || hex.length.isOdd) return null;
    // ASCII 数字的 HEX 也可能恰好只含 0-9，BCD 解失败后再按 ASCII 解。
    if (RegExp(r'^[0-9]+$').hasMatch(hex)) {
      final bcd = normalize(hex);
      if (bcd != null) return bcd;
    }
    if (!RegExp(r'^[0-9A-F]+$').hasMatch(hex)) return null;
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      final b = int.tryParse(hex.substring(i, i + 2), radix: 16);
      if (b == null) return null;
      bytes.add(b);
    }
    return normalize(String.fromCharCodes(bytes));
  }

  /// 规范化解码文本：`YYYY-MM` / `YYYY-MM-DD` / 4、6、8 位纯数字。
  static String? normalize(String value) {
    final text = value.trim();
    final dashed = RegExp(r'^(\d{4})-(\d{1,2})(?:-(\d{1,2}))?$')
        .firstMatch(text);
    if (dashed != null) {
      final year = int.parse(dashed.group(1)!);
      final month = int.parse(dashed.group(2)!);
      final dayText = dashed.group(3);
      if (year < 1900 || year > 2199 || month < 1 || month > 12) {
        return null;
      }
      if (dayText == null) return '$year-${_two(month)}';
      final day = int.parse(dayText);
      if (!_validDate(year, month, day)) return null;
      return '$year-${_two(month)}-${_two(day)}';
    }
    if (!RegExp(r'^[0-9]+$').hasMatch(text)) return null;
    return _fromDigits(text);
  }

  static String? _fromDigits(String digits) {
    switch (digits.length) {
      case 4: // YYMM
        final year = _expandYear(int.parse(digits.substring(0, 2)));
        final month = int.parse(digits.substring(2, 4));
        if (month < 1 || month > 12) return null;
        return '$year-${_two(month)}';
      case 6: // YYMMDD
        final year = _expandYear(int.parse(digits.substring(0, 2)));
        final month = int.parse(digits.substring(2, 4));
        final day = int.parse(digits.substring(4, 6));
        if (!_validDate(year, month, day)) return null;
        return '$year-${_two(month)}-${_two(day)}';
      case 8: // YYYYMMDD
        final year = int.parse(digits.substring(0, 4));
        final month = int.parse(digits.substring(4, 6));
        final day = int.parse(digits.substring(6, 8));
        if (!_validDate(year, month, day)) return null;
        return '$year-${_two(month)}-${_two(day)}';
      default:
        return null;
    }
  }

  static int _expandYear(int yy) => yy <= 69 ? 2000 + yy : 1900 + yy;

  static bool _validDate(int year, int month, int day) {
    if (year < 1900 || year > 2199) return false;
    if (month < 1 || month > 12 || day < 1 || day > 31) return false;
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day;
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
