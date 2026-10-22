library;

import '../apdu_exchange.dart';
import '../local_card_models.dart';
import '../local_hex.dart';

/// 通过 ISO7816 READ RECORD (INS=0xB2) 逐条读取行程流水 + 余额重建
class TripRecordReader {
  TripRecordReader(this._apdu);
  final ApduExchange _apdu;

  static const int _maxRecords = 31;
  static const int _recLen = 0x17;

  Future<void> readFile(
    CardInfo info,
    List<ApduRecord> records,
    CardExtras extras,
    TripFile file, {
    bool isTU = false,
    bool force = false,
  }) async {
    int lastIdentityIndex = -1;

    for (var recNo = 1; recNo <= _maxRecords; recNo++) {
      final cmd = [0x00, 0xB2, recNo, file.p2 & 0xFF, _recLen];
      final resp = await _apdu(cmd, '0x18', records: records, strict: true);
      if (resp == null) continue;

      _markFileSeen(info, file, isTU, recNo);

      if (resp.length < 23) continue; // 记录过短，防御异常卡

      final when = _parseBcdDateTime(
        resp.sublist(16, 22),
        info.timezoneOffsetMinutes,
      );
      final statusByte = resp[9] & 0xFF;
      if (when == null &&
          (statusByte == 0 || statusByte == 0xFF) &&
          file == TripFile.metro) {
        continue;
      }

      final identity = resp.sublist(5, 23);
      if (!force &&
          lastIdentityIndex >= 0 &&
          lastIdentityIndex < records.length &&
          _sameBytes(
            records[lastIdentityIndex].identity ?? const [],
            identity,
          )) {
        continue;
      }
      lastIdentityIndex = records.length;

      final r = ApduRecord()
        ..recordNumber = recNo
        ..fileSelector = file.p2
        ..response = resp
        ..identity = identity
        ..rawBody = null
        ..label = '0x18#${file.name}'
        ..type = 2;

      r.statusCode = _readBits(resp.sublist(0, 2), 14);
      r.posType = statusByte;
      r.terminalHex = LocalHex.bytesToHex(resp.sublist(10, 16));
      r.timestamp = when ?? DateTime.fromMillisecondsSinceEpoch(0);

      final amount = _readBits(resp.sublist(6, 9), 14);
      final isExpense = _isExpense(info, r, isTU);
      r.balanceDelta = isExpense ? -amount : amount;

      r.cityCode =
          LocalHex.bcdToInt(resp[10]) * 100 + LocalHex.bcdToInt(resp[11]);

      switch (file) {
        case TripFile.metro:
          r.isMetro = true;
          break;
        case TripFile.bus:
          r.isBus = true;
          break;
        case TripFile.ferry:
          r.isFerry = true;
          break;
        case TripFile.suxinTx:
          r.isOtherA = true;
          break;
        case TripFile.other:
          r.isOtherB = true;
          break;
      }

      records.add(r);
    }
  }

  Future<void> reconstructBalances(
    CardInfo info,
    List<ApduRecord> records,
  ) async {
    var running = info.balance;
    var negativeFix = (!info.isCU && running >= 0) ? 0 : running;

    for (var i = 0; i < records.length; i++) {
      final r = records[i];
      final isTransit =
          r.isMetro || r.isBus || r.isFerry || r.isOtherA || r.isOtherB;
      if (i <= info.lastSeenRecordIndex && isTransit) {
        if (info.isCU && r.type == 2) {
          await _matchLookup(
            info,
            r,
            records,
            negativeFix,
            (v) => negativeFix = v,
          );
        }
        r.balanceAfter = running;
        running -= r.balanceDelta;
      }
      _advanceLastSeen(info, r, i);
    }
  }

  Future<void> _matchLookup(
    CardInfo info,
    ApduRecord r,
    List<ApduRecord> records,
    int negFix,
    void Function(int) setNegFix,
  ) async {
    if (negFix >= 0 || r.type != 2) return;
    if (r.response == null || r.response!.length < 20) return;
    r.balanceDelta += negFix;
    var localFix = 0;
    for (var i6 = 1; i6 < 31; i6++) {
      final probe = await _apdu(
        [0x00, 0xB2, i6, 0x9C, 0x17],
        '0x13',
        records: records,
        strict: true,
      );
      if (probe == null || probe.length < 20) continue;
      final termMatch = _sameBytes(
        r.response!.sublist(10, 16),
        probe.sublist(11, 17),
      );
      final posMatch = _sameBytes(
        r.response!.sublist(17, 20),
        probe.sublist(8, 11),
      );
      if (termMatch && posMatch) {
        if ((probe[0] & 0xFF) == 0xFF) {
          localFix = _readBits(probe.sublist(0, 3), 6);
          r.balanceDelta = info.balance - localFix;
        } else {
          localFix = 0;
        }
        setNegFix(localFix);
        break;
      }
    }
    setNegFix(localFix);
  }

  void _advanceLastSeen(CardInfo info, ApduRecord r, int i) {
    if (info.lastSeenRecordIndex <= i) return;
    if ((r.isMetro && r.cityCode == info.cityCode) ||
        (r.isBus && r.cityCode == info.cityCode && !r.isMetro) ||
        (r.isFerry && r.cityCode == info.cityCode && !r.isMetro) ||
        (r.isOtherA && r.cityCode == info.cityCode) ||
        (r.isOtherB && r.cityCode == info.cityCode)) {
      info.lastSeenRecordIndex = i;
    }
  }

  void _markFileSeen(CardInfo info, TripFile file, bool isTU, int recNo) {
    // 记录“某文件已读到第 recNo 条”——原语义未回传展示层，保留占位。
  }

  static bool _isExpense(CardInfo info, ApduRecord r, bool isTU) {
    final t = r.posType;
    if ((isTU || !info.isCU) && (t == 2 || t == 18)) return true;
    if (!isTU && info.isCU && t == 1) return true;
    return false;
  }

  static int _readBits(List<int> bytes, int shift) =>
      LocalHex.readBEInt(bytes) >> shift;

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] & 0xFF) != (b[i] & 0xFF)) return false;
    }
    return true;
  }

  static DateTime? _parseBcdDateTime(List<int> b, int tzMinutes) {
    if (b.length < 6) return null;
    final yy = LocalHex.bcdToInt(b[0]) * 100 + LocalHex.bcdToInt(b[1]);
    final mo = LocalHex.bcdToInt(b[2]);
    final dd = LocalHex.bcdToInt(b[3]);
    final hh = LocalHex.bcdToInt(b[4]);
    final mi = LocalHex.bcdToInt(b[5]);
    if (mo == 0 || mo > 12 || dd == 0 || dd > 31) return null;
    return DateTime.utc(
      yy,
      mo,
      dd,
      hh,
      mi,
    ).add(Duration(minutes: -tzMinutes)).toLocal();
  }
}
