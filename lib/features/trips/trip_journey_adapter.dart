import '../../protocols/transit/tunion/tunion_models.dart';
import '../reference_data/data/tunion_bus_location.dart';
import '../reference_data/domain/station_codes.dart';
import '../transit_analysis/tunion_analysis_models.dart';
import '../transit_analysis/tunion_record_context.dart';
import 'journey_presentation.dart';
import 'trip_entry_presenter.dart';
import 'trip_filters.dart';
import 'trip_presentation_context.dart';

export '../transit_analysis/process_journey_positions.dart';

/// Adapts current-read evidence without parsing labels from the detail title.
/// Amounts never establish entry/exit roles and unknown seat data stays absent.
JourneyEvent<TripEntryInfo> describeJourneyEvent(
  TripEntry entry,
  TripPresentationContext display,
  TripEntryInfo info, {
  String? applicationRecordId,
  Map<String, int> processPositions = const {},
  bool allowProcessBalance = true,
}) {
  final TripModeFilter mode;
  final JourneyEventRole role;
  final DateTime? time;
  final String? cityCode;
  final String? station;
  String? cityLabel;
  String? decodedBusLine;
  String? balanceAfterText;
  int? confirmedBalanceFen;
  TUnionTripRecord? balanceProcess;
  int? fareFen;
  var isConsume = false;
  int? sequence;
  var recordId = applicationRecordId;

  switch (entry) {
    case TransactionTripEntry(:final trip):
      final process = trip.matchedProcessTrip;
      mode = _transactionMode(trip);
      role =
          _statusRole(trip.rideStatusName, mode) ??
          (process == null ? null : _processRole(process, mode)) ??
          (trip.isEntry
              ? JourneyEventRole.entry
              : mode == TripModeFilter.bus && trip.isConsume
              ? JourneyEventRole.single
              : JourneyEventRole.unknown);
      time = trip.time;
      cityCode = _cityCode(trip.cityCode);
      cityLabel = _text(trip.cityName);
      sequence = trip.sequence;
      decodedBusLine = trip.resolvedBusLineLabel;
      fareFen = trip.amountFen;
      isConsume = trip.isConsume;
      if (trip.balanceAfterIsRecorded == false) {
        balanceAfterText = display.formatBalance(trip.balanceAfterFen);
        confirmedBalanceFen = trip.balanceAfterFen;
      }
      balanceProcess = process;
      station = mode == TripModeFilter.bus
          ? _busStation(
              trip.stationLabel,
              rawCode: trip.stationConfidence != StationMatchConfidence.exact,
            )
          : _stationText(trip.stationLabel);

    case ProcessTripEntry(:final record):
      mode = _processMode(record);
      role = _processRole(record, mode);
      time = record.time;
      cityCode = _cityCode(record.cityCode);
      fareFen = record.amountFen;
      balanceProcess = record;
      isConsume = record.isConsume;
      if (mode == TripModeFilter.bus) {
        final location = display.resolveBusLocation(
          record.cityCode,
          record.lineStationCode,
          context: busContextForCycle(record),
        );
        decodedBusLine = location.lineLabel;
        station =
            _busStation(location.stationLabel ?? location.match.stationName) ??
            _busStation(record.stationCode, rawCode: true);
      } else {
        station = _stationText(
          display
              .resolveCycleStationMatch(
                normalizeTunionAcquirerCity(
                  record.cityCode,
                  rawCity36: cycleCityPair(record, 36),
                ),
                record.lineStationCode,
                terminalId: record.terminalId,
                time: record.time,
                appType: record.appTypeCode,
              )
              .stationName,
        );
      }

    case RailRecordEntry(:final record, :final isEntry):
      mode = TripModeFilter.rail;
      fareFen = isEntry ? record.entryAmountFen : record.exitAmountFen;
      isConsume = (fareFen ?? 0) > 0;
      time = isEntry ? record.entryTime : record.exitTime;
      cityCode = _cityCode(
        isEntry ? record.entryCityCode : record.exitCityCode,
      );
      final rawStation = isEntry ? record.entryStationId : record.exitStationId;
      final match = display.resolveStationMatch(
        cityCode,
        rawStation,
        lineValue: isEntry ? record.entryLineCode : record.exitLineCode,
      );
      station =
          _stationText(match.stationName) ??
          _stationText(
            isEntry ? record.entryStationName : record.exitStationName,
          ) ??
          _stationText(rawStation);
      // An entering record can retain an older exit field. Retain its source
      // details, but never use that field to complete the current journey.
      final staleExit = !isEntry && record.statusCode == 0x01;
      if (time == null || staleExit) {
        role = JourneyEventRole.unknown;
        recordId = null;
      } else {
        role = isEntry ? JourneyEventRole.entry : JourneyEventRole.exit;
        recordId ??= journeyApplicationIdentity(record, 'rail');
      }

    case BusRecordEntry(:final record, :final isEntry):
      mode = TripModeFilter.bus;
      fareFen = isEntry ? null : record.transactionAmountFen;
      isConsume = (fareFen ?? 0) > 0;
      time = isEntry ? record.entryTime : record.exitTime;
      cityCode = _cityCode(
        isEntry ? record.entryCityCode : record.exitCityCode,
      );
      final rawStation = isEntry
          ? record.entryStationCode
          : record.exitStationCode;
      final location = display.resolveBusLocation(
        cityCode,
        busRecordLocationField(
          isEntry ? record.entryLineCode : record.exitLineCode,
          rawStation,
          isEntry ? record.entryOperatorCode : record.exitOperatorCode,
        ),
        context: TunionBusDecodeContext(
          transactionTime: time,
          amountFen: isEntry || record.transactionAmountFen == null
              ? null
              : -record.transactionAmountFen!,
        ),
      );
      decodedBusLine = location.lineLabel;
      station =
          _busStation(location.stationLabel ?? location.match.stationName) ??
          _busStation(rawStation, rawHex: true);
      if (time == null) {
        role = JourneyEventRole.unknown;
        recordId = null;
      } else {
        role = isEntry ? JourneyEventRole.entry : JourneyEventRole.exit;
        recordId ??= journeyApplicationIdentity(record, 'bus');
      }
  }

  cityLabel ??= cityCode == null ? null : _text(display.cityNameOf(cityCode));
  if (cityLabel != null && cityLabel.length > 1 && cityLabel.endsWith('市')) {
    cityLabel = cityLabel.substring(0, cityLabel.length - 1);
  }
  return JourneyEvent(
    payload: info,
    mode: mode,
    role: role,
    endpoint: JourneyEndpoint(
      line: mode == TripModeFilter.bus
          ? formatJourneyBusLine(decodedBusLine) ?? _text(info.line)
          : _text(info.line),
      station: station,
      time: time,
      timeText: time == null ? null : _clockText(time),
    ),
    scopeKey: 'live:TU:${display.currency.code}',
    sourceIds: const {'live'},
    cityCode: cityCode,
    cityLabel: cityLabel,
    sequence: sequence,
    processPositions: Map.unmodifiable(processPositions),
    applicationRecordId: recordId,
    evidenceSource: switch (entry) {
      TransactionTripEntry() => JourneyEvidenceSource.transaction,
      ProcessTripEntry() => JourneyEvidenceSource.cycle,
      RailRecordEntry() ||
      BusRecordEntry() => JourneyEvidenceSource.application,
    },
    amountText: info.amountText,
    balanceAfterText: balanceAfterText,
    confirmedBalanceFen: confirmedBalanceFen,
    processBalance:
        allowProcessBalance &&
            display.currency.code == 'CNY' &&
            balanceProcess != null &&
            processPositions.isNotEmpty
        ? JourneyProcessBalanceEvidence(
            recordedFen: balanceProcess.balanceFen,
            balanceOffsetFen: display.balanceDisplay.offsetFen,
            amountFen: balanceProcess.amountFen,
            currencyCode: display.currency.code,
            currencySymbol: display.currency.symbol,
            positions: Map.unmodifiable(processPositions),
          )
        : null,
    seatLabel: mode == TripModeFilter.rail
        ? journeySeatLabel(
            line: info.line,
            amountFen: fareFen,
            isConsume: isConsume,
            currencyCode: display.currency.code,
          )
        : null,
  );
}

TripModeFilter _transactionMode(TransitTrip trip) {
  final process = trip.matchedProcessTrip;
  if (process != null && isTunionBusCycle(process)) return TripModeFilter.bus;
  final declared = tripModeOf(TransactionTripEntry(trip));
  if (declared != TripModeFilter.other) return declared;
  return switch (trip.stationType) {
    '公交' || 'BRT' || '公共汽电车' || 'bus' || 'brt' => TripModeFilter.bus,
    '地铁' || '城市轨道交通' || 'metro' || 'rail' => TripModeFilter.rail,
    _ => TripModeFilter.other,
  };
}

TripModeFilter _processMode(TUnionTripRecord record) => isTunionBusCycle(record)
    ? TripModeFilter.bus
    : record.isCityRail
    ? TripModeFilter.rail
    : TripModeFilter.other;

JourneyEventRole _processRole(TUnionTripRecord record, TripModeFilter mode) =>
    switch (record.typeCode) {
      0x01 || 0x03 => JourneyEventRole.entry,
      0x02 || 0x04 => JourneyEventRole.exit,
      0x05 || 0x06 when mode == TripModeFilter.bus => JourneyEventRole.single,
      _ => JourneyEventRole.unknown,
    };

JourneyEventRole? _statusRole(String? status, TripModeFilter mode) =>
    switch (_text(status)) {
      '进站' || '进闸' || '上车' => JourneyEventRole.entry,
      '出站' || '出闸' || '下车' => JourneyEventRole.exit,
      '单次消费' =>
        mode == TripModeFilter.bus
            ? JourneyEventRole.single
            : JourneyEventRole.unknown,
      '充值' || '补票' => JourneyEventRole.unknown,
      _ => null,
    };

// Object identity supplies the relationship, not matching raw values. Expando
// does not retain old read sessions and does not rely on hash-code uniqueness.
final _applicationIds = Expando<String>('journey-application-record');
var _nextApplicationId = 0;
String journeyApplicationIdentity(Object record, String kind) =>
    _applicationIds[record] ??= 'live:$kind:${_nextApplicationId++}';

String? _text(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}

String? _cityCode(String? value) {
  final text = _text(value);
  return text == null || RegExp(r'^[0Ff]+$').hasMatch(text) ? null : text;
}

String? _stationText(String? value) {
  final text = _text(value);
  return text == null || RegExp(r'^0+$|^[Ff]+$').hasMatch(text) ? null : text;
}

String? _busStation(
  String? value, {
  bool rawHex = false,
  bool rawCode = false,
}) {
  final text = _text(value);
  if (text == null || RegExp(r'^0+$').hasMatch(text)) return null;
  final ordinal = RegExp(r'^第(\d+)站$').firstMatch(text);
  if (ordinal != null) {
    final number = int.tryParse(ordinal.group(1)!);
    return number == null || number == 0 ? null : '站点$number';
  }
  // Only the 1A single-byte field has a generic hexadecimal ordinal meaning.
  // Unresolved 1E/transaction codes retain leading zeros and city semantics.
  if (rawHex && RegExp(r'^[0-9A-Fa-f]{1,2}$').hasMatch(text)) {
    final number = int.parse(text, radix: 16);
    return number == 0 ? null : '站点$number';
  }
  if (rawCode && RegExp(r'^[0-9A-Fa-f]+$').hasMatch(text)) {
    return '站点$text';
  }
  return text;
}

String _clockText(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}:'
    '${time.second.toString().padLeft(2, '0')}';
