library;

import '../../tunion/tunion_codec.dart';
import '../apdu_exchange.dart';
import '../card_aid.dart';
import '../local_card_models.dart';
import '../local_hex.dart';
import 'df1001_directory.dart';

/// 北京互通卡探测：0x04 / 0x05 / SELECT 1001 / BALANCE
class BeijingLocalCard {
  BeijingLocalCard(this._apdu);
  final ApduExchange _apdu;

  Future<bool> probe(CardInfo info, List<ApduRecord> records) async {
    final directory = Df1001Directory(_apdu);
    if (!await directory.select(records) || !identify(directory, info)) {
      return false;
    }
    await readBalance(directory.basic, info, records);
    return true;
  }

  static bool identify(Df1001Directory directory, CardInfo info) {
    final r0x04 = directory.issuer;
    if (r0x04 == null || r0x04.length < 32) return false;
    if (!(r0x04[0] == 16 &&
        r0x04[1] == 0 &&
        r0x04[24] == 32 &&
        r0x04[28] == 32)) {
      return false;
    }

    info.cardNumber = LocalHex.bytesToHex(r0x04.sublist(0, 10));
    info.rawInfo = r0x04;
    info.issuerCode = LocalHex.bytesToHex(r0x04.sublist(0, 8));
    info.cityCode = 1000;
    info.expiryDate = _bcdDate(r0x04.sublist(28, 32));

    info.isBeijing = true;
    return true;
  }

  Future<void> readBalance(
    List<int>? r0x05,
    CardInfo info,
    List<ApduRecord> records,
  ) async {
    final balance = await _apdu(
      CardAid.balanceCheck,
      'BALANCE CHECK',
      records: records,
      strict: true,
    );
    if (balance == null || balance.length != 4) return;
    if (!_isAllZero(balance)) {
      info.balance = LocalHex.readBEInt(balance.sublist(1));
    } else if (r0x05 != null && r0x05.length >= 9) {
      info.balance = -LocalHex.readBEInt(r0x05.sublist(6, 9));
    }
  }

  Future<void> readExtras(List<ApduRecord> records, CardExtras extras) async {
    final raw = await _apdu(
      const [0, 0xB0, 0x95, 0, 0x32],
      '0x15',
      records: records,
      strict: true,
      verbose: true,
    );
    if (raw == null || raw.length != 50 || raw[37] == 0) return;
    extras.dateRaw = raw.sublist(37, 39);
    // This DF stores the three-byte amount least significant byte first.
    extras.amount = raw[40] | (raw[41] << 8) | (raw[42] << 16);
    extras.slots['displayCategory'] = 'f806b';
    extras.slots['displayAmount'] = extras.amount;
    final date = TUnionCodec.parseBcdDate([0x20, ...raw.sublist(37, 40)]);
    if (date != null) extras.slots['displayDate'] = date;
  }

  static bool _isAllZero(List<int> b) {
    for (final x in b) {
      if ((x & 0xFF) != 0) return false;
    }
    return true;
  }

  static DateTime? _bcdDate(List<int> b) {
    if (b.length < 4) return null;
    final y = LocalHex.bcdToInt(b[0]) * 100 + LocalHex.bcdToInt(b[1]);
    final m = LocalHex.bcdToInt(b[2]);
    final d = LocalHex.bcdToInt(b[3]);
    return DateTime.utc(y, m, d).toLocal();
  }
}
