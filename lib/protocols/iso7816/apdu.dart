enum ApduCase {
  case1,
  case2Short,
  case3Short,
  case4Short,
  case2Extended,
  case3Extended,
  case4Extended,
}

/// A validated command. Data and Le occupy distinct ranges, including extended
/// commands; a case-3 SELECT/VERIFY can never acquire a retry by changing data.
class CommandApdu {
  CommandApdu._(List<int> bytes, this.apduCase, this.leOffset, this.leWidth)
    : bytes = List<int>.unmodifiable(bytes);

  final List<int> bytes;
  final ApduCase apduCase;
  final int? leOffset;
  final int leWidth;
  int get cla => bytes.first;
  bool get hasLe => leOffset != null;

  int? get encodedLe {
    final offset = leOffset;
    if (offset == null) return null;
    return leWidth == 1
        ? bytes[offset]
        : (bytes[offset] << 8) | bytes[offset + 1];
  }

  int? get expectedLength {
    final le = encodedLe;
    return le == 0 ? (leWidth == 1 ? 256 : 65536) : le;
  }

  factory CommandApdu.parse(List<int> bytes) {
    if (bytes.length < 4 || bytes.any((b) => b < 0 || b > 255)) {
      throw const FormatException('Invalid APDU header or byte');
    }
    if (bytes.length == 4) return CommandApdu._(bytes, ApduCase.case1, null, 0);
    if (bytes.length == 5) {
      return CommandApdu._(bytes, ApduCase.case2Short, 4, 1);
    }
    final lc = bytes[4];
    if (lc != 0) {
      if (bytes.length == 5 + lc) {
        return CommandApdu._(bytes, ApduCase.case3Short, null, 0);
      }
      if (bytes.length == 6 + lc) {
        return CommandApdu._(bytes, ApduCase.case4Short, 5 + lc, 1);
      }
    } else if (bytes.length >= 7) {
      if (bytes.length == 7) {
        return CommandApdu._(bytes, ApduCase.case2Extended, 5, 2);
      }
      final extendedLc = (bytes[5] << 8) | bytes[6];
      if (extendedLc > 0 && bytes.length == 7 + extendedLc) {
        return CommandApdu._(bytes, ApduCase.case3Extended, null, 0);
      }
      if (extendedLc > 0 && bytes.length == 9 + extendedLc) {
        return CommandApdu._(bytes, ApduCase.case4Extended, 7 + extendedLc, 2);
      }
    }
    throw const FormatException('APDU length does not match Lc/Le');
  }

  CommandApdu withEncodedLe(int le) {
    final offset = leOffset;
    if (offset == null) throw StateError('APDU has no Le');
    if (le < 0 || le > (leWidth == 1 ? 255 : 65535)) {
      throw RangeError.value(le, 'le');
    }
    final corrected = List<int>.of(bytes);
    if (leWidth == 2) corrected[offset] = le >> 8;
    corrected[offset + leWidth - 1] = le & 0xFF;
    return CommandApdu._(corrected, apduCase, offset, leWidth);
  }

  /// A 6C00 correction is 256, even when encoded in an extended Le field.
  CommandApdu correctedLe(int sw2) =>
      withEncodedLe(leWidth == 2 && sw2 == 0 ? 256 : sw2);
}

class ResponseApdu {
  ResponseApdu(List<int> data, this.sw1, this.sw2)
    : data = List<int>.unmodifiable(data);

  final List<int> data;
  final int sw1;
  final int sw2;
  int get statusWord => (sw1 << 8) | sw2;
  bool get isSuccess => statusWord == 0x9000;
  List<int> get raw => List<int>.unmodifiable([...data, sw1, sw2]);

  factory ResponseApdu.parse(List<int> bytes) {
    if (bytes.length < 2 || bytes.any((b) => b < 0 || b > 255)) {
      throw const FormatException('APDU 响应无有效状态字或包含非法字节');
    }
    return ResponseApdu(
      bytes.sublist(0, bytes.length - 2),
      bytes[bytes.length - 2],
      bytes.last,
    );
  }
}
