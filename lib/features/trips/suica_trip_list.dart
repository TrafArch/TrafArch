import 'package:flutter/material.dart';

import 'suica_trip_presenter.dart';
import 'trip_cards_view.dart';

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
  Widget build(BuildContext context) => TripCardsView(
    entries: [for (final trip in trips) trip.entry],
    projectedJourneys: [for (final trip in trips) trip.journey],
    sourceLabels: const {SuicaTripSource.history: 'Suica 历史'},
    summaryText: 'Suica · ${trips.length} 条记录',
    initialFilters: initialFilters,
    onFiltersChanged: onFiltersChanged,
  );
}
