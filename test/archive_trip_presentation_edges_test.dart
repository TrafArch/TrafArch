import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/domain/archive_context.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';

void main() {
  test('重庆旧公交交易用受理城市和线路识别设施，保留原始线路字段', () {
    for (final (line, name, mode) in [
      ('701', '长江索道', '索道'),
      ('0703', '凯旋路电梯', '电梯'),
      ('704', '皇冠大扶梯', '扶梯'),
    ]) {
      final entry = presentArchiveTrips([
        ArchiveHistoryRecord(
          kind: ArchiveRecordKind.transaction,
          cardCityCode: '5810',
          context: const ArchiveContext(
            currencyCode: 'CNY',
            minorUnitDigits: 2,
          ),
          fields: {
            'time': 1,
            'sequence': 1,
            'consume': true,
            'amountFen': 100,
            'cityCode': '6900',
            'appTypeName': '公共汽电车',
            'lineLabel': line,
            'rideStatusName': '单次消费',
          },
          sources: const [],
        ),
      ]).entries.single;
      expect(entry.info.title, name);
      expect(entry.info.category, mode);
      expect(entry.info.fields, contains(('线路', line)));
    }
  });

  test('同号轨道、充值及仅由发卡城市指向重庆的记录保留原交易分类', () {
    for (final (city, app, type, line) in [
      ('6900', '城市轨道交通', '复合消费', '703'),
      ('6900', '公共汽电车', '充值', '704'),
      ('5810', '公共汽电车', '复合消费', '701'),
      (null, '公共汽电车', '复合消费', '701'),
      ('6900', '公共汽电车', '复合消费', '702'),
      ('6900', null, '复合消费', '704'),
    ]) {
      final info = presentArchiveTrips([
        ArchiveHistoryRecord(
          kind: ArchiveRecordKind.transaction,
          cardCityCode: '6900',
          context: const ArchiveContext(),
          fields: {
            'time': 1,
            'sequence': 1,
            'consume': type != '充值',
            'amountFen': 100,
            'typeName': type,
            'cityCode': city,
            'appTypeName': app,
            'stationType': '公交',
            'lineLabel': line,
          },
          sources: const [],
        ),
      ]).entries.single.info;
      expect(info.category, type == '充值' ? isNull : app ?? '公共汽电车');
      expect(info.facility, isNull);
    }
  });

  test('空类型名的合法旧交易仍可展示', () {
    final entries = presentArchiveTrips([
      const ArchiveHistoryRecord(
        kind: ArchiveRecordKind.transaction,
        context: ArchiveContext(currencyCode: 'CNY', minorUnitDigits: 2),
        fields: {
          'time': 1,
          'sequence': 1,
          'consume': true,
          'amountFen': 100,
          'terminalId': '',
          'typeName': '',
        },
        sources: [],
      ),
    ], onDiagnostics: (_) {});
    expect(entries.entries.single.info.title, '其他 · 序号 1');
  });

  test('重庆公交设施必须与本笔交易受理城市相符', () {
    final projection = presentArchiveTrips([
      const ArchiveHistoryRecord(
        kind: ArchiveRecordKind.transaction,
        context: ArchiveContext(),
        fields: {
          'time': 1,
          'sequence': 1,
          'consume': true,
          'cityCode': '5810',
          'appTypeName': '公共汽电车',
          'matchedProcess': {
            'cityCode': '6900',
            'typeCode': 6,
            'appTypeCode': 2,
            'lineStationCode': '07040000000000',
            'amountFen': 200,
            'balanceFen': 0,
            'time': 1,
            'terminalId': '',
          },
        },
        sources: [],
      ),
    ]);
    expect(projection.entries.single.info.facility, isNull);
  });

  test('0x1A零值及未知扩展不虚构进出站事件', () {
    final entries = presentArchiveTrips([
      const ArchiveHistoryRecord(
        kind: ArchiveRecordKind.rail,
        context: ArchiveContext(),
        fields: {
          'status': 0,
          'entryTime': null,
          'exitTime': null,
          'entryAmountFen': 0,
          'exitAmountFen': 0,
          'entryStationId': '0000',
          'exitFutureFlag': 'future-extension',
        },
        sources: [],
      ),
    ], onDiagnostics: (_) {});
    expect(entries.entries, hasLength(1));
    expect(entries.entries.single.dateText, '日期未知');
    expect(entries.entries.single.info.title, isNot('进站'));
    expect(entries.entries.single.info.title, isNot('出站'));
  });
}
