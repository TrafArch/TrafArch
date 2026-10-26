import 'app_database.dart';
import '../domain/card_session_snapshot.dart';

/// Legacy scalars have only a conservative capture-time bound. New captures
/// carry observations explicitly, including confirmed zero values.
Map<String, int> archiveObservationTimes(
  SavedCard card,
  List<CardReadBatch> batches, {
  required Map<String, int> retainedTimes,
}) {
  // Explicit persisted times and payload observations take precedence over
  // the legacy bound. A later partial capture changes lastReadAt without
  // observing retained fields, so it cannot advance their fallback times.
  final result = Map<String, int>.of(retainedTimes);
  void add(String? payload, int at) {
    if (payload == null) return;
    final values = CardSessionSnapshot.decodeResult(payload)
        .snapshot
        ?.extensions['observations'];
    if (values is! Map) return;
    for (final entry in values.entries) {
      if (entry.value != null && entry.key is String) {
        final key = entry.key as String;
        if (at > (result[key] ?? -8640000000000000)) result[key] = at;
      }
    }
  }

  for (final batch in batches) {
    add(batch.payloadJson, batch.readAt);
  }
  final latestAt = card.lastReadAt ?? card.updatedAt;
  add(card.sessionDataJson, latestAt);
  final retained = <String, Object?>{
    'cardNumber': card.cardNumber,
    'balanceFen': card.balanceFen,
    'transactionCount': card.transactionCount,
    'officialName': card.officialName,
    'issuerName': card.issuerName,
    'cityName': card.cityName,
    'identity': card.identificationSource,
  };
  for (final entry in retained.entries) {
    if (entry.value != null) result.putIfAbsent(entry.key, () => latestAt);
  }
  return result;
}
