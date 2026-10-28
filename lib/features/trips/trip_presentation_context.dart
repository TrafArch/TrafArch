import '../transit_analysis/tunion_analysis_models.dart';
import '../transit_analysis/shanghai_balance_display.dart';
import '../reference_data/domain/station_codes.dart';
import '../reference_data/data/tunion_bus_location.dart';

typedef StationLookup = StationMatch Function(
  String? city,
  String? code, {
  int? lineValue,
});
typedef CycleStationLookup = StationMatch Function(
  String? city,
  String? field, {
  String? terminalId,
  DateTime? time,
  int? appType,
});
typedef BusLocationLookup = TunionBusLocation Function(
  String? city,
  String? field, {
  TunionBusDecodeContext context,
});

/// Captured currency plus explicit namespace-scoped reference lookups.
/// No BuildContext, AppDependencies, persistence or parser is needed by the formatter.
class TripPresentationContext {
  const TripPresentationContext({
    required this.currency,
    required this.cityNameOf,
    required this.resolveStationMatch,
    required this.resolveCycleStationMatch,
    required this.resolveLineName,
    required this.resolveBusLocation,
    this.balanceDisplay = const ShanghaiBalanceDisplay(),
  });
  final Currency currency;
  final ShanghaiBalanceDisplay balanceDisplay;
  String? formatBalance(int? fen) =>
      balanceDisplay.formatBalance(fen, symbol: currency.symbol);
  final String? Function(String?) cityNameOf;
  final StationLookup resolveStationMatch;
  final CycleStationLookup resolveCycleStationMatch;
  final String? Function(String?, String?) resolveLineName;
  final BusLocationLookup resolveBusLocation;
}
