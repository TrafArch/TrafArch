import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../platform/storage/archive_document_store.dart';
import '../../../shared/application/owned_notifier.dart';
import '../data/app_database.dart';
import '../data/card_repository.dart';
import '../domain/archive_export_options.dart';
import '../domain/card_archive_document.dart';
import '../domain/card_types.dart';
import 'archive_history.dart';
import 'archive_records_json.dart';

class ArchiveImportPreview {
  ArchiveImportPreview._({
    required this.name,
    required this.isPartial,
    required this.recordCount,
    required List<CardArchiveDocument> documents,
    required this.result,
  }) : _documents = List.unmodifiable(documents);

  final String name;
  final bool isPartial;
  final int recordCount;
  final ArchiveImportResult result;
  final List<CardArchiveDocument> _documents;
  int get cardCount => _documents.length;
  int get batchCount =>
      _documents.fold(0, (count, card) => count + card.batches.length);
  String get summary =>
      '$cardCount 张卡片 · $batchCount 个读取批次 · $recordCount 条记录\n'
      '新增 ${result.insertedCards} 张，合并 ${result.mergedCards} 张。'
      '${isPartial ? '\n此文件仅含已导出的字段，将作为导入记录保存。' : '\n保留本机已有的自定义名称，重复批次不会重复添加。'}';
}

/// Coordinates local file exchange. No network or reference-library lookup is
/// involved; confirmation applies only to the most recently previewed file.
class ArchiveTransferController extends OwnedNotifier {
  ArchiveTransferController(this.repository, this.documents);
  final CardRepository repository;
  final ArchiveDocumentStore documents;
  static const maxFileBytes = 32 * 1024 * 1024;
  final Set<Future<void>> _operations = {};
  ArchiveImportPreview? _pending;
  bool busy = false;

  Future<T> _run<T>(Future<T> Function() action) async {
    _ensureAlive();
    if (busy) throw StateError('正在处理另一个文件，请稍后重试');
    busy = true;
    final finished = Completer<void>();
    _operations.add(finished.future);
    notifyListeners();
    try {
      return await action();
    } finally {
      busy = false;
      _operations.remove(finished.future);
      finished.complete();
      notifyListeners();
    }
  }

  void _ensureAlive() {
    if (disposed) throw StateError('卡片导入导出已关闭');
  }

  Future<ArchiveImportPreview?> pickImport() => _run(() async {
    _pending = null;
    final file = await documents.openJson();
    _ensureAlive();
    if (file == null) return null;
    if (utf8.encode(file.content).length > maxFileBytes) {
      throw const FormatException('JSON 文件超过 32 MiB，请分卡片导出');
    }
    final text = file.content.startsWith('\uFEFF')
        ? file.content.substring(1)
        : file.content;
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('请选择 TrafArch 导出的 JSON 文件');
    }
    final List<CardArchiveDocument> cards;
    final bool partial;
    switch (decoded['format']) {
      case 'trafarch.archive':
        final bundle = CardArchiveBundle.decode(text);
        // Card-scoped extensions survive merges. Bundle-scoped metadata has no
        // lossless home when selecting or combining cards, so never discard it.
        if (bundle.extensions.isNotEmpty) {
          throw const FormatException('备份包含尚不支持的顶层扩展，无法完整恢复；未导入任何数据');
        }
        cards = bundle.cards;
        partial = false;
      case 'trafarch.records':
        cards = _documentsForRecords(decodeArchiveRecords(text));
        partial = true;
      default:
        throw const FormatException('无法识别卡片 JSON 文件格式');
    }
    if (cards.isEmpty) throw const FormatException('文件没有可导入的卡片记录');
    final result = await repository.previewImportDocuments(cards);
    _ensureAlive();
    final rows = projectArchiveRecords([
      for (final card in cards)
        ArchiveHistory.project(
          ArchiveRows(
            card: card.card,
            batches: card.batches,
            importedRecords: card.importedRecords,
            retainedSummaries: card.retainedSummaries,
          ),
          balanceObservedAt: card.fieldObservationTimes['balanceFen'],
        ),
    ]);
    return _pending = ArchiveImportPreview._(
      name: file.name,
      isPartial: partial,
      recordCount: rows.length,
      documents: cards,
      result: result,
    );
  });

  Future<ArchiveImportResult> confirmImport(ArchiveImportPreview preview) =>
      _run(() async {
        if (!identical(preview, _pending)) {
          throw StateError('导入预览已失效，请重新选择文件');
        }
        _pending = null;
        try {
          // Rechecks conflicts in the same transaction as the write. The live
          // archive may have changed since the user read the preview.
          return await repository.importDocuments(preview._documents);
        } catch (_) {
          if (!disposed) _pending = preview;
          rethrow;
        }
      });

  Future<String?> export({
    required ArchiveExportOptions options,
    Set<String>? cardIds,
  }) => _run(() async {
    if (cardIds != null && cardIds.isEmpty) {
      throw const FormatException('请至少选择一张卡片');
    }
    final cards = await repository.exportDocuments(cardIds: cardIds);
    _ensureAlive();
    if (cards.isEmpty) throw const FormatException('暂无卡片记录可导出');
    final now = DateTime.now().toUtc();
    final String content;
    final String prefix;
    if (options.mode == ArchiveExportMode.fullBackup) {
      content = CardArchiveBundle(cards: cards, exportedAt: now).encode();
      prefix = 'trafarch_backup';
    } else {
      final rows = projectArchiveRecords([
        for (final card in cards)
          ArchiveHistory.project(
            ArchiveRows(
              card: card.card,
              batches: card.batches,
              importedRecords: card.importedRecords,
              retainedSummaries: card.retainedSummaries,
            ),
            balanceObservedAt: card.fieldObservationTimes['balanceFen'],
          ),
      ]);
      if (rows.isEmpty) {
        throw const FormatException('所选卡片没有可导出的记录，请选择完整备份');
      }
      content = encodeArchiveRecords(
        rows,
        fields: options.fields,
        exportedAt: now,
      );
      prefix = 'trafarch_records';
    }
    if (utf8.encode(content).length > maxFileBytes) {
      throw const FormatException('JSON 文件超过 32 MiB，请分卡片导出');
    }
    _ensureAlive();
    final stamp = now.toIso8601String().replaceAll(RegExp(r'[^0-9]'), '');
    return documents.saveJson('${prefix}_$stamp.json', content);
  });

  Future<void> finishWrites() async {
    while (_operations.isNotEmpty) {
      await Future.wait(_operations.toList());
    }
  }

  @override
  void dispose() {
    _pending = null;
    super.dispose();
  }
}

List<CardArchiveDocument> _documentsForRecords(ArchiveRecordsDocument file) {
  // Content-based namespace prevents matching a real card by an unverified
  // exported name/number and remains stable across repeat imports and filenames.
  final fileHash = sha256
      .convert(
        utf8.encode(
          jsonEncode(
            _canonical({
              'fields': file.fields.map((field) => field.key).toList()..sort(),
              'records': file.records,
            }),
          ),
        ),
      )
      .toString();
  final groups = <String, List<Map<String, dynamic>>>{};
  for (final row in file.records) {
    final group = jsonEncode([row['card_number'], row['card_name']]);
    (groups[group] ??= []).add(row);
  }
  return [
    for (final group in groups.entries)
      _importedDocument(file, fileHash, group.key, group.value),
  ];
}

CardArchiveDocument _importedDocument(
  ArchiveRecordsDocument file,
  String fileHash,
  String group,
  List<Map<String, dynamic>> rows,
) {
  final key = sha256.convert(utf8.encode('$fileHash:$group')).toString();
  final at = file.exportedAt.millisecondsSinceEpoch;
  return CardArchiveDocument(
    card: SavedCard(
      id: 'json-$key',
      cardFingerprint: 'json-import:v1:$key',
      cardType: CardTypes.importedJson,
      officialName: rows.first['card_name'] as String? ?? '导入的卡片记录',
      identificationSource: 'json_import',
      cardNumber: rows.first['card_number'] as String?,
      createdAt: at,
      updatedAt: at,
      // File export time is not an NFC read time or a balance observation.
    ),
    batches: const [],
    fieldObservationTimes: const {},
    importedRecords: rows,
    extensions: {'importOrigin': 'selected_records'},
  );
}

Object? _canonical(Object? value) => switch (value) {
  Map<String, dynamic>() => {
    for (final key in value.keys.toList()..sort()) key: _canonical(value[key]),
  },
  List() => value.map(_canonical).toList(),
  _ => value,
};
