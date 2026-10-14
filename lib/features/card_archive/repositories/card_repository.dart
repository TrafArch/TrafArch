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
  /// [sessionDataJson] 为本次读取的行程记录快照（JSON）；已有档案在本轮
  /// 未解析到行程（传 null）时保留既有快照，避免历史记录被清空。
  Future<void> saveIdentity({
    required String fingerprint,
    required CardArchiveIdentity identity,
    String? cardNumber,
    int? balanceFen,
    String? currencyCode,
    int? transactionCount,
    String? sessionDataJson,
    DateTime? readAt,
  }) async {

    final at = (readAt ?? DateTime.now()).millisecondsSinceEpoch;

    await db.transaction(() async {
      final existing = await (db.select(db.savedCards)
            ..where((t) => t.cardFingerprint.equals(fingerprint)))
          .getSingleOrNull();

      if (existing == null) {
        await db.into(db.savedCards).insert(
              SavedCardsCompanion.insert(
                id: const Uuid().v4(),
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

  /// 单张档案数据流（卡片详情页监听改名 / 重复读取更新）；不存在时为空。
  Stream<SavedCard?> watchCard(String id) {
    return (db.select(db.savedCards)..where((t) => t.id.equals(id)))
        .watchSingleOrNull();
  }
}