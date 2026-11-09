import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/domain/archive_context.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';

void main() {
  for (final kind in [
    ArchiveRecordKind.process,
    ArchiveRecordKind.transaction,
  ]) {
    test('$kind卡片与详情统一优先使用捕获城市名且保留原始字段', () {
      final record = _record(kind, {
        'cityCode': '2500',
        'cityName': '旧城市名',
        'capturedDisplay': {
          'cityName': ' 济南市 ',
          'locationCityCode': '1000',
          'locationCityName': '北京市',
        },
      });
      final original = jsonEncode(record.fields);
      final entry = _project(record).entries.single;
      expect(entry.journeyEvent!.cityLabel, '济南');
      expect(entry.info.remoteCityText, '济南市（2500）');
      expect(entry.journeyEvent!.endpoint.locationCityLabel, '北京');
      expect(jsonEncode(record.fields), original);
    });

    for (final captured in [null, '', '   ']) {
      test('$kind捕获城市名为$captured时兼容旧顶层城市名', () {
        final entry = _project(
          _record(kind, {
            'cityCode': '2500',
            'cityName': '济南市',
            'capturedDisplay': {'cityName': captured},
          }),
        ).entries.single;
        expect(entry.info.remoteCityText, '济南市（2500）');
        expect(entry.journeyEvent!.cityLabel, '济南');
      });
    }

    test('$kind缺失城市名时不借用站点所属城市', () {
      final entry = _project(
        _record(kind, {
          'cityCode': '9999',
          'capturedDisplay': {
            'cityName': ' ',
            'locationCityCode': '1000',
            'locationCityName': '北京市',
          },
        }),
      ).entries.single;
      expect(entry.info.remoteCityText, '未知城市（9999）');
      expect(entry.journeyEvent!.cityLabel, isNull);
    });

    for (final city in [null, '', '0000', 'FFFF', '3910']) {
      test('$kind城市码$city不能判定异地时不附加受理城市提示', () {
        final entry = _project(
          _record(kind, {
            'cityCode': city,
            'capturedDisplay': {'cityName': '已保存城市'},
          }),
        ).entries.single;
        expect(entry.remote, isFalse);
        expect(entry.info.remoteCityText, isNull);
      });
    }
  }

  for (final kind in [ArchiveRecordKind.rail, ArchiveRecordKind.bus]) {
    for (final captured in [true, false]) {
      test('$kind两端按各自${captured ? '捕获' : '旧字段'}城市名展示详情', () {
        final record = _record(kind, {
          'entryCityCode': '1000',
          'exitCityCode': '2500',
          // A shared root name is not evidence for either endpoint.
          'cityName': '不属于任一端的城市',
          'entryCityName': captured ? '旧进入城市' : '北京市',
          'exitCityName': captured ? '旧离开城市' : '济南市',
          if (captured)
            'capturedDisplay': {
              'entry': {'cityName': '北京市'},
              'exit': {'cityName': '济南市'},
            },
        });
        final original = jsonEncode(record.fields);
        final events = _project(record).entries.map((e) => e.journeyEvent!);
        final entry = events.singleWhere(
          (e) => e.role == JourneyEventRole.entry,
        );
        final exit = events.singleWhere((e) => e.role == JourneyEventRole.exit);
        expect(entry.cityLabel, '北京');
        expect(entry.payload.remoteCityText, '北京市（1000）');
        expect(exit.cityLabel, '济南');
        expect(exit.payload.remoteCityText, '济南市（2500）');
        expect(jsonEncode(record.fields), original);
      });
    }

    test('$kind同城一端不显示异地另一端保留自己的城市名', () {
      final record = _record(kind, {
        'entryCityCode': '3910',
        'exitCityCode': '2500',
        'capturedDisplay': {
          'entry': {'cityName': '福州市'},
          'exit': {'cityName': '济南市'},
        },
      });
      final events = _project(record).entries.map((e) => e.journeyEvent!);
      expect(
        events
            .singleWhere((e) => e.role == JourneyEventRole.entry)
            .payload
            .remoteCityText,
        isNull,
      );
      expect(
        events
            .singleWhere((e) => e.role == JourneyEventRole.exit)
            .payload
            .remoteCityText,
        '济南市（2500）',
      );
    });

    test('$kind缺少本端城市名时不借用共享或另一端名称', () {
      final record = _record(kind, {
        'entryCityCode': '1000',
        'exitCityCode': '9999',
        'cityName': '共享旧名称',
        'capturedDisplay': {
          'entry': {'cityName': '北京市'},
          'exit': {'locationCityName': '北京市'},
        },
      });
      final exit = _project(record).entries
          .singleWhere((e) => e.journeyEvent!.role == JourneyEventRole.exit);
      expect(exit.info.remoteCityText, '未知城市（9999）');
      expect(exit.journeyEvent!.cityLabel, isNull);
    });
  }
}

ArchiveTripProjection _project(ArchiveHistoryRecord record) =>
    presentArchiveTrips([record], onDiagnostics: (_) {});

ArchiveHistoryRecord _record(
  ArchiveRecordKind kind,
  Map<String, dynamic> fields,
) => ArchiveHistoryRecord(
  kind: kind,
  cardCityCode: '3910',
  context: const ArchiveContext(
    systemId: 'tunion',
    applicationId: 'A000000632010105',
    currencyCode: 'CNY',
    minorUnitDigits: 2,
  ),
  fields: {
    'time': 1792972800000,
    'amountFen': 100,
    'terminalId': '0000000000000001',
    'rawHex': 'ABCD',
    if (kind == ArchiveRecordKind.process) ...{
      'typeCode': 6,
      'appTypeCode': 2,
      'lineStationCode': '0001000A000100',
      'balanceFen': 9000,
    },
    if (kind == ArchiveRecordKind.transaction) ...{
      'sequence': 1,
      'typeName': '消费',
      'consume': true,
      'appTypeName': '公共汽电车',
    },
    if (kind == ArchiveRecordKind.rail || kind == ArchiveRecordKind.bus) ...{
      'status': 2,
      'entryTime': 1792972800000,
      'exitTime': 1792974600000,
    },
    ...fields,
  },
  sources: const [ArchiveRecordSource('city-context', 'record[0]', 15, null)],
);
