enum ResetProviderSource {
  historicalBytes,
  higherLayerResponse,
  nfcBApplicationData,
  nfcBProtocolInfo,
}

enum ResetProviderLayout {
  tUnionHistoricalBytes,
  atr,
  providerBlock,
  providerBlockWithoutHighByte,
}

class ResetProviderCandidate {
  const ResetProviderCandidate({
    required this.chipProviderCode,
    required this.icCardProviderCode,
    required this.source,
    required this.layout,
    required this.byteOffset,
  });

  /// Only the observed low byte for [ResetProviderLayout.providerBlockWithoutHighByte].
  final String chipProviderCode;
  final String icCardProviderCode;
  final ResetProviderSource source;
  final ResetProviderLayout layout;
  final int byteOffset;
}

/// Extracts provider codes at known positions in reset information.
/// Registry lookup is independent of decoding.
class ResetProviderParser {
  static Iterable<ResetProviderCandidate> parse(
    String? hex,
    ResetProviderSource source,
  ) sync* {
    final bytes = _decodeHex(hex);
    if (bytes.length < 6) return;

    // PC/SC readers can wrap the same ATS historical bytes in a synthetic ATR.
    final pcscWrapped =
        bytes[0] == 0x3B &&
        (bytes[1] & 0xF0) == 0x80 &&
        bytes[2] == 0x80 &&
        bytes[3] == 0x01;
    final historyOffset = pcscWrapped ? 4 : 0;
    final historyLength = pcscWrapped ? bytes[1] & 0x0F : bytes.length;
    final validPcscAtr = pcscWrapped && _hasValidPcscAtr(bytes, historyLength);
    if (bytes[historyOffset] == 0x4D && bytes[historyOffset + 1] == 0x54) {
      if (source != ResetProviderSource.historicalBytes ||
          historyLength < 8 ||
          (pcscWrapped && !validPcscAtr)) {
        return;
      }
      // The bundled chip registry uses the 00xx and FFxx ranges. Check the
      // range so an unrelated MT-prefixed value such as MTCOS is rejected.
      final chipHighByte = bytes[historyOffset + 2];
      if (chipHighByte != 0x00 && chipHighByte != 0xFF) return;
      yield _candidate(
        bytes,
        historyOffset,
        chipOffset: historyOffset + 2,
        cardOffset: historyOffset + 6,
        source: source,
        layout: ResetProviderLayout.tUnionHistoricalBytes,
      );
      return;
    }

    // Legacy 3B 8D inputs may omit the TCK but still carry all 13 bytes.
    final legacyPcscAtr =
        pcscWrapped &&
        bytes[1] == 0x8D &&
        (validPcscAtr || bytes.length == historyOffset + historyLength);
    final legacyAtr =
        legacyPcscAtr ||
        (bytes[0] == 0x3B && (bytes[1] == 0x6B || bytes[1] == 0x6D));
    final blockOffset = legacyAtr || validPcscAtr ? 4 : 0;
    final blockLength = validPcscAtr
        ? historyLength
        : bytes.length - blockOffset;
    if (blockLength >= 7) {
      final hasLegacyMarker = _hasLegacyMarker(bytes, blockOffset + 2);
      if (hasLegacyMarker || legacyAtr) {
        yield _candidate(
          bytes,
          blockOffset,
          chipOffset: blockOffset,
          cardOffset: blockOffset + 5,
          source: source,
          layout: hasLegacyMarker
              ? ResetProviderLayout.providerBlock
              : ResetProviderLayout.atr,
        );
        return;
      }
    }

    if (_hasLegacyMarker(bytes, 1)) {
      yield ResetProviderCandidate(
        chipProviderCode: _hexByte(bytes[0]),
        icCardProviderCode: _hexBytes(bytes.sublist(4, 6)),
        source: source,
        layout: ResetProviderLayout.providerBlockWithoutHighByte,
        byteOffset: 0,
      );
    }
  }

  static bool _hasValidPcscAtr(List<int> bytes, int historyLength) =>
      // TS, T0, TD1, TD2, historical bytes, and a TCK covering all but TS.
      bytes.length == historyLength + 5 &&
      bytes.skip(1).fold(0, (checksum, byte) => checksum ^ byte) == 0;

  static bool _hasLegacyMarker(List<int> bytes, int offset) =>
      bytes[offset] == 0x54 &&
      bytes[offset + 1] == 0x31 &&
      bytes[offset + 2] == 0x00;

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

  static List<int> _decodeHex(String? value) {
    if (value == null) return const [];
    final compact = value.replaceAll(RegExp(r'\s+'), '');
    if (compact.length.isOdd || !_hexPattern.hasMatch(compact)) return const [];
    return [
      for (var index = 0; index < compact.length; index += 2)
        int.parse(compact.substring(index, index + 2), radix: 16),
    ];
  }

  static final _hexPattern = RegExp(r'^[0-9A-Fa-f]+$');

  static String _hexBytes(List<int> bytes) => bytes.map(_hexByte).join();

  static String _hexByte(int value) =>
      (value & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
}
