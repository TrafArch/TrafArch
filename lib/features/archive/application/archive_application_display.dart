import '../../../protocols/transit/tunion/tunion_models.dart';
import '../../reference_data/data/tunion_bus_location.dart';
import '../../reference_data/data/tunion_knowledge_base.dart';
import '../../reference_data/domain/station_codes.dart';
import '../../reference_data/domain/tu_cycle_station_resolver.dart';
import '../../transit_analysis/tunion_record_context.dart';

/// Captures each 1A endpoint from its own fields and the current reference data.
/// Raw codes and the protocol model's shared lineName are never display proof.
Map<String, dynamic> captureRailApplicationDisplay(
  KnowledgeBase knowledge,
  TransitRecord record,
) {
  if (knowledge.loadIssues.containsKey('TU')) return const {};
  return _endpoints(
    _railEndpoint(
      knowledge,
      record.entryCityCode,
      record.entryStationId,
      record.entryLineCode,
    ),
    _railEndpoint(
      knowledge,
      record.exitCityCode,
      record.exitStationId,
      record.exitLineCode,
    ),
  );
}

Map<String, dynamic> captureBusApplicationDisplay(
  KnowledgeBase knowledge,
  BusTransitRecord record,
) {
  if (knowledge.loadIssues.containsKey('TU')) return const {};
  Map<String, String> endpoint(bool entry) {
    final location = resolveTunionBusLocation(
      stations: knowledge.stationCodes,
      cityCode: _city(entry ? record.entryCityCode : record.exitCityCode),
      field: busRecordLocationField(
        entry ? record.entryLineCode : record.exitLineCode,
        entry ? record.entryStationCode : record.exitStationCode,
        entry ? record.entryOperatorCode : record.exitOperatorCode,
      ),
      context: TunionBusDecodeContext(
        transactionTime: entry ? record.entryTime : record.exitTime,
        amountFen: entry || record.transactionAmountFen == null
            ? null
            : -record.transactionAmountFen!,
      ),
    );
    return _labels(
      location.lineLabel,
      location.stationLabel,
      cityName: _cityName(
        knowledge,
        entry ? record.entryCityCode : record.exitCityCode,
      ),
    );
  }

  return _endpoints(endpoint(true), endpoint(false));
}

/// Freezes only this process record's resolved display values. Missing names
/// stay absent; raw city, line/station bytes and terminal remain in the record.
Map<String, String> captureProcessDisplay(
  KnowledgeBase knowledge,
  TUnionTripRecord record,
) {
  if (knowledge.loadIssues.containsKey('TU')) return const {};
  final cityName = _cityName(knowledge, record.cityCode);
  if (isTunionBusCycle(record)) {
    final location = resolveTunionBusLocation(
      stations: knowledge.stationCodes,
      cityCode: _city(record.cityCode),
      field: record.lineStationCode,
      context: busContextForCycle(record),
    );
    return _labels(
      location.lineLabel,
      location.stationLabel,
      cityName: cityName,
    );
  }
  final city = _city(
    normalizeTunionAcquirerCity(
      record.cityCode,
      rawCity36: cycleCityPair(record, 36),
    ),
  );
  var match = StationMatch.unmatched;
  if (city != null && record.lineStationCode.isNotEmpty) {
    match = resolveTuCycleStation(
      stations: knowledge.stationCodes,
      lookup: knowledge.tuLookup,
      cityCode: city,
      field: record.lineStationCode,
      terminalId: record.terminalId,
      time: record.time,
      appType: record.appTypeCode,
    );
  }
  return _labels(match.lineName, match.stationName, cityName: cityName);
}

Map<String, dynamic> _endpoints(
  Map<String, String> entry,
  Map<String, String> exit,
) => {if (entry.isNotEmpty) 'entry': entry, if (exit.isNotEmpty) 'exit': exit};

Map<String, String> _railEndpoint(
  KnowledgeBase knowledge,
  String? cityCode,
  String? station,
  int? line,
) {
  final city = _city(cityCode);
  if (city == null) return const {};
  final stations = knowledge.stationCodes;
  final code = station?.replaceAll(RegExp(r'[^0-9A-Za-z]'), '');
  var match = StationMatch.unmatched;
  if (code != null && code.isNotEmpty) {
    match = stations.matchTuStationByCardId(
      rawStationId: code,
      cityCode: city,
      lineValue: line,
    );
    if (match.isUnmatched) {
      final fallback = stations.lookupStation(rawCode: code, cityCode: city);
      if (fallback != null) {
        match = StationMatch(fallback, StationMatchConfidence.exact);
      }
    }
  }
  final lineName =
      match.lineName ??
      (line == null
          ? null
          : _lineName(stations, city, line.toRadixString(16).toUpperCase()) ??
                _lineName(stations, city, line.toString()));
  return _labels(
    lineName,
    match.stationName,
    cityName: _cityName(knowledge, cityCode),
  );
}

String? _lineName(StationCodeTable stations, String city, String code) {
  final match = stations.matchTuLineByCardValue(
    rawLineCode: code,
    cityCode: city,
  );
  if (match.confidence == StationMatchConfidence.ambiguous) return null;
  return match.entry?.line ??
      stations.lookupLineName(rawLineCode: code, cityCode: city);
}

Map<String, String> _labels(
  String? line,
  String? station, {
  String? cityName,
}) => {
  'cityName': ?_label(cityName),
  'line': ?_label(line),
  'station': ?_label(station),
};

String? _cityName(KnowledgeBase knowledge, String? code) {
  final city = _city(code);
  return city == null ? null : knowledge.cities.lookup(city)?.name;
}

String? _label(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}

String? _city(String? value) {
  final city = _label(value)?.toUpperCase();
  return city == null || city.replaceAll('0', '').isEmpty ? null : city;
}
