import 'package:flutter/material.dart';

import '../application/archive_history.dart';

class LocalCardHistoryRecords extends StatelessWidget {
  const LocalCardHistoryRecords({super.key, required this.records});

  final List<LocalCardHistoryRecord> records;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          '本地卡交易记录 · ${records.length} 条',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        for (final (index, record) in records.indexed)
          Card(
            child: ListTile(
              title: Text(_title(record, index)),
              subtitle: Text(_details(record)),
              isThreeLine: true,
            ),
          ),
      ],
    );
  }

  String _title(LocalCardHistoryRecord record, int index) {
    final f = record.fields;
    if (record.cardType == 'lingnanTong') {
      final type = switch (f['subtype']) {
        0x02 => '充值',
        0x06 => '消费',
        0x09 => '复合消费',
        final int value =>
          '交易类型 0x${value.toRadixString(16).padLeft(2, '0').toUpperCase()}',
        _ => '交易记录',
      };
      return '$type · 序号 ${_sequence(f) ?? index + 1}';
    }
    return '澳门通交易 · 序号 ${f['recordNumber'] ?? index + 1}';
  }

  String _details(LocalCardHistoryRecord record) {
    final f = record.fields;
    final parts = <String>[];
    final timestamp = f['timestamp'];
    if (timestamp is int && timestamp != 0) {
      final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
      String pad(int value) => value.toString().padLeft(2, '0');
      parts.add(
        '${date.year}-${pad(date.month)}-${pad(date.day)} '
        '${pad(date.hour)}:${pad(date.minute)}'
        '${record.cardType == 'lingnanTong' ? '（年份推断，秒未知）' : ''}',
      );
    }
    if (record.cardType == 'lingnanTong') {
      final amount = f['amountDelta'];
      if (amount is int) {
        final sign = amount > 0
            ? '+'
            : amount < 0
            ? '-'
            : '';
        parts.add('金额变化 $sign¥${(amount.abs() / 100).toStringAsFixed(2)}');
      }
      if (f['terminalHex'] case final String terminal
          when terminal.isNotEmpty) {
        parts.add('终端 $terminal');
      }
    } else {
      parts.add('金额和地点未解析');
    }
    return parts.isEmpty ? '时间未解析；原始记录已保留' : parts.join(' · ');
  }

  int? _sequence(Map<String, dynamic> fields) {
    final raw = fields['rawBody'];
    if (raw is! List || raw.length < 2 || raw[0] is! int || raw[1] is! int) {
      return null;
    }
    return ((raw[0] as int) << 8) | (raw[1] as int);
  }
}
