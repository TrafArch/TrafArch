library;

import '../apdu_exchange.dart';
import '../card_aid.dart';
import '../local_card_models.dart';
import '../local_hex.dart';
import '../../tunion/tunion_codec.dart';
import 'local_wallet_session.dart';

/// SELECT TFT
class TftLocalCard implements LocalWalletReader {
  TftLocalCard(this._apdu);
  final ApduExchange _apdu;

  static const String moduleName = '天府通';

  @override
  Future<bool> select(CardInfo info, List<ApduRecord> records) async {
    final r = await _apdu(CardAid.tft, 'SELECT TFT', records: records);
    if (r == null) return false;
    info.isTFT = true;
    return true;
  }

  @override
  Future<void> read(LocalWalletSession session) async {
    await session.readPurse(suxin: false);
    final stats = await session.read(
      const [0, 0xB2, 2, 0xD4, 0x33],
      '0x1A #2',
      length: 51,
      optional: true,
    );
    final slots = session.extras.slots;
    if (stats != null && stats[46] != 0) {
      final date = stats.sublist(46, 48);
      final month = LocalHex.bcdToInt(date[1]);
      if (date.every(TUnionCodec.isBcdByte) && month >= 1 && month <= 12) {
        slots['tft.statsMonth'] =
            (2000 + LocalHex.bcdToInt(date[0])) * 100 + month;
      }
      slots['tft.statsCount'] = LocalHex.readBEInt(stats.sublist(37, 39));
      slots['tft.statsAmountFen'] = LocalHex.readBEInt(stats.sublist(39, 42));
    }
    for (final file in [TripFile.metro, TripFile.suxinTx, TripFile.bus]) {
      await session.readTransactions(file);
    }
    if (await session.read(CardAid.select1002, 'SELECT 1002', optional: true) ==
        null) {
      return;
    }
    session.directory = '1002';
    final table = await session.read(
      const [0, 0xB0, 0x9A, 0, 0x30],
      '0x1A',
      length: 48,
      optional: true,
    );
    if (table != null) {
      final months = <String, int>{};
      for (var i = 0; i < 12; i++) {
        final offset = i * 4;
        final yearBytes = table.sublist(offset, offset + 2);
        if (!yearBytes.every(TUnionCodec.isBcdByte)) continue;
        final year = TUnionCodec.bcdToInt(yearBytes);
        if (year < 1970 || year > 2099) continue;
        final key = '$year-${(i + 1).toString().padLeft(2, '0')}';
        months[key] = LocalHex.readBEInt(table.sublist(offset + 2, offset + 4));
      }
      slots['tft.monthlyCounts'] = months;
    }
    await session.readTransactions(TripFile.metro);
    await session.readTransactions(TripFile.bus);
  }
}
