import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/transit_analysis/balance_reconstruction.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

TUnionTransaction _txn({
  required int sequence,
  required DateTime time,
  required int amountFen,
  int rawType = 0x06,
  int? recordNumber,
}) => TUnionTransaction(
  recordNumber: recordNumber,
  sequence: sequence,
  overdraftLimitFen: 0,
  amountFen: amountFen,
  rawType: rawType,
  terminalId: '0000000000000001',
  time: time,
);

void main() {
  final day1 = DateTime(2024, 5, 1, 8);
  final day2 = DateTime(2024, 5, 2, 8);
  final earlier = DateTime(2024, 5, 1, 7);

  test('缺口后的记录余额重新锚定，仅沿后续连续槽位倒推', () {
    final balances = reconstructTransactionBalances(
      [
        _txn(sequence: 5, time: day2, amountFen: 100, recordNumber: 2),
        _txn(sequence: 3, time: day1, amountFen: 300, recordNumber: 4),
        _txn(sequence: 2, time: earlier, amountFen: 100, recordNumber: 5),
      ],
      openingBalanceFen: 10000,
      recordedBalanceFen: (t) => t.recordNumber == 4 ? 5000 : null,
    );
    expect(balances.map((b) => b?.fen), [null, 5000, 5300]);
  });

  test('混合旧构造与原始槽位不能证明连续', () {
    final balances = reconstructTransactionBalances([
      _txn(sequence: 2, time: day2, amountFen: 100, recordNumber: 1),
      _txn(sequence: 1, time: day1, amountFen: 100),
    ], openingBalanceFen: 10000);
    expect(balances.map((b) => b?.fen), [10000, null]);
  });

  test('充值不强制共用消费计数器，序号不要求相邻减一', () {
    final balances = reconstructTransactionBalances([
      _txn(sequence: 2, time: day2, amountFen: 1000, rawType: 0x02),
      _txn(sequence: 20, time: day1, amountFen: 300),
      _txn(sequence: 18, time: earlier, amountFen: 100),
    ], openingBalanceFen: 10000);
    expect(balances.map((b) => b?.fen), [10000, 9000, 9300]);
  });

  test('无 0x1E：按当前钱包余额由新到旧倒推', () {
    final balances = reconstructTransactionBalances([
      _txn(sequence: 3, time: day2, amountFen: 300),
      _txn(sequence: 2, time: day1, amountFen: 4660),
      _txn(sequence: 1, time: earlier, amountFen: 0),
    ], openingBalanceFen: 10000);
    // 最新消费 3.00 元后余额 100.00 元；该笔之前为 103.00 元，
    // 再之前（消费 46.60 元之前）为 149.60 元。
    expect([for (final b in balances) b?.fen], [10000, 10300, 14960]);
    expect([for (final b in balances) b?.isRecorded], [false, false, false]);
  });

  test('充值增加余额、消费扣减余额', () {
    final balances = reconstructTransactionBalances([
      _txn(sequence: 2, time: day2, amountFen: 1000, rawType: 0x02),
      _txn(sequence: 1, time: day1, amountFen: 300),
    ], openingBalanceFen: 10000);
    expect([for (final b in balances) b?.fen], [10000, 9000]);
  });

  test('0x1E 记录余额优先，并作为更旧记录的推算锚点', () {
    final balances = reconstructTransactionBalances(
      [
        _txn(sequence: 3, time: day2, amountFen: 500),
        _txn(sequence: 2, time: day1, amountFen: 300),
        _txn(sequence: 1, time: earlier, amountFen: 100),
      ],
      openingBalanceFen: null,
      recordedBalanceFen: (txn) => txn.sequence == 2 ? 5000 : null,
    );
    expect(balances[0], isNull);
    expect(balances[1]?.fen, 5000);
    expect(balances[1]?.isRecorded, isTrue);
    // 记录余额为消费 3.00 元之后；更旧一笔消费 1.00 元之后为 53.00 元。
    expect(balances[2]?.fen, 5300);
    expect(balances[2]?.isRecorded, isFalse);
  });

  test('最新交易类型未知：给出最新余额，但不继续向更旧记录推算', () {
    final balances = reconstructTransactionBalances([
      _txn(sequence: 2, time: day2, amountFen: 200, rawType: 0x07),
      _txn(sequence: 1, time: day1, amountFen: 300),
    ], openingBalanceFen: 10000);
    expect(balances[0]?.fen, 10000);
    expect(balances[0]?.isRecorded, isFalse);
    expect(balances[1], isNull);
  });

  test('中间交易类型未知：已记录余额仍可重新锚定', () {
    final balances = reconstructTransactionBalances(
      [
        _txn(sequence: 3, time: day2, amountFen: 200, rawType: 0x07),
        _txn(sequence: 2, time: day1, amountFen: 300),
        _txn(sequence: 1, time: earlier, amountFen: 100),
      ],
      openingBalanceFen: 10000,
      recordedBalanceFen: (txn) => txn.sequence == 2 ? 5000 : null,
    );
    expect(balances[0]?.fen, 10000);
    expect(balances[1]?.fen, 5000);
    expect(balances[2]?.fen, 5300);
  });

  test('未读到钱包余额且无记录余额：保持未知', () {
    final balances = reconstructTransactionBalances([
      _txn(sequence: 1, time: day1, amountFen: 300),
    ], openingBalanceFen: null);
    expect(balances.single, isNull);
  });

  test('账本时间倒序被破坏：从该条起停止推算', () {
    final balances = reconstructTransactionBalances([
      _txn(sequence: 2, time: day1, amountFen: 300),
      _txn(sequence: 1, time: day2, amountFen: 100),
    ], openingBalanceFen: 10000);
    expect(balances[0]?.fen, 10000);
    expect(balances[1], isNull);
  });

  test('相邻记录时间与序号均相同：顺序不可判定，停止推算', () {
    final balances = reconstructTransactionBalances([
      _txn(sequence: 1, time: day1, amountFen: 300),
      _txn(sequence: 1, time: day1, amountFen: 100),
      _txn(sequence: 0, time: day1, amountFen: 50),
    ], openingBalanceFen: 10000);
    expect(balances[0]?.fen, 10000);
    expect(balances[1], isNull);
    expect(balances[2], isNull);
  });

  test('同一时刻序号不同：序号证明先后，可继续推算', () {
    final balances = reconstructTransactionBalances([
      _txn(sequence: 2, time: day1, amountFen: 300),
      _txn(sequence: 1, time: day1, amountFen: 100),
    ], openingBalanceFen: 10000);
    expect([for (final b in balances) b?.fen], [10000, 10300]);
  });
}
