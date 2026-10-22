import 'dart:convert';

import 'package:drift/drift.dart' show Variable;

import '../data/app_database.dart';
import '../domain/card_session_snapshot.dart';
import '../data/card_repository.dart';
import '../domain/archive_balance.dart';
import '../../transit_analysis/balance_interpretation.dart';

enum ArchiveRecordKind { transaction, rail, bus, process }

class ArchiveBatchEvidence {
  final String id;
  final int readAt;
  final int storedParseVersion;
  final String origin;
  final String timeSource;
  final SnapshotDecodeResult decoded;
  final List<SnapshotIssue> issues;

  const ArchiveBatchEvidence({
    required this.id,
    required this.readAt,
    required this.storedParseVersion,
    required this.origin,
    required this.timeSource,
    required this.decoded,
    required this.issues,
  });
}

class ArchiveRecordSource {
  final String batchId;
  final String path;
  final int capturedParseVersion;
  final Object? provenance;
  const ArchiveRecordSource(
    this.batchId,
    this.path,
    this.capturedParseVersion,
    this.provenance,
  );
}

/// A display record keeps its captured context and every batch attribution.
/// The immutable batch JSON remains authoritative; this is projection v1.
class ArchiveHistoryRecord {
  final ArchiveRecordKind kind;
  final Map<String, dynamic> fields;
  final ArchiveContext context;
  final String? cardCityCode;
  final List<ArchiveRecordSource> sources;
  const ArchiveHistoryRecord({
    required this.kind,
    required this.fields,
    required this.context,
    this.cardCityCode,
    required this.sources,
  });

  DateTime? get time {
    final millis = fields['time'] ?? fields['exitTime'] ?? fields['entryTime'];
    return millis is int ? DateTime.fromMillisecondsSinceEpoch(millis) : null;
  }
}

class ArchiveHistoryResult {
  static const projectionVersion = 1;
  final SavedCard? card;
  final List<ArchiveBatchEvidence> batches;
  final List<ArchiveHistoryRecord> records;
  final SnapshotDecodeResult? latestCapture;
  final int? balanceObservedAt;

  const ArchiveHistoryResult({
    required this.card,
    this.batches = const [],
    this.records = const [],
    this.latestCapture,
    this.balanceObservedAt,
  });

  bool get missing => card == null;

  /// Select by capture identity and observation time, never by equal amounts.
  /// A scalar match only validates a source already selected independently.
  ArchiveBalanceSource? get balanceSource {
    final saved = card;
    if (saved == null || saved.balanceFen == null) return null;
    final latest = latestCapture?.snapshot;
    if (snapshotObservesBalance(latest)) {
      final at = saved.lastReadAt ?? saved.updatedAt;
      if (!snapshotBalanceMatches(saved, latest) ||
          (balanceObservedAt != null && at != balanceObservedAt)) {
        return null;
      }
      final payload = latestCapture!.rawJson;
      String? id;
      for (final batch in batches) {
        if (batch.decoded.rawJson == payload) {
          id = batch.id;
          break;
        }
      }
      return ArchiveBalanceSource(
        payloadJson: payload,
        observedAt: at,
        batchId: id,
      );
    }
    final retained = ArchiveBalanceSource.fromJson(
      latest?.extensions['retainedBalanceSource'],
    );
    if (retained != null &&
        (balanceObservedAt == null ||
            retained.observedAt == balanceObservedAt) &&
        retained.observedAt <= (saved.lastReadAt ?? saved.updatedAt) &&
        snapshotBalanceMatches(saved, retained.snapshot) &&
        batches.any(
          (b) =>
              b.decoded.rawJson == retained.payloadJson &&
              (retained.batchId == null || b.id == retained.batchId),
        )) {
      return retained;
    }
    final observed = batches.where(
      (b) => snapshotObservesBalance(b.decoded.snapshot),
    );
    final at =
        balanceObservedAt ??
        (observed.isEmpty
            ? null
            : observed.map((b) => b.readAt).reduce((a, b) => a > b ? a : b));
    final candidates = {
      for (final b in observed)
        if (b.readAt == at) b.decoded.rawJson: b,
    };
    // Replayed payloads may have an observation time with no surviving batch.
    // Without an explicit link, retain the scalar as unverified history.
    if (candidates.length != 1) return null;
    final source = candidates.values.single;
    if (!snapshotBalanceMatches(saved, source.decoded.snapshot)) return null;
    return ArchiveBalanceSource(
      payloadJson: source.decoded.rawJson,
      observedAt: source.readAt,
      batchId: source.id,
    );
  }

  BalanceInterpretation? get balanceInterpretation {
    final saved = card;
    if (saved == null) return null;
    return capturedBalanceInterpretation(
      saved,
      saved.balanceFen == null
          ? latestCapture?.snapshot
          : balanceSource?.snapshot,
    );
  }

  /// Match the retained summary to the batch that observed it. A newer partial
  /// read may carry a different/unknown wallet context and must not relabel it.
  String? get balanceText {
    final saved = card;
    if (balanceInterpretation case final interpretation?) {
      return interpretation.accountBalanceText;
    }
    if (saved != null && isOctopusArchiveCard(saved)) {
      return unknownHistoricalOctopusBalance;
    }
    if (saved == null || saved.balanceFen == null) return null;
    final source = balanceSource?.snapshot;
    if (source?.context.minorUnitDigits != null) {
      return source!.context.formatAmount(saved.balanceFen!);
    }
    return ArchiveContext(
      currencyCode: saved.currencyCode,
      minorUnitDigits: 2,
    ).formatAmount(saved.balanceFen!);
  }

  String? get balanceObservationLabel =>
      balanceInterpretation?.observationLabel ??
      (card != null && isOctopusArchiveCard(card!) ? '历史金额（口径待核验）' : null);

  /// Some old payloads never included the scalar. Keep it visible in exports
  /// even when its role cannot be verified as a real HKD account balance.
  String? get balanceObservationText {
    if (balanceInterpretation case final interpretation?) {
      return interpretation.observedBalanceText;
    }
    final saved = card;
    if (saved == null ||
        !isOctopusArchiveCard(saved) ||
        saved.balanceFen == null) {
      return null;
    }
    return ArchiveContext(
      currencyCode: saved.currencyCode,
      minorUnitDigits: 2,
    ).formatAmount(saved.balanceFen!);
  }

  Map<String, bool> get latestObservedFields =>
      latestCapture?.snapshot?.context.observedFields ?? const {};
  bool get hasDiagnostics => batches.any((b) => b.issues.isNotEmpty);
}

/// One authoritative card-scoped query for detail and export. Database failures
/// propagate; a successfully loaded missing card is represented explicitly.
class ArchiveHistory {
  final CardRepository repository;
  const ArchiveHistory(this.repository);

  Stream<ArchiveHistoryResult> watch(String cardId) =>
      repository.watchArchiveRows(cardId).asyncMap((_) => load(cardId));

  Future<ArchiveHistoryResult> load(String cardId) =>
      repository.db.transaction(() async {
        final rows = await repository.getArchiveRows(cardId);
        final time = await repository.db
            .customSelect(
              'SELECT observed_at FROM archive_field_observation_times '
              'WHERE card_id=? AND field_name=?',
              variables: [
                Variable<String>(cardId),
                Variable<String>('balanceFen'),
              ],
            )
            .getSingleOrNull();
        return project(rows, balanceObservedAt: time?.read<int>('observed_at'));
      });

  Future<List<ArchiveHistoryResult>> loadAll() =>
      repository.db.transaction(() async {
        final cards = await repository.getAllCards();
        return [for (final card in cards) await load(card.id)];
      });

  /// Public for adapters with an already-consistent card/batch capture. A
  /// surviving scalar is included unless an exact payload batch already exists.
  static ArchiveHistoryResult project(
    ArchiveRows rows, {
    int? balanceObservedAt,
  }) {
    final card = rows.card;
    if (card == null) return const ArchiveHistoryResult(card: null);
    final batches = <ArchiveBatchEvidence>[];
    void add(
      String id,
      int at,
      int parser,
      String raw, {
      String? origin,
      String? timeSource,
    }) {
      final decoded = CardSessionSnapshot.decodeResult(raw);
      final legacy = id.startsWith('legacy-scalar-v6:');
      final issues = <SnapshotIssue>[...decoded.issues];
      if (decoded.snapshot case final snapshot?) {
        if (snapshot.parseVersion != parser) {
          issues.add(
            SnapshotIssue(
              'parseVersion',
              '批次列 $parser 与捕获内容 ${snapshot.parseVersion} 不一致；均已保留',
            ),
          );
        }
        if (snapshot.formatVersion < 3) {
          issues.add(
            const SnapshotIssue('context', '旧版未保存完整读取上下文；缺失币种、时区及来源保持未知'),
          );
        }
      }
      batches.add(
        ArchiveBatchEvidence(
          id: id,
          readAt: at,
          storedParseVersion: parser,
          origin:
              origin ??
              (legacy ? 'legacy_saved_cards.session_data_json' : 'capture'),
          timeSource: timeSource ?? (legacy ? id.split(':')[1] : 'read_at'),
          decoded: decoded,
          issues: List.unmodifiable(issues),
        ),
      );
    }

    for (final batch in rows.batches) {
      add(batch.id, batch.readAt, batch.parseVersion, batch.payloadJson);
    }
    final scalar = card.sessionDataJson;
    if (scalar != null && !rows.batches.any((b) => b.payloadJson == scalar)) {
      add(
        'surviving-scalar:${card.id}',
        card.lastReadAt ?? card.updatedAt,
        CardSessionSnapshot.decodeResult(scalar).snapshot?.parseVersion ?? 1,
        scalar,
        origin: 'unbackfilled_saved_cards.session_data_json',
        timeSource: card.lastReadAt == null ? 'updated_at' : 'last_read_at',
      );
    }
    batches.sort((a, b) {
      final time = b.readAt.compareTo(a.readAt);
      return time != 0 ? time : b.id.compareTo(a.id);
    });
    final records = <String, ArchiveHistoryRecord>{};
    for (final batch in batches) {
      final snapshot = batch.decoded.snapshot;
      if (snapshot == null) continue;
      final envelope =
          jsonDecode(batch.decoded.rawJson) as Map<String, dynamic>;
      for (final section in const {
        'trips': ArchiveRecordKind.transaction,
        'rails': ArchiveRecordKind.rail,
        'buses': ArchiveRecordKind.bus,
        'cycle': ArchiveRecordKind.process,
      }.entries) {
        var name = section.key;
        if (snapshot.formatVersion == 1) {
          if (name == 'cycle') continue;
          if (name == 'rails') name = 'rail';
          if (name == 'buses') name = 'bus';
        }
        final raw = envelope[name];
        if (raw == null) continue;
        final items = name == 'rail' || name == 'bus' ? [raw] : raw;
        if (items is! List) continue;
        for (var i = 0; i < items.length; i++) {
          final fields = items[i];
          final path = name == 'rail' || name == 'bus' ? name : '$name[$i]';
          if (fields is! Map<String, dynamic> ||
              !validateSnapshotRecord(fields, section.key, path, [])) {
            continue;
          }
          final captured = snapshot.context;
          final currency =
              fields['currency'] as String? ?? captured.currencyCode;
          final context = ArchiveContext(
            systemId: captured.systemId,
            applicationId: captured.applicationId,
            currencyCode: currency,
            // Legacy *Fen fields have a known /100 unit even when the wallet
            // currency was never captured. The latter remains unknown.
            minorUnitDigits:
                captured.minorUnitDigits ??
                (snapshot.formatVersion < 3 ? 2 : null),
            timeZoneOffsetMinutes: captured.timeZoneOffsetMinutes,
            clockBasis: captured.clockBasis,
            referencePackages: captured.referencePackages,
            extensions: captured.extensions,
          );
          // Exact complete records + context only. Incomplete historical keys
          // must not collapse distinct raw bytes/currencies/operators/cities.
          final key = jsonEncode(
            _canonical({
              'kind': section.key,
              'fields': fields,
              'context': {
                'systemId': context.systemId,
                'applicationId': context.applicationId,
                'currencyCode': context.currencyCode,
                'minorUnitDigits': context.minorUnitDigits,
                'timeZoneOffsetMinutes': context.timeZoneOffsetMinutes,
                'clockBasis': context.clockBasis,
              },
              'cardCityCode': snapshot.cardCityCode,
            }),
          );
          final previous = records[key];
          records[key] = ArchiveHistoryRecord(
            kind: section.value,
            fields: Map.unmodifiable(fields),
            context: context,
            cardCityCode: snapshot.cardCityCode,
            sources: List.unmodifiable([
              ...?previous?.sources,
              ArchiveRecordSource(batch.id, path, snapshot.parseVersion, {
                'referencePackages': captured.referencePackages,
                'record':
                    snapshot.recordProvenance[path] ??
                    {
                      'capture': snapshot.recordProvenance,
                      'recordPath': path,
                      'location': fields['location'],
                      'stationConfidence': fields['stationConfidence'],
                    },
              }),
            ]),
          );
        }
      }
    }
    final sorted = records.values.toList()
      ..sort((a, b) {
        final time = (b.time?.millisecondsSinceEpoch ?? -8640000000000000)
            .compareTo(a.time?.millisecondsSinceEpoch ?? -8640000000000000);
        return time != 0
            ? time
            : a.sources.first.path.compareTo(b.sources.first.path);
      });
    return ArchiveHistoryResult(
      card: card,
      batches: List.unmodifiable(batches),
      records: List.unmodifiable(sorted),
      latestCapture: scalar == null
          ? null
          : CardSessionSnapshot.decodeResult(scalar),
      balanceObservedAt: balanceObservedAt,
    );
  }
}

Object? _canonical(Object? value) {
  if (value is Map<String, dynamic>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}
