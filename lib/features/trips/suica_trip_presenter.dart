import '../../protocols/felica/models/felica_models.dart';
import '../../protocols/felica/models/jpy_amount_formatter.dart';
import '../../protocols/felica/models/suica_transaction_details.dart';
import '../home/presentation/summary_formatters.dart';
import '../reference_data/data/suica_station_repository.dart';
import 'journey_presentation.dart';
import 'trip_cards_view.dart';
import 'trip_entry_presenter.dart';
import 'trip_filters.dart';

enum SuicaTripSource { history }

/// A captured Suica display. Restoration uses these frozen words and endpoints,
/// without interpreting raw bytes or looking up a newer station database.
class SuicaTripPresentation {
  const SuicaTripPresentation._({required this.entry, required this.journey});

  final TripCardPresentation<SuicaTripSource> entry;
  final JourneyPresentation<TripCardPresentation<SuicaTripSource>> journey;

  Map<String, dynamic> toJson() => {
    'version': 1,
    'mode': entry.mode.name,
    'dateText': entry.dateText,
    'state': journey.state.name,
    'info': {
      'sourceLabel': entry.info.sourceLabel,
      'title': entry.info.title,
      'line': entry.info.line,
      'timeText': entry.info.timeText,
      'amountText': entry.info.amountText,
      'isConsume': entry.info.isConsume,
      'subText': entry.info.subText,
      'category': entry.info.category,
      'badges': entry.info.badges,
      'rawHex': entry.info.rawHex,
      'fields': [
        for (final field in entry.info.fields) [field.$1, field.$2],
      ],
    },
    'point': _endpointJson(journey.events.single.endpoint),
    'start': _endpointJson(journey.start),
    'end': _endpointJson(journey.end),
    'balanceAfterText': journey.balanceAfterText,
  };

  /// Old captures do not contain this format. Malformed or future projections
  /// are ignored independently, so one bad record does not break recovery.
  static SuicaTripPresentation? fromJson(Object? json) {
    if (json is! Map || json['version'] != 1) return null;
    try {
      final info = json['info'];
      if (info is! Map || info['isConsume'] is! bool) return null;
      final mode = TripModeFilter.values.byName(_requiredString(json['mode']));
      final state = JourneyState.values.byName(_requiredString(json['state']));
      final badges = info['badges'];
      final fields = info['fields'];
      if (badges is! List || fields is! List) return null;
      final entryInfo = TripEntryInfo(
        sourceLabel: _requiredString(info['sourceLabel']),
        title: _requiredString(info['title']),
        line: _optionalString(info['line']),
        timeText: _optionalString(info['timeText']),
        amountText: _optionalString(info['amountText']),
        isConsume: info['isConsume'] as bool,
        subText: _optionalString(info['subText']),
        category: _optionalString(info['category']),
        badges: List.unmodifiable(badges.map(_requiredString)),
        rawHex: _optionalString(info['rawHex']),
        fields: List.unmodifiable(
          fields.map((field) {
            if (field is! List || field.length != 2) {
              throw const FormatException('Invalid Suica detail field');
            }
            return (_requiredString(field[0]), _requiredString(field[1]));
          }),
        ),
      );
      final point = _restoreEndpoint(json['point']);
      if (point == null) return null;
      return _projection(
        info: entryInfo,
        mode: mode,
        dateText: _requiredString(json['dateText']),
        state: state,
        point: point,
        start: _restoreEndpoint(json['start']),
        end: _restoreEndpoint(json['end']),
        balanceAfterText: _optionalString(json['balanceAfterText']),
      );
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }
}

/// The order and cardinality are exactly those of the captured history stream.
/// Each rail block already contains its two ends; no inter-record pairing runs.
List<SuicaTripPresentation> presentSuicaTrips(
  Iterable<FelicaTransaction> transactions, {
  SuicaStationRepository? stations,
}) => List.unmodifiable([
  for (final tx in transactions) _presentSuicaTrip(tx, stations: stations),
]);

SuicaTripPresentation _presentSuicaTrip(
  FelicaTransaction tx, {
  SuicaStationRepository? stations,
}) {
  final details = tx.suica;
  final kind = details?.kind ?? SuicaRecordKind.unknown;
  final mode = switch (kind) {
    SuicaRecordKind.rail => TripModeFilter.rail,
    SuicaRecordKind.bus => TripModeFilter.bus,
    _ => TripModeFilter.other,
  };
  final kindLabel = details?.kindLabel ?? '未解析记录';
  final processLabel = details?.processLabel ?? '处理类型未知';
  final timeText = felicaTime(tx);
  final timeKnown = details?.hasTime == true;
  final stationTime = tx.time == null
      ? '时刻未解析'
      : timeKnown
      ? '${_two(tx.time!.hour)}:${_two(tx.time!.minute)}'
      : '时刻未记录';
  final entryStation = _station(details?.entryStation, stations);
  final exitStation = _station(details?.exitStation, stations);
  final balance = tx.amountIsBalance && tx.amountMinorUnits != null
      ? tx.currency == 'JPY'
            ? formatJpyAmount(tx.amountMinorUnits!)
            : '${tx.amountMinorUnits}（币种未知）'
      : null;
  final change = tx.currency == 'JPY' ? details?.balanceChangeYen : null;
  final amount = change == null
      ? null
      : '余额差 ${formatJpyAmount(change, showPositiveSign: true)}';
  final fields = <(String, String)>[
    ('记录类型', kindLabel),
    ('处理类型', processLabel),
    ('历史块号', tx.sequence?.toString() ?? '未知'),
    if (details != null) ...[
      ('交易流水号', '${details.recordSequence}'),
      ('处理码', _hex(details.processCode)),
      ('端末类型', details.terminalLabel),
      ('端末码', _hex(details.terminalCode)),
      ('区域字节', _hex(details.regionCode)),
    ],
    ('记录时间', timeText),
    (
      '时间精度',
      tx.time == null
          ? '未知（日期未解析）'
          : timeKnown
          ? '分钟（卡片记录）'
          : '日期；时刻未记录',
    ),
    ('交易后余额', balance ?? '未知'),
    if (amount != null) ('余额差', amount.substring('余额差 '.length)),
    if (change != null) ('余额差说明', '相邻连续历史记录的交易后余额之差，不保证等同单笔票价'),
    ..._stationFields(
      kind == SuicaRecordKind.special ? '地点' : '进站',
      details?.entryStation,
      entryStation,
    ),
    ..._stationFields('出站', details?.exitStation, exitStation),
    if (details?.busOperatorCode case final operator?)
      ('公交事业者码', _hex(operator, width: 4)),
    if (stations != null &&
        (details?.entryStation?.canLookup == true ||
            details?.exitStation?.canLookup == true))
      ('站点数据 SHA256', stations.hash),
    if (tx.note?.isNotEmpty == true) ('解析说明', tx.note!),
  ];
  final route =
      kind == SuicaRecordKind.rail &&
          entryStation != null &&
          exitStation != null
      ? '${entryStation.station} → ${exitStation.station}'
      : null;
  final info = TripEntryInfo(
    sourceLabel: 'Suica 090F 历史',
    title: '$kindLabel · $processLabel',
    timeText: timeText,
    amountText: amount,
    // The color represents the observed debit. It never changes processLabel.
    isConsume: change != null && change < 0,
    subText: [if (balance != null) '交易后余额 $balance', ?route].join(' · '),
    category: kindLabel,
    rawHex: tx.rawHex,
    fields: List.unmodifiable(fields),
  );
  final point = JourneyEndpoint(
    time: tx.time,
    timeText: stationTime,
    line: kind == SuicaRecordKind.bus && details?.busOperatorCode != null
        ? '公交事业者 ${_hex(details!.busOperatorCode!, width: 4)}'
        : entryStation?.line,
    station: entryStation?.station,
  );
  JourneyEndpoint? endpoint(_StationPresentation? station) => station == null
      ? null
      : JourneyEndpoint(
          time: tx.time,
          timeText: stationTime,
          line: station.line,
          station: station.station,
        );
  final start = kind == SuicaRecordKind.rail ? endpoint(entryStation) : null;
  final end = kind == SuicaRecordKind.rail ? endpoint(exitStation) : null;
  return _projection(
    info: info,
    mode: mode,
    dateText: tx.time == null ? '日期未知' : summaryDate(tx.time!),
    state: start != null && end != null
        ? JourneyState.completed
        : JourneyState.single,
    point: point,
    start: start,
    end: end,
    balanceAfterText: balance,
  );
}

SuicaTripPresentation _projection({
  required TripEntryInfo info,
  required TripModeFilter mode,
  required String dateText,
  required JourneyState state,
  required JourneyEndpoint point,
  JourneyEndpoint? start,
  JourneyEndpoint? end,
  String? balanceAfterText,
}) {
  final event = JourneyEvent(
    payload: info,
    mode: mode,
    role: JourneyEventRole.single,
    endpoint: point,
    evidenceSource: JourneyEvidenceSource.transaction,
    amountText: info.amountText,
    balanceAfterText: balanceAfterText,
  );
  final entry = TripCardPresentation(
    info: info,
    source: SuicaTripSource.history,
    mode: mode,
    dateText: dateText,
    remote: false,
    journeyEvent: event,
  );
  return SuicaTripPresentation._(
    entry: entry,
    journey: JourneyPresentation(
      events: List.unmodifiable([event.withPayload(entry)]),
      mode: mode,
      state: state,
      start: start,
      end: end,
      amountText: info.amountText,
      balanceAfterText: balanceAfterText,
    ),
  );
}

/// Compact overview; full record details remain on the trip page.
String suicaTransactionSummary(
  FelicaTransaction tx, {
  SuicaStationRepository? stations,
}) {
  final trip = _presentSuicaTrip(tx, stations: stations);
  final start = trip.journey.start?.station;
  final end = trip.journey.end?.station;
  return [
    trip.entry.info.title,
    if (start != null && end != null) '$start → $end',
    if (trip.entry.info.amountText != null) trip.entry.info.amountText!,
  ].join(' · ');
}

class _StationPresentation {
  const _StationPresentation({required this.station, this.line, this.company});
  final String station;
  final String? line;
  final String? company;
}

_StationPresentation? _station(
  SuicaStationCode? code,
  SuicaStationRepository? repository,
) {
  if (code == null) return null;
  if (!code.canLookup) {
    return _StationPresentation(
      station: '${code.statusLabel}（${code.codeText}）',
    );
  }
  final match = repository?.lookup(
    areaCode: code.areaCode,
    lineCode: code.lineCode,
    stationCode: code.stationCode,
  );
  return _StationPresentation(
    station:
        _nonempty(match?.stationName) ??
        '${repository == null ? '站点数据不可用' : '站点未收录'}（${code.codeText}）',
    line: _nonempty(match?.lineName),
    company: _nonempty(match?.companyName),
  );
}

List<(String, String)> _stationFields(
  String side,
  SuicaStationCode? code,
  _StationPresentation? station,
) => [
  if (code != null) ...[
    ('$side原码', code.codeText),
    ('$side编码状态', code.statusLabel),
    if (station != null) (side == '地点' ? '发生地点' : '$side站点', station.station),
    if (station?.line case final line?) ('$side线路', line),
    if (station?.company case final company?) ('$side运营方', company),
  ],
];

Map<String, dynamic>? _endpointJson(JourneyEndpoint? endpoint) =>
    endpoint == null
    ? null
    : {
        'line': endpoint.line,
        'station': endpoint.station,
        'time': endpoint.time?.toIso8601String(),
        'timeText': endpoint.timeText,
      };

JourneyEndpoint? _restoreEndpoint(Object? json) {
  if (json == null) return null;
  if (json is! Map) throw const FormatException('Invalid Suica endpoint');
  final time = _optionalString(json['time']);
  final parsedTime = time == null ? null : DateTime.tryParse(time);
  if (time != null && parsedTime == null) {
    throw const FormatException('Invalid captured Suica date');
  }
  return JourneyEndpoint(
    line: _optionalString(json['line']),
    station: _optionalString(json['station']),
    time: parsedTime,
    timeText: _optionalString(json['timeText']),
  );
}

String _requiredString(Object? value) {
  if (value is! String) throw const FormatException('Expected captured text');
  return value;
}

String? _optionalString(Object? value) =>
    value == null ? null : _requiredString(value);
String? _nonempty(String? value) =>
    value == null || value.trim().isEmpty ? null : value;
String _two(int value) => value.toString().padLeft(2, '0');
String _hex(int value, {int width = 2}) =>
    '0x${value.toRadixString(16).padLeft(width, '0').toUpperCase()}';
