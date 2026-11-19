import 'card_fingerprint.dart';
import 'card_session_snapshot.dart';
import 'card_types.dart';

/// Read-only presentation of captured Suica identity; never a card number.
class SuicaArchiveIdentity {
  const SuicaArchiveIdentity({this.idm, this.hasConflict = false});

  final String? idm;
  final bool hasConflict;

  factory SuicaArchiveIdentity.resolve({
    required String cardType,
    required String fingerprint,
    Iterable<CardSessionSnapshot> snapshots = const [],
  }) {
    if (cardType != CardTypes.suica) return const SuicaArchiveIdentity();
    final values = <String>{};
    final match = RegExp(r'^felica:suica:idm:([0-9A-Fa-f]{16})$')
        .firstMatch(fingerprint);
    final fingerprintIdm = normalizeIdm(match?.group(1));
    if (fingerprintIdm != null) values.add(fingerprintIdm);
    for (final snapshot in snapshots) {
      final section = snapshot.extensions['suica'];
      if (section is! Map || section['version'] != 1) continue;
      final captured = section['idm'];
      final idm = captured is String ? normalizeIdm(captured) : null;
      if (idm != null) values.add(idm);
    }
    if (values.length > 1) {
      return const SuicaArchiveIdentity(hasConflict: true);
    }
    return SuicaArchiveIdentity(idm: values.isEmpty ? null : values.single);
  }

  static String? normalizeIdm(String? value) =>
      CardFingerprint.buildSuica(value)?.split(':').last;

  @override
  bool operator ==(Object other) =>
      other is SuicaArchiveIdentity &&
      idm == other.idm &&
      hasConflict == other.hasConflict;

  @override
  int get hashCode => Object.hash(idm, hasConflict);
}
