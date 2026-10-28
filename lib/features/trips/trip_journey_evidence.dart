import '../../protocols/transit/tunion/tunion_models.dart';
import '../../protocols/transit/tunion/tunion_trip_matcher.dart';
import '../transit_analysis/process_journey_positions.dart';
import '../transit_analysis/tunion_analysis_models.dart';
import '../transit_analysis/tunion_record_context.dart';
import 'journey_presentation.dart';
import 'trip_filters.dart';
import 'trip_journey_adapter.dart' show journeyApplicationIdentity;

typedef LiveJourneyEvidence = ({
  String? applicationRecordId,
  Map<String, int> processPositions,
});

/// Verify display links before they can contribute physical slots or an
/// application identity to journey pairing. POS-only annotations stay display
/// annotations. The raw stream, transaction ledger and saved JSON are untouched.
Map<TripEntry, LiveJourneyEvidence> buildLiveJourneyEvidence({
  required List<TripEntry> stream,
  required Iterable<TUnionProcessRecord> processRecords,
  required Iterable<TransitRecord> rails,
  required Iterable<BusTransitRecord> buses,
}) {
  final records = processRecords.toList();
  final positions = buildProcessJourneyPositions(records);
  final cycles = [
    for (final record in records)
      if (record.sfi == 0x1E && !record.isBlank && record.trip != null)
        record.trip!,
  ];
  final applications = [
    for (final rail in rails.toSet())
      for (final entry in [true, false])
        if (entry || rail.statusCode != 1)
          TunionApplicationSide(rail: rail, isEntry: entry),
    for (final bus in buses.toSet())
      for (final entry in [true, false])
        TunionApplicationSide(bus: bus, isEntry: entry),
  ];
  String identity(TunionApplicationSide side) => journeyApplicationIdentity(
    (side.rail ?? side.bus)!,
    side.rail != null ? 'rail' : 'bus',
  );
  final cycleApplications = <TUnionTripRecord, TunionApplicationSide>{};
  final cycleUseCounts = <TunionApplicationSide, int>{};
  for (final cycle in cycles) {
    final matches = applications
        .where(
          (side) => matchesTunionJourneySide(
            isEntry: side.isEntry,
            isRail: side.rail != null,
            time: side.time,
            cityCode: _applicationCity(side),
            terminalId: side.terminal,
            amountFen: _applicationAmount(side),
            cycle: cycle,
          ),
        )
        .toList();
    if (matches.length != 1) continue;
    cycleApplications[cycle] = matches.single;
    cycleUseCounts[matches.single] = (cycleUseCounts[matches.single] ?? 0) + 1;
  }
  cycleApplications.removeWhere((cycle, side) => cycleUseCounts[side] != 1);

  final transactionCycles = <TripEntry, TUnionTripRecord>{};
  final transactionApplications = <TripEntry, TunionApplicationSide>{};
  final transactionCycleCounts = <TUnionTripRecord, int>{};
  final transactionApplicationCounts = <TunionApplicationSide, int>{};
  for (final entry in stream) {
    if (entry case TransactionTripEntry(:final trip)) {
      final key =
          trip.displayProcessKey ??
          (trip.matchedProcessTrip == null
              ? null
              : cycleDisplayKey(trip.matchedProcessTrip!));
      final matches = cycles
          .where(
            (cycle) =>
                key != null &&
                key == cycleDisplayKey(cycle) &&
                _transactionMatchesCycle(trip, cycle),
          )
          .toList();
      if (matches.length == 1) {
        final cycle = matches.single;
        transactionCycles[entry] = cycle;
        transactionCycleCounts[cycle] =
            (transactionCycleCounts[cycle] ?? 0) + 1;
      }
      final sides = applications
          .where(
            (side) =>
                trip.displayApplicationKey == side.key &&
                trip.time == side.time &&
                _city(trip.cityCode) != null &&
                _city(trip.cityCode) == _city(_applicationCity(side)) &&
                _transactionRole(trip) ==
                    (side.isEntry
                        ? JourneyEventRole.entry
                        : JourneyEventRole.exit) &&
                _transactionMode(trip) ==
                    (side.rail != null
                        ? TripModeFilter.rail
                        : TripModeFilter.bus) &&
                (_applicationAmount(side) == null ||
                    trip.amountFen == _applicationAmount(side)),
          )
          .toList();
      if (sides.length == 1) {
        transactionApplications[entry] = sides.single;
        transactionApplicationCounts[sides.single] =
            (transactionApplicationCounts[sides.single] ?? 0) + 1;
      }
    }
  }
  transactionCycles.removeWhere(
    (entry, cycle) => transactionCycleCounts[cycle] != 1,
  );
  transactionApplications.removeWhere(
    (entry, side) => transactionApplicationCounts[side] != 1,
  );

  return {
    for (final entry in stream)
      entry: switch (entry) {
        ProcessTripEntry(:final record) => (
          applicationRecordId: cycleApplications[record] == null
              ? null
              : identity(cycleApplications[record]!),
          processPositions: positions[record] ?? const {},
        ),
        RailRecordEntry(:final record) => (
          applicationRecordId: journeyApplicationIdentity(record, 'rail'),
          processPositions: const {},
        ),
        BusRecordEntry(:final record) => (
          applicationRecordId: journeyApplicationIdentity(record, 'bus'),
          processPositions: const {},
        ),
        TransactionTripEntry() => _transactionEvidence(
          entry,
          positions,
          transactionCycles,
          transactionApplications,
          cycleApplications,
          identity,
        ),
      },
  };
}

LiveJourneyEvidence _transactionEvidence(
  TripEntry entry,
  Map<TUnionTripRecord, Map<String, int>> positions,
  Map<TripEntry, TUnionTripRecord> cycles,
  Map<TripEntry, TunionApplicationSide> directApplications,
  Map<TUnionTripRecord, TunionApplicationSide> cycleApplications,
  String Function(TunionApplicationSide) identity,
) {
  final cycle = cycles[entry];
  final direct = directApplications[entry];
  final indirect = cycleApplications[cycle];
  final side =
      direct != null &&
          indirect != null &&
          identity(direct) != identity(indirect)
      ? null
      : direct ?? indirect;
  return (
    applicationRecordId: side == null ? null : identity(side),
    processPositions: positions[cycle] ?? const {},
  );
}

String? _applicationCity(TunionApplicationSide side) => side.isEntry
    ? side.rail?.entryCityCode ?? side.bus?.entryCityCode
    : side.rail?.exitCityCode ?? side.bus?.exitCityCode;

int? _applicationAmount(TunionApplicationSide side) => side.rail != null
    ? (side.isEntry ? side.rail!.entryAmountFen : side.rail!.exitAmountFen)
    : side.isEntry
    ? null
    : side.bus?.transactionAmountFen;

bool _transactionMatchesCycle(TransitTrip trip, TUnionTripRecord cycle) {
  final mode = isTunionBusCycle(cycle)
      ? TripModeFilter.bus
      : cycle.isCityRail
      ? TripModeFilter.rail
      : TripModeFilter.other;
  final role = cycle.isEntry
      ? JourneyEventRole.entry
      : const {0x02, 0x04}.contains(cycle.typeCode)
      ? JourneyEventRole.exit
      : JourneyEventRole.unknown;
  return role != JourneyEventRole.unknown &&
      mode != TripModeFilter.other &&
      _transactionRole(trip) == role &&
      _transactionMode(trip) == mode &&
      trip.time == cycle.time &&
      trip.amountFen == cycle.amountFen &&
      _city(trip.cityCode) != null &&
      _city(trip.cityCode) == _city(cycle.cityCode);
}

JourneyEventRole _transactionRole(TransitTrip trip) =>
    switch (trip.rideStatusName) {
      '进站' || '进闸' || '上车' => JourneyEventRole.entry,
      '出站' || '出闸' || '下车' => JourneyEventRole.exit,
      '单次消费' || '充值' || '补票' => JourneyEventRole.unknown,
      _ =>
        trip.isEntry
            ? JourneyEventRole.entry
            : trip.matchedProcessTrip?.isEntry == true
            ? JourneyEventRole.entry
            : const {0x02, 0x04}.contains(trip.matchedProcessTrip?.typeCode)
            ? JourneyEventRole.exit
            : JourneyEventRole.unknown,
    };

TripModeFilter _transactionMode(TransitTrip trip) {
  if (trip.matchedProcessTrip case final process?) {
    if (isTunionBusCycle(process)) return TripModeFilter.bus;
  }
  final declared = tripModeOf(TransactionTripEntry(trip));
  if (declared != TripModeFilter.other) return declared;
  return switch (trip.stationType) {
    '公交' || 'BRT' || '公共汽电车' || 'bus' || 'brt' => TripModeFilter.bus,
    '地铁' || '城市轨道交通' || 'metro' || 'rail' => TripModeFilter.rail,
    _ => TripModeFilter.other,
  };
}

String? _city(String? value) {
  final city = value?.trim().toUpperCase();
  return city != null &&
          RegExp(r'^[0-9A-F]{4}$').hasMatch(city) &&
          !RegExp(r'^[0F]+$').hasMatch(city)
      ? city
      : null;
}
