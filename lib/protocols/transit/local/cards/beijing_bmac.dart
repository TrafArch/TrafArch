library;

import '../apdu_exchange.dart';
import '../card_aid.dart';
import '../local_card_models.dart';
import '../local_hex.dart';

class BeijingBmac {
  BeijingBmac(this._apdu);
  final ApduExchange _apdu;

  static const moduleName = '北京市政交通一卡通（BMAC）';

  Future<bool> select(
    CardInfo info,
    List<ApduRecord> records,
    CardExtras extras,
  ) async {
    if (await _apdu(CardAid.selectMf, 'BMAC MF', records: records) == null) {
      return false;
    }
    final issuer = await _apdu(
      const [0x00, 0xB0, 0x84, 0x00, 0x3C],
      'BMAC 发行信息',
      records: records,
      strict: true,
    );
    if (issuer == null || issuer.length != 60) return false;
    final serial = issuer.sublist(0, 8);
    final effective = _date(issuer.sublist(24, 28));
    final expiry = _date(issuer.sublist(28, 32));
    if (!_bcd(serial) ||
        serial.every((b) => b == 0) ||
        effective == null ||
        expiry == null ||
        expiry.isBefore(effective)) {
      return false;
    }
    final basic = await _apdu(
      const [0x00, 0xB0, 0x85, 0x00, 0x20],
      'BMAC 基本信息',
      records: records,
      strict: true,
    );
    if (basic == null || basic.length != 32) return false;
    if (await _apdu(CardAid.select1001, 'BMAC DF 1001', records: records) ==
        null) {
      return false;
    }
    info
      ..isBmac = true
      ..cardNumber = LocalHex.bytesToHex(serial)
      ..rawInfo = List.of(issuer)
      ..cityCode = 1000
      ..issueDate = effective
      ..expiryDate = expiry;
    extras.slots['bmac.issuerRaw'] = LocalHex.bytesToHex(issuer);
    extras.slots['bmac.basicRaw'] = LocalHex.bytesToHex(basic);
    extras.slots['bmac.overdraftRaw'] = _uint(basic.sublist(0, 3));
    extras.slots['bmac.transactionCount'] = _uint(basic.sublist(3, 5));
    return true;
  }

  Future<void> read(
    CardInfo info,
    List<ApduRecord> records,
    CardExtras extras,
  ) async {
    final balance = await _apdu(
      CardAid.balanceCheck,
      'BMAC 余额',
      records: records,
      strict: true,
    );
    if (balance != null && balance.length == 4) {
      extras.slots['bmac.balanceRaw'] = LocalHex.bytesToHex(balance);
      final value = _uint(balance);
      info.balance = value == 0
          ? -(extras.slots['bmac.overdraftRaw']! as int)
          : value;
    }
    final recharges = <Map<String, Object?>>[];
    extras.slots['bmac.recharges'] = recharges;
    for (var n = 1; n <= 3; n++) {
      final raw = await _apdu(
        [0x00, 0xB2, n, 0x9C, 0x17],
        'BMAC 充值 #$n',
        records: records,
        strict: true,
      );
      if (raw == null) break;
      final entry = <String, Object?>{
        'recordNumber': n,
        'rawHex': LocalHex.bytesToHex(raw),
      };
      recharges.add(entry);
      if (raw.length != 23) {
        entry['malformed'] = true;
        continue;
      }
      entry.addAll({
        'balanceBeforeRaw': _uint(raw.sublist(0, 3)),
        'balanceAfterRaw': _uint(raw.sublist(3, 6)),
        'dateBcd': LocalHex.bytesToHex(raw.sublist(8, 11)),
        'dateBcdValid': _shortDateValid(raw.sublist(8, 11)),
        'terminalHex': LocalHex.bytesToHex(raw.sublist(11, 17)),
      });
      // YY does not establish a century; preserve it without inventing a date.
    }
    final bus = await _apdu(
      const [0x00, 0xB0, 0x94, 0x00, 0x18],
      'BMAC 公交过程',
      records: records,
      strict: true,
    );
    if (bus == null) return;
    extras.slots['bmac.busRaw'] = LocalHex.bytesToHex(bus);
    if (bus.length != 24) return;
    extras.slots['bmac.bus'] = {
      'boardingTimeBcd': LocalHex.bytesToHex(bus.sublist(0, 6)),
      'boardingTimeBcdValid':
          _shortDateValid(bus.sublist(0, 3)) &&
          _bcd(bus.sublist(3, 6)) &&
          _decimal(bus[3]) < 24 &&
          _decimal(bus[4]) < 60 &&
          _decimal(bus[5]) < 60,
      'directionRaw': bus[6],
      'lineCode': bus[9] | (bus[10] << 8),
    };
  }

  static int _uint(List<int> bytes) =>
      bytes.fold(0, (value, byte) => (value << 8) | byte);

  static bool _bcd(List<int> bytes) =>
      bytes.every((b) => b >> 4 <= 9 && (b & 15) <= 9);

  static int _decimal(int b) => (b >> 4) * 10 + (b & 15);

  static DateTime? _date(List<int> bytes) {
    if (!_bcd(bytes)) return null;
    final year = _decimal(bytes[0]) * 100 + _decimal(bytes[1]);
    final month = _decimal(bytes[2]);
    final day = _decimal(bytes[3]);
    final date = DateTime.utc(year, month, day);
    return year > 0 &&
            date.year == year &&
            date.month == month &&
            date.day == day
        ? date
        : null;
  }

  static bool _shortDateValid(List<int> bytes) =>
      _bcd(bytes) && _date([0x20, ...bytes]) != null;
}
