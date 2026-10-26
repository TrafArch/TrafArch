import 'dart:convert';

import '../data/app_database.dart';

/// Versioned complete card archive. Captured payload strings are never decoded
/// or rewritten by this envelope, including unsupported or malformed snapshots.
class CardArchiveDocument {
  static const format = 'trafarch.card';
  static const version = 1;

  final SavedCard card;
  final List<CardReadBatch> batches;
  final Map<String, int> fieldObservationTimes;
  final List<Map<String, dynamic>> importedRecords;

  /// Original summary envelopes displaced by a merge. These retain their
  /// source card IDs and raw scalar text without inventing NFC capture batches.
  final List<Map<String, dynamic>> retainedSummaries;
  final Map<String, dynamic> extensions;
  final Map<String, dynamic> cardExtensions;
  final Map<String, Map<String, dynamic>> batchExtensions;

  CardArchiveDocument({
    required this.card,
    required List<CardReadBatch> batches,
    required Map<String, int> fieldObservationTimes,
    List<Map<String, dynamic>> importedRecords = const [],
    List<Map<String, dynamic>> retainedSummaries = const [],
    Map<String, dynamic> extensions = const {},
    Map<String, dynamic> cardExtensions = const {},
    Map<String, Map<String, dynamic>> batchExtensions = const {},
  }) : batches = List.unmodifiable(batches),
       fieldObservationTimes = Map.unmodifiable(fieldObservationTimes),
       importedRecords = List.unmodifiable(importedRecords.map(_freezeMap)),
       retainedSummaries = List.unmodifiable(retainedSummaries.map(_freezeMap)),
       extensions = _freezeMap(extensions),
       cardExtensions = _freezeMap(cardExtensions),
       batchExtensions = Map.unmodifiable({
         for (final entry in batchExtensions.entries)
           entry.key: _freezeMap(entry.value),
       });

  CardArchiveDocument copyWith({
    SavedCard? card,
    List<CardReadBatch>? batches,
    Map<String, int>? fieldObservationTimes,
    List<Map<String, dynamic>>? importedRecords,
    List<Map<String, dynamic>>? retainedSummaries,
    Map<String, dynamic>? extensions,
    Map<String, dynamic>? cardExtensions,
    Map<String, Map<String, dynamic>>? batchExtensions,
  }) => CardArchiveDocument(
    card: card ?? this.card,
    batches: batches ?? this.batches,
    fieldObservationTimes: fieldObservationTimes ?? this.fieldObservationTimes,
    importedRecords: importedRecords ?? this.importedRecords,
    retainedSummaries: retainedSummaries ?? this.retainedSummaries,
    extensions: extensions ?? this.extensions,
    cardExtensions: cardExtensions ?? this.cardExtensions,
    batchExtensions: batchExtensions ?? this.batchExtensions,
  );

  Map<String, dynamic> toJson() => {
    ...extensions,
    'format': format,
    'version': version,
    'card': {...cardExtensions, ...card.toJson()},
    'batches': [
      for (final batch in batches)
        {...?batchExtensions[batch.id], ...batch.toJson()},
    ],
    'fieldObservationTimes': fieldObservationTimes,
    'importedRecords': importedRecords,
    'retainedSummaries': retainedSummaries,
  };

  String encode() => jsonEncode(toJson());

  factory CardArchiveDocument.decode(String text) =>
      CardArchiveDocument.fromJson(_object(jsonDecode(text), '卡片档案'));

  factory CardArchiveDocument.fromJson(Map<String, dynamic> json) {
    if (json['format'] != format || json['version'] != version) {
      throw const FormatException('不支持的卡片 JSON 档案格式或版本');
    }
    final fields = _object(json['card'], 'card');
    final card = _readCard(fields);
    final rawBatches = json['batches'];
    if (rawBatches is! List) throw const FormatException('batches 应为数组');
    final batches = <CardReadBatch>[];
    final batchExtras = <String, Map<String, dynamic>>{};
    final ids = <String>{};
    for (final raw in rawBatches) {
      final fields = _object(raw, 'batch');
      for (final name in ['id', 'cardId', 'cardFingerprint']) {
        _string(fields, name, required: true, nonempty: true);
      }
      _string(fields, 'payloadJson', required: true);
      _integer(fields, 'readAt', required: true, timestamp: true);
      _integer(fields, 'parseVersion', required: true, minimum: 1);
      final batch = CardReadBatch.fromJson(fields);
      if (batch.cardId != card.id ||
          batch.cardFingerprint != card.cardFingerprint) {
        throw const FormatException('读取批次不属于所在卡片');
      }
      if (!ids.add(batch.id)) throw const FormatException('卡片中存在重复批次 ID');
      batches.add(batch);
      final extra = _extras(fields, batch.toJson().keys.toSet());
      if (extra.isNotEmpty) batchExtras[batch.id] = extra;
    }
    final times = _readObservationTimes(json['fieldObservationTimes']);
    final rawRows = json['importedRecords'] ?? const [];
    if (rawRows is! List) throw const FormatException('importedRecords 应为数组');
    final rows = <Map<String, dynamic>>[];
    for (final row in rawRows) {
      final fields = _object(row, 'importedRecords');
      for (final value in fields.values) {
        if (value != null &&
            value is! String &&
            value is! bool &&
            value is! num) {
          throw const FormatException('导入记录的字段应为文本、数值、布尔值或 null');
        }
        if (value is num && !value.isFinite) {
          throw const FormatException('导入数值必须有限');
        }
      }
      rows.add(fields);
    }
    final rawSummaries = json['retainedSummaries'] ?? const [];
    if (rawSummaries is! List) {
      throw const FormatException('retainedSummaries 应为数组');
    }
    final summaries = <Map<String, dynamic>>[];
    for (final raw in rawSummaries) {
      final summary = _object(raw, 'retainedSummaries');
      if (summary['format'] != 'trafarch.card-summary' ||
          summary['version'] != 1) {
        throw const FormatException('不支持的保留摘要格式或版本');
      }
      final summaryFields = _object(summary['card'], 'retainedSummaries.card');
      final summaryCard = _readCard(summaryFields);
      _string(summaryFields, 'sessionDataJson', required: true);
      if (summaryCard.cardFingerprint != card.cardFingerprint) {
        throw const FormatException('保留摘要不属于所在卡片');
      }
      _readObservationTimes(summary['fieldObservationTimes']);
      // Keep source IDs, unknown metadata and even invalid/future raw snapshot
      // text exactly as supplied; validation does not decode those snapshots.
      summaries.add(summary);
    }
    return CardArchiveDocument(
      card: card,
      batches: batches,
      fieldObservationTimes: times,
      importedRecords: rows,
      retainedSummaries: summaries,
      extensions: _extras(json, const {
        'format',
        'version',
        'card',
        'batches',
        'fieldObservationTimes',
        'importedRecords',
        'retainedSummaries',
      }),
      cardExtensions: _extras(fields, card.toJson().keys.toSet()),
      batchExtensions: batchExtras,
    );
  }
}

class CardArchiveBundle {
  static const format = 'trafarch.archive';
  static const version = 1;
  final List<CardArchiveDocument> cards;
  final DateTime exportedAt;
  final Map<String, dynamic> extensions;

  CardArchiveBundle({
    required List<CardArchiveDocument> cards,
    required this.exportedAt,
    Map<String, dynamic> extensions = const {},
  }) : cards = List.unmodifiable(cards),
       extensions = _freezeMap(extensions);

  Map<String, dynamic> toJson() => {
    ...extensions,
    'format': format,
    'version': version,
    'exportedAt': exportedAt.toUtc().toIso8601String(),
    'cards': [for (final card in cards) card.toJson()],
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory CardArchiveBundle.decode(String text) =>
      CardArchiveBundle.fromJson(_object(jsonDecode(text), '备份文件'));

  factory CardArchiveBundle.fromJson(Map<String, dynamic> json) {
    if (json['format'] != format || json['version'] != version) {
      throw const FormatException('不支持的卡片备份格式或版本');
    }
    final at = json['exportedAt'];
    final exportedAt = at is String ? DateTime.tryParse(at) : null;
    if (exportedAt == null ||
        !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(at as String)) {
      throw const FormatException('exportedAt 应为带时区的 ISO 8601 时间');
    }
    final rows = json['cards'];
    if (rows is! List) throw const FormatException('cards 应为数组');
    final cards = <CardArchiveDocument>[];
    final ids = <String>{};
    final fingerprints = <String>{};
    final batches = <String>{};
    for (final value in rows) {
      final document = CardArchiveDocument.fromJson(_object(value, 'cards'));
      if (!ids.add(document.card.id) ||
          !fingerprints.add(document.card.cardFingerprint)) {
        throw const FormatException('备份存在重复的卡片 ID 或指纹');
      }
      for (final batch in document.batches) {
        if (!batches.add(batch.id)) throw const FormatException('备份存在重复的批次 ID');
      }
      cards.add(document);
    }
    return CardArchiveBundle(
      cards: cards,
      exportedAt: exportedAt,
      extensions: _extras(json, const {
        'format',
        'version',
        'exportedAt',
        'cards',
      }),
    );
  }
}

class ArchiveImportResult {
  final int insertedCards;
  final int mergedCards;
  final int addedBatches;
  final int addedRecords;
  final int skippedBatches;
  final int skippedRecords;
  const ArchiveImportResult({
    this.insertedCards = 0,
    this.mergedCards = 0,
    this.addedBatches = 0,
    this.addedRecords = 0,
    this.skippedBatches = 0,
    this.skippedRecords = 0,
  });
}

SavedCard _readCard(Map<String, dynamic> fields) {
  for (final name in [
    'id',
    'cardFingerprint',
    'cardType',
    'identificationSource',
  ]) {
    _string(fields, name, required: true, nonempty: true);
  }
  for (final name in [
    'officialName',
    'customName',
    'issuerName',
    'cityName',
    'cardNumber',
    'cardNumberMasked',
    'currencyCode',
    'sessionDataJson',
    'cardImagePath',
  ]) {
    _string(fields, name);
  }
  _integer(fields, 'createdAt', required: true, timestamp: true);
  _integer(fields, 'updatedAt', required: true, timestamp: true);
  _integer(fields, 'lastReadAt', timestamp: true);
  _integer(fields, 'balanceFen');
  _integer(fields, 'transactionCount', minimum: 0);
  final confidence = fields['identificationConfidence'];
  if (confidence != null && (confidence is! num || !confidence.isFinite)) {
    throw const FormatException('identificationConfidence 应为有限数值');
  }
  return SavedCard.fromJson({
    ...fields,
    'identificationConfidence': (confidence as num?)?.toDouble(),
  });
}

Map<String, int> _readObservationTimes(Object? value) {
  final raw = _object(value ?? {}, 'fieldObservationTimes');
  final times = <String, int>{};
  for (final entry in raw.entries) {
    _integer(raw, entry.key, required: true, timestamp: true);
    times[entry.key] = entry.value as int;
  }
  return times;
}

Map<String, dynamic> _object(Object? value, String name) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw FormatException('$name 应为对象');
  }
  return Map<String, dynamic>.from(value);
}

Map<String, dynamic> _freezeMap(Map<String, dynamic> value) =>
    Map.unmodifiable(_freezeJson(value) as Map<String, dynamic>);

Object? _freezeJson(Object? value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.unmodifiable({
      for (final entry in value.entries) entry.key: _freezeJson(entry.value),
    });
  }
  if (value is List) return List<Object?>.unmodifiable(value.map(_freezeJson));
  return value;
}

Map<String, dynamic> _extras(Map<String, dynamic> values, Set<String> known) =>
    {
      for (final entry in values.entries)
        if (!known.contains(entry.key)) entry.key: entry.value,
    };

void _string(
  Map<String, dynamic> fields,
  String name, {
  bool required = false,
  bool nonempty = false,
}) {
  final value = fields[name];
  if (value == null && !required) return;
  if (value is! String || (nonempty && value.trim().isEmpty)) {
    throw FormatException('$name 应为${nonempty ? '非空' : ''}字符串');
  }
}

void _integer(
  Map<String, dynamic> fields,
  String name, {
  bool required = false,
  bool timestamp = false,
  int? minimum,
}) {
  final value = fields[name];
  if (value == null && !required) return;
  if (value is! int ||
      (timestamp && (value < -8640000000000000 || value > 8640000000000000)) ||
      (minimum != null && value < minimum)) {
    throw FormatException('$name 应为有效范围内的整数');
  }
}
