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

  static List<int> _decodeHex(String? value) {
    if (value == null) return const [];
    final compact = value.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    if (compact.isEmpty || compact.length.isOdd) return const [];
    return [
      for (var index = 0; index < compact.length; index += 2)
        int.parse(compact.substring(index, index + 2), radix: 16),
    ];
  }

  static String _hexBytes(List<int> bytes) => bytes.map(_hexByte).join();

  static String _hexByte(int value) =>
      (value & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
}
