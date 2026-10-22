library;

import '../apdu_exchange.dart';
import '../card_aid.dart';
import '../local_card_models.dart';
import '../local_hex.dart';

/// SELECT PAY.APPY + PAY.TICL 读资料与余额
class YangchengTong {
  YangchengTong(this._apdu);
  final ApduExchange _apdu;

  Future<bool> selectAppy(List<ApduRecord> records) async {
    final r = await _apdu(CardAid.payAppy, 'SELECT YCT1', records: records);
    return r != null;
  }

  Future<void> readInfoAndBalance(
    CardInfo info,
    List<ApduRecord> records,
  ) async {
    final r0x15 = await _apdu(
      const [0x00, 0xB0, 0x95, 0x00, 0x46],
      '0x15',
      records: records,
      strict: true,
    );
    if (r0x15 == null) throw Exception('info');

    info.cardNumber = LocalHex.bytesToHex(r0x15.sublist(8, 18));
    info.rawInfo = r0x15;
    info.issuerCode = LocalHex.bytesToHex(r0x15.sublist(11, 16));
    info.validFromDays = r0x15[49] & 0xFF;
    info.expiryDate = _bcdDate(r0x15.sublist(27, 31));

    final ticl = await _apdu(CardAid.payTicl, 'SELECT YCT2', records: records);
    if (ticl == null) throw Exception('info');

    final balance = await _apdu(
      CardAid.balanceCheck,
      'BALANCE CHECK',
      records: records,
      strict: true,
    );
    if (balance == null) throw Exception('balance');
    info.balance = LocalHex.readBEInt(balance.sublist(1));
  }

  static DateTime? _bcdDate(List<int> b) {
    if (b.length < 4) return null;
    final y = LocalHex.bcdToInt(b[0]) * 100 + LocalHex.bcdToInt(b[1]);
    return DateTime.utc(
      y,
      LocalHex.bcdToInt(b[2]),
      LocalHex.bcdToInt(b[3]),
    ).toLocal();
  }
}
