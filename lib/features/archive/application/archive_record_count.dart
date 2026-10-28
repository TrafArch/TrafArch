import '../data/app_database.dart';
import '../data/card_repository.dart';
import '../domain/snapshot_diagnostics.dart';
import 'archive_history.dart';
import 'archive_records_json.dart';
import 'cu_archive_projection.dart';

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
    try {
      if (projectCuArchive(history).issues.isNotEmpty) {
        return ArchiveRecordCount.unavailable(
          latestTransactionCount: history.card?.transactionCount,
        );
      }
      rows = projectArchiveRecords([history]).length;
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
    final hasEmptyCapture =
        history.batches.isNotEmpty &&
        history.batches.every(
          (batch) =>
              batch.decoded.snapshot != null &&
              (batch.decoded.status == SnapshotDecodeStatus.supported ||
                  batch.decoded.status == SnapshotDecodeStatus.legacy),
        );
    // A legacy/observation-only payload may retain a positive numeric summary
    // without its underlying rows. Do not relabel that summary as saved history
    // or let an otherwise empty capture turn it into zero.
    final int? saved = rows > 0
        ? rows
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

  const ArchiveCardSummary(this.card, this.recordCount);

  @override
  bool operator ==(Object other) =>
      other is ArchiveCardSummary &&
      card == other.card &&
      recordCount == other.recordCount;

  @override
  int get hashCode => Object.hash(card, recordCount);
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
          if (row.card case final card?)
            ArchiveCardSummary(card, _countArchiveRows(row)),
      ]);
    })
    .distinct(_sameSummaries);

ArchiveRecordCount _countArchiveRows(ArchiveRows row) {
  try {
    return ArchiveRecordCount.fromHistory(ArchiveHistory.project(row));
  } on FormatException {
    return ArchiveRecordCount.unavailable(
      latestTransactionCount: row.card?.transactionCount,
    );
  } on RangeError {
    return ArchiveRecordCount.unavailable(
      latestTransactionCount: row.card?.transactionCount,
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
