library;

import '../apdu_exchange.dart';
import '../card_aid.dart';
import '../local_card_models.dart';
import '../local_hex.dart';

/// 多城市卡共用：卡号 / 发行方 / 有效期 / 余额
class CommonCardInfo {
  CommonCardInfo(this._apdu);
  final ApduExchange _apdu;

  Future<bool> read(CardInfo info, List<ApduRecord> records) async {
    if (info.isSuzhou && info.isCikaMode) {
      return _readSuzhouCika(info, records);
    }

    final r0x15 = await _apdu(
      const [0x00, 0xB0, 0x95, 0x00, 0x1E],
      '0x15',
      records: records,
      strict: true,
    );
    if (r0x15 == null) return false;

    info.issuerCode2 = LocalHex.bytesToHex(r0x15.sublist(0, 4));
    info.cardNumber = LocalHex.bytesToHex(r0x15.sublist(10, 20));

    if (info.isTU) {
      info.cityCode =
          LocalHex.bcdToInt(r0x15[3]) + LocalHex.bcdToInt(r0x15[2]) * 100;
      if (info.issuerCode.isNotEmpty) {
        info.issuerCode2 = info.issuerCode;
      }
      info.issuerCode = _shiftFirstDigit(
        LocalHex.bytesToHex(r0x15.sublist(10, 20)),
      );

      final r0x17 = await _apdu(
        const [0x00, 0xB0, 0x97, 0x00, 0x3C],
        '0x17',
        records: records,
        strict: true,
      );
      if (r0x17 == null) return false;
      info.terminalCode =
          LocalHex.bcdToInt(r0x17[7]) + LocalHex.bcdToInt(r0x17[6]) * 100;
      info.remainingTrips = LocalHex.readBEInt(r0x17.sublist(8, 10));
      info.validFromDays = r0x17[10] & 0xFF;
      return _readTuBalance(info, r0x15, records);
    }

    if (info.isSuzhou) {
      info.cityCode = 2150;
      info.issuerCode = LocalHex.bytesToHex(r0x15.sublist(0, 8));
    } else if (info.isBeijing) {
      info.cityCode = 5180;
      info.cardNumber = _tailN(
        LocalHex.readBEInt(r0x15.sublist(16, 20)).toString().padLeft(10, '0'),
        9,
      );
    } else {
      info.cityCode =
          LocalHex.bcdToInt(r0x15[3]) + LocalHex.bcdToInt(r0x15[2]) * 100;
      info.cardTypeCode = r0x15[8] & 0xFF;
      info.subtypeCode = r0x15[9] & 0xFF;
      return _dispatchByCityCode(info, r0x15, records);
    }

    return _readPlainBalance(info, r0x15, records);
  }

  Future<bool> _readSuzhouCika(CardInfo info, List<ApduRecord> records) async {
    await _apdu(CardAid.selectMf, 'SELECT MF', records: records);
    final r0x06 = await _apdu(
      const [0x00, 0xB0, 0x86, 0x00, 0x1A],
      '0x06',
      records: records,
      strict: true,
    );
    if (r0x06 == null || (r0x06[6] & 0xFF) != 2) return false;
    final cika = await _apdu(
      CardAid.suzCika,
      'SELECT SUZ CIKA',
      records: records,
    );
    if (cika == null) return false;

    info.cityCode = 2150;
    info.rawInfo = r0x06;
    info.subtypeCode = r0x06[6] & 0xFF;
    final days = LocalHex.readBEInt(r0x06.sublist(9, 11));
    info.startDate = DateTime.fromMillisecondsSinceEpoch(0)
        .add(Duration(days: days));

    final bal = await _apdu(
      CardAid.balanceCheck,
      'BALANCE CHECK',
      records: records,
      strict: true,
    );
    if (bal == null) return false;
    info.bonus = LocalHex.readBEInt(bal.sublist(1));
    return true;
  }

  Future<bool> _dispatchByCityCode(
    CardInfo info,
    List<int> r0x15,
    List<ApduRecord> records,
  ) async {
    switch (info.cityCode) {
      case 1160:
      case 2253:
        info.cardNumber =
            LocalHex.bytesToHex(r0x15.sublist(15, 16)) +
            _tailN(
              LocalHex.readBEInt(r0x15.sublist(16, 20))
                  .toString()
                  .padLeft(10, '0'),
              10,
            );
        break;
      case 2000:
      case 2140:
        info.cardNumber = _luhnExpand(r0x15.sublist(16, 20));
        break;
    }
    info.expiryDate = _bcdDate(r0x15.sublist(24, 28));
    return _readPlainBalance(info, r0x15, records);
  }

  Future<bool> _readPlainBalance(
    CardInfo info,
    List<int> r0x15,
    List<ApduRecord> records,
  ) async {
    info.rawInfo = r0x15;
    final cmd = info.cityCode == 2150
        ? CardAid.balanceCheck3
        : CardAid.balanceCheck;
    final bal = await _apdu(
      cmd,
      'BALANCE CHECK',
      records: records,
      strict: true,
    );
    if (bal == null) return false;
    info.balance = LocalHex.readBEInt(bal.sublist(1));
    return true;
  }

  Future<bool> _readTuBalance(
    CardInfo info,
    List<int> r0x15,
    List<ApduRecord> records,
  ) async {
    info.rawInfo = r0x15;
    final bal = await _apdu(
      CardAid.balanceCheck2,
      'BALANCE CHECK',
      records: records,
      strict: true,
    );
    if (bal == null) return false;

    var amount = LocalHex.readBEInt(bal.sublist(1, 4));
    final counter = LocalHex.readBEInt(bal.sublist(9, 12));
    if (amount == 0) amount -= counter;

    if (info.cityCode == 3060 || info.balance == -99999999) {
      info.balance = amount;
    } else {
      info.previousBalance = info.balance;
      info.deposit = amount;
      info.balance = info.balance + amount;
    }
    info.extraBalance = LocalHex.readBEInt(bal.sublist(13, 16));
    return true;
  }

  static String _shiftFirstDigit(String hex) =>
      hex.isEmpty ? hex : '0${hex.length > 1 ? hex.substring(1) : ''}';

  static String _tailN(String s, int width) =>
      s.length >= width ? s.substring(s.length - width) : s;

  static DateTime? _bcdDate(List<int> b) {
    if (b.length < 4) return null;
    final y = LocalHex.bcdToInt(b[0]) * 100 + LocalHex.bcdToInt(b[1]);
    return DateTime.utc(
      y,
      LocalHex.bcdToInt(b[2]),
      LocalHex.bcdToInt(b[3]),
    ).toLocal();
  }

  static String _luhnExpand(List<int> bytes) {
    final digits = LocalHex.readBEInt(bytes).toString().padLeft(10, '0');
    final table = const [0, 2, 4, 6, 8, 1, 3, 5, 7, 9];
    var sum = 0;
    var alt = true;
    for (var i = digits.length - 1; i >= 0; i--) {
      final d = int.parse(digits[i]);
      sum = alt ? (sum + table[d]) % 10 : (sum + d) % 10;
      alt = !alt;
    }
    final check = (10 - sum) % 10;
    return '$check$digits';
  }
}
