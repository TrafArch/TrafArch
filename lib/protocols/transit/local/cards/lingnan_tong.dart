library;

import 'dart:typed_data';

import '../apdu_exchange.dart';
import '../card_aid.dart';
import '../local_card_models.dart';

class LingnanTong {
  LingnanTong(this._apdu, {DateTime Function()? today})
    : _today = today ?? DateTime.now;

  static const moduleName = '岭南通';
  final ApduExchange _apdu;
  final DateTime Function() _today;

  static bool matchesTuIdentity({
    required bool confirmed,
    required String? cardNumber,
  }) {
    if (!confirmed ||
        cardNumber == null ||
        cardNumber.isEmpty ||
        RegExp(r'[^0-9]').hasMatch(cardNumber)) {
      return false;
    }
    final number = cardNumber.replaceFirst(RegExp(r'^0+'), '');
    return const ['31048703', '31048709', '31048724'].any(number.startsWith);
  }

  Future<bool> selectAppy(List<ApduRecord> records, [CardExtras? extras]) =>
      _select(CardAid.payAppy, 'appy', records, extras ?? CardExtras());

  // Both application names are eight bytes. Keep shared Case 3 AIDs unchanged;
  // LNT needs Case 4 (Le=00) before any MF, TU or PSE selection.
  Future<bool> _select(
    List<int> aid,
    String name,
    List<ApduRecord> records,
    CardExtras extras,
  ) async {
    extras.slots['lnt.${name}Confirmed'] = false;
    final attempts = <Map<String, Object?>>[];
    extras.slots['lnt.${name}Select'] = attempts;
    for (final command in [
      <int>[...aid, 0x00],
      aid,
    ]) {
      final evidence = <String, Object?>{'command': _hex(command)};
      attempts.add(evidence);
      final result = await _apdu.exchange(
        command,
        policy: const ExchangePolicy(),
      );
      final response = result.response;
      evidence['statusWord'] = response?.statusWord;
      evidence['response'] = response == null
          ? null
          : List<int>.of(response.raw);
      evidence['selected'] = result.isSuccess;
      if (response != null) {
        records.add(
          ApduRecord()
            ..commandHex = _hex(command)
            ..response = response.raw
            ..label = 'SELECT PAY.${name.toUpperCase()}',
        );
      }
      if (result.isSuccess) {
        extras.slots['lnt.${name}Confirmed'] = true;
        return true;
      }
      // Only a real status rejection permits the single no-Le compatibility try.
      if (response == null) return false;
    }
    return false;
  }

  Future<void> read(
    CardInfo info,
    List<ApduRecord> records,
    CardExtras extras,
  ) async {
    info.isYCT = true;
    info.isLNT = true;
    info.currencyCode = 'CNY';
    // Only an explicit card status failure permits another info-file variant.
    for (final command in const [
      [0x00, 0xB0, 0x95, 0x00, 0x46],
      [0x00, 0xB0, 0x95, 0x40, 0x46],
      [0x00, 0xB0, 0x95, 0x00, 0x00],
      [0x00, 0xB0, 0x2D, 0x40, 0x46],
    ]) {
      final result = await _apdu.exchange(command);
      final response = result.response;
      if (response == null) break;
      if (!result.isSuccess) continue;
      final body = response.data;
      info.rawInfo = List<int>.of(body);
      extras.slots['lnt.infoRaw'] = List<int>.of(body);
      if (body.length >= 16) {
        final number = _hex(body.sublist(11, 16));
        if (RegExp(r'^[0-9]+$').hasMatch(number)) info.cardNumber = number;
      }
      if (body.length >= 27) info.issueDate = _fullDate(body.sublist(23, 27));
      if (body.length >= 31) info.expiryDate = _fullDate(body.sublist(27, 31));
      if (body.length >= 52) info.issuerCode = _hex(body.sublist(48, 52));
      if (body.length < 52) extras.slots['lnt.infoShort'] = true;
      break;
    }

    Future<List<int>?> stats() => _apdu.call(
      const [0x00, 0xB2, 0x01, 0x44, 0x16],
      'LNT monthly statistics',
      records: records,
      verbose: true,
    );
    var monthly = await stats();
    final ticl = await _select(CardAid.payTicl, 'ticl', records, extras);
    if (!ticl) return;
    if (monthly == null || monthly.length < 5) monthly = await stats();
    int? statsMonth;
    if (monthly != null) {
      extras.slots['lnt.statsRaw'] = List<int>.of(monthly);
      if (monthly.length >= 5) {
        final year = _bcd(monthly[3]);
        final month = _bcd(monthly[4]);
        if (year != null && month != null && month >= 1 && month <= 12) {
          statsMonth = (2000 + year) * 100 + month;
        }
      }
    }
    extras.slots['lnt.statsMonth'] = statsMonth;
    final balance = await _apdu.call(
      CardAid.balanceCheck,
      'LNT balance',
      records: records,
      verbose: true,
    );
    if (balance != null) {
      extras.slots['lnt.balanceRaw'] = List<int>.of(balance);
      if (balance.length == 4) {
        final raw = _be(balance);
        final low = raw & 0x7FFFFFFF;
        info.balance = raw & 0x80000000 == 0
            ? raw
            : low <= 1000000
            ? low
            : raw - 0x100000000;
      } else {
        extras.slots['lnt.balanceShortOrInvalid'] = true;
      }
    }

    final fares = <ApduRecord>[];
    final metadata = <Map<String, Object?>>[];
    extras.slots['lnt.transactions'] = metadata;
    for (var n = 1; n <= 30; n++) {
      final body = await _apdu.call([
        0x00,
        0xB2,
        n,
        0xC4,
        0x17,
      ], 'LNT transaction $n');
      if (body == null || body.length < 23) break;
      if (body.every((b) => b == 0)) continue;
      final type = body[9];
      final subtype = body[22];
      final amount = _be(body.sublist(6, 9));
      final record = ApduRecord()
        ..type = 2
        ..rawBody = Uint8List.fromList(body)
        ..recordNumber = n
        ..fileSelector = 0xC4
        ..posType = type
        ..terminalHex = _hex(body.sublist(10, 16))
        ..balanceDelta = type == 0x02 ? amount : -amount
        ..isMetro = type == 0x09 && const [0x11, 0x17, 0x31].contains(subtype);
      records.add(record);
      fares.add(record);
      metadata.add({
        'recordNumber': n,
        'rawBody': List<int>.of(body),
        'rawMonthDay': _hex(body.sublist(18, 20)),
        'rawTime': _hex(body.sublist(20, 23)),
        'subtype': subtype,
        'secondsKnown': false,
        'balanceKnown': false,
        'direction': record.isMetro
            ? (subtype == 0x11 ? 'entry' : 'exit')
            : null,
        'yearInferred': true,
      });
      // Update immediately so a later transport failure still leaves partial dates.
      _dateFares(fares, metadata, statsMonth, info.issueDate);
    }
  }

  void _dateFares(
    List<ApduRecord> fares,
    List<Map<String, Object?>> metadata,
    int? statsMonth,
    DateTime? issue,
  ) {
    final now = _today();
    final today = DateTime.utc(now.year, now.month, now.day);
    final lower = issue == null
        ? null
        : DateTime.utc(issue.year, issue.month, issue.day);
    final relative = <int?>[];
    int? newer;
    var wraps = 0;
    final days = <int?>[];
    for (final record in fares) {
      final b = record.rawBody!;
      final m = _bcd(b[18]);
      final d = _bcd(b[19]);
      final valid = m != null && d != null && _date(2000, m, d) != null;
      final mmdd = valid ? m * 100 + d : null;
      days.add(mmdd);
      if (mmdd == null) {
        relative.add(null);
      } else {
        if (newer != null && mmdd > newer) wraps--;
        relative.add(wraps);
        newer = mmdd;
      }
    }
    final indices = [
      for (var i = 0; i < days.length; i++)
        if (days[i] != null) i,
    ];
    DateTime? at(int i, int base) =>
        _date(base + relative[i]!, days[i]! ~/ 100, days[i]! % 100);
    bool bounded(int base) => indices.every((i) {
      final date = at(i, base);
      return date != null &&
          !date.isAfter(today) &&
          (lower == null || !date.isBefore(lower));
    });
    int? base;
    var basis = 'today';
    if (indices.isNotEmpty && statsMonth != null) {
      for (final i in indices) {
        if (days[i]! ~/ 100 != statsMonth % 100) continue;
        final candidate = statsMonth ~/ 100 - relative[i]!;
        if (bounded(candidate)) {
          base = candidate;
          basis = 'statistics-month-match';
          break;
        }
      }
      if (base == null) {
        final oldest = indices.last;
        var candidate = statsMonth ~/ 100 - relative[oldest]!;
        final day = at(oldest, candidate);
        if (day == null || day.year * 100 + day.month <= statsMonth) {
          candidate++;
        }
        if (lower != null) {
          candidate = candidate < lower.year - relative[oldest]!
              ? lower.year - relative[oldest]!
              : candidate;
          if (at(oldest, candidate)?.isBefore(lower) ?? false) {
            candidate++;
          }
        }
        if (bounded(candidate)) {
          base = candidate;
          basis = 'after-statistics-month';
        }
      }
    }
    if (base == null && indices.isNotEmpty) {
      final minimum = lower?.year ?? 1;
      for (var year = today.year; year >= minimum; year--) {
        if (bounded(year)) {
          base = year;
          break;
        }
      }
    }
    for (var i = 0; i < fares.length; i++) {
      final b = fares[i].rawBody!;
      final hour = _bcd(b[20]);
      final minute = _bcd(b[21]);
      final day = base == null || relative[i] == null ? null : at(i, base);
      final valid =
          day != null &&
          hour != null &&
          hour < 24 &&
          minute != null &&
          minute < 60;
      fares[i].timestamp = valid
          ? DateTime.utc(day.year, day.month, day.day, hour, minute)
          : DateTime.fromMillisecondsSinceEpoch(0);
      metadata[i]['yearBasis'] = base == null ? 'unknown' : basis;
      metadata[i]['inferredYear'] = day?.year;
      metadata[i]['dateUncertain'] = true;
      metadata[i]['invalidOrUnboundedDate'] = !valid;
      metadata[i]['statsMonth'] = statsMonth;
      metadata[i]['issueDate'] = lower?.toIso8601String();
      metadata[i]['today'] = today.toIso8601String();
    }
  }

  static int? _bcd(int b) =>
      (b >> 4) > 9 || (b & 15) > 9 ? null : (b >> 4) * 10 + (b & 15);
  static int _be(List<int> bytes) => bytes.fold(0, (v, b) => (v << 8) | b);
  static String _hex(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
  static DateTime? _date(int y, int m, int d) {
    if (y < 1 || m < 1 || m > 12 || d < 1 || d > 31) return null;
    final value = DateTime.utc(y, m, d);
    return value.year == y && value.month == m && value.day == d ? value : null;
  }

  static DateTime? _fullDate(List<int> b) {
    final parts = b.map(_bcd).toList();
    if (parts.any((v) => v == null)) return null;
    return _date(parts[0]! * 100 + parts[1]!, parts[2]!, parts[3]!);
  }
}
