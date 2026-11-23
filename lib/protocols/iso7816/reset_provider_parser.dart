enum ResetProviderSource {
  historicalBytes,
  higherLayerResponse,
  nfcBApplicationData,
  nfcBProtocolInfo,
}

enum ResetProviderLayout { atr, providerBlock, providerBlockWithoutHighByte }

class ResetProviderCandidate {
  const ResetProviderCandidate({
    required this.chipProviderCode,
    required this.icCardProviderCode,
    required this.source,
    required this.layout,
    required this.byteOffset,
  });

  final String chipProviderCode;
  final String icCardProviderCode;
  final ResetProviderSource source;
  final ResetProviderLayout layout;
  final int byteOffset;
}

/// Extracts the two registered provider codes from reset information layouts
/// used by Chinese contact and contactless IC cards. Registry membership is
/// checked separately so unrelated 7-byte sequences are never displayed.
class ResetProviderParser {
  static Iterable<ResetProviderCandidate> parse(
    String? hex,
    ResetProviderSource source,
  ) sync* {
    final bytes = _decodeHex(hex);
    if (bytes.length < 6) return;

    for (var offset = 0; offset + 11 <= bytes.length; offset++) {
      if (bytes[offset] != 0x3B ||
          !const {0x6B, 0x6D, 0x8D}.contains(bytes[offset + 1])) {
        continue;
      }
      yield _candidate(
        bytes,
        offset,
        chipOffset: offset + 4,
        cardOffset: offset + 9,
        source: source,
        layout: ResetProviderLayout.atr,
      );
    }

    for (var offset = 0; offset + 7 <= bytes.length; offset++) {
      if (!_plausibleBlockStart(bytes, offset)) continue;
      if (bytes[offset + 2] == 0x54 &&
          bytes[offset + 3] == 0x31 &&
          bytes[offset + 4] == 0x00) {
        yield _candidate(
          bytes,
          offset,
          chipOffset: offset,
          cardOffset: offset + 5,
          source: source,
          layout: ResetProviderLayout.providerBlock,
        );
      }
    }

    // "MT" provider block: M T chip(2) 00 kind icCard(2). The trailing codes
    // are only read from a complete block anchored at the start of the reset
    // information (or inside a 3B ATR envelope); partial or shifted matches
    // must never surface as provider codes.
    for (var offset = 0; offset + 8 <= bytes.length; offset++) {
      if (bytes[offset] != 0x4D ||
          bytes[offset + 1] != 0x54 ||
          bytes[offset + 4] != 0x00) {
        continue;
      }
      if (!_plausibleBlockStart(bytes, offset)) continue;
      yield _candidate(
        bytes,
        offset,
        chipOffset: offset + 2,
        cardOffset: offset + 6,
        source: source,
        layout: ResetProviderLayout.providerBlock,
      );
    }

    if (bytes.length >= 6 &&
        bytes[1] == 0x54 &&
        bytes[2] == 0x31 &&
        bytes[3] == 0x00) {
      final lowByte = _hexByte(bytes[0]);
      yield ResetProviderCandidate(
        chipProviderCode: '00$lowByte',
        icCardProviderCode: _hexBytes(bytes.sublist(4, 6)),
        source: source,
        layout: ResetProviderLayout.providerBlockWithoutHighByte,
        byteOffset: 0,
      );
      yield ResetProviderCandidate(
        chipProviderCode: 'FF$lowByte',
        icCardProviderCode: _hexBytes(bytes.sublist(4, 6)),
        source: source,
        layout: ResetProviderLayout.providerBlockWithoutHighByte,
        byteOffset: 0,
      );
    }
  }

  static ResetProviderCandidate _candidate(
    List<int> bytes,
    int offset, {
    required int chipOffset,
    required int cardOffset,
    required ResetProviderSource source,
    required ResetProviderLayout layout,
  }) => ResetProviderCandidate(
    chipProviderCode: _hexBytes(bytes.sublist(chipOffset, chipOffset + 2)),
    icCardProviderCode: _hexBytes(bytes.sublist(cardOffset, cardOffset + 2)),
    source: source,
    layout: layout,
    byteOffset: offset,
  );

  /// A provider block is trusted at the start of the reset information or
  /// inside a contactless 3B… ATR envelope; anything shifted into arbitrary
  /// payload bytes stays uninterpreted.
  static bool _plausibleBlockStart(List<int> bytes, int offset) {
    if (offset == 0) return true;
    if (bytes.isEmpty || bytes[0] != 0x3B) return false;
    return offset <= 8;
  }

  static List<int> _decodeHex(String? value) {
    if (value == null) return const [];
    final trimmed = value.trim();
    if (trimmed.isEmpty) return const [];
    final tokens = trimmed.split(RegExp(r'\s+'));
    if (tokens.length == 1) {
      final compact = tokens.single;
      if (compact.length.isOdd ||
          !RegExp(r'^[0-9A-Fa-f]+$').hasMatch(compact)) {
        return const [];
      }
      return [
        for (var index = 0; index < compact.length; index += 2)
          int.parse(compact.substring(index, index + 2), radix: 16),
      ];
    }
    final bytes = <int>[];
    for (final token in tokens) {
      if (!RegExp(r'^[0-9A-Fa-f]{2}$').hasMatch(token)) return const [];
      bytes.add(int.parse(token, radix: 16));
    }
    return bytes;
  }

  static String _hexBytes(List<int> bytes) => bytes.map(_hexByte).join();

  static String _hexByte(int value) =>
      (value & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
}
