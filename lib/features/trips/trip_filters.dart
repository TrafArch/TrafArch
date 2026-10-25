import '../transit_analysis/tunion_analysis_models.dart';

enum TripSourceFilter { transaction, cycle, record }

enum TripModeFilter { rail, bus, other }

const tripSourceLabels = <TripSourceFilter, String>{
  TripSourceFilter.transaction: '0x18 交易',
  TripSourceFilter.cycle: '0x1E 过程',
  TripSourceFilter.record: '0x1A 记录',
};
const tripModeLabels = <TripModeFilter, String>{
  TripModeFilter.rail: '城市轨道交通',
  TripModeFilter.bus: '公共汽电车',
  TripModeFilter.other: '其他',
};

TripSourceFilter tripSourceOf(TripEntry entry) => switch (entry) {
  TransactionTripEntry() => TripSourceFilter.transaction,
  ProcessTripEntry() => TripSourceFilter.cycle,
  RailRecordEntry() || BusRecordEntry() => TripSourceFilter.record,
};

TripModeFilter tripModeOf(TripEntry entry) => switch (entry) {
  RailRecordEntry() => TripModeFilter.rail,
  BusRecordEntry() => TripModeFilter.bus,
  ProcessTripEntry(:final record) =>
    record.isBus
        ? TripModeFilter.bus
        : (record.isCityRail ? TripModeFilter.rail : TripModeFilter.other),
  TransactionTripEntry(:final trip) =>
    trip.matchedProcessTrip?.isBus == true || trip.appTypeName == '公共汽电车'
        ? TripModeFilter.bus
        : (trip.matchedProcessTrip?.isCityRail == true ||
                  trip.appTypeName == '城市轨道交通'
              ? TripModeFilter.rail
              : TripModeFilter.other),
};
