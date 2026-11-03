/// The wallet's display form, independent of stored balances and ledger money.
class GalleryBalancePresentation {
  const GalleryBalancePresentation._({
    required this.known,
    required this.currencyLabel,
    required this.number,
    required this.displayText,
    required this.prefix,
    required this.suffix,
  });

  /// An ISO code is supplied by the caller or explicitly present in [original].
  /// Ambiguous currency symbols never supply a code on their own.
  factory GalleryBalancePresentation.parse(
    String original, {
    String? currencyCode,
  }) {
    final amount = RegExp(r'[-−+]?\d[\d,]*(?:\.\d+)?').firstMatch(original);
    if (amount == null) {
      return GalleryBalancePresentation._(
        known: false,
        currencyLabel: '',
        number: '',
        displayText: original,
        prefix: '',
        suffix: '',
      );
    }

    var number = amount.group(0)!;
    var prefix = original.substring(0, amount.start).trim();
    final suffix = original.substring(amount.end).trim();
    // Some existing values put their sign before the currency marker. Keep the
    // same sign with the numeric column rather than discarding it with the unit.
    if (!RegExp(r'^[-−+]').hasMatch(number)) {
      final leadingSign = RegExp(r'^([-−+])\s*').firstMatch(prefix);
      final trailingSign = RegExp(r'([-−+])\s*$').firstMatch(prefix);
      final sign = leadingSign ?? trailingSign;
      if (sign != null) {
        number = '${sign.group(1)}$number';
        prefix = prefix.replaceRange(sign.start, sign.end, '').trim();
      }
    }

    final suppliedCode = currencyCode?.trim().toUpperCase();
    final explicitCode = suppliedCode == null || suppliedCode.isEmpty
        ? RegExp(
            r'(^|[^A-Za-z])(CNY|JPY|HKD|USD|MOP)(?=$|[^A-Za-z])',
            caseSensitive: false,
          ).firstMatch(original)?.group(2)?.toUpperCase()
        : suppliedCode;
    final symbol = _symbols[explicitCode];
    if (symbol != null) {
      final label = '$explicitCode $symbol';
      return GalleryBalancePresentation._(
        known: true,
        currencyLabel: label,
        number: number,
        displayText: '$label$number',
        prefix: label,
        suffix: '',
      );
    }

    return GalleryBalancePresentation._(
      known: true,
      currencyLabel: [
        prefix,
        suffix,
      ].where((part) => part.isNotEmpty).join(' '),
      number: number,
      displayText: original,
      prefix: prefix,
      suffix: suffix,
    );
  }

  static const _symbols = {
    'CNY': '¥',
    'JPY': '¥',
    'HKD': r'$',
    'USD': r'$',
    'MOP': '¥',
  };

  /// Whether [number] contains an observed amount, including zero or negatives.
  final bool known;

  /// The complete unit label for the common currency column.
  final String currencyLabel;

  /// Numeric text keeps its original precision, grouping, and sign character.
  final String number;

  /// Unknown currencies and unavailable balances retain their original text.
  final String displayText;

  /// Unrecognized markers keep their position for callers needing split text.
  /// Recognized currencies always use [prefix], with an empty [suffix].
  final String prefix, suffix;
}
