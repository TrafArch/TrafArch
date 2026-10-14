// 新建文件：lib/database/app_database.dart
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/saved_cards.dart';

part 'app_database.g.dart';

/// 应用本地数据库（Drift + SQLite）：卡片档案及后续的交易 / 余额快照等表
/// 统一在本数据库管理（应用文档目录下 transit_card_analyzer.sqlite）。
///
/// 表结构变更时递增 [schemaVersion] 并在 [migration] 中为已安装用户编写
/// 迁移逻辑，避免升级后既有卡片档案丢失。
@DriftDatabase(tables: [SavedCards])
class AppDatabase extends _$AppDatabase {
  /// 测试可注入内存执行器：
  /// `AppDatabase(DatabaseConnection(NativeDatabase.memory()))`。
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // v2：卡片档案新增读取快照（余额 / 货币 / 交易记录条数），
          // 已安装用户升级时追加列，既有档案不丢失。
          if (from < 2) {
            await m.addColumn(savedCards, savedCards.balanceFen);
            await m.addColumn(savedCards, savedCards.currencyCode);
            await m.addColumn(savedCards, savedCards.transactionCount);
          }
          // v3：卡号改为完整存储（不再脱敏）：脱敏列重命名为 card_number；
          // 历史行中的脱敏值（**** 开头）清空，待下次读卡写入完整卡号。
          if (from < 3) {
            await m.renameColumn(
              savedCards,
              'card_number_masked',
              savedCards.cardNumber,
            );
            await customStatement(
              "UPDATE saved_cards SET card_number = NULL "
              "WHERE card_number LIKE '****%'",
            );
          }
          // v4：卡片档案新增行程记录快照（JSON）：卡片详情页在读取其他
          // 卡片后继续展示该卡最近一次读取的行程记录；已安装用户升级时
          // 追加列，既有档案不丢失。
          if (from < 4) {
            await m.addColumn(savedCards, savedCards.sessionDataJson);
          }
        },
      );

  static QueryExecutor _openConnection() =>
      driftDatabase(name: 'transit_card_analyzer');
}