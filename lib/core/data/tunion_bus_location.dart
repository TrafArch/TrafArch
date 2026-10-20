import 'beijing_bus_decoder.dart';
import 'station_codes.dart';

/// Bus display labels are resolved separately from rail fragment matching.
/// A numbered stop is deliberately kept distinct from a database station name.
class TunionBusLocation {
  final String? lineLabel;
  final String? stationLabel;
  final StationMatch match;

  const TunionBusLocation({
    this.lineLabel,
    this.stationLabel,
    this.match = StationMatch.unmatched,
  });

  static const unknown = TunionBusLocation();
}

TunionBusLocation resolveTunionBusLocation({
  required StationCodeTable stations,
  required String? cityCode,
  required String? field,
}) {
  if (cityCode == null ||
      field == null ||
      !RegExp(r'^[0-9A-Fa-f]{14}$').hasMatch(field)) {
    return TunionBusLocation.unknown;
  }
  final match = stations.matchBusLineStationField(
    field: field,
    cityCode: cityCode,
  );
  final decoded = decodeBeijingBus(cityCode: cityCode, field: field);
  return TunionBusLocation(
    lineLabel: match.lineName ?? decoded?.lineLabel,
    stationLabel: match.stationName ?? decoded?.stationLabel,
    match: match,
  );
}

/// 1A stores the same bus fields separately, with a one-byte stop ordinal.
/// Require complete fields before applying a city-specific decoding rule.
String? busRecordLocationField(
  String? line,
  String? station,
  String? operator,
) {
  if (line == null ||
      station == null ||
      operator == null ||
      !RegExp(r'^[0-9A-Fa-f]{4}$').hasMatch(line) ||
      !RegExp(r'^[0-9A-Fa-f]{2}$').hasMatch(station) ||
      !RegExp(r'^[0-9A-Fa-f]{4}$').hasMatch(operator)) {
    return null;
  }
  return '${line}00$station${operator}00';
}
