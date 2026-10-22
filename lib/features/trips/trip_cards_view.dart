import 'package:flutter/material.dart';

import 'trip_entry_card.dart';
import 'trip_entry_details.dart';
import 'trip_entry_presenter.dart';
import 'trip_filters.dart';

/// A display projection: callers own record identity, context and statistics.
/// Both saved history and live trips use the same filters, cards and sheet.
class TripCardPresentation<S extends Enum> {
  const TripCardPresentation({
    required this.info,
    required this.source,
    required this.mode,
    required this.dateText,
    required this.remote,
    this.onDiagnostics,
  });

  final TripEntryInfo info;
  final S source;
  final TripModeFilter mode;
  final String dateText;
  final bool remote;
  final VoidCallback? onDiagnostics;
}

class TripCardsView<S extends Enum> extends StatefulWidget {
  const TripCardsView({
    super.key,
    required this.entries,
    required this.sourceLabels,
    required this.summaryText,
  });

  final List<TripCardPresentation<S>> entries;
  final Map<S, String> sourceLabels;
  final String summaryText;

  @override
  State<TripCardsView<S>> createState() => _TripCardsViewState<S>();
}

class _TripCardsViewState<S extends Enum> extends State<TripCardsView<S>> {
  final _sources = <S>{};
  final _modes = <TripModeFilter>{};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = <String, List<TripCardPresentation<S>>>{};
    for (final entry in widget.entries) {
      if ((_sources.isEmpty || _sources.contains(entry.source)) &&
          (_modes.isEmpty || _modes.contains(entry.mode))) {
        groups.putIfAbsent(entry.dateText, () => []).add(entry);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.summaryText,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        TripFilterChips(
          allLabel: '全部来源',
          labels: widget.sourceLabels,
          selected: _sources,
          onChanged: (next) => setState(() {
            _sources
              ..clear()
              ..addAll(next);
          }),
        ),
        const SizedBox(height: 6),
        TripFilterChips(
          allLabel: '全部方式',
          labels: tripModeLabels,
          selected: _modes,
          onChanged: (next) => setState(() {
            _modes
              ..clear()
              ..addAll(next);
          }),
        ),
        const SizedBox(height: 10),
        if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              widget.entries.isEmpty ? '暂无记录' : '当前筛选条件下没有记录',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        for (final group in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Text(
              '${group.key} · ${group.value.length} 条',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final entry in group.value)
            TripEntryCard(
              info: entry.info,
              remote: entry.remote,
              onTap: () => showTripEntryDetails(
                context,
                entry.info,
                onDiagnostics: entry.onDiagnostics,
              ),
            ),
        ],
      ],
    );
  }
}
