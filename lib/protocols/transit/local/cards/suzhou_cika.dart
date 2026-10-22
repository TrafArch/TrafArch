library;

import '../apdu_exchange.dart';
import '../card_aid.dart';
import '../local_card_models.dart';

/// SELECT SUZ CIKA（计次票）
class SuzhouCika {
  SuzhouCika(this._apdu);
  final ApduExchange _apdu;

  Future<bool> select(CardInfo info, List<ApduRecord> records) async {
    final r = await _apdu(CardAid.suzCika, 'SELECT SUZ CIKA', records: records);
    if (r == null) return false;
    info.isSuzhou = true;
    info.isCika = true;
    info.isCikaMode = true;
    return true;
  }
}
