import 'package:flutter/material.dart';

import 'expert_widgets.dart';

class ExpertTransactionRecord {
  const ExpertTransactionRecord({
    required this.time,
    required this.amount,
    required this.type,
    required this.sequence,
    required this.terminal,
    this.extraFields = const [],
    this.rawHex,
  });

  final String time;
  final String amount;
  final String type;
  final String sequence;
  final String terminal;
  final List<(String, String)> extraFields;
  final String? rawHex;
}

class TransactionRecordsPanel extends StatelessWidget {
  const TransactionRecordsPanel({
    super.key,
    required this.storageKey,
    required this.records,
  });

  final String storageKey;
  final List<ExpertTransactionRecord> records;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    key: PageStorageKey<String>(storageKey),
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(bottom: 8),
    shape: const Border(),
    collapsedShape: const Border(),
    title: const Text('交易明细记录'),
    subtitle: Text(records.isEmpty ? '未读取到交易记录' : '${records.length} 条'),
    children: [
      for (final (index, record) in records.indexed)
        ExpansionTile(
          key: PageStorageKey<String>('$storageKey-$index'),
          tilePadding: EdgeInsets.zero,
          shape: const Border(),
          collapsedShape: const Border(),
          title: Text('交易记录 ${index + 1}'),
          subtitle: Text(record.time),
          children: [
            ExpertField('交易日期时间', record.time),
            ExpertField('交易金额', record.amount),
            ExpertField('交易类型', record.type),
            ExpertField('交易序号', record.sequence),
            ExpertField('终端编号', record.terminal),
            for (final field in record.extraFields)
              ExpertField(field.$1, field.$2),
            if (record.rawHex case final raw?) ExpertHex(raw),
          ],
        ),
    ],
  );
}
