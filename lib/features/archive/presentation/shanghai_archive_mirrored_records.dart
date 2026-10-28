import '../../../protocols/transit/card_parser.dart';
import '../../../protocols/transit/tunion/tunion_models.dart';
import '../../transit_analysis/cu_transaction_analysis.dart';
import '../../trips/shanghai_mirrored_records.dart';
import '../application/archive_history.dart';
import '../application/cu_archive_projection.dart';
import '../domain/card_session_snapshot.dart';

/// Fold only observations supported by matching TU records in every original
/// capture. The archive projection, source attribution and JSON stay unchanged.
ShanghaiMirroredRecords partitionShanghaiArchiveMirroredRecords({
  required ArchiveHistoryResult history,
  required CuArchiveProjection cityUnion,
}) {
  final batches = <String, ArchiveBatchEvidence>{};
  final ambiguousBatches = <String>{};
  for (final batch in history.batches) {
    if (batches.containsKey(batch.id)) ambiguousBatches.add(batch.id);
    batches[batch.id] = batch;
  }
  final observations = <String, List<CuTransactionView>>{};
  for (final view in cityUnion.transactions) {
    for (final source
        in cityUnion.sources[view] ?? const <ArchiveRecordSource>[]) {
      observations.putIfAbsent(source.batchId, () => []).add(view);
    }
  }
  final matchedCounts = <String, Map<CuTransactionView, int>>{};
  for (final entry in observations.entries) {
    final snapshot = batches[entry.key]?.decoded.snapshot;
    if (ambiguousBatches.contains(entry.key) ||
        snapshot == null ||
        snapshot.context.systemId != CardParserIds.shanghaiTunion) {
      continue;
    }
    final matched = partitionShanghaiMirroredRecords(
      parserId: snapshot.context.systemId,
      tunionTransactions: _capturedTransactions(snapshot),
      cityUnionTransactions: entry.value,
    );
    final counts = <CuTransactionView, int>{};
    for (final view in matched.mirrored) {
      counts.update(view, (count) => count + 1, ifAbsent: () => 1);
    }
    matchedCounts[entry.key] = counts;
  }
  final independent = <CuTransactionView>[];
  final mirrored = <CuTransactionView>[];
  for (final view in cityUnion.transactions) {
    final needed = <String, int>{};
    for (final source
        in cityUnion.sources[view] ?? const <ArchiveRecordSource>[]) {
      needed.update(source.batchId, (count) => count + 1, ifAbsent: () => 1);
    }
    final supported =
        needed.isNotEmpty &&
        needed.entries.every(
          (entry) => matchedCounts[entry.key]?[view] == entry.value,
        );
    (supported ? mirrored : independent).add(view);
  }
  return ShanghaiMirroredRecords(independent: independent, mirrored: mirrored);
}

Iterable<TUnionTransaction> _capturedTransactions(
  CardSessionSnapshot snapshot,
) sync* {
  final rawTrips = snapshot.extensions['trips'];
  if (rawTrips is! List) return;
  final accepted = snapshot.trips.toList();
  for (final fields in rawTrips) {
    if (fields is! Map) continue;
    final raw = fields['rawHex'];
    final sequence = fields['sequence'];
    final amount = fields['amountFen'];
    final terminal = fields['terminalId'];
    final epoch = fields['time'];
    if (raw is! String ||
        sequence is! int ||
        amount is! int ||
        terminal is! String ||
        epoch is! int) {
      continue;
    }
    final compact = raw.replaceAll(RegExp(r'\s'), '').toUpperCase();
    if (!RegExp(r'^[0-9A-F]{46}$').hasMatch(compact)) continue;
    final civil = _capturedCivil(fields);
    if (civil == null) continue;
    final transaction = TUnionTransaction(
      sequence: sequence,
      overdraftLimitFen: 0,
      amountFen: amount,
      rawType: int.parse(compact.substring(18, 20), radix: 16),
      terminalId: terminal,
      time: civil,
      rawHex: raw,
    );
    if (fields['consume'] != transaction.isConsume ||
        fields['composite'] != transaction.isCompositeConsume ||
        fields['typeName'] != transaction.typeName) {
      continue;
    }
    // An invalid/unsupported TU entry may remain in the raw JSON, but cannot
    // stand in for a transaction that the primary history actually displays.
    final index = accepted.indexWhere(
      (trip) =>
          trip.rawHex == raw &&
          trip.sequence == sequence &&
          trip.amountFen == amount &&
          trip.terminalId == terminal &&
          trip.time.millisecondsSinceEpoch == epoch,
    );
    if (index < 0) continue;
    accepted.removeAt(index);
    yield transaction;
  }
}

DateTime? _capturedCivil(Map fields) {
  final times = fields['capturedTimes'];
  if (times is! Map) return null;
  final capture = times['time'];
  if (capture is! Map) return null;
  final text = capture['civil'];
  final offset = capture['conversionOffsetMinutes'];
  final basis = capture['basis'];
  if (text is! String || offset is! int || offset < -840 || offset > 840) {
    return null;
  }
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.0{1,6})?(Z)?$',
  ).firstMatch(text);
  if (match == null ||
      (basis != 'utc' && basis != 'parser-local-unverified') ||
      (basis == 'utc' && (match[7] != 'Z' || offset != 0)) ||
      (basis == 'parser-local-unverified' && match[7] != null)) {
    return null;
  }
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match[i]!)];
  final civil = DateTime.utc(
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    parts[4],
    parts[5],
  );
  if (civil.year != parts[0] ||
      civil.month != parts[1] ||
      civil.day != parts[2] ||
      civil.hour != parts[3] ||
      civil.minute != parts[4] ||
      civil.second != parts[5] ||
      civil.subtract(Duration(minutes: offset)).millisecondsSinceEpoch !=
          fields['time']) {
    return null;
  }
  return civil;
}
