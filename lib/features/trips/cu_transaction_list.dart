import 'package:flutter/material.dart';

import '../../protocols/transit/city_union/city_union_models.dart';

import '../transit_analysis/cu_transaction_analysis.dart';
import 'shanghai_mirrored_records.dart';

/// Keeps mirrored application records reachable below the primary journey list.
class CuApplicationRecords extends StatelessWidget {
  const CuApplicationRecords({
    super.key,
    required this.records,
    this.sourceLabels = const {},
  });

  final ShanghaiMirroredRecords records;
  final Map<CuTransactionView, String> sourceLabels;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (records.independent.isNotEmpty)
        CuTransactionList(
          transactions: records.independent,
          sourceLabels: sourceLabels,
        ),
      if (records.mirrored.isNotEmpty)
        Card(
          child: ExpansionTile(
            title: Text('城市一卡通应用记录 · ${records.mirroredCount} 条'),
            subtitle: const Text('与交通联合交易一致，展开查看原始应用记录'),
            childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            children: [
              CuTransactionList(
                transactions: records.mirrored,
                sourceLabels: sourceLabels,
                showHeader: false,
              ),
            ],
          ),
        ),
    ],
  );
}

class CuTransactionList extends StatelessWidget {
  const CuTransactionList({
    super.key,
    required this.transactions,
    this.sourceLabels = const {},
    this.showHeader = true,
  });
  final List<CuTransactionView> transactions;
  final Map<CuTransactionView, String> sourceLabels;
  final bool showHeader;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (showHeader)
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
