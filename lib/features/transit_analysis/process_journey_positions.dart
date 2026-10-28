import '../../protocols/transit/tunion/tunion_models.dart';

/// Source slots for independent 0x1E events; complete raw records are required.
Map<TUnionTripRecord, Map<String, int>> buildProcessJourneyPositions(
  Iterable<TUnionProcessRecord> records, {
  String sourceId = 'live',
}) {
  if (sourceId.trim().isEmpty) return const {};
  final cycles = records.where((record) => record.sfi == 0x1E).toList();
  final slots = <int, int>{};
  final objects = <TUnionTripRecord, int>{};
  final bytes = <String, int>{};
  for (final record in cycles) {
    slots[record.recordNumber] = (slots[record.recordNumber] ?? 0) + 1;
    if (record.trip case final trip?) objects[trip] = (objects[trip] ?? 0) + 1;
    final raw = record.rawHex;
    bytes[raw] = (bytes[raw] ?? 0) + 1;
  }
  return Map.unmodifiable({
    for (final record in cycles)
      if (record.trip != null &&
          record.recordNumber > 0 &&
          record.recordNumberIsReliable &&
          !record.isBlank &&
          record.raw.isNotEmpty &&
          slots[record.recordNumber] == 1 &&
          objects[record.trip] == 1 &&
          bytes[record.rawHex] == 1)
        record.trip!: Map<String, int>.unmodifiable({
          sourceId: record.recordNumber,
        }),
  });
}
