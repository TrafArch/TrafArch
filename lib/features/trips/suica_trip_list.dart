import 'package:flutter/material.dart';

import 'suica_trip_presenter.dart';
import 'trip_cards_view.dart';
import 'trip_filters.dart';

/// Live and recovered Suica records share the exact same frozen projection.
class SuicaTripList extends StatelessWidget {
  const SuicaTripList({
    super.key,
    required this.trips,
    this.initialFilters,
    this.onFiltersChanged,
  });

  final List<SuicaTripPresentation> trips;
  final List<String>? initialFilters;
  final ValueChanged<List<String>>? onFiltersChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (trips.any((trip) => trip.entry.mode == TripModeFilter.rail))
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '本次读取的乘车履历仅含日期，不含进出站时刻。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      TripCardsView(
        entries: [for (final trip in trips) trip.entry],
        projectedJourneys: [for (final trip in trips) trip.journey],
        sourceLabels: const {SuicaTripSource.history: 'Suica 历史'},
        summaryText: 'Suica · ${trips.length} 条记录',
        initialFilters: initialFilters,
        onFiltersChanged: onFiltersChanged,
      ),
    ],
  );
}
