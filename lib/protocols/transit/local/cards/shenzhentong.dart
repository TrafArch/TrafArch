library;

import '../apdu_exchange.dart';
import '../card_aid.dart';
import '../local_card_models.dart';

/// SELECT PAY.SZT
class Shenzhentong {
  Shenzhentong(this._apdu);
  final ApduExchange _apdu;

  Future<bool> select(CardInfo info, List<ApduRecord> records) async {
    final r = await _apdu(CardAid.paySzt, 'SELECT SZT', records: records);
    if (r == null) return false;
    info.isSZT = true;
    return true;
  }
}
