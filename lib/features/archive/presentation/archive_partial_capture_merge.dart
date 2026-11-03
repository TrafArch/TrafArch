import '../../trips/journey_presentation.dart';
import '../../trips/trip_cards_view.dart';
import '../../trips/trip_filters.dart';
import '../application/archive_history.dart';

typedef _Entry = TripCardPresentation<ArchiveRecordKind>;
typedef _Journey = JourneyPresentation<_Entry>;
typedef _Event = JourneyEvent<_Entry>;

/// Captured transaction facts, excluding display/classification annotations.
class ArchiveTransactionObservation {
  const ArchiveTransactionObservation({
    required this.occurrenceIdentity,
    required this.identity,
    required this.balanceFen,
    required this.balanceIsRecorded,
  });

  final String occurrenceIdentity;
  final String identity;
  final int? balanceFen;
  final bool balanceIsRecorded;
}

/// Attach repeated evidence to an already completed capture, never pair sides.
/// Original captures remain the authority for multiplicity and conflicts, even
/// when an earlier presentation merge has already combined their events.
List<JourneyPresentation<TripCardPresentation<ArchiveRecordKind>>>
attachArchivePartialCaptures(
  List<JourneyPresentation<TripCardPresentation<ArchiveRecordKind>>> journeys, {
  required List<JourneyPresentation<TripCardPresentation<ArchiveRecordKind>>>
  originalCaptures,
  required Map<
    TripCardPresentation<ArchiveRecordKind>,
    ArchiveTransactionObservation
  >
  observations,
}) {
  ArchiveTransactionObservation? observation(_Event event) =>
      event.payload.source == ArchiveRecordKind.transaction
      ? observations[event.payload]
      : null;

  final occurrences = <String, List<_Event>>{};
  final counts = <(String, String), int>{};
  for (final capture in originalCaptures) {
    for (final event in capture.events) {
      final witness = observation(event);
      if (witness == null) continue;
      occurrences.putIfAbsent(witness.occurrenceIdentity, () => []).add(event);
      for (final batch in event.sourceIds) {
        final key = (witness.occurrenceIdentity, batch);
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }
  }

  bool consistent(List<_Event> events) {
    final witnesses = [for (final event in events) observation(event)!];
    if (witnesses.map((w) => w.identity).toSet().length != 1) return false;
    final balances = {
      for (final witness in witnesses)
        if (witness.balanceFen != null)
          (witness.balanceFen, witness.balanceIsRecorded),
    };
    if (balances.length > 1) return false;
    bool unique<V>(V? Function(_Event) field) =>
        events.map(field).whereType<V>().toSet().length <= 1;
    return unique<String>((e) => e.scopeKey) &&
        unique<DateTime>((e) => e.endpoint.time) &&
        events
                .map((e) => e.endpoint.time?.isUtc)
                .whereType<bool>()
                .toSet()
                .length <=
            1 &&
        unique<String>((e) => e.cityCode) &&
        unique<int>((e) => e.sequence) &&
        unique<int>((e) => e.railAppTypeCode) &&
        unique<String>((e) => e.amountText) &&
        unique<String>((e) => e.balanceAfterText) &&
        unique<int>((e) => e.confirmedBalanceFen) &&
        unique<String>((e) => e.seatLabel) &&
        events
                .where((e) => e.mode != TripModeFilter.other)
                .map((e) => e.mode)
                .toSet()
                .length <=
            1 &&
        events
                .where((e) => e.role != JourneyEventRole.unknown)
                .map((e) => e.role)
                .toSet()
                .length <=
            1;
  }

  final safe = <String>{};
  for (final occurrence in occurrences.entries) {
    if (occurrence.value.every(
          (event) =>
              event.sourceIds.isNotEmpty &&
              event.sourceIds.every(
                (batch) =>
                    batch.trim().isNotEmpty &&
                    counts[(occurrence.key, batch)] == 1,
              ),
        ) &&
        consistent(occurrence.value)) {
      safe.add(occurrence.key);
    }
  }

  Set<String> batches(_Journey journey) => {
    for (final event in journey.events) ...event.sourceIds,
  };
  final completed = journeys
      .where((j) => j.state == JourneyState.completed)
      .toList();
  final proposals = <_Journey, List<_Journey>>{};
  for (final partial in journeys) {
    if (partial.state == JourneyState.completed || partial.events.isEmpty) {
      continue;
    }
    final ids = <String>[];
    for (final event in partial.events) {
      final witness = observation(event);
      if (witness == null) break;
      ids.add(witness.occurrenceIdentity);
    }
    if (ids.length != partial.events.length) continue;
    // Count structural choices before checking balances, batch overlap or
    // ambiguity. A conflicting candidate must not manufacture uniqueness.
    final candidates = completed.where((target) {
      final known = {
        for (final event in target.events)
          if (observation(event) case final witness?)
            witness.occurrenceIdentity,
      };
      return ids.every(known.contains);
    }).toList();
    if (candidates.length != 1 || !ids.every(safe.contains)) continue;
    final target = candidates.single;
    final targetBatches = batches(target);
    final partialBatches = batches(partial);
    if (partialBatches.isEmpty || partialBatches.any(targetBatches.contains)) {
      continue;
    }
    proposals.putIfAbsent(target, () => []).add(partial);
  }

  final absorbed = <_Journey>{};
  final replacements = <_Journey, _Journey>{};
  for (final proposal in proposals.entries) {
    final target = proposal.key;
    final additions = proposal.value;
    // Validate the complete proposal, not an order-dependent growing target.
    final byOccurrence = <String, List<_Event>>{};
    for (final journey in [target, ...additions]) {
      for (final event in journey.events) {
        final witness = observation(event);
        if (witness != null) {
          byOccurrence
              .putIfAbsent(witness.occurrenceIdentity, () => [])
              .add(event);
        }
      }
    }
    if (!byOccurrence.values.every(consistent)) continue;
    replacements[target] = JourneyPresentation(
      events: List.unmodifiable([
        ...target.events,
        for (final addition in additions) ...addition.events,
      ]),
      mode: target.mode,
      state: target.state,
      cityLabel: target.cityLabel,
      start: target.start,
      end: target.end,
      duration: target.duration,
      amountText: target.amountText,
      fareAdjustmentAmountText: target.fareAdjustmentAmountText,
      balanceAfterText: target.balanceAfterText,
      seatLabel: target.seatLabel,
    );
    absorbed.addAll(additions);
  }
  // The caller sorts this new list before freezing the public projection.
  return [
    for (final journey in journeys)
      if (!absorbed.contains(journey)) replacements[journey] ?? journey,
  ];
}
