import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_bus_location.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/station_codes.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_presenter.dart';
import 'package:transit_card_analyzer/features/trips/trip_filters.dart';
import 'package:transit_card_analyzer/features/trips/trip_journey_adapter.dart';
import 'package:transit_card_analyzer/features/trips/trip_presentation_context.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

void main() {
  test('大兴机场线50元消费按指定规则标注商务座且深圳11号线不推断', () {
    for (final (line, amount, consume, expected) in [
      ('大兴机场线', 5000, true, '商务座'),
      ('大兴机场线', 4999, true, null),
      ('大兴机场线', 15000, true, null),
      ('大兴机场线', 5000, false, null),
      ('11号线', 5000, true, null),
      ('首都机场线', 5000, true, null),
    ]) {
      final event = describeJourneyEvent(
        TransactionTripEntry(
          _trip(status: '出站', amount: amount, consume: consume),
        ),
        _display(),
        _info(line: line),
      );
      expect(event.seatLabel, expected, reason: '$line/$amount/$consume');
    }
  });

  test('大兴机场线商务座同样适用于独立1A出站和1E消费且不把港币当人民币', () {
    final rail = RailRecordEntry(_rail(exitAmount: 5000), isEntry: false);
    final process = ProcessTripEntry(_cycle(type: 4, amount: 5000));
    for (final entry in [rail, process]) {
      final known = describeJourneyEvent(
        entry,
        _display(),
        _info(line: '大兴机场线'),
      );
      expect(known.seatLabel, '商务座');
      final hkd = describeJourneyEvent(
        entry,
        _display(currency: Currency.hkd),
        _info(line: '大兴机场线'),
      );
      expect(hkd.seatLabel, isNull);
      expect(known.balanceAfterText, isNull);
    }
  });

  test('行程余额仅来自明确的交易后余额且零余额有效', () {
    for (final (balance, recorded, expected) in [
      (11850, false, '¥118.50'),
      (0, false, '¥0.00'),
      (11850, true, null),
      (11850, null, null),
      (null, false, null),
    ]) {
      final event = describeJourneyEvent(
        TransactionTripEntry(
          _trip(status: '出站', balance: balance, recorded: recorded),
        ),
        _display(),
        _info(),
      );
      expect(event.balanceAfterText, expected);
    }
    final process = describeJourneyEvent(
      ProcessTripEntry(_cycle(type: 4)),
      _display(),
      _info(),
    );
    expect(process.balanceAfterText, isNull);
  });

  test('已解码数字公交线路显示路字且不改原始详情', () {
    final info = _info(line: '345');
    final event = describeJourneyEvent(
      ProcessTripEntry(_cycle(type: 3, app: 2)),
      _display(busLine: '345'),
      info,
    );
    expect(event.endpoint.line, '345路');
    expect(event.payload.line, '345');
    expect(event.endpoint.station, '站点10');
  });

  test('未匹配的公交原码不会添加路字或丢失前导零', () {
    final event = describeJourneyEvent(
      ProcessTripEntry(_cycle(type: 3, app: 2)),
      _display(),
      _info(line: '0010'),
    );
    expect(event.endpoint.line, '0010');
  });

  test('交易仅格式化有解码来源的公交线路', () {
    for (final decoded in [null, '345']) {
      final event = describeJourneyEvent(
        TransactionTripEntry(_trip(app: '公共汽电车', busLine: decoded)),
        _display(),
        _info(line: decoded ?? '0010'),
      );
      expect(event.endpoint.line, decoded == null ? '0010' : '345路');
    }
    expect(formatJourneyBusLine('快速公交1线'), '快速公交1线');
    expect(formatJourneyBusLine('821支'), '821支');
    expect(formatJourneyBusLine('0010'), '0010');
  });

  test('调用者已核实的原始槽位转交行程投影且交易序号独立保留', () {
    final positions = {'live': 17};
    final process = describeJourneyEvent(
      ProcessTripEntry(_cycle(type: 3)),
      _display(),
      _info(),
      processPositions: positions,
    );
    expect(process.processPositions, positions);
    expect(process.sequence, isNull);
    final transaction = describeJourneyEvent(
      TransactionTripEntry(_trip(status: '进站')),
      _display(),
      _info(),
      processPositions: positions,
    );
    expect(transaction.processPositions, positions);
    expect(transaction.sequence, 42);
  });

  test('交易使用明确状态与自身城市站点并保持原详情', () {
    final info = _info();
    final result = describeJourneyEvent(
      TransactionTripEntry(_trip(status: '出站', cityName: '上海市')),
      _display(),
      info,
      applicationRecordId: 'provided-record',
    );
    expect(result.role, JourneyEventRole.exit);
    expect(result.mode, TripModeFilter.rail);
    expect(result.cityLabel, '上海');
    expect(result.cityCode, '3100');
    expect(result.sequence, 42);
    expect(result.endpoint.line, '信息线路');
    expect(result.endpoint.station, '原始站名');
    expect(result.endpoint.timeText, '08:01:02');
    expect(result.applicationRecordId, 'provided-record');
    expect(identical(result.payload, info), isTrue);
  });

  test('零金额及isEntry默认false不产生进出站角色', () {
    final result = describeJourneyEvent(
      TransactionTripEntry(_trip(amount: 0, station: null)),
      _display(),
      _info(amount: '-¥0.00'),
    );
    expect(result.role, JourneyEventRole.unknown);
    expect(result.endpoint.station, isNull);
  });

  test('已解析的isEntry标志可表达明确入站', () {
    final result = describeJourneyEvent(
      TransactionTripEntry(_trip(isEntry: true)),
      _display(),
      _info(),
    );
    expect(result.role, JourneyEventRole.entry);
  });

  test('上海推断来源不替代已有的rideStatusName角色', () {
    final result = describeJourneyEvent(
      TransactionTripEntry(
        _trip(status: '进站', statusSource: 'shanghai-cu-ledger-inference'),
      ),
      _display(),
      _info(),
    );
    expect(result.role, JourneyEventRole.entry);
  });

  test('配对1E类型能补交易角色但不改变其序号', () {
    final result = describeJourneyEvent(
      TransactionTripEntry(_trip(process: _cycle(type: 3))),
      _display(),
      _info(),
    );
    expect(result.role, JourneyEventRole.entry);
    expect(result.sequence, 42);
  });

  test('已识别公交消费无进出规则时为单次消费', () {
    final result = describeJourneyEvent(
      TransactionTripEntry(_trip(app: '公共汽电车', station: '0000')),
      _display(),
      _info(line: '100'),
    );
    expect(result.mode, TripModeFilter.bus);
    expect(result.role, JourneyEventRole.single);
    expect(result.endpoint.line, '100');
    expect(result.endpoint.station, isNull);
  });

  test('公交充值不得误作单次乘车', () {
    final result = describeJourneyEvent(
      TransactionTripEntry(_trip(app: '公共汽电车', consume: false)),
      _display(),
      _info(),
    );
    expect(result.role, JourneyEventRole.unknown);
  });

  test('站点表识别为公交时同样可保留单次方式', () {
    final result = describeJourneyEvent(
      TransactionTripEntry(_trip(app: null, stationType: '公交')),
      _display(),
      _info(),
    );
    expect(result.mode, TripModeFilter.bus);
    expect(result.role, JourneyEventRole.single);
  });

  test('来源证明的行业例外按公交方式展示', () {
    final record = _cycle(type: 6, app: 1, city: '1380');
    final process = describeJourneyEvent(
      ProcessTripEntry(record),
      _display(),
      _info(),
    );
    final transaction = describeJourneyEvent(
      TransactionTripEntry(_trip(process: record)),
      _display(),
      _info(),
    );
    expect(process.mode, TripModeFilter.bus);
    expect(process.role, JourneyEventRole.single);
    expect(transaction.mode, TripModeFilter.bus);
    expect(transaction.role, JourneyEventRole.single);
  });

  for (final (type, expected) in const [
    (1, JourneyEventRole.entry),
    (2, JourneyEventRole.exit),
    (3, JourneyEventRole.entry),
    (4, JourneyEventRole.exit),
    (5, JourneyEventRole.single),
    (6, JourneyEventRole.single),
    (9, JourneyEventRole.unknown),
    (0xFE, JourneyEventRole.unknown),
  ]) {
    test('公交过程类型$type映射明确角色且无交易序号', () {
      final result = describeJourneyEvent(
        ProcessTripEntry(_cycle(type: type, app: 2)),
        _display(),
        _info(),
      );
      expect(result.role, expected);
      expect(result.sequence, isNull);
    });
  }

  test('同一轨道记录两端共享对象身份且独立解析站点时间', () {
    final record = _rail();
    final start = describeJourneyEvent(
      RailRecordEntry(record, isEntry: true),
      _display(),
      _info(line: '1号线'),
    );
    final end = describeJourneyEvent(
      RailRecordEntry(record, isEntry: false),
      _display(),
      _info(line: '2号线'),
    );
    expect(start.role, JourneyEventRole.entry);
    expect(end.role, JourneyEventRole.exit);
    expect(start.applicationRecordId, isNotNull);
    expect(end.applicationRecordId, start.applicationRecordId);
    expect(start.endpoint.station, '查询进站');
    expect(end.endpoint.station, '查询出站');
    expect(start.endpoint.time, DateTime(2026, 10, 27, 8));
    expect(end.endpoint.time, DateTime(2026, 10, 27, 8, 30));
    expect(start.sequence, isNull);
    expect(end.sequence, isNull);
  });

  test('两个不同轨道对象不能仅因字段相同共享应用身份', () {
    final a = describeJourneyEvent(
      RailRecordEntry(_rail(), isEntry: true),
      _display(),
      _info(),
    );
    final b = describeJourneyEvent(
      RailRecordEntry(_rail(), isEntry: false),
      _display(),
      _info(),
    );
    expect(a.applicationRecordId, isNotNull);
    expect(b.applicationRecordId, isNot(a.applicationRecordId));
  });

  test('轨道进闸状态的旧出站侧保留详情但禁止配对', () {
    final info = _info();
    final result = describeJourneyEvent(
      RailRecordEntry(_rail(status: 1), isEntry: false),
      _display(),
      info,
      applicationRecordId: 'supplied-pair',
    );
    expect(result.role, JourneyEventRole.unknown);
    expect(result.applicationRecordId, isNull);
    expect(identical(result.payload, info), isTrue);
  });

  test('无时间的1A侧保持未知而不使用TripEntry的公元0年兜底', () {
    final result = describeJourneyEvent(
      const RailRecordEntry(TransitRecord(statusCode: 0), isEntry: false),
      _display(),
      _info(),
    );
    expect(result.endpoint.time, isNull);
    expect(result.endpoint.timeText, isNull);
    expect(result.endpoint.station, isNull);
    expect(result.role, JourneyEventRole.unknown);
    expect(result.applicationRecordId, isNull);
  });

  test('公交原始十六进制站号以站点号呈现且保留前导零证据', () {
    final info = _info();
    final record = BusTransitRecord(
      statusCode: 0,
      entryCityCode: '1000',
      entryLineCode: '0001',
      entryStationCode: '0A',
      entryOperatorCode: '0001',
      entryTime: DateTime(2026, 10, 27, 8),
    );
    final result = describeJourneyEvent(
      BusRecordEntry(record, isEntry: true),
      _display(busStation: null),
      info,
    );
    expect(result.mode, TripModeFilter.bus);
    expect(result.role, JourneyEventRole.entry);
    expect(result.endpoint.station, '站点10');
    expect(result.payload.fields, contains(('站点原码', '000A')));
  });

  test('已有公交第N站文本转为站点号且真实站名保持原样', () {
    final ordinal = describeJourneyEvent(
      ProcessTripEntry(_cycle(type: 2, app: 2)),
      _display(busStation: '第10站'),
      _info(),
    );
    final named = describeJourneyEvent(
      ProcessTripEntry(_cycle(type: 2, app: 2)),
      _display(busStation: '北京站东'),
      _info(),
    );
    expect(ordinal.endpoint.station, '站点10');
    expect(named.endpoint.station, '北京站东');
  });

  test('未解码1E站码0010保留原码而不按十六进制虚构站点16', () {
    final result = describeJourneyEvent(
      ProcessTripEntry(
        _cycle(type: 6, app: 2, lineStationCode: '00010010000100'),
      ),
      _display(busStation: null),
      _info(),
    );
    expect(result.endpoint.station, '站点0010');
  });

  test('未匹配交易公交站码保留前导零且不冒充十六进制站序', () {
    final result = describeJourneyEvent(
      TransactionTripEntry(_trip(app: '公共汽电车', station: '0010')),
      _display(busStation: null),
      _info(),
    );
    expect(result.endpoint.station, '站点0010');
  });

  test('轨道站码000F不被误作全零或全FF占位', () {
    final result = describeJourneyEvent(
      TransactionTripEntry(_trip(station: '000F')),
      _display(),
      _info(),
    );
    expect(result.endpoint.station, '000F');
  });

  test('公交两半以各自时间与同一对象身份适配', () {
    final record = BusTransitRecord(
      statusCode: 0,
      entryCityCode: '1000',
      exitCityCode: '1000',
      entryTime: DateTime(2026, 10, 27, 8),
      exitTime: DateTime(2026, 10, 27, 9),
    );
    final start = describeJourneyEvent(
      BusRecordEntry(record, isEntry: true),
      _display(),
      _info(),
    );
    final end = describeJourneyEvent(
      BusRecordEntry(record, isEntry: false),
      _display(),
      _info(),
    );
    expect(start.applicationRecordId, isNotNull);
    expect(end.applicationRecordId, start.applicationRecordId);
    expect(end.role, JourneyEventRole.exit);
    expect(end.endpoint.timeText, '09:00:00');
  });

  test('高额机场交易没有席别来源时不补普通座或商务座', () {
    final result = describeJourneyEvent(
      TransactionTripEntry(_trip(status: '出站', amount: 15000)),
      _display(),
      _info(line: '大兴机场线', amount: '-¥150.00'),
    );
    expect(result.seatLabel, isNull);
    expect(result.amountText, '-¥150.00');
  });

  test('范围包含当前币种且来源为本次读取', () {
    final result = describeJourneyEvent(
      TransactionTripEntry(_trip()),
      _display(currency: Currency.hkd),
      _info(),
    );
    expect(result.scopeKey, 'live:TU:HKD');
    expect(result.sourceIds, {'live'});
  });
}

TripEntryInfo _info({String? line = '信息线路', String? amount = '-¥7.00'}) =>
    TripEntryInfo(
      sourceLabel: '原始来源',
      title: '原始条目',
      isConsume: true,
      line: line,
      amountText: amount,
      fields: const [('站点原码', '000A')],
    );

TransitTrip _trip({
  String? status,
  String? statusSource,
  String? cityName,
  int amount = 700,
  String? station = '原始站名',
  bool isEntry = false,
  bool consume = true,
  String? app = '城市轨道交通',
  String? stationType,
  TUnionTripRecord? process,
  String? busLine,
  int? balance,
  bool? recorded,
}) => TransitTrip(
  time: DateTime(2026, 10, 27, 8, 1, 2),
  amountFen: amount,
  overdraftLimitFen: 0,
  isConsume: consume,
  typeName: consume ? '消费' : '充值',
  sequence: 42,
  terminalId: '000000000001',
  cityCode: '3100',
  cityName: cityName,
  stationLabel: station,
  appTypeName: app,
  stationType: stationType,
  isEntry: isEntry,
  rideStatusName: status,
  rideStatusSource: statusSource,
  matchedProcessTrip: process,
  resolvedBusLineLabel: busLine,
  balanceAfterFen: balance,
  balanceAfterIsRecorded: recorded,
);

TUnionTripRecord _cycle({
  required int type,
  int app = 1,
  String city = '3100',
  String lineStationCode = '0001000A000100',
  int amount = 100,
}) => TUnionTripRecord(
  typeCode: type,
  appTypeCode: app,
  terminalId: '0000000000000001',
  lineStationCode: lineStationCode,
  amountFen: amount,
  balanceFen: 10000,
  time: DateTime(2026, 10, 27, 8),
  cityCode: city,
);

TransitRecord _rail({int status = 2, int? exitAmount}) => TransitRecord(
  statusCode: status,
  entryCityCode: '3100',
  exitCityCode: '3100',
  entryStationId: '0000000000000001',
  exitStationId: '0000000000000002',
  entryLineCode: 1,
  exitLineCode: 2,
  exitAmountFen: exitAmount,
  entryTime: DateTime(2026, 10, 27, 8),
  exitTime: DateTime(2026, 10, 27, 8, 30),
);

TripPresentationContext _display({
  Currency currency = Currency.cny,
  String? busStation = '第10站',
  String? busLine,
}) => TripPresentationContext(
  currency: currency,
  cityNameOf: (code) => switch (code) {
    '3100' => '上海市',
    '1000' => '北京市',
    _ => null,
  },
  resolveStationMatch: (city, code, {int? lineValue}) => switch (code) {
    '0000000000000001' => _match('查询进站'),
    '0000000000000002' => _match('查询出站'),
    _ => StationMatch.unmatched,
  },
  resolveCycleStationMatch: (
    city,
    field, {
    String? terminalId,
    DateTime? time,
    int? appType,
  }) => _match('查询过程站'),
  resolveLineName: (city, code) => null,
  resolveBusLocation: (
    city,
    field, {
    TunionBusDecodeContext context = const TunionBusDecodeContext(),
  }) => TunionBusLocation(lineLabel: busLine, stationLabel: busStation),
);

StationMatch _match(String station) => StationMatch(
  StationCodeEntry(code: '001', station: station),
  StationMatchConfidence.exact,
);
