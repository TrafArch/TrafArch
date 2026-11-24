library;

import '../apdu_exchange.dart';
import '../card_aid.dart';
import '../local_card_models.dart';
import '../local_hex.dart';
import 'local_wallet_session.dart';

/// SELECT SUZ CIKA（计次票）
class SuzhouCika implements LocalWalletReader {
  SuzhouCika(this._apdu);
  final ApduExchange _apdu;

  @override
  Future<bool> select(CardInfo info, List<ApduRecord> records) async {
    final r = await _apdu(CardAid.suzCika, 'SELECT SUZ CIKA', records: records);
    if (r == null) return false;
    info.isSuzhou = true;
    info.isCika = true;
    info.isCikaMode = true;
    return true;
  }

  @override
  Future<void> read(LocalWalletSession session) async {
    if (await session.read(CardAid.selectMf, 'SELECT MF') == null) return;
    session.directory = '3F00';
    final raw = await session.read(
      const [0, 0xB0, 0x86, 0, 0x1A],
      '0x06',
      length: 26,
    );
    if (raw == null) return;
    final info = session.info;
    info.rawInfo = raw;
    info.subtypeCode = raw[6];
    if (raw[6] != 2) {
      session.issues.add('MF / 0x06 · 计次票类型不匹配（${raw[6]}）');
      return;
    }
    final days = LocalHex.readBEInt(raw.sublist(9, 11));
    info.cityCode = 2150;
    info.expiryDate = DateTime.utc(1970).add(Duration(days: days));
    if (await session.read(CardAid.suzCika, 'SELECT SZPK_ZYY') == null) return;
    session.directory = 'SZPK_ZYY';
    final count = await session.read(CardAid.balanceCheck, '剩余次数', length: 4);
    if (count != null) {
      info.remainingTrips = LocalHex.readBEInt(count.sublist(1));
    }
    await session.readTransactions(TripFile.metro);
  }
}
