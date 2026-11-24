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
    if (stats != null) {
      final time = _discountTime(stats);
      if (time != null) {
        session.extras.slots['suxin.discountTime'] = time;
        session.extras.slots['suxin.statsCount'] = stats[38];
      }
    }
    await session.readTransactions(TripFile.metro);
  }

  /// Calendar fields in the Suzhou metro discount record are packed MSB first.
  static String? _discountTime(List<int> stats) {
    if (stats[8] == 0) return null;
    final packed = TUnionCodec.beInt(stats, 8, 4);
    final year = 2000 + (packed >>> 26);
    final month = (packed >> 22) & 15;
    final day = (packed >> 17) & 31;
    final hour = (packed >> 12) & 31;
    final minute = (packed >> 6) & 63;
    final second = packed & 63;
    // Validate wall-clock fields independently of the phone's time zone.
    final clock = DateTime.utc(year, month, day, hour, minute, second);
    if (clock.month != month ||
        clock.day != day ||
        clock.hour != hour ||
        clock.minute != minute ||
        clock.second != second) {
      return null;
    }
    return '${clock.toIso8601String().substring(0, 19)}+08:00';
  }
}
