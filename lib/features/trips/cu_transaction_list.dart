import 'package:flutter/material.dart';

import '../../protocols/transit/city_union/city_union_models.dart';

import '../transit_analysis/cu_transaction_analysis.dart';

class CuTransactionList extends StatelessWidget {
  const CuTransactionList({
    super.key,
    required this.transactions,
    this.sourceLabels = const {},
  });
  final List<CuTransactionView> transactions;
  final Map<CuTransactionView, String> sourceLabels;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Text(
          '城市一卡通 · ${transactions.length} 条记录',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      for (final transaction in transactions)
        Card(
          child: ExpansionTile(
            title: Text(
              '${transaction.kindLabel} · ${transaction.locationLabel}',
            ),
            subtitle: Text(
              '${transaction.timeLabel}\n${transaction.sourceLabel} · 交易序号 ${transaction.record.sequence}',
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (sourceLabels[transaction] case final source?)
                Text('保存来源：$source'),
              Text('终端原始编码：${transaction.record.terminalHex ?? '未知'}'),
              if (transaction.regionCode != null)
                Text('受理地区代码：${transaction.regionCode}'),
              if (transaction.location.value?.lineCode != null)
                Text('线路原始编码：${transaction.location.value!.lineCode}'),
              if (transaction.location.value?.stationCode != null)
                Text('站点原始编码：${transaction.location.value!.stationCode}'),
              Text(
                '交易类型：0x${transaction.record.transactionType.toRadixString(16).toUpperCase().padLeft(2, '0')} · ${transaction.record.transactionTypeName}',
              ),
              Text('金额原始值：${transaction.record.amountRaw}（单位未确认）'),
              if (transaction.location.issue != null)
                Text(transaction.location.issue!),
              for (final error in transaction.record.errors) Text(error),
              const SizedBox(height: 8),
              SelectableText(
                transaction.record.rawHex,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
    ],
  );
}
