library;

import '../apdu_exchange.dart';
import '../card_aid.dart';
import '../local_card_models.dart';

/// SELECT TFT
class TftLocalCard {
  TftLocalCard(this._apdu);
  final ApduExchange _apdu;

  Future<bool> select(CardInfo info, List<ApduRecord> records) async {
    final r = await _apdu(CardAid.tft, 'SELECT TFT', records: records);
    if (r == null) return false;
    info.isTFT = true;
    return true;
  }
}
