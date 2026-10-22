import 'card_archive_identity.dart';
import 'card_types.dart';

/// 待用户确认保存的卡片档案（读取解析成功后的会话态）。
///
/// 首页「是否保存卡片」确认对话框展示其中的名称与卡号；用户确认后由
/// AppDependencies 经 CardRepository 写入数据库（指纹去重，重复读取更新快照但
/// 不覆盖自定义名称），放弃时直接丢弃。
class PendingCardSave {
  /// Runtime assigns a UUID/attempt ID. Empty is legacy fixture compatibility
  /// only; the parent controller confirms/cancels the exact captured ID.
  final String pendingSaveId;

  /// Time captured with the completed read, not the later confirmation dialog.
  final DateTime? readAt;

  /// 稳定的本地卡片指纹（CardFingerprint 构建规则）。
  final String fingerprint;

  /// 识别结果（卡型 / 正式名称 / 发行方 / 城市 / 依据）。
  final CardArchiveIdentity identity;

  /// 卡号（完整，不脱敏；入库与对话框展示共用）；未读到时为 null。
  final String? cardNumber;

  /// 本次读取的余额快照（分）；未读到余额时为 null。
  final int? balanceFen;

  /// 余额货币代码（ISO 4217）；未读到余额时为 null。
  final String? currencyCode;

  /// 本次读取解析到的交易记录条数。
  final int? transactionCount;

  /// 本次读取的行程记录快照（JSON 编码的 CardSessionSnapshot：
  /// 交易行程 / 0x1A 记录 / 读取时卡片城市代码）；无记录数据时为 null
  /// （保存时不写入 / 不覆盖既有快照）。
  final String? sessionDataJson;

  const PendingCardSave({
    this.pendingSaveId = '',
    this.readAt,
    required this.fingerprint,
    required this.identity,
    this.cardNumber,
    this.balanceFen,
    this.currencyCode,
    this.transactionCount,
    this.sessionDataJson,
  });

  /// 展示名称：正式卡名优先，未识别时回退卡型通用名称（不猜测）。
  String get displayName =>
      identity.officialName ?? cardTypeLabel(identity.cardType);

  /// 对话框卡号文本：完整卡号；未读取到时为兜底文案。
  String get cardNumberText => cardNumber ?? '未读取到卡号';
}
