import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'app_database.dart';
import 'archive_observation_times.dart';
import 'archive_document_store.dart';
import '../domain/card_archive_document.dart';
import '../domain/card_archive_identity.dart';
import '../domain/card_session_snapshot.dart';

/// 卡片档案仓库：写入 / 更新识别结果，维护用户自定义名称。
///
/// 核心业务规则：重复读取与识别规则升级可以更新识别结果（正式卡名 /
/// 发行方 / 城市 / 最近读取时间），但绝不覆盖用户自定义名称。
class CardRepository {
  final AppDatabase db;

  CardRepository(this.db);

  /// 保存识别结果与读取快照：按 [fingerprint] 命中已有档案时更新识别字段、
  /// 读取快照（余额 / 货币 / 交易条数）与最近读取时间（不触碰
  /// [SavedCards.customName]）；未命中时新建档案。
  /// [sessionDataJson] 为本次读取的原始记录快照（CardSessionSnapshot v3）；
  /// 同时作为**读取批次**累积写入 [CardReadBatches]（同卡同内容去重，
  /// 历史不覆盖），[parseVersion] 记录产出批次的解析口径版本。
  Future<void> saveIdentity({
    required String fingerprint,
    required CardArchiveIdentity identity,
    String? cardNumber,
    int? balanceFen,
    String? currencyCode,
    int? transactionCount,
    String? sessionDataJson,
    int? parseVersion,
    DateTime? readAt,
    ArchiveContext? readContext,
  }) async {
    final at = (readAt ?? DateTime.now()).millisecondsSinceEpoch;
    final hasIdentityObservation =
        identity.officialName != null ||
        identity.issuerName != null ||
        identity.cityName != null;
    final payload = _capturePayload(
      sessionDataJson,
      readContext: readContext,
      cardNumber: cardNumber,
      balanceFen: balanceFen,
      currencyCode: currencyCode,
      transactionCount: transactionCount,
      parseVersion: parseVersion,
      identity: identity,
    );

    await db.transaction(() async {
      final existing = await (db.select(
        db.savedCards,
      )..where((t) => t.cardFingerprint.equals(fingerprint))).getSingleOrNull();

      final String cardId;
      if (existing == null) {
        cardId = const Uuid().v4();
        await db
            .into(db.savedCards)
            .insert(
              SavedCardsCompanion.insert(
                id: cardId,
                cardFingerprint: fingerprint,
                cardType: identity.cardType,
                officialName: Value(identity.officialName),
                issuerName: Value(identity.issuerName),
                cityName: Value(identity.cityName),
                identificationSource: Value(identity.identificationSource),
                identificationConfidence: Value(identity.confidence),
                cardNumber: Value(cardNumber),
                balanceFen: Value(balanceFen),
                currencyCode: Value(currencyCode),
                transactionCount: Value(transactionCount),
                sessionDataJson: Value(payload),
                lastReadAt: Value(at),
                createdAt: at,
                updatedAt: at,
              ),
            );
      } else {
        cardId = existing.id;
        // Preserve the scalar BEFORE replacement, even when unrelated batches
        // already exist or the legacy payload cannot be decoded.
        await db.backfillLegacySnapshots(cardId: cardId);
        // Retained summary fields are ordered by their own observation times.
        // A newer partial capture does not erase the last known observation;
        // a delayed intermediate capture may improve it without replacing the
        // newest capture envelope or lastReadAt.
        final previousBatches = await (db.select(
          db.cardReadBatches,
        )..where((t) => t.cardId.equals(cardId))).get();
        final retainedTimes = await db
            .customSelect(
              'SELECT field_name, observed_at FROM archive_field_observation_times WHERE card_id=?',
              variables: [Variable<String>(cardId)],
            )
            .get();
        final observedAt = archiveObservationTimes(
          existing,
          previousBatches,
          retainedTimes: {
            for (final row in retainedTimes)
              row.read<String>('field_name'): row.read<int>('observed_at'),
          },
        );
        await _rememberObservationTimes(cardId, observedAt);
        bool newer(String field) =>
            at >= (observedAt[field] ?? -8640000000000000);
        Value<T> field<T>(String key, T? value) =>
            value != null && newer(key) ? Value(value) : const Value.absent();
        final latest =
            existing.lastReadAt == null || at >= existing.lastReadAt!;
        final updateBalance = balanceFen != null && newer('balanceFen');
        await (db.update(
          db.savedCards,
        )..where((t) => t.id.equals(existing.id))).write(
          SavedCardsCompanion(
            cardType: latest ? Value(identity.cardType) : const Value.absent(),
            officialName: field('officialName', identity.officialName),
            issuerName: field('issuerName', identity.issuerName),
            cityName: field('cityName', identity.cityName),
            identificationSource:
                !hasIdentityObservation ||
                    identity.identificationSource == 'unknown' ||
                    !newer('identity')
                ? const Value.absent()
                : Value(identity.identificationSource),
            identificationConfidence:
                hasIdentityObservation && newer('identity')
                ? _observed(identity.confidence)
                : const Value.absent(),
            cardNumber: field('cardNumber', cardNumber),
            balanceFen: updateBalance
                ? Value(balanceFen)
                : const Value.absent(),
            currencyCode: updateBalance
                ? Value(currencyCode)
                : const Value.absent(),
            transactionCount: field('transactionCount', transactionCount),
            sessionDataJson: latest ? Value(payload) : const Value.absent(),
            lastReadAt: latest ? Value(at) : const Value.absent(),
            updatedAt: Value(at > existing.updatedAt ? at : existing.updatedAt),
          ),
        );
      }
      await _rememberObservationTimes(cardId, {
        if (cardNumber != null) 'cardNumber': at,
        if (balanceFen != null) 'balanceFen': at,
        if (transactionCount != null) 'transactionCount': at,
        if (identity.officialName != null) 'officialName': at,
        if (identity.issuerName != null) 'issuerName': at,
        if (identity.cityName != null) 'cityName': at,
        if (hasIdentityObservation) 'identity': at,
      });
      // 读取批次累积：本次有记录快照时追加一行；同卡内容完全一致
      // （同一记录集重复读取）时去重跳过，历史批次绝不覆盖。
      {
        final duplicate =
            await (db.select(db.cardReadBatches)
                  ..where(
                    (t) =>
                        t.cardId.equals(cardId) & t.payloadJson.equals(payload),
                  )
                  ..limit(1))
                .getSingleOrNull();
        if (duplicate == null) {
          await db
              .into(db.cardReadBatches)
              .insert(
                CardReadBatchesCompanion.insert(
                  id: const Uuid().v4(),
                  cardId: cardId,
                  cardFingerprint: fingerprint,
                  readAt: at,
                  parseVersion: Value(
                    parseVersion ??
                        CardSessionSnapshot.decodeResult(payload)
                            .snapshot
                            ?.parseVersion ??
                        1,
                  ),
                  payloadJson: payload,
                ),
              );
        }
      }
      await ArchiveDocumentStore(db).refresh(cardId);
    });
  }

  Future<void> _rememberObservationTimes(
    String cardId,
    Map<String, int> times,
  ) async {
    for (final entry in times.entries) {
      await db.customStatement(
        'INSERT INTO archive_field_observation_times(card_id,field_name,observed_at) VALUES(?,?,?) '
        'ON CONFLICT(card_id,field_name) DO UPDATE SET observed_at='
        'MAX(archive_field_observation_times.observed_at,excluded.observed_at)',
        [cardId, entry.key, entry.value],
      );
    }
  }

  /// 设置用户自定义名称（trim 后为空视为清除，恢复展示正式卡名）。
  Future<void> renameCard(String id, String? customName) async {
    final name = customName?.trim();

    await db.transaction(() async {
      await (db.update(db.savedCards)..where((t) => t.id.equals(id))).write(
        SavedCardsCompanion(
          customName: Value(name == null || name.isEmpty ? null : name),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );
      await ArchiveDocumentStore(db).refresh(id);
    });
  }

  /// 删除卡片档案及其全部读取批次（同一事务，避免残留孤儿批次数据）；
  /// 返回是否确实删除了档案（档案不存在时返回 false）。
  /// 列表 / 详情页数据流会随删除自动刷新；该卡再次读取时可重新建档。
  Future<bool> deleteCard(String id) {
    return db.transaction(() async {
      await db.customStatement(
        'DELETE FROM archive_field_observation_times WHERE card_id=?',
        [id],
      );
      await (db.delete(
        db.cardReadBatches,
      )..where((t) => t.cardId.equals(id))).go();
      final deleted = await (db.delete(
        db.savedCards,
      )..where((t) => t.id.equals(id))).go();
      return deleted > 0;
    });
  }

  /// 卡片档案列表（最近读取优先，其次最近更新）。
  Stream<List<SavedCard>> watchCards() {
    return (db.select(db.savedCards)..orderBy([
          (t) => OrderingTerm(
            expression: t.lastReadAt,
            mode: OrderingMode.desc,
            nulls: NullsOrder.last,
          ),
          (t) => OrderingTerm.desc(t.updatedAt),
          (t) => OrderingTerm.asc(t.id),
        ]))
        .watch();
  }

  /// 一次性获取全部卡片档案（排序同 [watchCards]），供导出使用。
  Future<List<SavedCard>> getAllCards() {
    return (db.select(db.savedCards)..orderBy([
          (t) => OrderingTerm(
            expression: t.lastReadAt,
            mode: OrderingMode.desc,
            nulls: NullsOrder.last,
          ),
          (t) => OrderingTerm.desc(t.updatedAt),
          (t) => OrderingTerm.asc(t.id),
        ]))
        .get();
  }

  /// 单张档案数据流（卡片详情页监听改名 / 重复读取更新）；不存在时为空。
  Stream<SavedCard?> watchCard(String id) {
    return (db.select(
      db.savedCards,
    )..where((t) => t.id.equals(id))).watchSingleOrNull();
  }

  /// 单张档案的读取批次流（新批次优先）：详情页历史累积与按批重解析入口。
  Stream<List<CardReadBatch>> watchBatches(String cardId) {
    return (db.select(db.cardReadBatches)
          ..where((t) => t.cardId.equals(cardId))
          ..orderBy([
            (t) => OrderingTerm.desc(t.readAt),
            (t) => OrderingTerm.desc(t.id),
          ]))
        .watch();
  }

  /// A single joined query gives history a consistent card + batches view and
  /// propagates database errors. Null card is a loaded deletion, not loading.
  JoinedSelectStatement<HasResultSet, dynamic> _historyQuery(String cardId) =>
      (db.select(db.savedCards)..where((t) => t.id.equals(cardId))).join([
        leftOuterJoin(
          db.cardReadBatches,
          db.cardReadBatches.cardId.equalsExp(db.savedCards.id),
        ),
      ])..orderBy([
        OrderingTerm.desc(db.cardReadBatches.readAt),
        OrderingTerm.desc(db.cardReadBatches.id),
      ]);

  Stream<ArchiveRows> watchArchiveRows(String cardId) =>
      _historyQuery(cardId).watch().asyncMap((_) => getArchiveRows(cardId));

  JoinedSelectStatement<HasResultSet, dynamic> _allHistoryQuery() =>
      db.select(db.savedCards).join([
        leftOuterJoin(
          db.cardReadBatches,
          db.cardReadBatches.cardId.equalsExp(db.savedCards.id),
        ),
      ])..orderBy([
        OrderingTerm(
          expression: db.savedCards.lastReadAt,
          mode: OrderingMode.desc,
          nulls: NullsOrder.last,
        ),
        OrderingTerm.desc(db.savedCards.updatedAt),
        OrderingTerm.asc(db.savedCards.id),
        OrderingTerm.desc(db.cardReadBatches.readAt),
        OrderingTerm.desc(db.cardReadBatches.id),
      ]);

  /// A single subscription tracks both indexes. Re-read the joined rows and
  /// JSON-only fields in one transaction so imports and batch-only writes cannot
  /// mix observations. Bulk reads avoid a separate history query per list tile.
  Stream<List<ArchiveRows>> watchAllArchiveRows() =>
      _allHistoryQuery().watch().asyncMap(
        (_) => db.transaction(() async {
          final joined = await _allHistoryQuery().get();
          final cards = <String, SavedCard>{};
          final batches = <String, List<CardReadBatch>>{};
          for (final row in joined) {
            final card = row.readTable(db.savedCards);
            cards.putIfAbsent(card.id, () => card);
            final batch = row.readTableOrNull(db.cardReadBatches);
            if (batch != null) {
              batches.putIfAbsent(card.id, () => []).add(batch);
            }
          }
          final documents = await db.customSelect('''
            SELECT d.card_id,d.payload_json,d.dirty FROM archive_documents d
            INNER JOIN saved_cards s ON s.id=d.card_id
          ''').get();
          final stored = <String, QueryRow>{
            for (final row in documents) row.read<String>('card_id'): row,
          };
          return List<ArchiveRows>.unmodifiable([
            for (final card in cards.values)
              _archiveRowsForList(
                card,
                List<CardReadBatch>.unmodifiable(batches[card.id] ?? const []),
                stored[card.id],
              ),
          ]);
        }),
      );

  ArchiveRows _archiveRowsForList(
    SavedCard indexedCard,
    List<CardReadBatch> indexedBatches,
    QueryRow? stored,
  ) {
    if (stored == null) {
      return ArchiveRows(card: indexedCard, batches: indexedBatches);
    }
    try {
      final document = CardArchiveDocument.decode(
        stored.read<String>('payload_json'),
      );
      if (document.card.id != indexedCard.id ||
          document.card.cardFingerprint != indexedCard.cardFingerprint) {
        throw const FormatException('卡片 JSON 档案与索引身份不一致');
      }
      // Mirror ArchiveDocumentStore.read: a clean complete document is
      // authoritative. A dirty document preserves JSON-only fields while its
      // current card/batch indexes supply the same rows refresh would expose.
      final clean = stored.read<int>('dirty') == 0;
      return ArchiveRows(
        card: clean ? document.card : indexedCard,
        batches: clean ? document.batches : indexedBatches,
        importedRecords: document.importedRecords,
        retainedSummaries: document.retainedSummaries,
      );
    } on FormatException catch (issue) {
      // Keep this card reachable (including its delete action) and let other
      // cards load. Never present an incomplete index count as the full count.
      return ArchiveRows(
        card: indexedCard,
        batches: const [],
        documentReadIssue: issue,
      );
    }
  }

  Future<ArchiveRows> getArchiveRows(String cardId) => db.transaction(() async {
    final document = await ArchiveDocumentStore(db).read(cardId);
    return ArchiveRows(
      card: document?.card,
      batches: document?.batches ?? const [],
      importedRecords: document?.importedRecords ?? const [],
      retainedSummaries: document?.retainedSummaries ?? const [],
    );
  });

  Future<void> refreshDocument(String cardId) => db.transaction(() async {
    await ArchiveDocumentStore(db).refresh(cardId);
  });

  Future<List<CardArchiveDocument>> exportDocuments({Set<String>? cardIds}) =>
      db.transaction(() async {
        final documents = <CardArchiveDocument>[];
        for (final card in await getAllCards()) {
          if (cardIds != null && !cardIds.contains(card.id)) continue;
          final document = await ArchiveDocumentStore(db).read(card.id);
          if (document != null) documents.add(document);
        }
        return List.unmodifiable(documents);
      });

  Future<ArchiveImportResult> previewImportDocuments(
    List<CardArchiveDocument> documents,
  ) => db.transaction(() => ArchiveDocumentStore(db).preview(documents));

  Future<ArchiveImportResult> importDocuments(
    List<CardArchiveDocument> documents,
  ) => db.transaction(() => ArchiveDocumentStore(db).import(documents));

  /// Captured parser versions are immutable. Re-parsing must produce a separate
  /// projection with its own version, never relabel a historical batch.
  Future<void> updateBatchParseVersion(String batchId, int parseVersion) =>
      Future.error(
        UnsupportedError(
          'Store a separate projection; captured batch parser versions are immutable',
        ),
      );
}

class ArchiveRows {
  final SavedCard? card;
  final List<CardReadBatch> batches;
  final List<Map<String, dynamic>> importedRecords;
  final List<Map<String, dynamic>> retainedSummaries;
  final Object? documentReadIssue;
  const ArchiveRows({
    required this.card,
    required this.batches,
    this.importedRecords = const [],
    this.retainedSummaries = const [],
    this.documentReadIssue,
  });
}

Value<T> _observed<T>(T? value) =>
    value == null ? const Value.absent() : Value(value);

/// Only new, valid v3 captures receive explicit observation context. Legacy,
/// partial, corrupt and future envelopes are stored byte-for-byte unchanged.
String _capturePayload(
  String? raw, {
  ArchiveContext? readContext,
  String? cardNumber,
  int? balanceFen,
  String? currencyCode,
  int? transactionCount,
  int? parseVersion,
  CardArchiveIdentity? identity,
}) {
  final decoded = raw == null ? null : CardSessionSnapshot.decodeResult(raw);
  if (decoded != null &&
      (decoded.formatVersion != 3 ||
          decoded.status != SnapshotDecodeStatus.supported)) {
    return raw!;
  }
  final capture =
      decoded?.snapshot ?? CardSessionSnapshot(parseVersion: parseVersion ?? 1);
  final context = readContext ?? capture.context;
  final json = jsonDecode(capture.encode()) as Map<String, dynamic>;
  json['context'] = {
    ...context.toJson(),
    'currencyCode': context.currencyCode ?? currencyCode,
    // Existing repository amount fields are explicitly in hundredths. A
    // protocol adapter may supply another scale in readContext (e.g. JPY).
    'minorUnitDigits':
        context.minorUnitDigits ?? (currencyCode == null ? null : 2),
    'observedFields': {
      ...context.observedFields,
      'cardNumber': cardNumber != null,
      'balanceFen': balanceFen != null,
      'currencyCode': currencyCode != null,
      'transactionCount': transactionCount != null,
    },
  };
  json['observations'] = {
    'officialName': identity?.officialName,
    'issuerName': identity?.issuerName,
    'cityName': identity?.cityName,
    'identity':
        identity == null ||
            (identity.officialName == null &&
                identity.issuerName == null &&
                identity.cityName == null)
        ? null
        : true,
    'cardNumber': cardNumber,
    'balanceFen': balanceFen,
    'currencyCode': currencyCode,
    'transactionCount': transactionCount,
  };
  return jsonEncode(json);
}
