/// Transaction classification and the historical Shenzhen bus caller path.
/// Frozen from TripReader 1.7.17-cn m750d and C0304d's TU carrier construction.
/// Source subtype/carrier numbers remain separate from protocol industry codes.
library;

part 'tunion_bus_caller_data.dart';

class TunionBusCaller {
  const TunionBusCaller._();

  static int? _prefix(Map<String, int> values, String key) {
    for (var n = key.length; n > 4; n--) {
      final value = values[key.substring(0, n)];
      if (value != null) return value;
    }
    return null;
  }

  /// m750d's Beijing terminal exception, used only to permit a location query
  /// for industry 00. It does not assign a ride mode or transaction meaning.
  static bool hasBeijingRailTerminal(String? city, String? terminal) {
    if (city != '1000' || terminal == null) return false;
    final key = terminal.toUpperCase();
    return RegExp(r'^0000[0-9A-F]{12}$').hasMatch(key) &&
        _prefix(_carrierA, '1000${key.substring(4)}') == 2;
  }

  /// Known source classifications only. The original default maps every
  /// unrecognized subtype to bus; the app deliberately keeps those unknown.
  static int classification({
    required String city,
    required String terminal,
    required String field,
    required int industry,
    required int type,
    required int signedAmountFen,
    String? rawHex,
  }) {
    if (field.length < 12 || terminal.length != 16) return 99;
    final pos = field.substring(0, 12).toUpperCase();
    final line = pos.substring(0, 4);
    final station = pos.substring(4, 8);
    final operator = pos.substring(8, 12);
    final raw = rawHex?.toUpperCase();
    if ((city == '4520' || city == '7910' || city == '8210') &&
        terminal.startsWith('${city}0000')) {
      return 2;
    }
    if ((line == '9999' || line == '270F') && signedAmountFen >= -1) return 40;
    if (city == '3380' && line == '0999' && industry == 2) return 40;
    if (city == '2900' && station == '0178' && industry == 2) return 7;
    if (city == '3010') {
      if (pos.startsWith('00') && industry == 2 && operator == '0004') return 3;
      if (line == '9001' && (operator == '0000' || operator == '0015')) {
        return 7;
      }
      if (industry == 254) return 40;
    }
    if (city == '4530' && pos == '000000010031') return 40;
    if (city == '4680' && pos == '000200000000' && signedAmountFen == 0) {
      return 40;
    }
    if (city == '3720' && pos.startsWith('FE') && type == 6) return 40;
    if (city == '3010' && industry == 255 && type == 6) return 25;
    if (city == '5850' && industry == 2 && pos.substring(2, 4) == '09') {
      return 7;
    }
    if ((city == '5810' || city == '5880') &&
        industry == 1 &&
        signedAmountFen == 0 &&
        type == 6) {
      return 40;
    }
    if (city == '3350' && industry == 1 && line == '0000' && type == 6) {
      return 7;
    }
    if (city == '1121' && const {5, 6, 7}.contains(type)) return 1;
    if (city == '3050' && terminal.startsWith('30500000') && industry == 2) {
      return 2;
    }
    if (city == '3610' &&
        raw != null &&
        raw.length >= 52 &&
        raw.substring(50, 52) == '19' &&
        industry == 1 &&
        signedAmountFen == 0 &&
        type == 6) {
      return 40;
    }
    if (city == '1340' && industry == 3) return 1;
    if (city == '6510' && industry == 1 && line == '0098') return 7;
    if (city == '1000' && industry == 0 && terminal.startsWith('0000')) {
      return _prefix(_carrierA, '1000${terminal.substring(4)}') ?? 40;
    }
    if (city == '7010' &&
        raw != null &&
        raw.length >= 76 &&
        raw.substring(68, 76) == '12697010') {
      return 1;
    }
    if (industry == 2 &&
        const {'4910', '3320', '7310', '3620', '5880'}.contains(city) &&
        !const {5, 6}.contains(type)) {
      return 2;
    }
    if (industry == 1 &&
        const {'1380', '6560', '8210', '4220'}.contains(city)) {
      return 1;
    }
    return switch (industry) {
      1 => 2,
      2 || 11 || 13 => 1,
      3 || 9 => 3,
      4 || 5 => 6,
      6 => 14,
      7 => 22,
      8 => 10,
      10 || 14 => 4,
      12 => 24,
      _ => 99,
    };
  }

  /// Carrier precedence from the source reader: exact terminal; Shenzhen
  /// local prefix; bus prefix (unless rail-classified); then classification.
  /// Rail prefix values are used solely to prevent a bus fallback on rail.
  static int carrier({
    required String city,
    required String terminal,
    required String field,
    required int classification,
  }) {
    if (field.length < 12 || terminal.length != 16) return classification;
    final pos = field.substring(0, 12).toUpperCase();
    var carrier = _carrierC['$city$terminal'] ?? 99;
    if (city == '5840' && terminal.startsWith('00000002')) {
      carrier = _prefix(_carrierA, '5180${terminal.substring(8)}') ?? carrier;
    }
    if (classification != 2 && classification != 4) {
      final bus = _prefix(_carrierE, '$city$pos');
      if (bus != null) return bus;
      if (carrier == 99) return classification;
      if (carrier != 2) return carrier;
    }
    // These are the source rail carrier prefix inputs, not station lookups.
    String? special;
    if (city == '3910' || city == '7010') {
      special = '$city${pos.substring(2, 4)}${pos.substring(6, 8)}';
    } else if (city == '4520' && terminal.startsWith('45200000')) {
      special = '$city${terminal.substring(8, 12)}';
    } else if (city == '3320' && !pos.startsWith('00')) {
      special = '${city}00${pos.substring(0, 2)}00${pos.substring(2, 4)}';
    } else if (city == '6510') {
      special = '$city${pos.substring(4, 8)}';
    } else if (city == '7910' &&
        terminal.startsWith('79100000') &&
        terminal.substring(8, 10) != '00') {
      final number = int.tryParse(terminal.substring(10, 12));
      if (number != null) {
        special =
            '${city}00${terminal.substring(8, 10)}${number.toRadixString(16).toUpperCase().padLeft(4, '0')}';
      }
    }
    final rail =
        (special == null ? null : _prefix(_carrierF, special)) ??
        _prefix(_carrierF, '$city$pos');
    return rail ?? (carrier == 99 || carrier == 1 ? classification : carrier);
  }

  static bool routeFallbackAllowed(int classification, int carrier) =>
      (classification == 1 && carrier != 13) || carrier == 1;

  /// m763q's selected table is exact, never a cross-table best-effort lookup.
  /// The caller must establish TU city5840, terminal00000002, carrier1, missing
  /// station, bus lookup enabled and a transaction before the fixed boundary.
  ///
  /// The original m764r Shenzhen branch parses field[0:4] as hexadecimal and
  /// divides by ten (rejecting exact multiples of ten), so 0020 yields current
  /// route 3 and 0015 yields route 2. The historical name is kept only when it
  /// contains the current route; M292 therefore survives 0015 but not 0020.
  static String? historicalShenzhenLine({
    required String city,
    required String? terminal,
    required int? carrier,
    required DateTime? transactionTime,
    required String? currentLine,
  }) {
    if (city != '5840' ||
        terminal == null ||
        terminal.length != 16 ||
        !RegExp(r'^[0-9A-Fa-f]{16}$').hasMatch(terminal) ||
        !terminal.startsWith('00000002') ||
        carrier != 1 ||
        transactionTime == null ||
        transactionTime.millisecondsSinceEpoch >= 1735675200000) {
      return currentLine;
    }
    final key = terminal.substring(8).toUpperCase();
    final values = key.startsWith('20')
        ? _shenzhenTerminalJ
        : key.startsWith('24')
        ? _shenzhenTerminalK
        : key.startsWith('3101')
        ? _shenzhenTerminalL
        : _shenzhenTerminalM;
    final historical = values[key];
    // Original m1288J0 is case-sensitive contains(), not startsWith().
    return historical != null &&
            (currentLine == null || historical.contains(currentLine))
        ? historical
        : currentLine;
  }
}
