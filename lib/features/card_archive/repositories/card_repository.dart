// 新建文件：lib/features/card_archive/repositories/card_repository.dart
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../database/app_database.dart';
import '../models/card_archive_identity.dart';

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
  /// [sessionDataJson] 为本次读取的原始记录快照（CardSessionSnapshot v2）；
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
  }) async {

    final at = (readAt ?? DateTime.now()).millisecondsSinceEpoch;

    await db.transaction(() async {
      final existing = await (db.select(db.savedCards)
            ..where((t) => t.cardFingerprint.equals(fingerprint)))
          .getSingleOrNull();

      final String cardId;
      if (existing == null) {
        cardId = const Uuid().v4();
        await db.into(db.savedCards).insert(
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
                sessionDataJson: Value(sessionDataJson),
                lastReadAt: Value(at),
                createdAt: at,
                updatedAt: at,
              ),
            );
      } else {
        cardId = existing.id;
        // 更新识别结果，但绝不修改 customName。
        await (db.update(db.savedCards)
              ..where((t) => t.id.equals(existing.id)))
            .write(
          SavedCardsCompanion(
            cardType: Value(identity.cardType),
            officialName: Value(identity.officialName),
            issuerName: Value(identity.issuerName),
            cityName: Value(identity.cityName),
            identificationSource: Value(identity.identificationSource),
            identificationConfidence: Value(identity.confidence),
            cardNumber: Value(cardNumber),
            balanceFen: Value(balanceFen),
            currencyCode: Value(currencyCode),
            transactionCount: Value(transactionCount),
            // 无新快照时不覆盖既有行程记录（本轮未解析到行程）
            sessionDataJson: sessionDataJson == null
                ? const Value.absent()
                : Value(sessionDataJson),
            lastReadAt: Value(at),
            updatedAt: Value(at),
          ),
        );
      }
      // 读取批次累积：本次有记录快照时追加一行；同卡内容完全一致
      // （同一记录集重复读取）时去重跳过，历史批次绝不覆盖。
      if (sessionDataJson != null) {
        final duplicate = await (db.select(db.cardReadBatches)
              ..where((t) =>
                  t.cardFingerprint.equals(fingerprint) &
                  t.payloadJson.equals(sessionDataJson))
              ..limit(1))
            .getSingleOrNull();
        if (duplicate == null) {
          await db.into(db.cardReadBatches).insert(
                CardReadBatchesCompanion.insert(
                  id: const Uuid().v4(),
                  cardId: cardId,
                  cardFingerprint: fingerprint,
                  readAt: at,
                  parseVersion: Value(parseVersion ?? 1),
                  payloadJson: sessionDataJson,
                ),
              );
        }
      }
    });
  }

  /// 设置用户自定义名称（trim 后为空视为清除，恢复展示正式卡名）。
  Future<void> renameCard(String id, String? customName) async {
    final name = customName?.trim();

    await (db.update(db.savedCards)..where((t) => t.id.equals(id))).write(
      SavedCardsCompanion(
        customName: Value(name == null || name.isEmpty ? null : name),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// 删除卡片档案及其全部读取批次（同一事务，避免残留孤儿批次数据）；
  /// 返回是否确实删除了档案（档案不存在时返回 false）。
  /// 列表 / 详情页数据流会随删除自动刷新；该卡再次读取时可重新建档。
  Future<bool> deleteCard(String id) {
    return db.transaction(() async {
      await (db.delete(db.cardReadBatches)..where((t) => t.cardId.equals(id)))
          .go();
      final deleted =
          await (db.delete(db.savedCards)..where((t) => t.id.equals(id))).go();
      return deleted > 0;
    });
  }

  /// 卡片档案列表（最近读取优先，其次最近更新）。
  Stream<List<SavedCard>> watchCards() {
    return (db.select(db.savedCards)
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.lastReadAt,
                  mode: OrderingMode.desc,
                  nulls: NullsOrder.last,
                ),
            (t) => OrderingTerm.desc(t.updatedAt),
          ]))
        .watch();
  }

  /// 一次性获取全部卡片档案（排序同 [watchCards]），供导出使用。
  Future<List<SavedCard>> getAllCards() {
    return (db.select(db.savedCards)
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.lastReadAt,
                  mode: OrderingMode.desc,
                  nulls: NullsOrder.last,
                ),
            (t) => OrderingTerm.desc(t.updatedAt),
          ]))
        .get();
  }

  /// 单张档案数据流（卡片详情页监听改名 / 重复读取更新）；不存在时为空。
  Stream<SavedCard?> watchCard(String id) {
    return (db.select(db.savedCards)..where((t) => t.id.equals(id)))
        .watchSingleOrNull();
  }

  /// 单张档案的读取批次流（新批次优先）：详情页历史累积与按批重解析入口。
  Stream<List<CardReadBatch>> watchBatches(String cardId) {
    return (db.select(db.cardReadBatches)
          ..where((t) => t.cardId.equals(cardId))
          ..orderBy([(t) => OrderingTerm.desc(t.readAt)]))
        .watch();
  }

  /// 解析口径升级后重解析用：更新指定批次的解析版本号（原始 payload 不动）。
  Future<void> updateBatchParseVersion(String batchId, int parseVersion) {
    return (db.update(db.cardReadBatches)..where((t) => t.id.equals(batchId)))
        .write(CardReadBatchesCompanion(parseVersion: Value(parseVersion)));
  }
}