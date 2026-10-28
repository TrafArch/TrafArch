import 'station_codes.dart';
import 'tu_lookup_service.dart';

/// Resolves one TU rail cycle for both live display and archive capture.
/// Original complete keys, ambiguity and query errors retain priority. A
/// line-only native prefix may be completed by the existing strict station
/// lookup only for the explicit zero-padded form of a compact source key.
StationMatch resolveTuCycleStation({
  required StationCodeTable stations,
  required TuLookupService? lookup,
  required String? cityCode,
  required String field,
  required int? appType,
  String? terminalId,
  DateTime? time,
}) {
  final source =
      lookup?.resolveCycle(
        city: cityCode,
        field: field,
        terminalId: terminalId,
        time: time,
        appType: appType,
      ) ??
      StationMatch.unmatched;
  // Source-verified Beijing industry 00 can carry a location, but never earns
  // the ordinary rail fragment fallback or a derived transport classification.
  if (appType != 0x01) return source;
  if (!source.isUnmatched && !_isNativeLinePrefix(source, cityCode)) {
    return source;
  }

  final station = stations.matchLineStationField(
    field: field,
    cityCode: cityCode,
  );
  if (source.isUnmatched) return station;
  final entry = station.entry;
  final prefix = source.entry!;
  if (station.confidence != StationMatchConfidence.exact ||
      entry == null ||
      (station.stationName ?? '').trim().isEmpty ||
      entry.system != 'tu' ||
      entry.sourceField != prefix.sourceField ||
      !_isZeroPaddedCompactKey(
        field,
        cityCode!,
        prefix.sourceKey ?? prefix.code,
        entry.sourceKey ?? entry.code,
      )) {
    return source;
  }

  // Fragment matches from older sources may not carry an evidence list. Keep
  // both the original line prefix and the exact station's untouched source.
  final evidence = <StationMatchEvidence>[];
  final seen = <(String, String, String?)>{};
  for (final item in [
    ...source.evidence,
    ...station.evidence,
    StationMatchEvidence(
      sourceField: entry.sourceField ?? '',
      sourceKey: entry.sourceKey ?? entry.code,
      rawValueJson: entry.rawValueJson,
    ),
  ]) {
    if (seen.add((item.sourceField, item.sourceKey, item.rawValueJson))) {
      evidence.add(item);
    }
  }
  return StationMatch(
    entry,
    StationMatchConfidence.exact,
    candidates: station.candidates.isEmpty ? [entry] : station.candidates,
    evidence: evidence,
  );
}

bool _isNativeLinePrefix(StationMatch match, String? city) {
  if (city == null ||
      match.confidence != StationMatchConfidence.exact ||
      (match.stationName ?? '').trim().isNotEmpty ||
      (match.lineName ?? '').trim().isEmpty) {
    return false;
  }
  final entry = match.entry;
  if (entry == null ||
      entry.system != 'tu' ||
      entry.sourceField != StationCodeTable.tuRailSourceField(city)) {
    return false;
  }
  final key = entry.sourceKey ?? entry.code;
  return key.length > city.length && key.startsWith(city);
}

bool _isZeroPaddedCompactKey(
  String field,
  String city,
  String prefix,
  String key,
) {
  // Compact sources store city + one line byte + one station byte. Only
  // expand each byte with a zero low byte; never discard an unknown compact
  // station or a nonzero low byte, and never translate the raw numeric base.
  if (prefix.length != city.length + 2 ||
      key.length != city.length + 4 ||
      !key.startsWith(prefix)) {
    return false;
  }
  final line = key.substring(city.length, city.length + 2);
  final station = key.substring(city.length + 2);
  return field.toUpperCase().startsWith('${line}00${station}00');
}
