import '../../../iso7816/apdu.dart';

/// 银行卡读取的封闭指令白名单。GPO 即使金额为零也可能递增卡内 ATC，
/// 因此不允许 GPO、GENERATE AC、认证、PIN 或任何写入指令。
abstract final class BankReadOnlyPolicy {
  static void validate(List<int> bytes) {
    final command = CommandApdu.parse(bytes);
    final ins = bytes[1];
    final p1 = bytes[2];
    final p2 = bytes[3];
    final select =
        command.cla == 0 &&
        ins == 0xA4 &&
        p1 == 4 &&
        p2 == 0 &&
        command.apduCase == ApduCase.case4Short &&
        bytes[4] >= 1 &&
        bytes[4] <= 16;
    final readRecord =
        command.cla == 0 &&
        ins == 0xB2 &&
        p1 >= 1 &&
        p1 <= 254 &&
        (p2 & 7) == 4 &&
        (p2 >> 3) >= 1 &&
        (p2 >> 3) <= 30 &&
        command.apduCase == ApduCase.case2Short;
    final getAtc =
        command.cla == 0x80 &&
        ins == 0xCA &&
        p1 == 0x9F &&
        p2 == 0x36 &&
        command.apduCase == ApduCase.case2Short;
    final getResponse =
        command.cla == 0 &&
        ins == 0xC0 &&
        p1 == 0 &&
        p2 == 0 &&
        command.apduCase == ApduCase.case2Short;
    if (!select && !readRecord && !getAtc && !getResponse) {
      throw ArgumentError('银行卡只读流程禁止该 APDU');
    }
  }
}
