library;

import 'dart:typed_data';

import '../apdu_exchange.dart';
import '../card_aid.dart';
import '../local_card_models.dart';
import '../local_hex.dart';

class Shenzhentong {
  Shenzhentong(this._apdu);
  final ApduExchange _apdu;

  static const moduleName = '深圳通（PAY.SZT）';
  static const tuModuleName = '深圳通（交通联合版）';
  static const tuCardNumberPrefix = '31048704';

  static bool matchesTuIdentity({
    required bool confirmed,
    required String? cardNumber,
  }) {
    final digits = cardNumber?.trim() ?? '';
    return confirmed &&
        RegExp(r'^[0-9]+$').hasMatch(digits) &&
        digits.replaceFirst(RegExp(r'^0+'), '').startsWith(tuCardNumberPrefix);
  }

  Future<void> read(CardInfo info, List<ApduRecord> records) async {
    final basic = await _apdu(
      const [0x00, 0xB0, 0x95, 0x00, 0x20],
      '深圳通基本信息 SFI 15',
      records: records,
      verbose: true,
    );
    if (basic != null) {
      info.rawInfo = List<int>.of(basic);
      if (basic.length == 32) {
        info.cardNumber =
            (basic[16] |
                    (basic[17] << 8) |
                    (basic[18] << 16) |
                    (basic[19] << 24))
                .toUnsigned(32)
                .toString();
        info.startDate = _date(basic.sublist(20, 24));
        info.issueDate = info.startDate;
        info.expiryDate = _date(basic.sublist(24, 28));
      }
    }

    final balance = await _apdu(
      CardAid.balanceCheck,
      '深圳通余额',
      records: records,
      verbose: true,
    );
    if (balance != null && balance.length == 4) {
      info.balance = LocalHex.readBEInt(balance);
    }

    for (var number = 1; number <= 20; number++) {
      final raw = await _apdu(
        [0x00, 0xB2, number, 0xC4, 0x00],
        '深圳通交易记录 SFI 18',
        records: records,
      );
      if (raw == null) break;
      final record = ApduRecord()
        ..recordNumber = number
        ..fileSelector = 0xC4
        ..label = '深圳通交易记录 SFI 18'
        ..response = List<int>.unmodifiable(raw)
        ..rawBody = Uint8List.fromList(raw);
      records.add(record);
      if (raw.length != 23) {
        record.hasError = true;
        continue;
      }
      final kind = raw[9];
      final timestamp = _date(raw.sublist(16, 23));
      final terminal = raw.sublist(10, 16);
      record
        ..posType = kind
        ..timestamp = timestamp ?? DateTime.fromMillisecondsSinceEpoch(0)
        ..terminalHex = terminal.every(_isBcd)
            ? LocalHex.bytesToHex(terminal)
            : null
        ..identity = List<int>.of(raw)
        ..hasError = timestamp == null || !terminal.every(_isBcd);
      if (kind == 0x09 || kind == 0x02) {
        final amount = LocalHex.readBEInt(raw.sublist(5, 9));
        record
          ..type = 2
          ..balanceDelta = kind == 0x09 ? -amount : amount;
      }
    }
  }

  static DateTime? _date(List<int> bytes) {
    if (!bytes.every(_isBcd)) return null;
    final parts = bytes.map(LocalHex.bcdToInt).toList();
    final year = parts[0] * 100 + parts[1];
    final month = parts[2];
    final day = parts[3];
    final hour = parts.length == 7 ? parts[4] : 0;
    final minute = parts.length == 7 ? parts[5] : 0;
    final second = parts.length == 7 ? parts[6] : 0;
    if (year == 0 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31 ||
        hour > 23 ||
        minute > 59 ||
        second > 59) {
      return null;
    }
    final result = DateTime(year, month, day, hour, minute, second);
    return result.year == year && result.month == month && result.day == day
        ? result
        : null;
  }

  static bool _isBcd(int value) => (value >> 4) <= 9 && (value & 0x0F) <= 9;

  Future<bool> select(CardInfo info, List<ApduRecord> records) async {
    final r = await _apdu(CardAid.paySzt, 'SELECT SZT', records: records);
    if (r == null) return false;
    info.isSZT = true;
    return true;
  }
}
