library;

import '../apdu_exchange.dart';
import '../card_aid.dart';
import '../local_card_models.dart';
import '../local_hex.dart';

/// 读取“卡扩展信息”（各城市专属 READ BINARY / READ RECORD 记录）
class CardExtrasReader {
  CardExtrasReader(this._apdu);
  final ApduExchange _apdu;

  static const kCategory = 'displayCategory';
  static const kAmount = 'displayAmount';
  static const kCount = 'displayCount';
  static const kDate = 'displayDate';

  static const blob0x10 = 'blob_0x10';
  static const blob0x11 = 'blob_0x11';
  static const blob0x11b = 'blob_0x11_2';
  static const blob0x14_4 = 'blob_0x14_4';
  static const blob0x14_5 = 'blob_0x14_5';
  static const blob0x1A = 'blob_0x1A';
  static const yearA = 'yearA';
  static const yearB = 'yearB';

  Future<void> readCommon(
    CardInfo info,
    List<ApduRecord> records,
    CardExtras extras, {
    bool? specialLocal,
  }) async {
    final city = info.cityCode;
    final isSpecialLocal = specialLocal ?? info.specialLocal;

    if (city == 1000) {
      final r = await _apdu(const [0x00, 0xB0, 0x95, 0x00, 0x32], '0x15',
          records: records, strict: true);
      if (r != null && _at(r, 37) > 0) {
        extras.dateRaw = _sub(r, 37, 39);
        extras.amount = _amount(r, 40, 43, 12);
        extras.slots[kCategory] = 'f806b';
        extras.slots[kDate] = _parseDate(_sub(r, 37, 40), 326, info.timezoneOffsetMinutes);
        extras.slots[kAmount] = extras.amount;
      }
    }

    if (city == 2000) {
      final r11a = await _apdu(const [0x00, 0xB2, 0x01, 0x8C, 0x10], '0x11 #1',
          records: records, strict: true);
      extras.slots[blob0x11] = _clearIfDead(r11a, 0, 1);

      final r11b = await _apdu(const [0x00, 0xB2, 0x02, 0x8C, 0x10], '0x11 #2',
          records: records, strict: true);
      if (r11b != null && _at(r11b, 0) != 0 && _at(r11b, 1) != 0) {
        extras.slots[blob0x11b] = r11b;
        extras.dateRaw = _sub(r11b, 1, 6);
        extras.amount = _amount(r11b, 12, 15, 12);
        extras.slots[kCategory] = 'f807c';
        extras.slots[kDate] = _parseDate(extras.dateRaw!, 350, info.timezoneOffsetMinutes);
        extras.slots[kAmount] = extras.amount;
        extras.slots[kCount] = _at(r11b, 11);
      }

      final r14a = await _apdu(const [0x00, 0xB2, 0x04, 0xA4, 0x10], '0x14 #4',
          records: records, strict: true);
      extras.slots[blob0x14_4] = _clearIfDead(r14a, 0, 1);

      final r14b = await _apdu(const [0x00, 0xB2, 0x05, 0xA4, 0x10], '0x14 #5',
          records: records, strict: true);
      extras.slots[blob0x14_5] = _clearIfDead(r14b, 0, 1);

      final r10 = await _apdu(const [0x00, 0xB2, 0x02, 0x84, 0x10], '0x10 #2',
          records: records, strict: true);
      if (r10 != null && _at(r10, 3) == 0) {
        extras.slots[blob0x10] = null;
      } else {
        extras.slots[blob0x10] = r10;
      }
    }

    if (city == 3100) {
      final r = await _apdu(const [0x00, 0xB2, 0x06, 0xB8, 0x30], '0x17 ^06',
          records: records, strict: true);
      if (r != null) {
        final flag = _at(r, 4);
        if (flag == 1) {
          extras.lineCode = _sub(r, 5, 11);
          extras.lineDirection = false;
        } else if (flag == 2 || flag == 3) {
          extras.lineCode = _sub(r, 5, 11);
          extras.lineDirection = true;
        }
        if (_bcd(r, 30) + _bcd(r, 29) * 100 >= 2312) {
          extras.slots[kCategory] = 'f813i';
          extras.slots[kDate] = _parseDate(_sub(r, 28, 32), 326, info.timezoneOffsetMinutes);
          extras.slots[kAmount] = _amount(r, 35, 37, 12);
        }
      }
    }

    if (isSpecialLocal) {
      final r08 = await _apdu(const [0x00, 0xB2, 0x01, 0x44, 0x16], '0x08 #1',
          records: records, strict: true);
      if (r08 != null && _at(r08, 3) != 0) {
        extras.dateRaw = _sub(r08, 3, 5);
        extras.slots[yearA] = 2000 + _bcd(r08, 3);
        extras.bonus = _at(r08, 7);
        extras.counter = _at(r08, 5);
        extras.amount = _amount(r08, 12, 14, 14);
        if (_bcd(r08, 4) + _bcd(r08, 3) * 100 >= 2309) {
          extras.slots[kCategory] = 'f809e';
          extras.slots[kAmount] = extras.amount;
        } else {
          extras.slots[kCategory] = 'f808d';
        }
        extras.slots[kDate] = _parseDate(extras.dateRaw!, 322, info.timezoneOffsetMinutes);
        extras.slots[kCount] = extras.bonus;
      }

      final r15 = await _apdu(const [0x00, 0xB0, 0x95, 0x00, 0x21], '0x15 #1',
          records: records, strict: true);
      if (r15 != null && _at(r15, 24) == 0x20) {
        extras.slots[yearB] = 2000 + _bcd(r15, 25);
      }

      final r0817 = await _apdu(const [0x00, 0xB2, 0x11, 0x44, 0x56], '0x08 #17',
          records: records, strict: true);
      extras.slots[blob0x11] = _clearIfDead(r0817, 8, 23);
    }

    if (city == 5180) {
      final r = await _apdu(const [0x00, 0xB2, 0x01, 0xCC, 0x20], '0x19 #1',
          records: records, strict: true);
      if (r != null && _at(r, 20) == 0) {
        extras.slots[blob0x10] = null;
      } else {
        extras.slots[blob0x10] = r;
      }
    }

    if (city == 2150 && !info.isCikaMode) {
      final r = await _apdu(const [0x00, 0xB2, 0x01, 0xCC, 0x32], '0x19 #1',
          records: records, strict: true);
      if (r != null && _at(r, 8) != 0) {
        extras.slots[blob0x11] = r;
        extras.dateRaw = _sub(r, 8, 12);
        extras.bonus = _amount(r, 38, 39, 14);
        extras.slots[kCategory] = 'f811g';
        extras.slots[kDate] = _parseDate(extras.dateRaw!, 382, info.timezoneOffsetMinutes);
        extras.slots[kCount] = extras.bonus;
      }
    }

    if (info.isTFT) {
      final r = await _apdu(const [0x00, 0xB2, 0x02, 0xD4, 0x33], '0x1A #2',
          records: records, strict: true);
      if (r != null && _at(r, 46) != 0) {
        extras.slots[blob0x1A] = r;
        extras.dateRaw = _sub(r, 46, 48);
        extras.amount = _amount(r, 39, 42, 14);
        extras.slots[kCategory] = 'f812h';
        extras.slots[kDate] = _parseDate(extras.dateRaw!, 322, info.timezoneOffsetMinutes);
        extras.slots[kAmount] = extras.amount;
        extras.slots[kCount] = _amount(r, 37, 39, 14);
      }
    }
  }

  Future<void> readLine(
    CardInfo info,
    List<ApduRecord> records,
    CardExtras extras,
  ) async {
    final city = info.cityCode;
    if (city != 3310 && city != 3370) return;

    final r = await _apdu(const [0x00, 0xB2, 0x06, 0xC8, 0x30], '0x19 ^06',
        records: records, strict: true);
    if (r == null) return;

    final flag = _at(r, 4);
    if (flag == 1) {
      extras.lineCode = _sub(r, 5, 11);
      extras.lineDirection = false;
    } else if (flag == 2 || flag == 3) {
      extras.lineCode = _sub(r, 5, 11);
      extras.lineDirection = true;
    }

    if (city == 3310 && _bcd(r, 30) + _bcd(r, 29) * 100 >= 2312) {
      extras.slots[kCategory] = 'f813i';
      extras.slots[kDate] = _parseDate(_sub(r, 28, 32), 326, info.timezoneOffsetMinutes);
      extras.slots[kAmount] = _amount(r, 35, 37, 12);
    }
  }

  Future<void> readExtended(
    CardInfo info,
    List<ApduRecord> records,
    CardExtras extras,
  ) async {
    final city = info.cityCode;

    if (city == 1000) {
      if (await _apdu(CardAid.motBmac, 'SELECT BJ', records: records) != null) {
        final r = await _apdu(const [0x00, 0xB2, 0x01, 0x1C, 0x32], '0x03 #1',
            records: records, strict: true);
        if (r != null && _at(r, 9) > 16) {
          extras.dateRaw = _sub(r, 9, 11);
          extras.amount = _amount(r, 12, 15, 14);
          extras.slots[kCategory] = 'f806b';
          extras.slots[kDate] = _parseDate(_sub(r, 9, 12), 326, info.timezoneOffsetMinutes);
          extras.slots[kAmount] = extras.amount;
        }
      }
      if (await _apdu(CardAid.selectTU, 'SELECT TU', records: records) == null) {
        throw Exception('info');
      }
      final r08 = await _apdu(const [0x00, 0xB2, 0x01, 0x44, 0x32], '0x08 #1',
          records: records, strict: true);
      if (r08 != null && _at(r08, 9) > 16) {
        extras.dateRaw = _sub(r08, 9, 11);
        extras.amount = _amount(r08, 12, 15, 14);
        extras.slots[kCategory] = 'f806b';
        extras.slots[kDate] = _parseDate(_sub(r08, 9, 12), 326, info.timezoneOffsetMinutes);
        extras.slots[kAmount] = extras.amount;
      }
    }

    if (city == 2900) {
      final r11a = await _apdu(const [0x00, 0xB2, 0x01, 0x8C, 0x10], '0x11 #1',
          records: records, strict: true);
      extras.slots[blob0x11] = _clearIfDead(r11a, 0, 1);

      final r11b = await _apdu(const [0x00, 0xB2, 0x02, 0x8C, 0x10], '0x11 #2',
          records: records, strict: true);
      if (r11b != null && _at(r11b, 0) != 0 && _at(r11b, 1) != 0) {
        extras.slots[blob0x11b] = r11b;
        extras.dateRaw = _sub(r11b, 1, 6);
        extras.amount = _amount(r11b, 12, 15, 12);
        extras.slots[kCategory] = 'm753g';
        extras.slots[kDate] = _parseDate(extras.dateRaw!, 350, info.timezoneOffsetMinutes);
        extras.slots[kAmount] = extras.amount;
        extras.slots[kCount] = _at(r11b, 11);
      }

      final r14a = await _apdu(const [0x00, 0xB2, 0x04, 0xA4, 0x10], '0x14 #4',
          records: records, strict: true);
      extras.slots[blob0x14_4] = _clearIfDead(r14a, 0, 1);
      final r14b = await _apdu(const [0x00, 0xB2, 0x05, 0xA4, 0x10], '0x14 #5',
          records: records, strict: true);
      extras.slots[blob0x14_5] = _clearIfDead(r14b, 0, 1);

      final r10 = await _apdu(const [0x00, 0xB2, 0x02, 0x84, 0x10], '0x10 #2',
          records: records, strict: true);
      extras.slots[blob0x10] = (r10 != null && _at(r10, 3) == 0) ? null : r10;
    }

    if (city == 3010) {
      final r07a = await _apdu(const [0x00, 0xB2, 0x01, 0x3C, 0x40], '0x07 #1',
          records: records, strict: true);
      extras.slots[blob0x10] = (r07a != null && _at(r07a, 3) != 0x20) ? null : r07a;

      final r07b = await _apdu(const [0x00, 0xB2, 0x02, 0x3C, 0x40], '0x07 #2',
          records: records, strict: true);
      if (r07b != null && _at(r07b, 10) == 0x20) {
        extras.dateRaw = _sub(r07b, 35, 39);
        extras.amount = _amount(r07b, 39, 41, 14);
        extras.slots[kCategory] = 'm752f';
        extras.slots[kDate] = _parseDate(extras.dateRaw!, 326, info.timezoneOffsetMinutes);
        extras.slots[kAmount] = extras.amount;
        extras.slots[kCount] = _amount(r07b, 41, 43, 14);
      }
    }

    if (city == 3020) {
      final r07 = await _apdu(const [0x00, 0xB2, 0x01, 0x3C, 0x10], '0x07 #1',
          records: records, strict: true);
      extras.slots[blob0x10] = (r07 != null && _at(r07, 10) == 0) ? null : r07;
    }

    if (city == 3050) {
      final r = await _apdu(const [0x00, 0xB2, 0x01, 0xCC, 0x32], '0x19 #1',
          records: records, strict: true);
      if (r != null && _at(r, 8) != 0) {
        extras.dateRaw = _sub(r, 8, 12);
        extras.bonus = _amount(r, 38, 39, 14);
        extras.slots[kCategory] = 'm754h';
        extras.slots[kDate] = _parseDate(extras.dateRaw!, 382, info.timezoneOffsetMinutes);
        extras.slots[kCount] = extras.bonus;
      }
    }

    if (city == 5810 || city == 5880) {
      final r = await _apdu(const [0x00, 0xB2, 0x01, 0xCC, 0x30], '0x19 #1',
          records: records, strict: true);
      if (r != null && _at(r, 3) != 0) {
        extras.dateRaw = _sub(r, 3, 5);
        extras.bonus = _at(r, 7);
        extras.counter = _at(r, 5);
        extras.amount = _amount(r, 12, 14, 14);
        final parsed = _parseDate(extras.dateRaw!, 322, info.timezoneOffsetMinutes);
        final existing = extras.slots[kDate];
        final useNew = existing == null ||
            (existing is DateTime && parsed != null && existing.isBefore(parsed));
        if (useNew) {
          if (_bcd(r, 4) + _bcd(r, 3) * 100 >= 2309) {
            extras.slots[kCategory] = 'm751e';
            extras.slots[kAmount] = extras.amount;
          } else {
            extras.slots[kCategory] = 'f808d';
          }
          extras.slots[kDate] = parsed;
          extras.slots[kCount] = extras.bonus;
        }
      }
    }

    await _readInterchangeRecords(info, records);
  }

  Future<void> _readInterchangeRecords(
    CardInfo info,
    List<ApduRecord> records,
  ) async {
    const p2 = 0xF4;
    const le = 0x30;
    for (var recNo = 1; recNo <= 31; recNo++) {
      final r = await _apdu([0x00, 0xB2, recNo, p2, le], '0x1E',
          records: records, strict: true);
      if (r == null) break;
      if (r.length < 34) continue;

      final when = _parseDate(_sub(r, 25, 32), 126, info.timezoneOffsetMinutes);
      final rec = ApduRecord()
        ..recordNumber = recNo
        ..fileSelector = p2
        ..response = r
        ..terminalHex = LocalHex.bytesToHex(_sub(r, 10, 16))
        ..cityCode = _bcd(r, 32) * 100 + _bcd(r, 33)
        ..timestamp = when ?? DateTime.fromMillisecondsSinceEpoch(0)
        ..type = 2
        ..isOtherA = true;
      records.add(rec);
    }
  }

  /// m135i(subList(a,b), enum, shift) → 大端整数右移 shift。
  int _amount(List<int> r, int a, int b, int shift) =>
      LocalHex.readBEInt(_sub(r, a, b)) >> shift;

  /// 安全子列表：越界时收缩到合法范围。
  List<int> _sub(List<int> r, int a, int b) {
    if (a >= r.length) return const [];
    final end = b > r.length ? r.length : b;
    return r.sublist(a, end);
  }

  int _at(List<int> r, int i) => (i >= 0 && i < r.length) ? (r[i] & 0xFF) : 0;

  int _bcd(List<int> r, int i) => LocalHex.bcdToInt(_at(r, i));

  /// AbstractC0250g.m612b 的“有效性裁剪”近似：
  /// 若 [i] 处为 0，或 [j] 处为 0，则该 blob 视为无效 → null。
  List<int>? _clearIfDead(List<int>? r, int i, int j) {
    if (r == null) return null;
    if (_at(r, i) == 0) return null;
    if (_at(r, j) == 0) return null;
    return r;
  }

  /// AbstractC0019a.m131g(...) 的近似：BCD YY MM DD [HH mm ss]，按 format 选择位数。
  DateTime? _parseDate(List<int> b, int format, int tzMinutes) {
    if (b.length < 3) return null;
    int y, mo, d, hh = 0, mi = 0;
    if (format == 126 && b.length >= 6) {
      // 0x1E：YY MM DD HH mm ss
      y = LocalHex.bcdToInt(b[0]) * 100 + LocalHex.bcdToInt(b[1]);
      mo = LocalHex.bcdToInt(b[2]);
      d = LocalHex.bcdToInt(b[3]);
      hh = LocalHex.bcdToInt(b[4]);
      mi = LocalHex.bcdToInt(b[5]);
    } else {
      y = LocalHex.bcdToInt(b[0]) * 100 + LocalHex.bcdToInt(b[1]);
      mo = LocalHex.bcdToInt(b[2]);
      d = b.length >= 4 ? LocalHex.bcdToInt(b[3]) : 1;
    }
    if (mo == 0 || mo > 12 || d == 0 || d > 31) return null;
    return DateTime.utc(y, mo, d, hh, mi)
        .add(Duration(minutes: -tzMinutes))
        .toLocal();
  }
}
