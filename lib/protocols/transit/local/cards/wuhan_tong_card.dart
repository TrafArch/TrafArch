library;

import '../apdu_exchange.dart';
import '../card_aid.dart';
import '../local_card_models.dart';
import '../local_hex.dart';

/// 老版武汉通（WHCTC，非接触 CPU 卡）。
///
/// 该卡不按 PBOC / 交通联合文件布局组织，需先读取 MF 下的 SFI 10 与 SFI 5，
/// 再选择应用 `AP1.WHCTC` 才能读取钱包与流水。只在 `AP1.WHCTC` 选择成功
/// 后认领卡片，避免普通卡片被误判；完成认领后即使后续读取失败也应作为
/// 地方卡返回，不能再落入 PBOC 探测。
class WuhanTongCard {
  WuhanTongCard(this._apdu);
  final ApduExchange _apdu;

  static const int _sfiSerial = 10;
  static const int _sfiInfo = 5;
  static const int _sfiLog = 24;
  static const int _maxLogs = 10;
  static const int _recordLength = 23;
  static const int cityCode = 5210;

  /// 探测并读取卡号 / 有效期 / 余额；应用选择失败返回 false（继续后续探测）。
  Future<bool> probe(CardInfo info, List<ApduRecord> records) async {
    await _apdu(CardAid.selectMf, 'SELECT MF', records: records);
    final serial = await _apdu(
      const [0x00, 0xB0, 0x80 | _sfiSerial, 0x00, 0x00],
      'SFI 10',
      records: records,
    );
    if (serial == null) return false;
    final infoFile = await _apdu(
      const [0x00, 0xB0, 0x80 | _sfiInfo, 0x00, 0x00],
      'SFI 5',
      records: records,
    );
    if (infoFile == null) return false;

    var balance = await _apdu(
      CardAid.balanceCheck,
      'BALANCE CHECK',
      records: records,
    );
    final selected = await _apdu(
      CardAid.payWhctc,
      'SELECT AP1.WHCTC',
      records: records,
    );
    if (selected == null) return false;

    info.isWHCTC = true;
    info.cityCode = cityCode;
    info.rawInfo = infoFile;
    if (serial.length >= 5) {
      info.cardNumber = LocalHex.bytesToHex(serial.sublist(0, 5));
    }
    if (infoFile.length >= 24) {
      info.expiryDate = _bcdDate(infoFile.sublist(16, 20));
      info.startDate = _bcdDate(infoFile.sublist(20, 24));
    }

    balance ??= await _apdu(
      CardAid.balanceCheck,
      'BALANCE CHECK',
      records: records,
    );
    if (balance != null && balance.length >= 4) {
      info.balance = _balanceOf(balance.sublist(0, 4));
    }
    return true;
  }

  /// 读取 SFI 24 交易流水：优先整文件读取，失败后逐条读取，首条失败即停止。
  Future<void> readLogs(CardInfo info, List<ApduRecord> records) async {
    final whole = await _apdu(
      const [0x00, 0xB2, 0x01, (_sfiLog << 3) | 0x05, 0x00],
      '0x18#WHCTC',
      records: records,
    );
    if (whole != null && whole.length >= _recordLength) {
      final count = (whole.length ~/ _recordLength).clamp(0, _maxLogs);
      for (var i = 0; i < count; i++) {
        _appendLog(
          records,
          whole.sublist(i * _recordLength, (i + 1) * _recordLength),
          i + 1,
        );
      }
      return;
    }

    for (var recNo = 1; recNo <= _maxLogs; recNo++) {
      final resp = await _apdu(
        [0x00, 0xB2, recNo, (_sfiLog << 3) | 0x04, 0x00],
        '0x18#WHCTC',
        records: records,
      );
      if (resp == null || resp.length < _recordLength) break;
      _appendLog(records, resp.sublist(0, _recordLength), recNo);
    }
  }

  void _appendLog(List<ApduRecord> records, List<int> raw, int recordNumber) {
    final amount = _signed32(LocalHex.readBEInt(raw.sublist(5, 9)));
    if (amount <= 0) return;
    final type = raw[9] & 0xFF;
    final isExpense = type == 0x06 || type == 0x09;
    records.add(
      ApduRecord()
        ..recordNumber = recordNumber
        ..fileSelector = (_sfiLog << 3) | 0x04
        ..response = raw
        ..identity = raw.sublist(5, 23)
        ..label = '0x18#WHCTC'
        ..type = 2
        ..posType = type
        ..terminalHex = LocalHex.bytesToHex(raw.sublist(10, 16))
        ..balanceDelta = isExpense ? -amount : amount
        ..timestamp =
            _bcdDateTime(raw.sublist(16, 22)) ??
            DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// 4 字节大端余额（分）；高位为负值时按有符号数解释，
  /// 并兼容以 0x80 为符号位的余额表示。
  static int _balanceOf(List<int> bytes) {
    var value = LocalHex.readBEInt(bytes);
    if ((value & 0x80000000) != 0) value -= 0x100000000;
    if (value > 1000000 || value < -1000000) {
      final shifted = (value + 0x80000000) & 0xFFFFFFFF;
      value = (shifted & 0x80000000) != 0 ? shifted - 0x100000000 : shifted;
    }
    return value;
  }

  static int _signed32(int raw) =>
      (raw & 0x80000000) != 0 ? raw - 0x100000000 : raw;

  static DateTime? _bcdDate(List<int> bytes) {
    if (bytes.length < 4) return null;
    final year =
        LocalHex.bcdToInt(bytes[0]) * 100 + LocalHex.bcdToInt(bytes[1]);
    final month = LocalHex.bcdToInt(bytes[2]);
    final day = LocalHex.bcdToInt(bytes[3]);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime(year, month, day);
  }

  static DateTime? _bcdDateTime(List<int> bytes) {
    if (bytes.length < 6) return null;
    final year =
        LocalHex.bcdToInt(bytes[0]) * 100 + LocalHex.bcdToInt(bytes[1]);
    final month = LocalHex.bcdToInt(bytes[2]);
    final day = LocalHex.bcdToInt(bytes[3]);
    final hour = LocalHex.bcdToInt(bytes[4]);
    final minute = LocalHex.bcdToInt(bytes[5]);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    if (hour > 23 || minute > 59) return null;
    return DateTime(year, month, day, hour, minute);
  }
}
