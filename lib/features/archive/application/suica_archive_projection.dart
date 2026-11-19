import 'dart:convert';

import '../../../protocols/felica/felica_hex.dart';
import '../../../protocols/felica/parsers/suica_record_parser.dart';
import '../domain/archive_context.dart';
import '../../trips/suica_trip_presenter.dart';
import 'archive_history.dart';

/// Frozen Suica history. Neither the current station package nor live scan
/// state participates in restoration of a saved journey.
class SuicaArchiveRecord {
  const SuicaArchiveRecord({
    required this.fields,
    required this.presentation,
    required this.context,
    required this.sources,
  });

  final Map<String, dynamic> fields;
  final SuicaTripPresentation presentation;
  final ArchiveContext context;
  final List<ArchiveRecordSource> sources;
}

class SuicaArchiveProjection {
  const SuicaArchiveProjection({
    required this.records,
    required this.issues,
    required this.hasCaptures,
    required this.hasHistoryObservation,
  });

  final List<SuicaArchiveRecord> records;
  final List<String> issues;
  final bool hasCaptures;
  final bool hasHistoryObservation;

  bool get isHistoryUnobserved =>
      hasCaptures && !hasHistoryObservation && issues.isEmpty;

  List<SuicaTripPresentation> get trips =>
      List.unmodifiable(records.map((record) => record.presentation));
}

SuicaArchiveProjection projectSuicaArchive(ArchiveHistoryResult history) {
  final records = <String, SuicaArchiveRecord>{};
  final issues = <String>[];
  var hasCaptures = false;
  var hasHistoryObservation = false;
  for (final batch in history.batches) {
    final snapshot = batch.decoded.snapshot;
    final section = snapshot?.extensions['suica'];
    if (section == null) continue;
    hasCaptures = true;
    if (section is! Map ||
        section['version'] != 1 ||
        section['records'] is! List) {
      issues.add('${batch.id}: Suica 历史格式不支持，原始快照已保留');
      continue;
    }
    final context = snapshot!.context;
    final occurrences = <String, int>{};
    final rows = section['records'] as List;
    hasHistoryObservation |=
        section['historyObserved'] == true || rows.isNotEmpty;
    for (var index = 0; index < rows.length; index++) {
      final path = 'suica.records[$index]';
      final row = rows[index];
      if (row is! Map<String, dynamic> || !_validRecord(row)) {
        issues.add('${batch.id}/$path: Suica 历史记录不完整，原始快照已保留');
        continue;
      }
      final raw = (row['rawHex'] as String).replaceAll(' ', '').toUpperCase();
      // Older captures included initialized slots as unknown transactions.
      // Filter their exact bytes in the view while retaining the saved rows
      // and raw evidence. Other unknown or incomplete records stay visible.
      if (RegExp(r'^[0-9A-F]{32}$').hasMatch(raw) &&
          SuicaRecordParser.isBlankHistoryBlock(FelicaHex.hexToBytes(raw))) {
        continue;
      }
      final presentation = SuicaTripPresentation.fromJson(row['presentation']);
      if (presentation == null) {
        issues.add('${batch.id}/$path: Suica 历史展示无法恢复，原始快照已保留');
        continue;
      }
      final details = row['details'];
      final counter = details is Map ? details['recordSequence'] : null;
      // A history block moves when newer transactions arrive. Its physical
      // block number and inferred balance delta do not identify a transaction.
      // The card's date is already inside rawHex. Device-local epoch/timezone
      // interpretations of that civil date must not duplicate the transaction.
      // Incomplete bytes/counters never establish a cross-capture duplicate.
      final identity = jsonEncode({
        'systemId': context.systemId,
        'applicationId': context.applicationId,
        'currencyCode': context.currencyCode,
        'minorUnitDigits': context.minorUnitDigits,
        'rawHex': raw,
        'recordSequence': counter,
        'balanceYen': row['balanceYen'],
        'amountIsBalance': row['amountIsBalance'],
        'currency': row['currencyCode'],
        if (!RegExp(r'^[0-9A-F]{32}$').hasMatch(raw) ||
            counter is! int ||
            counter < 0 ||
            counter > 65535)
          'occurrence': [batch.id, index],
      });
      final occurrence = occurrences.update(
        identity,
        (count) => count + 1,
        ifAbsent: () => 0,
      );
      final key = '$identity:$occurrence';
      final previous = records[key];
      records[key] = SuicaArchiveRecord(
        // Histories arrive newest first. Keep that frozen display and all
        // provenance, while preserving repeated occurrences within one read.
        fields: previous?.fields ?? Map.unmodifiable(row),
        presentation: previous?.presentation ?? presentation,
        context: previous?.context ?? context,
        sources: List.unmodifiable([
          ...?previous?.sources,
          ArchiveRecordSource(batch.id, path, batch.storedParseVersion, row),
        ]),
      );
    }
  }
  final indexed = records.values.indexed.toList();
  indexed.sort((a, b) {
    final at = _capturedCivilDate(a.$2);
    final bt = _capturedCivilDate(b.$2);
    if (at != null && bt != null) {
      final order = bt.compareTo(at);
      if (order != 0) return order;
    } else if (at != null || bt != null) {
      return at != null ? -1 : 1;
    }
    // Railway records contain a date but no clock time. Their placeholder
    // midnight cannot order them against shopping records with minute clocks.
    // Preserve the capture's newest-first stream within each civil date.
    return a.$1.compareTo(b.$1);
  });
  return SuicaArchiveProjection(
    records: List.unmodifiable(indexed.map((entry) => entry.$2)),
    issues: List.unmodifiable(issues),
    hasCaptures: hasCaptures,
    hasHistoryObservation: hasHistoryObservation,
  );
}

String? _capturedCivilDate(SuicaArchiveRecord record) {
  for (final text in [
    record.presentation.entry.info.timeText,
    record.presentation.entry.dateText,
  ]) {
    if (text == null) continue;
    final match = RegExp(r'^(\d{4}-\d{2}-\d{2})(?: |$)').firstMatch(text);
    if (match != null) return match.group(1);
  }
  return null;
}

bool _validRecord(Map<String, dynamic> row) {
  if (row['rawHex'] is! String) return false;
  for (final field in ['blockNumber', 'timestamp', 'balanceYen']) {
    if (row[field] != null && row[field] is! int) return false;
  }
  for (final field in ['decoded', 'amountIsBalance']) {
    if (row[field] != null && row[field] is! bool) return false;
  }
  if (row['currencyCode'] != null && row['currencyCode'] is! String) {
    return false;
  }
  if (row['details'] != null && row['details'] is! Map) return false;
  return true;
}
