import 'dart:convert';

import 'package:drift/drift.dart';

import 'app_database.dart';
import 'archive_observation_times.dart';
import '../domain/card_archive_document.dart';

/// The JSON document is the complete durable archive representation; relational
/// tables remain query indexes and the existing capture-write transaction path.
/// SQL triggers invalidate documents for older callers that write indexes.
class ArchiveDocumentStore {
  const ArchiveDocumentStore(this.db);
  final AppDatabase db;

  Future<void> backfill() async {
    final ids = await db.customSelect('''
      SELECT s.id FROM saved_cards s LEFT JOIN archive_documents d ON d.card_id=s.id
      WHERE d.card_id IS NULL OR d.dirty=1
    ''').get();
    for (final row in ids) {
      await refresh(row.read<String>('id'));
    }
  }

  Future<CardArchiveDocument?> read(String cardId) async {
    final stored = await db
        .customSelect(
          'SELECT payload_json,dirty FROM archive_documents WHERE card_id=?',
          variables: [Variable<String>(cardId)],
        )
        .getSingleOrNull();
    if (stored == null || stored.read<int>('dirty') != 0) {
      return refresh(cardId);
    }
    return CardArchiveDocument.decode(stored.read<String>('payload_json'));
  }

  Future<CardArchiveDocument?> refresh(String cardId) async {
    final card = await (db.select(
      db.savedCards,
    )..where((t) => t.id.equals(cardId))).getSingleOrNull();
    if (card == null) {
      await db.customStatement(
        'DELETE FROM archive_documents WHERE card_id=?',
        [cardId],
      );
      return null;
    }
    final previous = await db
        .customSelect(
          'SELECT payload_json FROM archive_documents WHERE card_id=?',
          variables: [Variable<String>(cardId)],
        )
        .getSingleOrNull();
    // A damaged or unsupported canonical document must surface as an error,
    // never silently lose its imported rows or future metadata in a rebuild.
    final preserved = previous == null
        ? null
        : CardArchiveDocument.decode(previous.read<String>('payload_json'));
    final batches =
        await (db.select(db.cardReadBatches)
              ..where((t) => t.cardId.equals(cardId))
              ..orderBy([
                (t) => OrderingTerm.desc(t.readAt),
                (t) => OrderingTerm.desc(t.id),
              ]))
            .get();
    final timeRows = await db
        .customSelect(
          'SELECT field_name,observed_at FROM archive_field_observation_times WHERE card_id=?',
          variables: [Variable<String>(cardId)],
        )
        .get();
    final times = archiveObservationTimes(
      card,
      batches,
      retainedTimes: {
        for (final row in timeRows)
          row.read<String>('field_name'): row.read<int>('observed_at'),
      },
    );
    final document = CardArchiveDocument(
      card: card,
      batches: batches,
      fieldObservationTimes: times,
      importedRecords: preserved?.importedRecords ?? const [],
      retainedSummaries: preserved?.retainedSummaries ?? const [],
      extensions: preserved?.extensions ?? const {},
      cardExtensions: preserved?.cardExtensions ?? const {},
      batchExtensions: {
        for (final batch in batches)
          batch.id: ?preserved?.batchExtensions[batch.id],
      },
    );
    await put(document);
    return document;
  }

  Future<void> put(CardArchiveDocument document) => db.customStatement(
    'INSERT INTO archive_documents(card_id,payload_json,dirty) VALUES(?,?,0) '
    'ON CONFLICT(card_id) DO UPDATE SET payload_json=excluded.payload_json,dirty=0',
    [document.card.id, document.encode()],
  );

  Future<ArchiveImportResult> preview(List<CardArchiveDocument> input) async =>
      (await _plan(input)).result;

  Future<ArchiveImportResult> import(List<CardArchiveDocument> input) async {
    final plan = await _plan(input);
    for (final document in plan.documents) {
      // This is the complete merged summary, so null means unknown rather than
      // an absent update. Keep the SQL index identical to the canonical JSON.
      await db
          .into(db.savedCards)
          .insertOnConflictUpdate(document.card.toCompanion(false));
      for (final batch in document.batches) {
        await db
            .into(db.cardReadBatches)
            .insert(batch, mode: InsertMode.insertOrIgnore);
      }
      await db.customStatement(
        'DELETE FROM archive_field_observation_times WHERE card_id=?',
        [document.card.id],
      );
      for (final entry in document.fieldObservationTimes.entries) {
        await db.customStatement(
          'INSERT INTO archive_field_observation_times(card_id,field_name,observed_at) VALUES(?,?,?)',
          [document.card.id, entry.key, entry.value],
        );
      }
      await put(document);
    }
    return plan.result;
  }

  Future<_ImportPlan> _plan(List<CardArchiveDocument> input) async {
    final checked = CardArchiveBundle.fromJson(
      CardArchiveBundle(
        cards: input,
        exportedAt: DateTime.now().toUtc(),
      ).toJson(),
    ).cards;
    final planned = <CardArchiveDocument>[];
    var inserted = 0;
    var merged = 0;
    var addedBatches = 0;
    var addedRecords = 0;
    var skippedBatches = 0;
    var skippedRecords = 0;
    for (final source in checked) {
      final index =
          await (db.select(db.savedCards)..where(
                (t) => t.cardFingerprint.equals(source.card.cardFingerprint),
              ))
              .getSingleOrNull();
      final existing = index == null ? null : await read(index.id);
      final targetId = existing?.card.id ?? source.card.id;
      final idOwner = await (db.select(
        db.savedCards,
      )..where((t) => t.id.equals(targetId))).getSingleOrNull();
      if (idOwner != null &&
          idOwner.cardFingerprint != source.card.cardFingerprint) {
        throw const FormatException('卡片 ID 已被其他卡片使用，未导入任何数据');
      }
      final combinedBatches = <String, CardReadBatch>{
        for (final batch in existing?.batches ?? const <CardReadBatch>[])
          batch.id: batch,
      };
      final batchExtras = <String, Map<String, dynamic>>{
        ...?existing?.batchExtensions,
      };
      for (final sourceBatch in source.batches) {
        final incoming = sourceBatch.copyWith(cardId: targetId);
        final stored = await (db.select(
          db.cardReadBatches,
        )..where((t) => t.id.equals(incoming.id))).getSingleOrNull();
        if (stored != null) {
          if (stored != incoming) {
            throw FormatException('批次 ${incoming.id} 的内容冲突，未导入任何数据');
          }
          batchExtras[incoming.id] = _mergeExtras(
            batchExtras[incoming.id] ?? {},
            source.batchExtensions[incoming.id] ?? {},
            '批次扩展',
          );
          skippedBatches++;
        } else {
          combinedBatches[incoming.id] = incoming;
          if (source.batchExtensions[incoming.id] case final extra?) {
            batchExtras[incoming.id] = extra;
          }
          addedBatches++;
        }
      }
      final rows = List<Map<String, dynamic>>.of(
        existing?.importedRecords ?? const [],
      );
      final available = <String, int>{};
      for (final row in rows) {
        final key = _canonical(row);
        available[key] = (available[key] ?? 0) + 1;
      }
      for (final row in source.importedRecords) {
        final key = _canonical(row);
        final remaining = available[key] ?? 0;
        if (remaining > 0) {
          available[key] = remaining - 1;
          skippedRecords++;
        } else {
          rows.add(row);
          addedRecords++;
        }
      }
      final CardArchiveDocument document;
      if (existing == null) {
        inserted++;
        document = source.copyWith(
          batches: combinedBatches.values.toList(),
          importedRecords: rows,
        );
      } else {
        merged++;
        final summary = _mergeCard(existing, source);
        document = existing.copyWith(
          card: summary.card,
          batches: combinedBatches.values.toList(),
          fieldObservationTimes: summary.times,
          importedRecords: rows,
          retainedSummaries: _mergeSummaries(existing, source, summary.card),
          extensions: _mergeExtras(
            existing.extensions,
            source.extensions,
            '档案扩展',
          ),
          cardExtensions: _mergeExtras(
            existing.cardExtensions,
            source.cardExtensions,
            '卡片扩展',
          ),
          batchExtensions: batchExtras,
        );
      }
      planned.add(document);
    }
    return _ImportPlan(
      planned,
      ArchiveImportResult(
        insertedCards: inserted,
        mergedCards: merged,
        addedBatches: addedBatches,
        addedRecords: addedRecords,
        skippedBatches: skippedBatches,
        skippedRecords: skippedRecords,
      ),
    );
  }
}

List<Map<String, dynamic>> _mergeSummaries(
  CardArchiveDocument previous,
  CardArchiveDocument incoming,
  SavedCard merged,
) {
  final summaries = <String, Map<String, dynamic>>{};
  void retain(Map<String, dynamic> summary) {
    summaries.putIfAbsent(_canonical(summary), () => summary);
  }

  for (final summary in [
    ...previous.retainedSummaries,
    ...incoming.retainedSummaries,
  ]) {
    retain(summary);
  }
  for (final source in [previous, incoming]) {
    if (source.card.sessionDataJson != null &&
        source.card.sessionDataJson != merged.sessionDataJson) {
      retain({
        'format': 'trafarch.card-summary',
        'version': 1,
        'card': {...source.cardExtensions, ...source.card.toJson()},
        'fieldObservationTimes': source.fieldObservationTimes,
      });
    }
  }
  return summaries.values.toList();
}

class _ImportPlan {
  const _ImportPlan(this.documents, this.result);
  final List<CardArchiveDocument> documents;
  final ArchiveImportResult result;
}

class _SummaryMerge {
  const _SummaryMerge(this.card, this.times);
  final SavedCard card;
  final Map<String, int> times;
}

_SummaryMerge _mergeCard(
  CardArchiveDocument previous,
  CardArchiveDocument incoming,
) {
  final existing = previous.card;
  final source = incoming.card;
  final fields = Map<String, dynamic>.of(existing.toJson());
  final values = source.toJson();
  final previousTimes = archiveObservationTimes(
    existing,
    previous.batches,
    retainedTimes: previous.fieldObservationTimes,
  );
  final incomingTimes = archiveObservationTimes(
    source,
    incoming.batches,
    retainedTimes: incoming.fieldObservationTimes,
  );
  final times = Map<String, int>.of(previousTimes);
  // Known clocks belong to the scalar value actually selected below. A
  // timestamp for a missing value must not age an unrelated retained value.
  const selectedClocks = {
    'officialName',
    'issuerName',
    'cityName',
    'cardNumber',
    'transactionCount',
    'balanceFen',
    'currencyCode',
    'identity',
  };
  for (final entry in incomingTimes.entries) {
    if (!selectedClocks.contains(entry.key) &&
        entry.value > (times[entry.key] ?? -8640000000000000)) {
      times[entry.key] = entry.value;
    }
  }
  void remember(String name) {
    if (incomingTimes[name] case final at?) {
      times[name] = at;
    } else {
      times.remove(name);
    }
  }

  bool newer(String name) =>
      (incomingTimes[name] ?? -8640000000000000) >
      (previousTimes[name] ?? -8640000000000000);
  for (final name in [
    'officialName',
    'issuerName',
    'cityName',
    'cardNumber',
    'transactionCount',
  ]) {
    if (values[name] != null && (fields[name] == null || newer(name))) {
      fields[name] = values[name];
      remember(name);
    }
  }
  if (source.balanceFen != null &&
      (existing.balanceFen == null || newer('balanceFen'))) {
    fields['balanceFen'] = source.balanceFen;
    fields['currencyCode'] = source.currencyCode;
    remember('balanceFen');
    if (source.currencyCode == null) {
      times.remove('currencyCode');
    } else {
      times['currencyCode'] =
          incomingTimes['currencyCode'] ?? incomingTimes['balanceFen']!;
    }
  }
  if (source.identificationSource != 'unknown' &&
      (existing.identificationSource == 'unknown' || newer('identity'))) {
    fields['identificationSource'] = source.identificationSource;
    fields['identificationConfidence'] = source.identificationConfidence;
    remember('identity');
  }
  if (existing.customName == null || existing.customName!.trim().isEmpty) {
    fields['customName'] = source.customName;
  }
  if (existing.cardNumberMasked == null) {
    fields['cardNumberMasked'] = source.cardNumberMasked;
  }
  if (existing.cardImagePath == null) {
    fields['cardImagePath'] = source.cardImagePath;
  }
  if (source.lastReadAt != null &&
      (existing.lastReadAt == null ||
          source.lastReadAt! > existing.lastReadAt!)) {
    fields['lastReadAt'] = source.lastReadAt;
    fields['sessionDataJson'] = source.sessionDataJson;
    fields['cardType'] = source.cardType;
  }
  fields['createdAt'] = source.createdAt < existing.createdAt
      ? source.createdAt
      : existing.createdAt;
  fields['updatedAt'] = source.updatedAt > existing.updatedAt
      ? source.updatedAt
      : existing.updatedAt;
  return _SummaryMerge(SavedCard.fromJson(fields), times);
}

Map<String, dynamic> _mergeExtras(
  Map<String, dynamic> previous,
  Map<String, dynamic> incoming,
  String label,
) {
  final result = Map<String, dynamic>.of(previous);
  for (final entry in incoming.entries) {
    if (result.containsKey(entry.key) &&
        _canonical(result[entry.key]) != _canonical(entry.value)) {
      throw FormatException('$label ${entry.key} 内容冲突，原始数据未覆盖');
    }
    result[entry.key] = entry.value;
  }
  return result;
}

String _canonical(Object? value) => jsonEncode(_sort(value));
Object? _sort(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _sort(value[key])};
  }
  if (value is List) return value.map(_sort).toList();
  return value;
}
