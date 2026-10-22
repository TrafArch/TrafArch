import 'package:drift/drift.dart';

/// 卡片档案表：一张卡的识别结果与用户自定义名称分离存储。
///
/// - 识别结果（officialName / issuerName / cityName / …）随每次读取与
///   识别规则升级更新；
/// - [customName] 为用户自定义名称，识别结果更新绝不覆盖
///   （见 CardRepository.saveIdentity）；
/// - [cardFingerprint] 为稳定的本地卡片指纹（构建规则见 CardFingerprint），
///   不使用 NFC UID（UID 稳定性不可假定，也不作为公开标识展示）。
class SavedCards extends Table {
  /// App 内部卡片 ID（uuid v4）。
  TextColumn get id => text()();

  /// 稳定的本地卡片指纹（唯一，关联同一张卡的历次读取）。
  TextColumn get cardFingerprint => text().unique()();

  /// 卡型（CardTypes 常量：china_tunion / city_union / octopus_tunion / …）。
  TextColumn get cardType => text()();

  /// 自动识别的正式卡名（如「福路通」）；无可靠证据时为 NULL。
  TextColumn get officialName => text().nullable()();

  /// 用户自定义名称；为空时展示层回退正式卡名。
  TextColumn get customName => text().nullable()();

  /// 发卡机构或运营方。
  TextColumn get issuerName => text().nullable()();

  /// 已确认的城市或地区。
  TextColumn get cityName => text().nullable()();

  /// 名称的识别依据（CardIdentificationSources 常量）。
  TextColumn get identificationSource =>
      text().withDefault(const Constant('unknown'))();

  /// 识别置信度（仅有明确规则依据时记录）。
  RealColumn get identificationConfidence => real().nullable()();

  /// 卡号（完整存储，不做脱敏）：交通联合为逻辑卡号（应用序列号去前导 0），
  /// 城市一卡通为 0x15 公共应用基本信息的应用序列号；未读到卡号时为 NULL。
  TextColumn get cardNumber => text().nullable()();

  /// 旧版兼容列：保留原脱敏值；v6 按实际表结构补齐，不据此生成完整卡号。
  TextColumn get cardNumberMasked => text().nullable()();

  /// 最近已观察到的余额（分）；部分读取保留旧值，本次缺失在批次中标记。
  IntColumn get balanceFen => integer().nullable()();

  /// 与已观察余额对应的货币代码（如 CNY / HKD）；NULL 显示币种未知。
  TextColumn get currencyCode => text().nullable()();

  /// 最近一次读取解析到的交易记录条数；未解析到交易文件时为 NULL。
  IntColumn get transactionCount => integer().nullable()();

  /// 最近一次保存到档案的行程记录快照（JSON：CardSessionSnapshot——
  /// 交易行程 / 0x1A 进出站与上下车记录 / 读取时卡片城市代码）；
  /// v6 写入本次观察（含缺失状态）；历史快照在替换前转存读取批次。
  TextColumn get sessionDataJson => text().nullable()();

  /// 卡面图片路径（用户提供的图片 / 已验证的本地卡面资源）；
  /// 未匹配时为空，展示层使用统一占位图（不猜测卡面）。
  TextColumn get cardImagePath => text().nullable()();

  /// 最近一次读取时间（毫秒时间戳）。
  IntColumn get lastReadAt => integer().nullable()();

  /// 创建时间（毫秒时间戳）。
  IntColumn get createdAt => integer()();

  /// 更新时间（毫秒时间戳）。
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
