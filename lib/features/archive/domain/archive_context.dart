/// Context captured with a read, never resolved from the current scan.
/// Null values mean unknown, including for legacy snapshots.
class ArchiveContext {
  final String? systemId;
  final String? applicationId;
  final String? currencyCode;
  final int? minorUnitDigits;
  final int? timeZoneOffsetMinutes;
  final String? clockBasis;
  final Map<String, dynamic> referencePackages;
  final Map<String, bool> observedFields;
  final Map<String, dynamic> extensions;

  const ArchiveContext({
    this.systemId,
    this.applicationId,
    this.currencyCode,
    this.minorUnitDigits,
    this.timeZoneOffsetMinutes,
    this.clockBasis,
    this.referencePackages = const {},
    this.observedFields = const {},
    this.extensions = const {},
  });

  factory ArchiveContext.fromJson(Map<String, dynamic> json) => ArchiveContext(
    systemId: json['systemId'] as String?,
    applicationId: json['applicationId'] as String?,
    currencyCode: json['currencyCode'] as String?,
    minorUnitDigits: json['minorUnitDigits'] as int?,
    timeZoneOffsetMinutes: json['timeZoneOffsetMinutes'] as int?,
    clockBasis: json['clockBasis'] as String?,
    referencePackages: Map.unmodifiable(
      (json['referencePackages'] as Map<String, dynamic>?) ?? const {},
    ),
    observedFields: Map.unmodifiable(
      ((json['observedFields'] as Map<String, dynamic>?) ?? const {})
          .cast<String, bool>(),
    ),
    extensions: Map.unmodifiable(json),
  );

  Map<String, dynamic> toJson() => {
    ...extensions,
    'systemId': systemId,
    'applicationId': applicationId,
    'currencyCode': currencyCode,
    'minorUnitDigits': minorUnitDigits,
    'timeZoneOffsetMinutes': timeZoneOffsetMinutes,
    'clockBasis': clockBasis,
    'referencePackages': referencePackages,
    'observedFields': observedFields,
  };

  /// Missing currency/scale is displayed explicitly, never defaulted to CNY.
  String formatAmount(int amount) {
    final digits = minorUnitDigits;
    final currency = currencyCode;
    if (digits == null || digits < 0 || digits > 9) {
      return '$amount 最小单位（${currency ?? '币种未知'}，单位精度未知）';
    }
    // String magnitude also handles the minimum signed integer without abs overflow.
    final magnitude = amount
        .toString()
        .replaceFirst('-', '')
        .padLeft(digits + 1, '0');
    final number = digits == 0
        ? magnitude
        : '${magnitude.substring(0, magnitude.length - digits)}.'
              '${magnitude.substring(magnitude.length - digits)}';
    final symbol = switch (currency) {
      'CNY' => '¥',
      'HKD' => 'HK\$',
      null => '币种未知',
      _ => currency,
    };
    return '$symbol ${amount < 0 ? '-' : ''}$number';
  }
}
