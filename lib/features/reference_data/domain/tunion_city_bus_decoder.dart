/// Frozen TripReader TU bus route rules, scoped by accepting transaction city.
///
/// The generated data is a graph of string slices, numeric conversions, exact
/// comparisons and labels. It is reduced from the original Smali control flow;
/// JADX's omitted jumps are not used as executable logic. The reproducible audit
/// and per-city source evidence live in work/upgrade-20261021 in the workspace.
/// No database key or raw record is rewritten by these display rules.
///
/// Provenance is the user's locally unpacked TripReader 1.7.17-cn APK. The
/// source audit proves compatibility behavior, not a redistribution license.
/// No upstream license grant for the unpacked application has been verified.
library;

part 'shanghai_bus_routes.dart';
part 'tunion_city_bus_rules.dart';

/// Additional ORIGINAL m764r arguments. A missing value never means zero, the
/// issuing city, or today's date. Only paths reading that value become unknown.
class TunionBusDecodeContext {
  final int? rawCity32;
  final int? rawCity36;

  /// Original signed transaction delta in fen: consumption is NEGATIVE.
  /// C0296Y.m694c()/f739n; C0304d.java:2781 negates the 1E amount bytes.
  /// Do not pass the unsigned record amount without its transaction direction.
  final int? amountFen;
  final DateTime? transactionTime;

  /// Full original TU terminal and source-derived carrier. Only the historical
  /// Shenzhen path reads these; a missing value never selects another table.
  final String? terminalId;
  final int? carrierCode;

  /// Source caller gate, when the record supplies classification context.
  /// Direct known-bus callers (including 1A) may leave this absent.
  final bool? routeFallbackAllowed;

  /// Original language index: 1 zh-Hans, 2 zh-Hant, 3 English, 4 Japanese.
  final int language;

  const TunionBusDecodeContext({
    this.rawCity32,
    this.rawCity36,
    this.amountFen,
    this.transactionTime,
    this.terminalId,
    this.carrierCode,
    this.routeFallbackAllowed,
    this.language = 1,
  });

  /// The original caller reads bytes 32/33 and 36/37 independently, even when
  /// a nibble exceeds nine. AF therefore means 175 - (175 ~/ 16) * 6 = 115.
  /// A short record leaves both city inputs unknown; no issuer fallback occurs.
  factory TunionBusDecodeContext.fromCycleRecord(
    List<int> raw, {
    int? amountFen,
    DateTime? transactionTime,
    int language = 1,
  }) {
    int bcdArithmetic(int byte) {
      final unsigned = byte & 0xff;
      return unsigned - (unsigned ~/ 16) * 6;
    }

    int? cityAt(int offset) => raw.length < 48
        ? null
        : bcdArithmetic(raw[offset]) * 100 + bcdArithmetic(raw[offset + 1]);
    return TunionBusDecodeContext(
      rawCity32: cityAt(32),
      rawCity36: cityAt(36),
      amountFen: amountFen,
      transactionTime: transactionTime,
      language: language,
    );
  }
}

/// [field] is the complete seven-byte 1E field (or the equivalent 1A field).
/// Original txLine/pos comprises its first six bytes; the last byte is reserved.
/// The special city -2 is available only when explicitly passed by the caller.
String? decodeTunionCityBusLine({
  required String cityCode,
  required String field,
  TunionBusDecodeContext context = const TunionBusDecodeContext(),
}) {
  if (!_busField.hasMatch(field) ||
      !_busCity.hasMatch(cityCode) ||
      context.language < 1 ||
      context.language > 4) {
    return null;
  }
  final root = _cityBusRoots[cityCode];
  if (root == null) return null;
  final values = <String, Object?>{
    'pos': field.substring(0, 12).toUpperCase(),
    'language': context.language,
    'rawCity32': context.rawCity32,
    'rawCity36': context.rawCity36,
    'amountFen': context.amountFen,
    'timeMs': context.transactionTime?.millisecondsSinceEpoch,
  };
  try {
    final result = _BusRuleEvaluation(values).read(root);
    // String.valueOf(toIntOrNull(...)) in two original paths can produce the
    // literal "null". Retain unknown raw data instead of displaying that word.
    return result is String && result.isNotEmpty && result != 'null'
        ? result
        : null;
  } on _MissingBusContext {
    return null;
  }
}

final _busField = RegExp(r'^[0-9A-Fa-f]{14}$');
final _busCity = RegExp(r'^(?:[0-9]{4}|-2)$');

class _MissingBusContext implements Exception {
  const _MissingBusContext();
}

/// Evaluates only the selected path, so an unrelated missing date/amount does
/// not disable a city's context-free mappings. Node results are per-call cached.
class _BusRuleEvaluation {
  _BusRuleEvaluation(this.inputs);

  final Map<String, Object?> inputs;
  final Map<int, Object?> _cache = {};

  Object? read(int id) {
    if (_cache.containsKey(id)) return _cache[id];
    final node = _cityBusRules[id];
    Object? arg(int i) => read(node[i] as int);
    int integer(int i) => arg(i) as int;
    String string(int i) => arg(i) as String;
    int predicate(bool value) => value ? 1 : 0;
    final Object? result;
    switch (node[0]) {
      case 'value':
        result = node[1];
      case 'input':
        result = inputs[node[1]];
        if (result == null) throw const _MissingBusContext();
      case 'shanghai':
        result = _shanghaiBusRoutes;
      case 'if':
        result = arg(integer(1) != 0 ? 2 : 3);
      case 'switch':
        final branches = node[3] as Map<String, int>;
        result = read(branches[arg(1).toString()] ?? node[2] as int);
      case 'get':
        final source = arg(1);
        final key = integer(2);
        result = source is List ? source[key] : (source as Map)[key];
      case 'sub':
        result = string(1).substring(integer(2), integer(3));
      case 'take':
        final value = string(1);
        final count = integer(2);
        result = value.substring(
          0,
          count < value.length ? count : value.length,
        );
      case 'drop':
        final value = string(1);
        final count = integer(2);
        result = value.substring(count < value.length ? count : value.length);
      case 'last':
        final value = string(1);
        final count = integer(2);
        result = value.substring(
          count < value.length ? value.length - count : 0,
        );
      case 'char':
        result = string(1).codeUnitAt(integer(2));
      case 'chr':
        result = String.fromCharCode(integer(1));
      case 'trim':
        final value = string(1);
        final characters = arg(2) as List;
        var start = 0;
        while (start < value.length &&
            characters.contains(value.codeUnitAt(start))) {
          start++;
        }
        result = value.substring(start);
      case 'parse':
        final value = string(1);
        final parsed = _busInteger.hasMatch(value)
            ? int.tryParse(value, radix: integer(2))
            : null;
        // Kotlin's toIntOrNull uses signed 32-bit integers.
        result = parsed != null && parsed >= -2147483648 && parsed <= 2147483647
            ? parsed
            : null;
      case 'str':
        result = arg(1).toString();
      case 'concat':
        result = [for (var i = 1; i < node.length; i++) arg(i)].join();
      case 'eq':
        result = predicate(arg(1) == arg(2));
      case 'zero':
        final value = arg(1);
        result = predicate(value == null || value == 0);
      case 'isNull':
        // A boxed decimal zero is NOT null in the original Dalvik code.
        result = predicate(arg(1) == null);
      case 'not':
        result = predicate(integer(1) == 0);
      case 'lt':
        result = predicate(integer(1) < integer(2));
      case 'le':
        result = predicate(integer(1) <= integer(2));
      case 'gt':
        result = predicate(integer(1) > integer(2));
      case 'ge':
        result = predicate(integer(1) >= integer(2));
      case 'add':
        result = integer(1) + integer(2);
      case 'minus':
        result = integer(1) - integer(2);
      case 'div':
        result = integer(1) ~/ integer(2);
      case 'mod':
        final dividend = integer(1);
        final divisor = integer(2);
        result = dividend - (dividend ~/ divisor) * divisor;
      case 'cmp':
        result = integer(1).compareTo(integer(2));
      case 'hash':
        var hash = 0;
        for (final unit in string(1).codeUnits) {
          hash = (31 * hash + unit) & 0xffffffff;
        }
        result = hash >= 0x80000000 ? hash - 0x100000000 : hash;
      default:
        throw StateError('Unknown frozen TU bus expression: ${node[0]}');
    }
    _cache[id] = result;
    return result;
  }
}

final _busInteger = RegExp(r'^[+-]?[0-9A-Za-z]+$');
