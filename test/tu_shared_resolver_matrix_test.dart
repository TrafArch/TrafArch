import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tu_region_live_source.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tu_station_repository.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/station_codes.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/tu_cycle_station_resolver.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/tu_lookup_service.dart';

// Exercise the product's shared live/archive resolver with literal expectations,
// rather than constructing an expected answer from the asset being queried.
// The first thirteen vectors are the source-checked constants already recorded
// in tu_lookup_service_test.dart. Chongqing fields/names are frozen in
// chongqing_read_window_regression_test.dart and chongqing_station_completion_test.dart.
// Tianjin's two existing-line keys were independently checked in M0.i0.a during
// the screenshot audit. All field length variants are synthetic layout probes;
// none claims to reconstruct a physical APDU or an entire city's station order.
void main() {
  late Database db;
  late TuStationRepository repository;
  late TuLookupService lookup;
  late StationCodeTable stations;

  setUpAll(() {
    db = sqlite3.open(
      'assets/data/TrafArch_Database_TU.sqlite',
      mode: OpenMode.readOnly,
    );
    repository = TuStationRepository(db);
    lookup = TuLookupService(repository);
    stations = StationCodeTable.empty.withLive(TuRegionLiveSource(repository));
  });
  tearDownAll(() => db.close());

  StationMatch resolve(_Vector vector, {String? field, int? appType = 1}) =>
      resolveTuCycleStation(
        stations: stations,
        lookup: lookup,
        cityCode: vector.city,
        field: field ?? vector.field,
        terminalId: vector.terminal,
        appType: appType,
      );

  for (final vector in _vectors) {
    test(
      'shared TU resolver ${vector.city}/${vector.key} preserves station and source',
      () {
        final rawValue = jsonEncode(['', vector.line, vector.station]);
        // The final byte is reserved. Querying the six-byte form must retain
        // the same source key, including zeros and hexadecimal letters.
        for (final field in [vector.field, vector.field.substring(0, 12)]) {
          final match = resolve(vector, field: field);
          final reason = '${vector.city}/$field/${vector.terminal}';
          // The developer database explicitly retains both line labels for
          // this same raw key. It must remain ambiguous, never pick the row
          // inserted last or silently discard either source.
          if (vector.city == '4520' && vector.key == '45201121') {
            expect(match.confidence, StationMatchConfidence.ambiguous);
            expect(match.candidates.map((e) => e.line).toSet(), {
              '11号线',
              '蓝谷快线',
            });
            expect(match.candidates.map((e) => e.station).toSet(), {'苗岭路'});
            expect(match.candidates.map((e) => e.sourceKey).toSet(), {
              '45201121',
            });
            expect(match.candidates.map((e) => e.sourceField).toSet(), {
              'M0.a0.a',
            });
            continue;
          }
          expect(
            match.confidence,
            StationMatchConfidence.exact,
            reason: reason,
          );
          expect(match.lineName, vector.line, reason: reason);
          expect(match.stationName, vector.station, reason: reason);
          expect(match.entry?.system, 'tu', reason: reason);
          expect(match.entry?.sourceKey, vector.key, reason: reason);
          expect(match.entry?.sourceField, vector.source, reason: reason);
          expect(match.entry?.rawValueJson, rawValue, reason: reason);
          expect(match.candidates.map((entry) => entry.sourceKey).toSet(), {
            vector.key,
          }, reason: reason);
          expect(
            match.evidence.any(
              (entry) =>
                  entry.sourceKey == vector.key &&
                  entry.sourceField == vector.source &&
                  entry.rawValueJson == rawValue,
            ),
            isTrue,
            reason: reason,
          );
        }
        expect(repository.queryIssue, isNull);
      },
    );
  }

  test(
    'shared TU resolver gives identical raw fields independent city meanings',
    () {
      const field = '00010101000000';
      final hefei = resolve(_vectors[3], field: field);
      final guiyang = resolve(_vectors[11], field: field);
      expect(hefei.stationName, '合肥火车站');
      expect(hefei.entry?.sourceKey, '361000010101');
      expect(hefei.entry?.sourceField, 'M0.W.a');
      expect(guiyang.stationName, '窦官');
      expect(guiyang.entry?.sourceKey, '70100101');
      expect(guiyang.entry?.sourceField, 'M0.e0.a');
    },
  );

  test(
    'shared TU resolver cannot borrow stations for missing or unknown cities',
    () {
      for (final city in <String?>[null, '', '0000', 'FFFF', '9999', '112']) {
        for (final vector in _vectors) {
          final match = resolveTuCycleStation(
            stations: stations,
            lookup: lookup,
            cityCode: city,
            field: vector.field,
            terminalId: vector.terminal,
            appType: 1,
          );
          expect(match.isUnmatched, isTrue, reason: '$city/${vector.field}');
          expect(match.lineName, isNull);
          expect(match.stationName, isNull);
          expect(match.candidates, isEmpty);
        }
      }
      expect(repository.queryIssue, isNull);
    },
  );

  test(
    'shared TU resolver rejects bus and unknown industry rail fallbacks',
    () {
      // These cities have no Beijing industry-00 exception. Even the exact
      // M0.S.a terminal must not bypass the application classification gate.
      for (final vector in _vectors) {
        for (final appType in <int?>[null, 0, 2, 0xFE]) {
          final match = resolve(vector, appType: appType);
          expect(
            match.isUnmatched,
            isTrue,
            reason: '${vector.city}/${vector.field}/$appType',
          );
          expect(match.stationName, isNull);
          expect(match.candidates, isEmpty);
        }
      }
      expect(repository.queryIssue, isNull);
    },
  );

  for (final (field, terminal, station) in const [
    ('00070018000000', '0000000007180605', '丽江道'),
    ('00070020000000', '0000000007200609', '天塔'),
  ]) {
    test(
      'Tianjin line 7 $field uses its developer city-table raw source key',
      () {
        final match = resolveTuCycleStation(
          stations: stations,
          lookup: lookup,
          cityCode: '1121',
          field: field,
          terminalId: terminal,
          appType: 1,
        );
        expect(match.isUnmatched, isFalse);
        expect(match.lineName, '7号线');
        expect(match.stationName, station);
        expect(match.entry?.sourceKey, field.substring(0, 8));
        expect(match.entry?.sourceField, 'M0.i0.a');
        expect(repository.queryIssue, isNull);
      },
    );
  }

  for (final field in const ['00990018000000', '00990020000000']) {
    test('unknown Tianjin line $field cannot borrow a shared station name', () {
      final match = resolveTuCycleStation(
        stations: stations,
        lookup: lookup,
        cityCode: '1121',
        field: field,
        terminalId: 'FFFFFFFFFFFFFFFF',
        appType: 1,
      );
      expect(match.isUnmatched, isTrue);
      expect(match.stationName, isNull);
      expect(match.candidates, isEmpty);
    });
  }

  const guangzhou12 = [
    '浔峰岗',
    '浔峰岗北',
    '西洲',
    '聚龙',
    '广州白云站',
    '棠涌',
    '新市墟',
    '白云文化广场',
    '广州体育馆',
  ];
  for (var i = 0; i < guangzhou12.length; i++) {
    final code = '001200${(i + 1).toString().padLeft(2, '0')}';
    test('Guangzhou raw key $code precedes numeric fragment fallback', () {
      final match = resolveTuCycleStation(
        stations: stations,
        lookup: lookup,
        cityCode: '5810',
        field: '${code}FFFF00',
        appType: 1,
      );
      expect(match.confidence, StationMatchConfidence.exact);
      expect(match.lineName, '12号线');
      expect(match.stationName, guangzhou12[i]);
      expect(match.entry?.sourceKey, '5810$code');
      expect(match.entry?.sourceField, 'M0.a0.a');
    });
  }
}

class _Vector {
  const _Vector(
    this.city,
    this.field,
    this.key,
    this.source,
    this.line,
    this.station, {
    this.terminal,
  });

  final String city;
  final String field;
  final String key;
  final String source;
  final String line;
  final String station;
  final String? terminal;
}

const _vectors = [
  _Vector('2220', '08010000000000', '22200801', 'M0.i0.a', '12号线', '河口'),
  _Vector('3040', '01030000000000', '30400103', 'M0.W.a', '1号线', '南夏墅'),
  _Vector('5510', '01000100000000', '5510010001', 'M0.a0.a', '1号线', '尚双塘'),
  _Vector('3610', '00010101000000', '361000010101', 'M0.W.a', '1号线', '合肥火车站'),
  _Vector('6020', '00020202000000', '602000020202', 'M0.e0.a', '2号线', '茶山'),
  _Vector('2210', '000A0403000000', '2210000A0403', 'M0.i0.a', '10号线', '塔湾街'),
  _Vector('6510', '00001021000000', '65101021', 'M0.e0.a', '10号线', '太平园'),
  _Vector('3320', '01200000000000', '332000010020', 'M0.W.a', '1号线', '东环南路'),
  _Vector(
    '4520',
    '00000000000000',
    '45201121',
    'M0.a0.a',
    '11号线',
    '苗岭路',
    terminal: '4520000011210000',
  ),
  _Vector(
    '7910',
    '00000000000000',
    '79100001000A',
    'M0.e0.a',
    '1号线',
    '陈杨寨',
    terminal: '7910000001100000',
  ),
  _Vector('3910', '00010011000000', '39100111', 'M0.W.a', '1号线', '象峰'),
  _Vector('7010', '00010101000000', '70100101', 'M0.e0.a', '1号线', '窦官'),
  _Vector(
    '3610',
    '00000101000000',
    '36100000413106085352',
    'M0.S.a',
    '',
    '铜陵新村',
    terminal: '0000413106085352',
  ),
  _Vector('6900', '03040200000000', '69000304', 'M0.e0.a', '3号线', '学堂湾'),
  _Vector('6900', '10221000000000', '69001022', 'M0.e0.a', '10号线', '鹿山'),
  _Vector('6900', '05141200000000', '69000514', 'M0.e0.a', '5号线', '石桥铺'),
  _Vector('6900', '18164203000000', '69001816', 'M0.e0.a', '18号线', '石坪桥'),
  _Vector('6900', '18000100000000', '69001801', 'M0.e0.a', '18号线', '跳磴南'),
  _Vector('1121', '00030017000000', '112100030017', 'M0.i0.a', '3号线', '天塔'),
  _Vector('1121', '00100049000000', '112100100049', 'M0.i0.a', '10号线', '丽江道'),
  _Vector('5810', '00180001FFFF00', '581000180001', 'M0.a0.a', '18号线', '广州东站'),
];
