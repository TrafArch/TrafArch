import 'package:drift/drift.dart';

/// 卡片读取批次表：一次"读取 + 保存"累积一行原始记录快照，历史不覆盖。
///
/// - [payloadJson] 为 CardSessionSnapshot v1/v2/v3 的 JSON（原始 HEX + 解析版本
///   + 0x1E 关联证据），详情和导出使用 ArchiveHistory 的同一投影；
/// - [parseVersion] 为该批次的解析口径版本（kTripParseVersion），解析器
///   升级后据此识别旧批次并支持按批次重新解析；
/// - 去重规则：同卡且 payload 内容完全一致（同一内容重复读取）时不重复
///   入库，由 CardRepository.saveIdentity 保证。
@DataClassName('CardReadBatch')
class CardReadBatches extends Table {
  /// 新捕获为 uuid v4；旧标量回填使用 `legacy-scalar-v6:<timeSource>:<random>`。
  TextColumn get id => text()();

  /// 所属卡片档案 ID（SavedCards.id）。
  TextColumn get cardId => text()();

  /// 卡片指纹（冗余存储，跨档案迁移与内容去重查询用）。
  TextColumn get cardFingerprint => text()();

  /// 读取时刻（毫秒时间戳）。
  IntColumn get readAt => integer()();

  /// 产出该批次的解析口径版本。
  IntColumn get parseVersion => integer().withDefault(const Constant(1))();

  /// 原始记录快照 JSON（CardSessionSnapshot v1/v2/v3）。
  TextColumn get payloadJson => text()();

  @override
  Set<Column> get primaryKey => {id};
}
