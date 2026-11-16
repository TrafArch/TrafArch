library;

import 'amusement_ic_substitution_tables.dart';

/// Decodes the Access Code stored in an Amusement IC SPAD0 block.
///
/// The public format uses a substitution/rotation transform, not an IDm
/// conversion. Format checks do not validate the issuer's five-digit checksum
/// or authenticate the card. See third_party/amusement_ic/README.md.
class AmusementIcParser {
  const AmusementIcParser();

  String? parseAccessCode(List<int> spad0) {
    if (spad0.length != 16 || spad0.any((byte) => byte < 0 || byte > 255)) {
      return null;
    }

    final decoded = [
      for (final byte in spad0) amusementIcInverseSubstitutionTables[8][byte],
    ];
    final rounds = (decoded[15] >> 4) + 7;
    var table = decoded[15] + 5 * rounds;

    for (var round = 0; round < rounds; round++) {
      table -= 5;
      var previous = decoded[14];
      for (var index = 0; index < 15; index++) {
        final current = decoded[index];
        decoded[index] = ((current >> 5) | (previous << 3)) & 0xFF;
        previous = current;
      }
      final substitutions = amusementIcInverseSubstitutionTables[table % 8];
      for (var index = 0; index < 15; index++) {
        decoded[index] = substitutions[decoded[index]];
      }
    }

    // Only the lower nibble has a documented version meaning.
    if ((decoded[0] & 0x0F) != 0) return null;

    final code = StringBuffer();
    for (var index = 6; index < 16; index++) {
      final high = decoded[index] >> 4;
      final low = decoded[index] & 0x0F;
      if (high > 9 || low > 9) return null;
      code
        ..write(high)
        ..write(low);
    }
    final accessCode = code.toString();
    if (!_companyCodes.contains(accessCode.substring(0, 3))) return null;
    return accessCode;
  }

  static const _companyCodes = {'500', '501', '510', '520', '530'};
}
