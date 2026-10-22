library;

import '../apdu_exchange.dart';
import '../card_aid.dart';
import '../local_card_models.dart';

/// SELECT SUXIN.DDF01 + SUZHOU PIN VERIFY
class SuzhouCard {
  SuzhouCard(this._apdu);
  final ApduExchange _apdu;

  Future<bool> select(CardInfo info, List<ApduRecord> records) async {
    final a = await _apdu(CardAid.suxin, 'SELECT SUXIN', records: records);
    if (a == null) return false;
    final b = await _apdu(
      CardAid.suzhouPinVerify,
      'SUZHOU PIN VERIFY',
      records: records,
    );
    if (b == null) return false;
    info.isSuzhou = true;
    info.isSuxin = true;
    return true;
  }
}
