import '../../protocols/transit/tunion/tunion_models.dart';

/// 交易后余额证据：金额（分）与来源（0x1E 记录 / 倒推）。
class TransactionBalance {
  final int fen;

  /// true 表示来自 0x1E 过程记录（记录余额）；false 表示按后续交易
  /// 余额与交易金额倒推得出。
  final bool isRecorded;

  const TransactionBalance(this.fen, {required this.isRecorded});
}

/// 按"记录余额优先、缺失处倒推"重建每条交易发生后的钱包余额。
///
/// [transactions] 必须保持卡内 0x18 文件的账本顺序（最新 → 最旧）；
/// [openingBalanceFen] 为当前钱包余额（最新交易之后的余额）。
/// [recordedBalanceFen] 返回与交易唯一配对的 0x1E 记录余额，未配对返回 null。
///
/// 倒推口径（与读卡识途一致）：消费扣减、充值增加，沿"较新 → 较旧"方向
/// 逐条减去本笔交易的有符号金额。只有可证明连续的记录才给出余额：
/// - 当前钱包余额即最新交易之后的余额；交易类型未知时仍可给出最新一条，
///   但无法继续向更旧记录推算；
/// - 仅原始 record 1（或旧调用者明确声明的完整列表）绑定钱包；
/// - 槽位缺口、混合槽位证据、时间倒序被破坏、重复序号或消费序号反向时
///   停止推算，返回 null；
/// - 已记录的 0x1E 余额始终采用并作为新的推算锚点，不因推算中断而丢弃；
/// - 未读取到钱包余额且无记录余额时保持 null（不猜测）。
List<TransactionBalance?> reconstructTransactionBalances(
  List<TUnionTransaction> transactions, {
  required int? openingBalanceFen,
  int? Function(TUnionTransaction transaction)? recordedBalanceFen,
}) {
  final result = List<TransactionBalance?>.filled(transactions.length, null);
  // 无槽位号兼容旧调用者的“从最新起、无遗漏”声明；读取器不使用此默认。
  int? running =
      transactions.isNotEmpty &&
          (transactions.first.recordNumber == null ||
              transactions.first.recordNumber == 1)
      ? openingBalanceFen
      : null;
  for (var i = 0; i < transactions.length; i++) {
    final transaction = transactions[i];
    if (i > 0 && !_followsInLedger(transactions[i - 1], transaction)) {
      running = null;
    }
    final recorded = recordedBalanceFen?.call(transaction);
    final delta = _signedDeltaFen(transaction);
    final balance = recorded != null
        ? TransactionBalance(recorded, isRecorded: true)
        : (running != null
              ? TransactionBalance(running, isRecorded: false)
              : null);
    result[i] = balance;
    running = balance != null && delta != null ? balance.fen - delta : null;
  }
  return result;
}

/// 原始槽位须相邻；时间逆序、重复序号均不能作为连续性证据。
/// 消费计数器只对两笔消费检查方向，不强求差 1（充值计数语义未确认）。
/// 回绕规则未被现有代码/样本证实，遇到升序保守中断，而非猜测回绕。
bool _followsInLedger(TUnionTransaction newer, TUnionTransaction older) {
  final newerSlot = newer.recordNumber;
  final olderSlot = older.recordNumber;
  if (newerSlot != null || olderSlot != null) {
    if (newerSlot == null || olderSlot != newerSlot + 1) return false;
  }
  if (newer.time.isBefore(older.time)) return false;
  if (newer.sequence == older.sequence) return false;
  if (newer.isConsume && older.isConsume && newer.sequence < older.sequence) {
    return false;
  }
  return true;
}

/// 交易对余额的有符号影响（分）：充值增加，消费（含复合消费）扣减，
/// 其他类型未知（不猜测）。
int? _signedDeltaFen(TUnionTransaction transaction) {
  if (transaction.isRecharge) return transaction.amountFen;
  if (transaction.isConsume) return -transaction.amountFen;
  return null;
}
