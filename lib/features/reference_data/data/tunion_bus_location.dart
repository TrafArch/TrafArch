import '../domain/beijing_bus_decoder.dart';
import '../domain/tu_lookup_service.dart';
import 'tu_region_live_source.dart';
import '../domain/station_codes.dart';
import '../domain/taiyuan_bus_decoder.dart';
import '../domain/tunion_city_bus_decoder.dart';
import '../domain/tunion_bus_caller.dart';

export '../domain/tunion_city_bus_decoder.dart' show TunionBusDecodeContext;

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
  TunionBusDecodeContext context = const TunionBusDecodeContext(),
}) {
  StationMatch? compatibility;
  final live = stations.live;
  if (live is TuRegionLiveSource) {
    final special = TuLookupService(live.repository)
        .resolveShenzhenTerminal(city: cityCode, terminal: context.terminalId);
    if (!special.isUnmatched) {
      // Operator-only prefixes must not suppress Shenzhen's dated route decoding.
      if (special.confidence != StationMatchConfidence.exact ||
          (special.stationName ?? '').isNotEmpty) {
        return TunionBusLocation(
          lineLabel: special.lineName,
          stationLabel: special.stationName,
          match: special,
        );
      }
      compatibility = special;
    }
  }
  if (cityCode == null ||
      field == null ||
      !RegExp(r'^[0-9A-Fa-f]{14}$').hasMatch(field)) {
    return TunionBusLocation.unknown;
  }
  final exact =
      compatibility ??
      stations.matchBusLineStationField(field: field, cityCode: cityCode);
  if (!exact.isUnmatched && exact.entry == null) {
    return TunionBusLocation(match: exact);
  }
  final match = !exact.isUnmatched
      ? exact
      : _sourceBusPrefix(stations, cityCode, field) ?? exact;
  if (match.confidence == StationMatchConfidence.ambiguous ||
      match.confidence == StationMatchConfidence.unavailable) {
    return TunionBusLocation(match: match);
  }
  final fallbackAllowed = context.routeFallbackAllowed != false;
  final decoded = fallbackAllowed
      ? decodeBeijingBus(cityCode: cityCode, field: field)
      : null;
  final cityLine = fallbackAllowed
      ? decodeTunionCityBusLine(
          cityCode: cityCode,
          field: field,
          context: context,
        )
      : null;
  final line = fallbackAllowed
      ? TunionBusCaller.historicalShenzhenLine(
          city: cityCode,
          terminal: context.terminalId,
          carrier: context.carrierCode,
          transactionTime: context.transactionTime,
          currentLine: context.language == 1
              ? decoded?.lineLabel ??
                    decodeTaiyuanBusLine(cityCode: cityCode, field: field) ??
                    cityLine
              : cityLine,
        )
      : null;
  return TunionBusLocation(
    lineLabel: compatibility != null
        ? line ?? match.lineName
        : match.lineName ?? line,
    stationLabel: compatibility != null
        ? decoded?.stationLabel
        : (match.stationName ?? '').trim().isNotEmpty
        ? match.stationName
        : decoded?.stationLabel,
    match: match,
  );
}

/// m756j(city + txLine, mode=4) checks longest prefixes in M0.S.c before m764r.
/// Restrict this path to that proven namespace: terminal tables such as Taiyuan
/// M0.n0.a, Nanjing M0.E.a and Chengdu M0.b.a use different input fields.
StationMatch? _sourceBusPrefix(
  StationCodeTable stations,
  String city,
  String field,
) {
  if (!RegExp(r'^[0-9]{4}$').hasMatch(city)) return null;
  final key = '$city${field.substring(0, 12).toUpperCase()}';
  for (var length = key.length; length >= 5; length--) {
    final candidate = key.substring(0, length);
    final entry = stations.lookup(code: candidate, cityCode: city);
    if (entry == null ||
        entry.sourceField != 'M0.S.c' ||
        (entry.sourceKey != null && entry.sourceKey != candidate) ||
        entry.system != 'tu' ||
        !(entry.kind == 'bus' || entry.kind == 'brt')) {
      continue;
    }
    return StationMatch(entry, StationMatchConfidence.exact);
  }
  return null;
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
