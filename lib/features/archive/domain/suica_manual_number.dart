final _suicaPrintedNumberPattern = RegExp(r'^[A-Z]{2}[0-9]{15}$');

/// A card-back number entered by the user, separate from captured NFC identity.
/// An empty input means clear. Only whitespace and letter case are normalized.
String? normalizeSuicaManualNumber(String? input) {
  if (input == null) return null;
  final value = input.replaceAll(RegExp(r'\s'), '').toUpperCase();
  if (value.isEmpty) return null;
  if (!_suicaPrintedNumberPattern.hasMatch(value)) {
    throw const FormatException('卡面号码应为 2 位英文字母和 15 位数字，可包含空格');
  }
  return value;
}

class SuicaManualNumber {
  const SuicaManualNumber._(this.value, this.updatedAt);

  final String value;
  final int updatedAt;

  String get formatted =>
      '${value.substring(0, 5)} ${value.substring(5, 9)} '
      '${value.substring(9, 13)} ${value.substring(13)}';

  /// Clearing is represented by a supported v1 entry with a null value. It
  /// remains in backups so an older value cannot silently revive on import.
  static bool isSupportedJson(Object? json) {
    if (json is! Map ||
        json['version'] != 1 ||
        json['source'] != 'user' ||
        !json.containsKey('value')) {
      return false;
    }
    final updatedAt = json['updatedAt'];
    if (updatedAt is! int || updatedAt < 0 || updatedAt > 8640000000000000) {
      return false;
    }
    final value = json['value'];
    return value == null ||
        (value is String && _suicaPrintedNumberPattern.hasMatch(value));
  }

  /// Unsupported or malformed metadata is retained by storage but is never
  /// displayed as an observed or user-confirmed printed card number.
  static SuicaManualNumber? fromJson(Object? json) {
    if (!isSupportedJson(json)) return null;
    final fields = json as Map;
    final value = fields['value'];
    if (value is! String) return null;
    return SuicaManualNumber._(value, fields['updatedAt'] as int);
  }
}
