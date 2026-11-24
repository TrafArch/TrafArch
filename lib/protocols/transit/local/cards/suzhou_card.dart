library;

import '../apdu_exchange.dart';
import '../card_aid.dart';
import '../local_card_models.dart';
import '../../tunion/tunion_codec.dart';
import 'local_wallet_session.dart';

/// 只读选择 SUXIN.DDF01；保护文件的状态字由读取层记录。
class SuzhouCard implements LocalWalletReader {
  SuzhouCard(this._apdu);
  final ApduExchange _apdu;

  @override
  Future<bool> select(CardInfo info, List<ApduRecord> records) async {
    final a = await _apdu(CardAid.suxin, 'SELECT SUXIN', records: records);
    if (a == null) return false;
    info.isSuzhou = true;
    info.isSuxin = true;
    return true;
  }

  @override
  Future<void> read(LocalWalletSession session) async {
    await session.readPurse(suxin: true);
    final stats = await session.read(
      const [0, 0xB2, 1, 0xCC, 0x32],
      '0x19 #1',
      optional: true,
      length: 50,
    );
    if (stats != null && stats[8] != 0) {
      session.extras.slots['suxin.statsDate'] = TUnionCodec.parseBcdDate(
        stats.sublist(8, 12),
      )?.toIso8601String();
      session.extras.slots['suxin.statsCount'] = stats[38];
    }
    await session.readTransactions(TripFile.metro);
  }
}
