import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_bus_location.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/station_codes.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/tunion_city_bus_decoder.dart';

// Literal expectations follow TripReader 1.7.17-cn's original m764r Smali.
// These tests catch missing city dispatch, wrong slices/radices, lost leading
// zeroes, ignored contextual gates and accidental lookup in another namespace.
// Flutter execution is intentionally left to the parent integration task while
// sqlite3.dll is locked. No mock SQL, source-text assertions or guessed routes.
void main() {
  test(
    'raw city arguments retain original byte BCD arithmetic including AF',
    () {
      final raw = List<int>.filled(48, 0);
      raw[32] = 0xAF;
      raw[33] = 0x01;
      raw[36] = 0x12;
      raw[37] = 0x97;
      final context = TunionBusDecodeContext.fromCycleRecord(
        raw,
        amountFen: -180,
      );
      expect(context.rawCity32, 11501);
      expect(context.rawCity36, 1297);
      expect(context.amountFen, -180);
      expect(raw[32], 0xAF);
      final short = TunionBusDecodeContext.fromCycleRecord(raw.sublist(0, 37));
      expect(short.rawCity32, isNull);
      expect(short.rawCity36, isNull);
    },
  );

  test('Hohhot signed amount selects only the original matching branch', () {
    const field = '20840000000000';
    for (final (amount, expected) in [(-500, '113'), (-200, '一环1号线')]) {
      expect(
        decodeTunionCityBusLine(
          cityCode: '1910',
          field: field,
          context: TunionBusDecodeContext(amountFen: amount),
        ),
        expected,
      );
    }
    expect(decodeTunionCityBusLine(cityCode: '1910', field: field), isNull);
  });

  test('Changchun uses rawCity36 to select decimal or hexadecimal parsing', () {
    for (final (rawCity, expected) in [(2410, '16'), (2420, '22')]) {
      expect(
        decodeTunionCityBusLine(
          cityCode: '2410',
          field: '00160000000000',
          context: TunionBusDecodeContext(rawCity36: rawCity),
        ),
        expected,
      );
    }
    expect(
      decodeTunionCityBusLine(cityCode: '2410', field: '00160000000000'),
      isNull,
    );
  });

  test('Suzhou rawCity32 selects its original two-character or four-character slice', () {
    for (final (rawCity, expected) in [(3050, '100'), (3052, '1')]) {
      expect(
        decodeTunionCityBusLine(
          cityCode: '3050',
          field: '00010000000100',
          context: TunionBusDecodeContext(rawCity32: rawCity),
        ),
        expected,
      );
    }
    expect(
      decodeTunionCityBusLine(cityCode: '3050', field: '00010000000100'),
      isNull,
    );
  });

  test(
    'Liuzhou amount signs and unknown amounts do not select another route',
    () {
      for (final (amount, expected) in <(int, String?)>[
        (-180, '73'),
        (-90, '快9'),
        (180, null),
        (-100, null),
      ]) {
        expect(
          decodeTunionCityBusLine(
            cityCode: '6140',
            field: '49000000000000',
            context: TunionBusDecodeContext(amountFen: amount),
          ),
          expected,
        );
      }
    },
  );

  test('Qiqihar changes radix at the source date boundary, not today', () {
    const boundary = 1640995200000;
    for (final (time, expected) in [(boundary - 1, '16'), (boundary, '22')]) {
      expect(
        decodeTunionCityBusLine(
          cityCode: '2640',
          field: '00160000000000',
          context: TunionBusDecodeContext(
            transactionTime: DateTime.fromMillisecondsSinceEpoch(
              time,
              isUtc: true,
            ),
          ),
        ),
        expected,
      );
    }
    expect(
      decodeTunionCityBusLine(cityCode: '2640', field: '00160000000000'),
      isNull,
    );
    expect(
      decodeTunionCityBusLine(cityCode: '2640', field: '00160001000000'),
      '22',
      reason: 'Station field 0001 selects hex without reading the date',
    );
  });
  group('independently checked frozen source examples', () {
    const cases = <(String, String, String)>[
      ('1121', '07480000000400', '大沙河专线'),
      ('1210', '07250000000100', '72'),
      ('1240', '00006013000100', 'D03'),
      ('1240', '00006015000100', 'D01支'),
      ('1340', '00010000000000', '106'),
      ('1660', '20050000000000', '五福专线'),
      ('1710', '00010000000000', '73'),
      ('1730', '00160000000000', '16'),
      ('1810', '01230000000000', '12'),
      ('2900', '00010000000000', '01'),
      ('2900', '11510000000000', '国际旅游度假区1'),
      ('2900', '31140000000000', '虹桥枢纽7'),
      ('3670', '01000000000000', '1'),
      ('5840', '00160000000000', '2'),
      ('8810', '04030000000000', 'S403'),
      ('8810', '04100000000000', 'S410/420'),
      ('8840', '00160000000000', '16'),
      ('1610', '0016000000D500', '864'),
      ('1000', '00160000000100', '22'),
    ];
    for (final (city, field, expected) in cases) {
      test('$city $field -> $expected without station SQL', () {
        final result = resolveTunionBusLocation(
          stations: StationCodeTable.empty,
          cityCode: city,
          field: field,
        );
        expect(result.lineLabel, expected);
        expect(result.stationLabel, isNull);
        expect(result.match.entry, isNull);
      });
    }
  });

  test('the same raw code has independent meanings in different cities', () {
    final expected = <String, String?>{
      '1610': '864',
      '1730': '16',
      '1000': '22',
      '5840': '2',
      '3330': null,
      '9999': null,
    };
    for (final entry in expected.entries) {
      final field = entry.key == '1000' ? '00160000000100' : '0016000000D500';
      expect(
        decodeTunionCityBusLine(cityCode: entry.key, field: field),
        entry.value,
        reason: entry.key,
      );
    }
  });

  test(
    'decimal city rejects hexadecimal letters instead of converting them',
    () {
      expect(
        decodeTunionCityBusLine(cityCode: '8840', field: '001A0000000000'),
        isNull,
      );
      expect(
        decodeTunionCityBusLine(cityCode: '8840', field: '00000000000000'),
        isNull,
      );
    },
  );

  test('reserved byte is ignored and the original field remains unchanged', () {
    const field = '0016000000d5a5';
    expect(decodeTunionCityBusLine(cityCode: '1610', field: field), '864');
    expect(field, '0016000000d5a5');
    for (final invalid in [
      '',
      '0016000000D5',
      '0016000000D50000',
      '0016000000D5GG',
      ' 0016000000D500',
    ]) {
      expect(decodeTunionCityBusLine(cityCode: '1610', field: invalid), isNull);
    }
    expect(decodeTunionCityBusLine(cityCode: '01610', field: field), isNull);
  });

  test('Shanghai 835 respects the original timestamp boundary', () {
    const boundary = 1572033600000;
    for (final (time, expected) in [
      (boundary - 1, '835'),
      (boundary, '71 T2'),
    ]) {
      expect(
        decodeTunionCityBusLine(
          cityCode: '2900',
          field: '08350000000000',
          context: TunionBusDecodeContext(
            transactionTime: DateTime.fromMillisecondsSinceEpoch(
              time,
              isUtc: true,
            ),
          ),
        ),
        expected,
      );
    }
    expect(
      decodeTunionCityBusLine(cityCode: '2900', field: '08350000000000'),
      isNull,
    );
    // Missing date must not disable independent Shanghai rules.
    expect(
      decodeTunionCityBusLine(cityCode: '2900', field: '00010000000000'),
      '01',
    );
  });

  test('Shanghai preserves all four source languages and SQL omissions', () {
    const labels = ['虹桥枢纽7', '虹橋樞紐7', 'Hongqiao Hub 7', '虹橋ハブ7'];
    for (var language = 1; language <= 4; language++) {
      expect(
        decodeTunionCityBusLine(
          cityCode: '2900',
          field: '31140000000000',
          context: TunionBusDecodeContext(language: language),
        ),
        labels[language - 1],
      );
    }
    for (final language in [0, 5]) {
      expect(
        decodeTunionCityBusLine(
          cityCode: '2900',
          field: '31140000000000',
          context: TunionBusDecodeContext(language: language),
        ),
        isNull,
      );
    }
  });

  test('exact BRT prefix SQL retains source fields and wins over fallback', () {
    const key = '22202901';
    final stations = StationCodeTable.fromDatasets([
      const StationDataset(
        file: 'frozen-tu-test-fixture',
        cityCode: '2220',
        kind: 'brt',
        codes: {
          key: StationCodeEntry(
            code: key,
            sourceKey: key,
            sourceField: 'M0.S.c',
            line: 'BRT',
            station: 'source station',
          ),
        },
      ),
    ]);
    final result = resolveTunionBusLocation(
      stations: stations,
      cityCode: '2220',
      field: '29010000000000',
    );
    expect(result.lineLabel, 'BRT');
    expect(result.stationLabel, 'source station');
    expect(result.match.entry?.sourceKey, key);
    expect(result.match.entry?.sourceField, 'M0.S.c');
    final otherCity = resolveTunionBusLocation(
      stations: stations,
      cityCode: '1730',
      field: '29010000000000',
    );
    expect(otherCity.lineLabel, '2901');
    expect(otherCity.stationLabel, isNull);
  });

  test(
    'terminal and rail rows cannot impersonate BRT field-prefix records',
    () {
      for (final (kind, sourceField) in [
        ('bus', 'M0.n0.a'),
        ('bus', 'M0.E.a'),
        ('metro', 'M0.S.c'),
      ]) {
        final stations = StationCodeTable.fromDatasets([
          StationDataset(
            file: 'frozen-tu-test-fixture',
            cityCode: '1610',
            kind: kind,
            codes: {
              '16100016': StationCodeEntry(
                code: '16100016',
                sourceKey: '16100016',
                sourceField: sourceField,
                line: 'wrong namespace',
                station: 'wrong station',
              ),
            },
          ),
        ]);
        final result = resolveTunionBusLocation(
          stations: stations,
          cityCode: '1610',
          field: '0016000000D500',
        );
        expect(result.lineLabel, '864');
        expect(result.stationLabel, isNull);
      }
    },
  );

  group(
    'original Smali oracle: every city, four languages and unknown fields',
    () {
      for (final (city, field, languages, zero, sentinel)
          in _sourceOracleCases) {
        test('$city original branch is isolated and language-aware', () {
          final cityNumber = int.parse(city);
          TunionBusDecodeContext context(int language) =>
              TunionBusDecodeContext(
                rawCity32: cityNumber,
                rawCity36: cityNumber,
                amountFen: -100,
                transactionTime: DateTime.fromMillisecondsSinceEpoch(
                  1792512000000,
                  isUtc: true,
                ),
                language: language,
              );
          for (var language = 1; language <= 4; language++) {
            expect(
              decodeTunionCityBusLine(
                cityCode: city,
                field: field,
                context: context(language),
              ),
              languages[language - 1],
              reason: '$city language=$language field=$field',
            );
          }
          expect(
            decodeTunionCityBusLine(
              cityCode: city,
              field: '00000000000000',
              context: context(1),
            ),
            zero,
          );
          expect(
            decodeTunionCityBusLine(
              cityCode: city,
              field: 'FFFFFFFFFFFF00',
              context: context(1),
            ),
            sentinel,
          );
          expect(
            decodeTunionCityBusLine(cityCode: '9999', field: field),
            isNull,
            reason: 'No cross-city reuse of $city rules',
          );
        });
      }
    },
  );
}

// Expected labels are literal outputs of original Smali, not the Dart decoder.
const _sourceOracleCases = <(String, String, List<String?>, String?, String?)>[
  ("-2", "00010000000000", ["1", "1", "1", "1"], null, null),
  ("1000", "00010000000000", ["其他1", "其他1", "Other 1", "その他1"], null, "其他535"),
  ("1121", "00010000000400", ["1", "1", "1", "1"], null, null),
  ("1210", "00000001000000", ["1", "1", "1", "1"], null, null),
  ("1240", "00000001000000", ["1", "1", "1", "1"], null, null),
  ("1270", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("1340", "00010000000000", ["106", "106", "106", "106"], null, "535"),
  ("1380", "00010000000000", ["1", "1", "1", "1"], null, null),
  ("1410", "000100000FA000", ["1", "1", "1", "1"], null, null),
  ("1610", "00120000000000", ["13", "13", "13", "13"], null, null),
  ("1660", "0001000003E800", ["1", "1", "1", "1"], null, null),
  ("1710", "00000000000000", ["72", "72", "72", "72"], "72", "607"),
  ("1730", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("1750", "00010000000000", ["1", "1", "1", "1"], null, "65535"),
  ("1770", "00010001000100", ["1", "1", "1", "1"], null, "65535"),
  ("1810", "0016000000D500", ["1", "1", "1", "1"], null, null),
  ("1910", "00010000000000", ["0", "0", "0", "0"], null, null),
  ("2011", "11010000000000", ["1", "1", "1", "1"], null, null),
  ("2030", "01000000000000", ["1", "1", "1", "1"], null, null),
  ("2210", "00000001000000", ["环路", "環路", "Huanlu", "環路"], null, null),
  ("2220", "00000000000000", ["0", "0", "0", "0"], "0", "65535"),
  ("2240", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("2280", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("2320", "00010000000000", ["1", "1", "1", "1"], null, null),
  ("2330", "00010000000000", ["1环", "1環", "1 Huan", "1環"], null, null),
  ("2340", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("2410", "00010000097300", ["1", "1", "1", "1"], null, null),
  ("2420", "00010000009100", ["1", "1", "1", "1"], null, "535"),
  ("2430", "00000000000000", ["0", "0", "0", "0"], "0", "535"),
  ("2491", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("2640", "00000100000000", ["1", "1", "1", "1"], null, null),
  ("2690", "00010000004C00", ["1", "1", "1", "1"], null, null),
  ("2720", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("2900", "00010000000000", ["01", "01", "01", "01"], null, null),
  ("3010", "00010000000100", ["仪征1", "儀徵1", "Yizheng 1", "儀徵1"], null, null),
  ("3020", "00020000000000", ["江阴2", "江陰2", "Jiangyin 2", "江陰2"], null, null),
  ("3023", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("3030", "00010000000100", ["1", "1", "1", "1"], null, null),
  ("3040", "00010000005000", ["1", "1", "1", "1"], null, null),
  ("3050", "00000100000000", ["1", "1", "1", "1"], null, null),
  ("3052", "00000100000000", ["1", "1", "1", "1"], null, null),
  ("3070", "00010000000000", ["1", "1", "1", "1"], null, null),
  ("3110", "01000000000000", ["1", "1", "1", "1"], null, "255"),
  ("3120", "00000000000000", ["0", "0", "0", "0"], "0", null),
  ("3140", "00010000000000", ["1", "1", "1", "1"], null, null),
  ("3142", "00010000001000", ["1", "1", "1", "1"], null, null),
  ("3162", "00010001000100", ["1", "1", "1", "1"], null, "65535"),
  ("3163", "01000000000000", ["100", "100", "100", "100"], null, null),
  ("3316", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("3320", "0016000000D500", ["1-6", "1-6", "1-6", "1-6"], null, null),
  ("3330", "10010000000000", ["1", "1", "1", "1"], null, null),
  ("3360", "00010000000000", ["1", "1", "1", "1"], null, null),
  ("3370", "00000001000000", ["1", "1", "1", "1"], null, null),
  ("3380", "00010000005000", ["1", "1", "1", "1"], null, null),
  ("3410", "00010000038C00", ["1", "1", "1", "1"], null, null),
  ("3430", "00010000003C00", ["1", "1", "1", "1"], null, null),
  ("3450", "00010000000000", ["1", "1", "1", "1"], null, null),
  ("3610", "00010000002F00", ["1", "1", "1", "1"], null, null),
  ("3615", "00000001000000", ["1", "1", "1", "1"], null, null),
  ("3630", "00010000002F00", ["1", "1", "1", "1"], null, "FFF"),
  ("3640", "00010000001800", ["1", "1", "1", "1"], null, "65535"),
  ("3650", "00010000000000", ["1", "1", "1", "1"], null, null),
  ("3660", "00010000000000", ["1", "1", "1", "1"], null, null),
  ("3670", "01000000000000", ["1", "1", "1", "1"], null, "FF"),
  ("3710", "01000000000000", ["1", "1", "1", "1"], null, "255"),
  ("3720", "01000000000000", ["1", "1", "1", "1"], null, "255"),
  ("3740", "00010000000000", ["1", "1", "1", "1"], null, null),
  ("3750", "00010000000000", ["1", "1", "1", "1"], null, null),
  ("3760", "00010000000000", ["1", "1", "1", "1"], null, null),
  ("3770", "00010000038400", ["1", "1", "1", "1"], null, null),
  ("3790", "00010000000000", ["1", "1", "1", "1"], null, null),
  ("3810", "01000000000000", ["1", "1", "1", "1"], null, "255"),
  ("3910", "00000001000000", ["1", "1", "1", "1"], null, null),
  ("3918", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("3930", "00010000270900", ["1", "1", "1", "1"], null, null),
  ("3950", "00010000006400", ["1", "1", "1", "1"], null, null),
  ("3990", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("4210", "00010000006A00", ["1", "1", "1", "1"], null, null),
  ("4220", "00000001000000", ["1", "1", "1", "1"], null, null),
  ("4240", "0001000000AA00", ["1", "1", "1", "1"], null, null),
  ("4330", "00000001000000", ["1", "1", "1", "1"], null, null),
  ("4370", "00010000000000", ["B1", "B1", "B1", "B1"], null, null),
  ("4510", "0001000003C700", ["1", "1", "1", "1"], null, null),
  ("4520", "00000100000000", ["1", "1", "1", "1"], null, "65535"),
  ("4540", "0001000000E000", ["1", "1", "1", "1"], null, "255"),
  ("4550", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("4580", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("4630", "0001000001F400", ["1", "1", "1", "1"], null, null),
  ("4660", "00010001000100", ["1", "1", "1", "1"], null, "65535"),
  ("4680", "00010000004600", ["1", "1", "1", "1"], null, "65535"),
  ("4710", "0001000000CB00", ["1", "1", "1", "1"], null, null),
  ("4730", "00010000000000", ["1", "1", "1", "1"], null, null),
  ("4750", "000100000BBA00", ["1", "1", "1", "1"], null, "65535"),
  ("4770", "000100000F9F00", ["1", "1", "1", "1"], null, null),
  ("4790", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("4910", "00010000000000", ["1", "1", "1", "1"], null, null),
  ("4930", "00000001000000", ["1", "1", "1", "1"], null, "255"),
  ("4960", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("4980", "01000000000000", ["1", "1", "1", "1"], null, "255"),
  ("5060", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("5110", "00000100000000", ["1", "1", "1", "1"], null, null),
  ("5130", "00010000000000", ["1", "1", "1", "1"], null, "255"),
  ("5150", "00010001000100", ["1", "1", "1", "1"], null, "65535"),
  ("5220", "01000000000000", ["1", "1", "1", "1"], null, null),
  ("5230", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("5280", "00010001000100", ["1", "1", "1", "1"], null, "65535"),
  ("5370", "00010001000100", ["1", "1", "1", "1"], null, "65535"),
  ("5410", "01000000000000", ["1", "1", "1", "1"], null, null),
  ("5510", "01000000000000", ["100", "100", "100", "100"], null, null),
  ("5540", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("5550", "006E0000000000", ["10", "10", "10", "10"], null, null),
  ("5570", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("5620", "00010001000100", ["1", "1", "1", "1"], null, "535"),
  ("5630", "00010000000000", ["1", "1", "1", "1"], null, null),
  ("5840", "0016000000D500", ["2", "2", "2", "2"], null, "6553"),
  ("5850", "00010000000000", ["0/x00", "0/x00", "0/x00", "0/x00"], null, null),
  ("5860", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("5910", "01000000000000", ["1", "1", "1", "1"], null, "FF"),
  ("5920", "00010000000000", ["1", "1", "1", "1"], null, null),
  ("6110", "00000001000000", ["1", "1", "1", "1"], null, "FFF"),
  ("6140", "00010000000000", ["1", "1", "1", "1"], null, "65535"),
  ("6320", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("6410", "00010000000000", ["1", "1", "1", "1"], null, null),
  ("6550", "00010000005400", ["1", "1", "1", "1"], null, null),
  ("6560", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("6580", "00010000000000", ["1", "1", "1", "1"], null, null),
  ("6584", "00010000000000", ["1", "1", "1", "1"], null, null),
  ("6610", "00010001000100", ["1", "1", "1", "1"], null, "65535"),
  ("6620", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("6630", "00000001000000", ["1", "1", "1", "1"], null, null),
  ("6650", "00010000000000", ["1", "1", "1", "1"], null, null),
  ("6670", "00000001000000", ["1", "1", "1", "1"], null, null),
  ("6690", "00000001000000", ["1", "1", "1", "1"], null, null),
  ("6710", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("6730", "00000001000000", ["1", "1", "1", "1"], null, null),
  ("6743", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("6770", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("6810", "00000001000000", ["康定1", "康定1", "Kangding 1", "康定1"], null, null),
  ("6840", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("6900", "000100001E7800", ["1", "1", "1", "1"], null, null),
  ("7010", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("7030", "00010001000100", ["1", "1", "1", "1"], null, "65535"),
  ("7050", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("7310", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("7380", "000100000FA000", ["1", "1", "1", "1"], null, null),
  ("7530", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("7710", "00010000005700", ["1", "1", "1", "1"], null, null),
  ("7904", "00010000072F00", ["1", "1", "1", "1"], null, "65535"),
  ("7910", "0001000000A500", ["1", "1", "1", "1"], null, null),
  ("7950", "01000000000000", ["1", "1", "1", "1"], null, "FF"),
  ("7990", "00010001000100", ["1", "1", "1", "1"], null, "5535"),
  ("8030", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("8040", "00010000000000", ["1", "1", "1", "1"], null, null),
  ("8210", "00010000000000", ["1", "1", "1", "1"], null, null),
  ("8250", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("8510", "0001000007D000", ["1", "1", "1", "1"], null, "65535"),
  ("8590", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("8710", "00010000038400", ["1", "1", "1", "1"], null, null),
  ("8730", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("8810", "00010000019200", ["1", "1", "1", "1"], null, null),
  ("8840", "00010001000100", ["1", "1", "1", "1"], null, null),
  ("8940", "00010001000100", ["1", "1", "1", "1"], null, null),
];
