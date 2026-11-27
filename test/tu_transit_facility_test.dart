import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/tu_transit_facility.dart';

void main() {
  test('重庆三类设施提供调用方使用的编号、名称与交通方式', () {
    for (final (facility, route, name, mode) in [
      (TuTransitFacility.yangtzeCableway, '701', '长江索道', '索道'),
      (TuTransitFacility.kaixuanRoadElevator, '703', '凯旋路电梯', '电梯'),
      (TuTransitFacility.crownEscalator, '704', '皇冠大扶梯', '扶梯'),
    ]) {
      expect(facility.routeNumber, route);
      expect(facility.nameLabel, name);
      expect(facility.modeLabel, mode);
      for (final line in [route, '0$route', '$route路', ' 0$route路 ']) {
        expect(
          TuTransitFacility.fromBusLine('6900', line),
          facility,
          reason: line,
        );
      }
    }
  });

  test('缺少重庆受理城市证据时不识别同号设施', () {
    for (final city in [null, '', '1000', '5810', '690', '06900']) {
      for (final line in ['701', '0703', '704路']) {
        expect(TuTransitFacility.fromBusLine(city, line), isNull);
      }
    }
  });

  test('未知线路、名称、非数字和复合字段不误识别为设施', () {
    for (final line in [
      null,
      '',
      ' ',
      '0',
      '702',
      '705',
      '1701',
      '7010',
      '07030000000000',
      '00000000000703',
      '703A',
      '703支',
      '703路区间',
      '公交703路',
      '长江索道',
      '+703',
      '-703',
      '703.0',
      '0x2BF',
    ]) {
      expect(
        TuTransitFacility.fromBusLine('6900', line),
        isNull,
        reason: '$line',
      );
    }
  });
}
