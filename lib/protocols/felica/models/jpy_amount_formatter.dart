/// Formats the integer yen stored by Suica, with an unambiguous currency mark.
String formatJpyAmount(int yen, {bool showPositiveSign = false}) {
  final sign = yen < 0 ? '-' : (showPositiveSign && yen > 0 ? '+' : '');
  final digits = yen.toString().replaceFirst('-', '');
  final grouped = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) grouped.write(',');
    grouped.write(digits[index]);
  }
  return '${sign}JP￥$grouped';
}
