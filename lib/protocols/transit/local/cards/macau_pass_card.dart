library;

import 'dart:typed_data';

import '../apdu_exchange.dart';
import '../local_card_models.dart';
import '../local_hex.dart';

/// 澳门通实体卡（ISO-DEP）钱包应用。
///
/// 只解析实卡响应中已验证的字段；未确认的金额、终端号及卡号只保留原文。
class MacauPassCard {
  MacauPassCard(this._apdu);
  final ApduExchange _apdu;

  static const List<int> walletName = [
    0xB0,
    0xC4,
    0xC3,
    0xC5,
    0xCD,
    0xA8,
    0xC7,
    0xAE,
    0xB0,
    0xFC,
  ];
  static const int _logP2 = 0xC4;
  static const int _recordLength = 23;

  Future<bool> select(CardInfo info, List<ApduRecord> records) async {
    final fci = await _apdu.call(
      [0x00, 0xA4, 0x04, 0x00, walletName.length, ...walletName, 0x00],
      'SELECT 澳门通钱包',
      records: records,
    );
    if (fci == null || !_containsWalletNameTlv(fci)) return false;
    info.isMacauPass = true;
    info.currencyCode = 'MOP';
    final proprietary = _findTlv(fci, 0x9F0C);
    final cardNumber = proprietary == null
        ? null
        : _parseCardNumber(proprietary);
    if (cardNumber != null) info.cardNumber = cardNumber;
    return true;
  }

  Future<void> readBalanceAndRecords(
    CardInfo info,
    List<ApduRecord> records,
  ) async {
    final balance = await _apdu.call(
      const [0x80, 0x5C, 0x00, 0x02, 0x04],
      '澳门通余额',
      records: records,
    );
    if (balance != null && balance.length == 4) {
      info.balance = LocalHex.readBEInt(balance);
    }

    for (var number = 1; number <= 20; number++) {
      final body = await _apdu.call(
        [0x00, 0xB2, number, _logP2, 0x00],
        '澳门通交易记录',
        records: records,
      );
      if (body == null) break;
      if (body.length != _recordLength) continue;
      final timestamp = _parseTimestamp(body.sublist(16));
      records.add(
        ApduRecord()
          ..recordNumber = number
          ..fileSelector = _logP2
          ..label = '澳门通交易记录'
          ..response = List<int>.unmodifiable(body)
          ..rawBody = Uint8List.fromList(body)
          ..timestamp = timestamp ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
    }
  }

  static bool _containsWalletNameTlv(List<int> fci) {
    for (var i = 0; i + 2 + walletName.length <= fci.length; i++) {
      if (fci[i] != 0x84 || fci[i + 1] != walletName.length) continue;
      if (LocalHex.bytesToHex(fci.sublist(i + 2, i + 2 + walletName.length)) ==
          LocalHex.bytesToHex(walletName)) {
        return true;
      }
    }
    return false;
  }

  /// 已观察到的澳门通 9F0C 卡片资料为 45 字节，偏移 35..39 是 5 字节
  /// BCD 卡号。长度或 BCD 不符合时保持未知，避免从其他卡版式猜测卡号。
  static String? _parseCardNumber(List<int> proprietary) {
    if (proprietary.length != 45) return null;
    final bytes = proprietary.sublist(35, 40);
    if (bytes.any((b) => !_isBcd(b)) || bytes.every((b) => b == 0)) {
      return null;
    }
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
  }

  static List<int>? _findTlv(List<int> bytes, int expectedTag) {
    for (var offset = 0; offset < bytes.length;) {
      final first = bytes[offset++];
      var tag = first;
      if ((first & 0x1F) == 0x1F) {
        if (offset >= bytes.length) return null;
        tag = (first << 8) | bytes[offset++];
      }
      if (offset >= bytes.length) return null;
      final lengthByte = bytes[offset++];
      if ((lengthByte & 0x80) != 0) return null;
      final end = offset + lengthByte;
      if (end > bytes.length) return null;
      if (tag == expectedTag) return bytes.sublist(offset, end);
      if ((first & 0x20) != 0) {
        final nested = _findTlv(bytes.sublist(offset, end), expectedTag);
        if (nested != null) return nested;
      }
      offset = end;
    }
    return null;
  }

  static DateTime? _parseTimestamp(List<int> bytes) {
    if (bytes.length != 7 || bytes.any((b) => !_isBcd(b))) return null;
    final year =
        LocalHex.bcdToInt(bytes[0]) * 100 + LocalHex.bcdToInt(bytes[1]);
    final month = LocalHex.bcdToInt(bytes[2]);
    final day = LocalHex.bcdToInt(bytes[3]);
    final hour = LocalHex.bcdToInt(bytes[4]);
    final minute = LocalHex.bcdToInt(bytes[5]);
    final second = LocalHex.bcdToInt(bytes[6]);
    if (month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31 ||
        hour > 23 ||
        minute > 59 ||
        second > 59) {
      return null;
    }
    final value = DateTime(year, month, day, hour, minute, second);
    return value.year == year && value.month == month && value.day == day
        ? value
        : null;
  }

  static bool _isBcd(int value) =>
      ((value >> 4) & 0x0F) <= 9 && (value & 0x0F) <= 9;
}
