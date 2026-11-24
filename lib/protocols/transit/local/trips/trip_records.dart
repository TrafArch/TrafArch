library;

import 'dart:typed_data';

import '../../tunion/tunion_codec.dart';
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

      final r = decode(info, resp, file, recNo, isTU: isTU);
      if (r == null) continue;
      if (!force &&
          lastIdentityIndex >= 0 &&
          _sameBytes(records[lastIdentityIndex].identity!, r.identity!)) {
        continue;
      }
      lastIdentityIndex = records.length;
      records.add(r);
    }
  }

  /// Standard 23-byte local purse record. Specialized SZT and LNT layouts
  /// are decoded by their own readers. A file address alone is not a mode.
  static ApduRecord? decode(
    CardInfo info,
    List<int> body,
    TripFile file,
    int number, {
    bool isTU = false,
    String? directory,
  }) {
    if (body.length != 23) return null;
    final type = body[9];
    final time = TUnionCodec.parseBcdDateTime(body.sublist(16, 23));
    if (time == null &&
        (type == 0 || type == 0xFF) &&
        (file == TripFile.metro ||
            body.every((b) => b == 0) ||
            body.every((b) => b == 0xFF))) {
      return null;
    }
    final amount = LocalHex.readBEInt(body.sublist(6, 9));
    final suxin =
        info.isSuxin || (info.isSuzhou && !info.isCikaMode && !info.isCika);
    final credit = !isTU && suxin
        ? type == 1
        : type == 2 || type == 0x12;
    final sfi = file.sfi.toRadixString(16).padLeft(2, '0').toUpperCase();
    final record = ApduRecord()
      ..recordNumber = number
      ..fileSelector = file.p2
      ..directory = directory
      ..response = body
      ..rawBody = Uint8List.fromList(body)
      ..identity = body.sublist(5, 23)
      ..label = [?directory, '0x$sfi #$number'].join(' / ')
      ..type = 2
      ..statusCode = LocalHex.readBEInt(body.sublist(0, 2))
      ..posType = type
      ..terminalHex = LocalHex.bytesToHex(body.sublist(10, 16));
    final delta = credit ? amount : -amount;
    if (info.isCika || (info.isTFT && directory == '1002')) {
      record.tripDelta = delta;
    } else {
      record.balanceDelta = delta;
    }
    if (time != null) {
      record.timestamp = info.timezoneOffsetMinutes == 0
          ? time
          : DateTime.utc(
              time.year,
              time.month,
              time.day,
              time.hour,
              time.minute,
              time.second,
            ).subtract(Duration(minutes: info.timezoneOffsetMinutes)).toLocal();
    }
    if (TUnionCodec.isBcdByte(body[10]) && TUnionCodec.isBcdByte(body[11])) {
      record.cityCode = TUnionCodec.bcdToInt(body.sublist(10, 12));
    }
    if (!info.isSuzhou && !info.isTFT) {
      record.isMetro = file == TripFile.metro;
      record.isBus = file == TripFile.bus;
      record.isFerry = file == TripFile.ferry;
      record.isOtherA = file == TripFile.suxinTx;
      record.isOtherB = file == TripFile.other;
    }
    return record;
  }

  Future<void> reconstructBalances(
    CardInfo info,
    List<ApduRecord> records,
  ) async {
    final balance = info.observedBalance;
    if (balance == null) return;
    var running = balance;
    for (var i = 0; i < records.length && i <= info.lastSeenRecordIndex; i++) {
      final r = records[i];
      if (!r.isMetro && !r.isBus && !r.isFerry && !r.isOtherA && !r.isOtherB) {
        continue;
      }
      r.balanceAfter = running;
      running -= r.balanceDelta;
      if (r.cityCode == info.cityCode) info.lastSeenRecordIndex = i;
    }
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] & 0xFF) != (b[i] & 0xFF)) return false;
    }
    return true;
  }
}
