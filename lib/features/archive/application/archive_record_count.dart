import '../data/app_database.dart';
import '../data/card_repository.dart';
import '../domain/snapshot_diagnostics.dart';
import '../domain/card_types.dart';
import '../domain/amusement_ic_archive_identity.dart';
import '../domain/suica_archive_identity.dart';
import '../domain/suica_manual_number.dart';
import 'amusement_ic_archive_projection.dart';
import 'archive_history.dart';
import 'archive_records_json.dart';
import 'cu_archive_projection.dart';
import 'suica_archive_projection.dart';

/// Counts the same complete, deduplicated rows that the archive can export.
/// The scalar transaction count remains the latest read's separate observation.
class ArchiveRecordCount {
  final int? savedRecordCount;
  final int? latestTransactionCount;
  final bool isUnavailable;

  const ArchiveRecordCount._({
    required this.savedRecordCount,
    required this.latestTransactionCount,
  }) : isUnavailable = false;

  /// The complete document or its row projection could not be read. A partial
  /// index count must not stand in for the full archive's unknown record count.
  const ArchiveRecordCount.unavailable({this.latestTransactionCount})
    : savedRecordCount = null,
      isUnavailable = true;

  factory ArchiveRecordCount.fromHistory(ArchiveHistoryResult history) {
    if (history.documentReadIssue != null ||
        history.batches.any(
          (batch) =>
              batch.decoded.status != SnapshotDecodeStatus.supported &&
              batch.decoded.status != SnapshotDecodeStatus.legacy,
        )) {
      return ArchiveRecordCount.unavailable(
        latestTransactionCount: history.card?.transactionCount,
      );
    }
    final int rows;
    final SuicaArchiveProjection suica;
    try {
      suica = projectSuicaArchive(history);
      if (projectCuArchive(history).issues.isNotEmpty ||
          suica.issues.isNotEmpty) {
        return ArchiveRecordCount.unavailable(
          latestTransactionCount: history.card?.transactionCount,
        );
      }
      rows =
          projectArchiveRecords([history]).length +
          history.localCardRecords
              .where((record) => record.cardType == 'macauPass')
              .length;
    } on FormatException {
      return ArchiveRecordCount.unavailable(
        latestTransactionCount: history.card?.transactionCount,
      );
    } on RangeError {
      return ArchiveRecordCount.unavailable(
        latestTransactionCount: history.card?.transactionCount,
      );
    }
    final latest = history.card?.transactionCount;
    // A fully observed Suica history can now project to zero after removing
    // initialized slots from old captures. Its stale positive scalar must not
    // restore those slots as transactions. Observation-only captures still
    // leave the complete count unknown, as do archives for other card types.
    final hasObservedSuicaCaptures =
        suica.hasHistoryObservation &&
        history.batches.every((batch) {
          final section = batch.decoded.snapshot?.extensions['suica'];
          if (section is! Map) return false;
          final records = section['records'];
          return section['historyObserved'] == true ||
              (records is List && records.isNotEmpty);
        });
    final hasEmptyCapture =
        history.batches.isNotEmpty &&
        history.batches.every(
          (batch) =>
              batch.decoded.snapshot != null &&
              (batch.decoded.status == SnapshotDecodeStatus.supported ||
                  batch.decoded.status == SnapshotDecodeStatus.legacy) &&
              // A Suica capture may contain identity/evidence only because
              // history could not be read. Its empty array is not a zero-row
              // observation; a successful empty read declares that explicitly.
              (!batch.decoded.snapshot!.extensions.containsKey('suica') ||
                  (batch.decoded.snapshot!.extensions['suica'] is Map &&
                      (batch.decoded.snapshot!.extensions['suica']
                              as Map)['historyObserved'] ==
                          true)),
        );
    // A legacy/observation-only payload may retain a positive numeric summary
    // without its underlying rows. Do not relabel that summary as saved history
    // or let an otherwise empty capture turn it into zero.
    final int? saved = rows > 0
        ? rows
        : hasObservedSuicaCaptures
        ? 0
        : latest != null && latest > 0
        ? null
        : latest == 0 || hasEmptyCapture
        ? 0
        : null;
    return ArchiveRecordCount._(
      savedRecordCount: saved,
      latestTransactionCount: latest,
    );
  }

  String get label =>
      !isUnavailable && savedRecordCount == null && _hasLatestCount
      ? '最近读取交易'
      : '已保存记录';

  String get valueText {
    if (isUnavailable) return '—';
    final value =
        savedRecordCount ?? (_hasLatestCount ? latestTransactionCount : null);
    return value == null ? '—' : '$value条';
  }

  String get listText {
    if (isUnavailable) return '记录数待核实';
    if (savedRecordCount case final count?) return '已保存 $count 条';
    if (_hasLatestCount) return '最近读取 $latestTransactionCount 条';
    return '已保存记录 —';
  }

  bool get _hasLatestCount =>
      latestTransactionCount != null && latestTransactionCount! >= 0;

  @override
  bool operator ==(Object other) =>
      other is ArchiveRecordCount &&
      isUnavailable == other.isUnavailable &&
      savedRecordCount == other.savedRecordCount &&
      latestTransactionCount == other.latestTransactionCount;

  @override
  int get hashCode =>
      Object.hash(savedRecordCount, latestTransactionCount, isUnavailable);
}

class ArchiveCardSummary {
  final SavedCard card;
  final ArchiveRecordCount recordCount;
  final SuicaArchiveIdentity? suicaIdentity;
  final String? suicaManualNumberText;
  final AmusementIcArchiveIdentity? amusementIcIdentity;

  const ArchiveCardSummary(
    this.card,
    this.recordCount, {
    this.suicaIdentity,
    this.suicaManualNumberText,
    this.amusementIcIdentity,
  });

  @override
  bool operator ==(Object other) =>
      other is ArchiveCardSummary &&
      card == other.card &&
      recordCount == other.recordCount &&
      suicaIdentity == other.suicaIdentity &&
      suicaManualNumberText == other.suicaManualNumberText &&
      amusementIcIdentity == other.amusementIcIdentity;

  @override
  int get hashCode => Object.hash(
    card,
    recordCount,
    suicaIdentity,
    suicaManualNumberText,
    amusementIcIdentity,
  );
}

/// One list stream observes card and batch changes, including batch-only writes.
/// All cards are captured consistently before history projection and counting.
Stream<List<ArchiveCardSummary>> watchArchiveCardSummaries(
  CardRepository repository,
) => repository
    .watchAllArchiveRows()
    .map((rows) {
      return List<ArchiveCardSummary>.unmodifiable([
        for (final row in rows)
          if (row.card != null) _summarizeArchiveRows(row),
      ]);
    })
    .distinct(_sameSummaries);

ArchiveCardSummary _summarizeArchiveRows(ArchiveRows row) {
  final card = row.card!;
  try {
    final history = ArchiveHistory.project(row);
    return ArchiveCardSummary(
      card,
      ArchiveRecordCount.fromHistory(history),
      amusementIcIdentity: card.cardType == CardTypes.amusementIc
          ? AmusementIcArchiveIdentity.fromCapturedData(
              projectAmusementIcArchive(history).data,
            )
          : null,
      suicaIdentity: card.cardType == CardTypes.suica
          ? SuicaArchiveIdentity.resolve(
              cardType: card.cardType,
              fingerprint: card.cardFingerprint,
              snapshots: history.batches
                  .map((batch) => batch.decoded.snapshot)
                  .nonNulls,
            )
          : null,
      suicaManualNumberText: card.cardType == CardTypes.suica
          ? SuicaManualNumber.fromJson(
              history.cardExtensions['suicaManualNumber'],
            )?.formatted
          : null,
    );
  } on FormatException {
    return ArchiveCardSummary(
      card,
      ArchiveRecordCount.unavailable(
        latestTransactionCount: card.transactionCount,
      ),
    );
  } on RangeError {
    return ArchiveCardSummary(
      card,
      ArchiveRecordCount.unavailable(
        latestTransactionCount: card.transactionCount,
      ),
    );
  }
}

bool _sameSummaries(
  List<ArchiveCardSummary> previous,
  List<ArchiveCardSummary> next,
) {
  if (previous.length != next.length) return false;
  for (var i = 0; i < previous.length; i++) {
    if (previous[i] != next[i]) return false;
  }
  return true;
}
