import '../../../protocols/felica/models/amusement_ic_data.dart';
import '../domain/card_fingerprint.dart';
import '../domain/card_types.dart';
import 'archive_history.dart';

/// A complete identity from one frozen capture, never assembled from separate
/// reads or decoded again from raw blocks using the current protocol parser.
class AmusementIcArchiveProjection {
  const AmusementIcArchiveProjection({
    this.data,
    this.idm,
    this.readAt,
    this.issues = const [],
    this.hasCaptures = false,
  });

  final AmusementIcData? data;
  final String? idm;
  final DateTime? readAt;
  final List<String> issues;
  final bool hasCaptures;
}

AmusementIcArchiveProjection projectAmusementIcArchive(
  ArchiveHistoryResult history,
) {
  final card = history.card;
  if (card == null || card.cardType != CardTypes.amusementIc) {
    return const AmusementIcArchiveProjection();
  }

  final issues = <String>[];
  var hasCaptures = false;
  AmusementIcData? selected;
  String? selectedIdm;
  DateTime? selectedAt;
  // ArchiveHistory already orders captures newest-first. Also keep the public
  // projection safe for callers that constructed an unordered result directly.
  final batches = history.batches.indexed.toList()
    ..sort((a, b) {
      final time = b.$2.readAt.compareTo(a.$2.readAt);
      return time == 0 ? a.$1.compareTo(b.$1) : time;
    });

  for (final entry in batches) {
    final batch = entry.$2;
    final snapshot = batch.decoded.snapshot;
    if (snapshot == null) {
      issues.add('${batch.id}: Amusement IC 快照无法恢复，原始快照已保留');
      continue;
    }
    final section = snapshot.extensions['amusementIc'];
    if (section == null) continue;
    hasCaptures = true;
    if (section is! Map || section['version'] != 1) {
      issues.add('${batch.id}: Amusement IC 档案格式不支持，原始快照已保留');
      continue;
    }
    if (snapshot.context.systemId != 'felica_amusement_ic' ||
        section['identityKind'] != 'amusement-ic-access-code') {
      issues.add('${batch.id}: Amusement IC 身份上下文不一致，原始快照已保留');
      continue;
    }

    final data = AmusementIcData.fromJson(section['data']);
    final fingerprint = CardFingerprint.buildAmusementIc(data?.accessCode);
    if (data == null ||
        fingerprint == null ||
        data.issuer == null ||
        data.issuer!.trim().isEmpty) {
      issues.add('${batch.id}: Amusement IC 身份字段不完整，原始快照已保留');
      continue;
    }
    if (fingerprint != card.cardFingerprint) {
      issues.add('${batch.id}: Amusement IC 身份与卡片指纹不一致，原始快照已保留');
      continue;
    }

    final rawIdm = section['idm'];
    final validIdm =
        rawIdm is String && RegExp(r'^[0-9A-Fa-f]{16}$').hasMatch(rawIdm);
    if (rawIdm != null && !validIdm) {
      issues.add('${batch.id}: Amusement IC IDm 字段损坏，原始快照已保留');
    }
    if (selected == null) {
      selected = data;
      selectedIdm = validIdm ? rawIdm : null;
      selectedAt = DateTime.fromMillisecondsSinceEpoch(batch.readAt);
    }
  }

  return AmusementIcArchiveProjection(
    data: selected,
    idm: selectedIdm,
    readAt: selectedAt,
    issues: List.unmodifiable(issues),
    hasCaptures: hasCaptures,
  );
}
