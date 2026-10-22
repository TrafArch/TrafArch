library;

import '../apdu_exchange.dart';
import '../card_aid.dart';
import '../local_card_models.dart';
import '../local_hex.dart';

/// 北京互通卡探测：0x04 / 0x05 / SELECT 1001 / BALANCE
class BeijingLocalCard {
  BeijingLocalCard(this._apdu);
  final ApduExchange _apdu;

  Future<bool> probe(CardInfo info, List<ApduRecord> records) async {
    final r0x04 = await _apdu(
      const [0x00, 0xB0, 0x84, 0x00, 0x3C],
      '0x04',
      records: records,
      strict: true,
    );
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

    final r0x05 = await _apdu(
      const [0x00, 0xB0, 0x85, 0x00, 0x20],
      '0x05',
      records: records,
      strict: true,
    );
    await _apdu(CardAid.select1001, 'SELECT 1001', records: records);
    final balance = await _apdu(
      CardAid.balanceCheck,
      'BALANCE CHECK',
      records: records,
      strict: true,
    );
    if (balance == null) return false;

    if (!_isAllZero(balance)) {
      info.balance = LocalHex.readBEInt(balance.sublist(1));
      return true;
    }
    if (r0x05 != null && r0x05.length >= 9) {
      info.balance = -LocalHex.readBEInt(r0x05.sublist(6, 9));
      return true;
    }
    return false;
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
