import 'package:flutter/material.dart';

import '../transit_analysis/cu_transaction_analysis.dart';
import 'cu_trip_presenter.dart';
import 'shanghai_mirrored_records.dart';
import 'trip_cards_view.dart';

/// Keeps mirrored application records reachable below the primary journey list.
class CuApplicationRecords extends StatelessWidget {
  const CuApplicationRecords({
    super.key,
    required this.records,
    this.sourceLabels = const {},
    this.cityNameOf,
    this.isRemote,
    this.initialFilters,
    this.onFiltersChanged,
    this.currencySymbol = '¥',
  });

  final ShanghaiMirroredRecords records;
  final Map<CuTransactionView, String> sourceLabels;
  final String? Function(String?)? cityNameOf;
  final bool Function(CuTransactionView)? isRemote;
  final List<String>? initialFilters;
  final ValueChanged<List<String>>? onFiltersChanged;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (records.independent.isNotEmpty)
        CuTransactionList(
          transactions: records.independent,
          sourceLabels: sourceLabels,
          cityNameOf: cityNameOf,
          isRemote: isRemote,
          initialFilters: initialFilters,
          onFiltersChanged: onFiltersChanged,
          currencySymbol: currencySymbol,
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
                cityNameOf: cityNameOf,
                isRemote: isRemote,
                currencySymbol: currencySymbol,
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
    this.cityNameOf,
    this.isRemote,
    this.initialFilters,
    this.onFiltersChanged,
    this.currencySymbol = '¥',
  });
  final List<CuTransactionView> transactions;
  final Map<CuTransactionView, String> sourceLabels;
  final bool showHeader;
  final String? Function(String?)? cityNameOf;
  final bool Function(CuTransactionView)? isRemote;
  final List<String>? initialFilters;
  final ValueChanged<List<String>>? onFiltersChanged;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final entries = [
      for (final transaction in transactions)
        describeCuTrip(
          transaction,
          cityName: cityNameOf?.call(transaction.regionCode),
          remote: isRemote?.call(transaction) ?? false,
          savedSource: sourceLabels[transaction],
          currencySymbol: currencySymbol,
        ),
    ];
    return TripCardsView(
      entries: entries,
      sourceLabels: cuTripSourceLabels,
      summaryText: showHeader
          ? '城市一卡通 · ${transactions.length} 条记录'
          : '交易 ${transactions.length} 笔',
      initialFilters: initialFilters,
      onFiltersChanged: onFiltersChanged,
    );
  }
}
