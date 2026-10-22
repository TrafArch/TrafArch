import 'package:flutter_test/flutter_test.dart';

import 'package:transit_card_analyzer/features/reference_data/domain/beijing_bus_decoder.dart';

void main() {
  // Literal txLine fixtures reconstructed from Trip Reader's Beijing branch:
  // AbstractC0299a0.m764r, simple JADX lines 7564–8135.
  // The display expectations are source-derived, not real-card observations.
  group('Beijing operator 0001 route categories', () {
    const fixtures = <String, String?>{
      '0001000A000100': '1', // 1
      '0012000A000100': '18', // 18
      '03E7000A000100': '999', // 999
      '03E9000A000100': '其他1', // 1001
      '07D1000A000100': '1区间', // 2001
      '0972000A000100': '418区间', // 2418
      '0B67000A000100': '919区间', // 2919
      '2AF9000A000100': '雄安高铁巴士1线', // 11001
      '2AFA000A000100': '雄安高铁巴士2线', // 11002
      '2B2C000A000100': '雄安高铁巴士2线旅游专线', // 11052
      '2AFB000A000100': null, // 11003
      '2EE1000A000100': '通医专线1', // 12001
      '32C9000A000100': '通游专线1', // 13001
      '34BD000A000100': '朝阳文旅公交专线', // 13501
      '34BE000A000100': '朝阳文旅公交专线区间', // 13502
      '5209000A000100': 'C1', // 21001
      '55F1000A000100': 'F1', // 22001
      '59D9000A000100': 'X1', // 23001
      '5DC1000A000100': '专1', // 24001
      '6DC5000A000100': 'S101', // 28101
      '6DC6000A000100': '其他102', // 28102
      '7149000A000100': 'T1', // 29001
      '7531000A000100': '1', // 30001
      '7919000A000100': '房1', // 31001
      '7D01000A000100': 'Y1', // 32001
      '80E9000A000100': 'M1', // 33001
      '84D1000A000100': 'H1', // 34001
      '9089000A000100': '1通勤快车', // 37001
      '90EC000A000100': '凤河营通勤班车', // 37100
      '93C9000A000100': '通勤朱家坟', // 37833
      '93D4000A000100': '通勤礼贤', // 37844
      '93D8000A000100': '通勤海子角', // 37848
      '9402000A000100': '通勤苹果园', // 37890
      '941D000A000100': '通勤东湖港', // 37917
      '941E000A000100': '通勤关上', // 37918
      '943F000A000100': '通勤石花洞', // 37951
      '9443000A000100': '通勤东方太阳城', // 37955
      '9451000A000100': '通勤向阳', // 37969
      '9471000A000100': '快速直达专线', // 38001
      '97FC000A000100': '儿研所专线', // 38908
      '97FF000A000100': '北京后花园临线', // 38911
      '9C41000A000100': '燕郊专线', // 40001
      '9CB1000A000100': '集体出行3', // 40113
      '9CB9000A000100': '北京密码通勤班车', // 40121
      '9CBA000A000100': '高家坡班车', // 40122
      '9DD4000A000100': '北京朝阳站地铁摆渡车', // 40404
      '9DD5000A000100': '北京丰台站夜间摆渡车', // 40405
      '9DD6000A000100': '副中心三大建筑摆渡车', // 40406
      '9FC7000A000100': '北京妇产医院东院专线', // 40903
      '9FC8000A000100': '少年宫专线', // 40904
      '9C42000A000100': '其他2', // 40002
      'A411000A000100': '临1', // 42001
      'A7F9000A000100': '特1', // 43001
      'C351000A000100': '1', // 50001
      'C739000A000100': '1内', // 51001
      'CB21000A000100': '1外', // 52001
      'D6D9000A000100': '特1内', // 55001
      'DAC1000A000100': '特1外', // 56001
      'DEA9000A000100': '1快内', // 57001
      'E291000A000100': '1快外', // 58001
      'EA61000A000100': '1快', // 60001
      'F231000A000100': '夜1', // 62001
      'FFFF000A000100': '其他535', // 65535
      '03E8000A000100': '其他0', // 1000
      '07D0000A000100': '0区间', // 2000
      'C350000A000100': '0', // 50000
    };
    for (final entry in fixtures.entries) {
      test('${entry.key} displays ${entry.value}', () {
        final result = decodeBeijingBus(cityCode: '1000', field: entry.key);
        expect(result, isNotNull);
        expect(result!.lineLabel, entry.value);
      });
    }
  });

  group('all 44 numbered quick-direct legacy mappings', () {
    const fixtures = <String, String>{
      '9485000A000100': '快速直达专线139', // 38021
      '9489000A000100': '快速直达专线25', // 38025
      '94A4000A000100': '快速直达专线52', // 38052
      '94AD000A000100': '快速直达专线61', // 38061
      '94C1000A000100': '快速直达专线81', // 38081
      '94D7000A000100': '快速直达专线21', // 38103
      '94D8000A000100': '快速直达专线36', // 38104
      '94E8000A000100': '快速直达专线141', // 38120
      '9509000A000100': '快速直达专线153', // 38153
      '950D000A000100': '快速直达专线157', // 38157
      '950F000A000100': '快速直达专线213', // 38159
      '9510000A000100': '快速直达专线160', // 38160
      '9511000A000100': '快速直达专线161', // 38161
      '9513000A000100': '快速直达专线163', // 38163
      '9515000A000100': '快速直达专线165', // 38165
      '9527000A000100': '快速直达专线183', // 38183
      '953A000A000100': '快速直达专线22', // 38202
      '953B000A000100': '快速直达专线23', // 38203
      '953F000A000100': '快速直达专线207', // 38207
      '9542000A000100': '快速直达专线91', // 38210
      '9543000A000100': '快速直达专线211', // 38211
      '9545000A000100': '快速直达专线109', // 38213
      '9547000A000100': '快速直达专线215', // 38215
      '959E000A000100': '快速直达专线24', // 38302
      '95A1000A000100': '快速直达专线45', // 38305
      '95A6000A000100': '快速直达专线97', // 38310
      '95AB000A000100': '快速直达专线120', // 38315
      '95AE000A000100': '快速直达专线131', // 38318
      '95B5000A000100': '快速直达专线145', // 38325
      '95B6000A000100': '快速直达专线146', // 38326
      '95B9000A000100': '快速直达专线181', // 38329
      '95BA000A000100': '快速直达专线182', // 38330
      '9603000A000100': '快速直达专线26', // 38403
      '9604000A000100': '快速直达专线39', // 38404
      '960C000A000100': '快速直达专线178', // 38412
      '960D000A000100': '快速直达专线179', // 38413
      '9667000A000100': '快速直达专线15', // 38503
      '9732000A000100': '快速直达专线54', // 38706
      '9796000A000100': '快速直达专线58', // 38806
      '9797000A000100': '快速直达专线59', // 38807
      '97F7000A000100': '快速直达专线35', // 38903
      '97FB000A000100': '快速直达专线94', // 38907
      '9809000A000100': '快速直达专线201', // 38921
      '980B000A000100': '快速直达专线203', // 38923
    };
    for (final entry in fixtures.entries) {
      test('${entry.key} displays ${entry.value}', () {
        expect(
          decodeBeijingBus(cityCode: '1000', field: entry.key)!.lineLabel,
          entry.value,
        );
      });
    }
  });

  group('district operators and exceptional full route codes', () {
    // Airport 61..99 is confirmed against L0/a0.smali:41473–41508:
    // simple JADX drops the goto from L7436 back to L7439.
    const fixtures = <String, String>{
      '0012000A001200': 'T18', // 18, operator 0012
      '5DD2000A001300': '专18', // 24018, operator 0013
      'A80A000A001300': '其他18', // 43018, operator 0013
      '0012000A001400': '运通18', // 18, operator 0014
      '0001000A001F00': '密1', // 1, operator 001F
      '004F000A001F00': '密79', // 79, operator 001F
      '0050000A001F00': '郊80', // 80, operator 001F
      '03E8000A001F00': '郊0', // 1000, operator 001F
      '0001000A002000': '密1', // 1, operator 0020
      '004F000A002000': '密79', // 79, operator 0020
      '0050000A002000': '郊80', // 80, operator 0020
      '03E8000A002000': '郊0', // 1000, operator 0020
      '521A000A002100': '昌18', // 21018, operator 0021
      '0001000A002300': '兴航城1', // 1, operator 0023
      '0002000A002300': '兴航城2', // 2, operator 0023
      '0003000A002300': '兴3', // 3, operator 0023
      '0024000A002300': '兴环一线', // 36, operator 0023
      '003C000A002300': '兴西环线', // 60, operator 0023
      '014A000A002300': '兴环二线', // 330, operator 0023
      '02A8000A002300': '兴68', // 680, operator 0023
      '02D0000A002300': '兴72内', // 720, operator 0023
      '02D1000A002300': '兴72外', // 721, operator 0023
      '0001000A002400': '兴航城1', // 1, operator 0024
      '0002000A002400': '兴航城2', // 2, operator 0024
      '0003000A002400': '兴3', // 3, operator 0024
      '0024000A002400': '兴环一线', // 36, operator 0024
      '003C000A002400': '兴西环线', // 60, operator 0024
      '014A000A002400': '兴环二线', // 330, operator 0024
      '02A8000A002400': '兴68', // 680, operator 0024
      '02D0000A002400': '兴72内', // 720, operator 0024
      '02D1000A002400': '兴72外', // 721, operator 0024
      '715A000A002700': '通18', // 29018, operator 0027
      '0012000A002C00': '顺18', // 18, operator 002C
      '5214000A002C00': '顺42', // 21012, operator 002C
      '563A000A002C00': '国门智慧城专线', // 22074, operator 002C
      'E0DE000A002C00': '顺73', // 57566, operator 002C
      '000C000A002C00': '顺12', // 12, operator 002C
      '2EEC000A002C00': '顺12', // 12012, operator 002C
      '003C000A002D00': '其他60', // 60, operator 002D
      '003D000A002D00': '空港1', // 61, operator 002D
      '0046000A002D00': '空港10', // 70, operator 002D
      '0047000A002D00': '空港10', // 71, operator 002D
      '0048000A002D00': '空港15', // 72, operator 002D
      '0049000A002D00': '空港13', // 73, operator 002D
      '004A000A002D00': '空港11', // 74, operator 002D
      '004B000A002D00': '空港5区间', // 75, operator 002D
      '0053000A002D00': '空港3区间', // 83, operator 002D
      '0063000A002D00': '空港39', // 99, operator 002D
      '0064000A002D00': '其他100', // 100, operator 002D
      '0425000A002D00': '其他61', // 1061, operator 002D
      '042F000A002D00': '其他71', // 1071, operator 002D
      '0012000A002E00': '平18', // 18, operator 002E
      'CF62000A002F00': '平谷–三河', // 53090, operator 002F
      '0012000A002F00': '郊18', // 18, operator 002F
      '005A000A002F00': '郊90', // 90, operator 002F
      'A80A000A123400': '其他18', // 43018, operator 1234
    };
    for (final entry in fixtures.entries) {
      test('${entry.key} displays ${entry.value}', () {
        expect(
          decodeBeijingBus(cityCode: '1000', field: entry.key)!.lineLabel,
          entry.value,
        );
      });
    }
  });

  group('raw segments and station ordinals', () {
    test('ordinary bus integration fixture displays 1 and 第10站', () {
      final result = decodeBeijingBus(
        cityCode: '1000',
        field: '0001000A000100',
      )!;
      expect(result.rawLineCode, '0001');
      expect(result.rawStationCode, '000A');
      expect(result.rawOperatorCode, '0001');
      expect(result.lineLabel, '1');
      expect(result.stationLabel, '第10站');
    });

    test('keeps all leading zeros and uses HEX for the station ordinal', () {
      final result = decodeBeijingBus(
        cityCode: '1000',
        field: '0012000A000100',
      )!;
      expect(result.rawLineCode, '0012');
      expect(result.rawStationCode, '000A');
      expect(result.rawOperatorCode, '0001');
      expect(result.lineLabel, '18');
      expect(result.stationLabel, '第10站');
    });

    test('accepts lowercase HEX without changing raw segment spelling', () {
      final result = decodeBeijingBus(
        cityCode: '1000',
        field: 'cf62000a002fef',
      )!;
      expect(result.rawLineCode, 'cf62');
      expect(result.rawStationCode, '000a');
      expect(result.rawOperatorCode, '002f');
      expect(result.lineLabel, '平谷–三河');
      expect(result.stationLabel, '第10站');
    });

    const stations = <String, String?>{
      '00010000000100': null,
      '00010001000100': '第1站',
      '00010010000100': '第16站',
      '000100FF000100': '第255站',
      '00010101000100': null,
      '0001FF0A000100': null,
    };
    for (final entry in stations.entries) {
      test('${entry.key} station is ${entry.value}', () {
        expect(
          decodeBeijingBus(cityCode: '1000', field: entry.key)!.stationLabel,
          entry.value,
        );
      });
    }

    test('retains non-ordinal station bytes without inventing a name', () {
      final result = decodeBeijingBus(
        cityCode: '1000',
        field: '0001010A000100',
      )!;
      expect(result.rawStationCode, '010A');
      expect(result.lineLabel, '1');
      expect(result.stationLabel, isNull);
    });

    test('a route without a source label cannot acquire a station label', () {
      final result = decodeBeijingBus(
        cityCode: '1000',
        field: '2AFB000A000100',
      )!;
      expect(result.rawLineCode, '2AFB');
      expect(result.rawStationCode, '000A');
      expect(result.lineLabel, isNull);
      expect(result.stationLabel, isNull);
    });

    test('last byte is preserved by caller but has no display semantics', () {
      final result = decodeBeijingBus(
        cityCode: '1000',
        field: '0012000A0001FF',
      )!;
      expect(result.lineLabel, '18');
      expect(result.stationLabel, '第10站');
    });
  });

  group('input boundaries', () {
    for (final city in ['', '01000', '1000 ', ' 1000', '1100', '2900']) {
      test('rejects city "$city"', () {
        expect(
          decodeBeijingBus(cityCode: city, field: '0012000A000100'),
          isNull,
        );
      });
    }

    for (final field in [
      '',
      '0012000A0001',
      '0012000A00010',
      '0012000A0001000',
      '0012000A00010000',
      '0x0012000A000100',
      ' 0012000A000100',
      '0012000A000100 ',
      '0012000A000100\n',
      '0012000A0001\n0',
      '0012000A0001GG',
      'GG12000A000100',
      '0012000G000100',
      '0012000A00G100',
      '-012000A000100',
      '+012000A000100',
      '００１２０００Ａ０００１００',
    ]) {
      test('rejects malformed raw field ${field.codeUnits}', () {
        expect(decodeBeijingBus(cityCode: '1000', field: field), isNull);
      });
    }

    for (final field in ['00000000000000', '0000000A000100']) {
      test('rejects absent line code in $field', () {
        expect(decodeBeijingBus(cityCode: '1000', field: field), isNull);
      });
    }
  });
}
