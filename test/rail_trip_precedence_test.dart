import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/domain/archive_context.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

const _terminal = '0000300089000340';
final _entryTime = DateTime(2026, 8, 8, 9, 6, 2);
final _exitTime = DateTime(2026, 8, 8, 9, 12, 31);

void main() {
  group('行程流：1A + 1E + 18', () {
    test('整条 1A 与已关联 1E 隐藏，18+1E 作为最终行程', () {
      final process = _process();
      final rail = _rail();
      final stream = buildTripStream(
        trips: [_trip(process)],
        rails: [rail],
        processTrips: [process],
      );
      expect(stream, hasLength(1));
      final trip = stream.single as TransactionTripEntry;
      expect(trip.trip.matchedProcessTrip, same(process));
      expect(stream.whereType<RailRecordEntry>(), isEmpty);
      expect(stream.whereType<ProcessTripEntry>(), isEmpty);
    });

    test('仅出站侧与 1E 对应时，进站侧也随整条 1A 隐藏', () {
      final process = _process();
      final stream = buildTripStream(
        trips: [_trip(process)],
        rails: [_rail(entryTime: DateTime(2026, 8, 8, 8, 0))],
        processTrips: [process],
      );
      expect(stream.whereType<RailRecordEntry>(), isEmpty);
      expect(stream.whereType<TransactionTripEntry>(), hasLength(1));
    });

    test('未与 18 关联的 1E 保留展示，1A 隐藏', () {
      final process = _process();
      final unrelatedProcess = _process(
        time: DateTime(2026, 8, 8, 9, 30),
        terminalId: '000000000000000C',
        rawHex: '1E02',
      );
      final unrelatedRail = _rail(
        entryTime: DateTime(2026, 8, 8, 9, 20),
        exitTime: DateTime(2026, 8, 8, 9, 30),
        exitTerminalId: '000000000000000C',
        rawHex: '1A02',
      );
      final stream = buildTripStream(
        trips: [_trip(process)],
        rails: [_rail(), unrelatedRail],
        processTrips: [process, unrelatedProcess],
      );
      expect(stream.whereType<TransactionTripEntry>(), hasLength(1));
      expect(
        stream.whereType<RailRecordEntry>().where(
          (entry) => identical(entry.record, unrelatedRail),
        ),
        isEmpty,
      );
      expect(stream.whereType<ProcessTripEntry>(), hasLength(1));
    });

    test('关联 1E 为公交行业时同样隐藏轨道 1A', () {
      final process = _process(appTypeCode: 0x02, rawHex: '1E03');
      final rail = _rail();
      final stream = buildTripStream(
        trips: [_trip(process, composite: false)],
        rails: [rail],
        processTrips: [process],
      );
      expect(stream.whereType<RailRecordEntry>(), isEmpty);
      expect(stream.whereType<ProcessTripEntry>(), isEmpty);
    });
  });

  test('仅 1A 保留，任意行业独立或已并入 18 的 1E 隐藏两种 1A', () {
    final rails = [_rail()];
    final buses = [
      BusTransitRecord(
        statusCode: 2,
        entryTime: _entryTime,
        exitTime: _exitTime,
      ),
    ];
    expect(
      buildTripStream(trips: [], rails: rails, buses: buses),
      hasLength(4),
    );
    for (final industry in [1, 2, 99]) {
      final process = _process(appTypeCode: industry);
      for (final linked in [false, true]) {
        final stream = buildTripStream(
          trips: linked ? [_trip(process)] : [],
          processTrips: linked ? [] : [process],
          rails: rails,
          buses: buses,
        );
        expect(stream, hasLength(1));
        expect(stream.whereType<RailRecordEntry>(), isEmpty);
        expect(stream.whereType<BusRecordEntry>(), isEmpty);
      }
    }
    expect(rails, hasLength(1));
    expect(buses, hasLength(1));
  });

  group('卡片历史：1A + 1E + 18', () {
    for (final linked in [false, true]) {
      test('按来源批次隐藏，保留跨批次及未知来源 1A（linked=$linked）', () {
        final process = _processJson(_process(appTypeCode: 2));
        final records = [
          _record(
            linked ? ArchiveRecordKind.transaction : ArchiveRecordKind.process,
            linked ? _transactionFields(process) : process,
            batches: ['with-1e'],
          ),
          for (final kind in [ArchiveRecordKind.rail, ArchiveRecordKind.bus])
            for (final batches in [
              <String>['with-1e'],
              <String>['only-1a'],
              <String>['with-1e', 'only-1a'],
              <String>[],
            ])
              _record(kind, _railJson(_rail()), batches: batches),
        ];
        final projection = presentArchiveTrips(records, onDiagnostics: (_) {});
        for (final kind in [ArchiveRecordKind.rail, ArchiveRecordKind.bus]) {
          expect(
            projection.entries.where((entry) => entry.source == kind),
            hasLength(6),
          );
        }
        expect(records, hasLength(9)); // 原始证据未删除
        expect(projection.mergedRecordCount, 0); // 隐藏不冒称已关联 18
      });
    }

    test('无效过程字段不隐藏 1A', () {
      final projection = presentArchiveTrips([
        _record(ArchiveRecordKind.process, {'rawHex': '0000'}),
        _record(
          ArchiveRecordKind.transaction,
          _transactionFields({'rawHex': 'FFFF'}),
        ),
        _record(ArchiveRecordKind.rail, _railJson(_rail())),
      ], onDiagnostics: (_) {});
      expect(
        projection.entries.where(
          (entry) => entry.source == ArchiveRecordKind.rail,
        ),
        hasLength(2),
      );
    });
    test('同批次所有 1A 隐藏，仅关联 1E 并入 18', () {
      final process = _process();
      final unrelatedProcess = _process(
        time: DateTime(2026, 8, 8, 9, 30),
        terminalId: '000000000000000C',
        rawHex: '1E02',
      );
      final records = [
        _record(
          ArchiveRecordKind.transaction,
          _transactionFields(_processJson(process)),
        ),
        _record(ArchiveRecordKind.rail, _railJson(_rail())),
        _record(
          ArchiveRecordKind.rail,
          _railJson(
            _rail(
              entryTime: DateTime(2026, 8, 8, 9, 20),
              exitTime: DateTime(2026, 8, 8, 9, 30),
              exitTerminalId: '000000000000000C',
              rawHex: '1A02',
            ),
          ),
        ),
        _record(ArchiveRecordKind.process, _processJson(process)),
        _record(ArchiveRecordKind.process, _processJson(unrelatedProcess)),
      ];
      final projection = presentArchiveTrips(records, onDiagnostics: (_) {});
      expect(
        projection.entries.where(
          (entry) => entry.source == ArchiveRecordKind.transaction,
        ),
        hasLength(1),
      );
      expect(
        projection.entries.where(
          (entry) => entry.source == ArchiveRecordKind.rail,
        ),
        isEmpty,
      );
      expect(
        projection.entries.where(
          (entry) => entry.source == ArchiveRecordKind.process,
        ),
        hasLength(1),
      );
      expect(projection.transactionCount, 1);
      expect(projection.processRecordCount, 1);
      expect(projection.mergedRecordCount, 1);
      expect(projection.summaryText, '交易 1 条 · 过程及应用记录 1 条（1 条已并入 0x18 交易）');
    });

    test('1A 与关联 1E 时间不匹配时仍隐藏 1A', () {
      final process = _process();
      final records = [
        _record(
          ArchiveRecordKind.transaction,
          _transactionFields(_processJson(process)),
        ),
        _record(
          ArchiveRecordKind.rail,
          _railJson(_rail(exitTime: DateTime(2026, 8, 8, 9, 13))),
        ),
        _record(ArchiveRecordKind.process, _processJson(process)),
      ];
      final projection = presentArchiveTrips(records, onDiagnostics: (_) {});
      expect(projection.entries, hasLength(1)); // 仅 18，1A 无需关联
      expect(projection.processRecordCount, 0);
      expect(projection.mergedRecordCount, 1); // 已关联 1E 并入 18
    });
  });
}

TUnionTripRecord _process({
  int typeCode = 0x04,
  int appTypeCode = 0x01,
  String terminalId = _terminal,
  DateTime? time,
  String? rawHex = '1E01',
}) => TUnionTripRecord(
  typeCode: typeCode,
  terminalId: terminalId,
  appTypeCode: appTypeCode,
  lineStationCode: '02310000000000',
  amountFen: 300,
  balanceFen: 2200,
  time: time ?? _exitTime,
  cityCode: '3501',
  rawHex: rawHex,
);

TransitRecord _rail({
  DateTime? entryTime,
  DateTime? exitTime,
  String exitTerminalId = _terminal,
  String? rawHex = '1A01',
}) => TransitRecord(
  statusCode: 2,
  entryCityCode: '3501',
  exitCityCode: '3501',
  entryTerminalId: '000000000000000A',
  exitTerminalId: exitTerminalId,
  entryTime: entryTime ?? _entryTime,
  exitTime: exitTime ?? _exitTime,
  entryAmountFen: 0,
  exitAmountFen: 300,
  rawHex: rawHex,
);

TransitTrip _trip(TUnionTripRecord process, {bool composite = true}) =>
    TransitTrip(
      time: process.time,
      amountFen: process.amountFen,
      overdraftLimitFen: 0,
      isConsume: true,
      typeName: composite ? '复合消费' : '消费',
      isCompositeConsume: composite,
      sequence: 1,
      terminalId: process.terminalId,
      appTypeName: '城市轨道交通',
      matchedProcessTrip: process,
      currency: Currency.cny,
    );

Map<String, dynamic> _processJson(TUnionTripRecord process) => {
  'typeCode': process.typeCode,
  'terminalId': process.terminalId,
  'appTypeCode': process.appTypeCode,
  'lineStationCode': process.lineStationCode,
  'amountFen': process.amountFen,
  'balanceFen': process.balanceFen,
  'time': process.time.millisecondsSinceEpoch,
  'cityCode': process.cityCode,
  'acquirerId': process.acquirerId,
  'rawHex': process.rawHex,
};

Map<String, dynamic> _railJson(TransitRecord rail) => {
  'status': rail.statusCode,
  'entryCityCode': rail.entryCityCode,
  'exitCityCode': rail.exitCityCode,
  'entryTerminalId': rail.entryTerminalId,
  'exitTerminalId': rail.exitTerminalId,
  'entryTime': rail.entryTime?.millisecondsSinceEpoch,
  'exitTime': rail.exitTime?.millisecondsSinceEpoch,
  'entryAmountFen': rail.entryAmountFen,
  'exitAmountFen': rail.exitAmountFen,
  'rawHex': rail.rawHex,
};

Map<String, dynamic> _transactionFields(Map<String, dynamic> process) => {
  'time': process['time'],
  'amountFen': process['amountFen'],
  'consume': true,
  'composite': true,
  'typeName': '复合消费',
  'sequence': 1,
  'terminalId': process['terminalId'],
  'appTypeName': '城市轨道交通',
  'balanceAfterFen': process['balanceFen'],
  'matchedProcess': process,
};

ArchiveHistoryRecord _record(
  ArchiveRecordKind kind,
  Map<String, dynamic> fields, {
  List<String> batches = const ['same-read'],
}) => ArchiveHistoryRecord(
  kind: kind,
  fields: fields,
  context: const ArchiveContext(currencyCode: 'CNY', minorUnitDigits: 2),
  cardCityCode: '3501',
  sources: [
    for (final batch in batches) ArchiveRecordSource(batch, 'test', 6, null),
  ],
);
