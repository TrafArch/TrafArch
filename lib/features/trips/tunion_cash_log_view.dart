import 'package:flutter/material.dart';

import '../../protocols/transit/tunion/tunion_cash_log.dart';
import 'trip_entry_card.dart';
import 'trip_entry_details.dart';
import 'trip_entry_presenter.dart';

/// Cash log entries carry a transaction time and amount independently of trips.
class TUnionCashLogView extends StatelessWidget {
  const TUnionCashLogView({super.key, required this.log});

  final TUnionCashLog log;

  @override
  Widget build(BuildContext context) {
    final purchases = log.records.where((record) => record.isPurchase).toList()
      ..sort((a, b) => b.time!.compareTo(a.time!));
    if (purchases.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Text(
            '交通联合电子现金消费',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        for (final record in purchases) _buildEntry(context, record),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildEntry(BuildContext context, TUnionCashLogRecord record) {
    final time = record.time!
        .toIso8601String()
        .split('.')
        .first
        .replaceFirst('T', ' ');
    final amount = '-¥${(record.amountFen! / 100).toStringAsFixed(2)}';
    final info = TripEntryInfo(
      sourceLabel: '交通联合电子现金 · 0x0B',
      title: '消费',
      timeText: time,
      amountText: amount,
      isConsume: true,
      rawHex: record.rawHex,
      fields: [
        ('记录槽位', '${record.recordNumber}'),
        ('交易时间', time),
        ('交易金额', amount),
      ],
    );
    return TripEntryCard(
      info: info,
      remote: false,
      onTap: () => showTripEntryDetails(context, info),
    );
  }
}
