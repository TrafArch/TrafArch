import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_trip_matcher.dart';

// Same-operation evidence from transit_card_log_20261104_160640; the 1A
// entry city differs from 1E. No city equivalence is inferred outside this layout.
void main() {
  test('绍兴城际两侧以机构及位置字节确认1A和1E同次操作', () {
    expect(_matches(), isTrue);
    expect(
      _matches(
        entry: false,
        city: '3370',
        station: '4112305000001135',
        terminal: '3050000011351501',
        line: 0x11,
        cycle: _cycle(entry: false),
      ),
      isTrue,
    );
  });

  final variants = <String, bool Function()>{
    '错误城市': () => _matches(city: '3310'),
    '未知城市': () => _matches(city: '0000'),
    '无金额': () => _matches(amount: null),
    '金额冲突': () => _matches(amount: 1),
    '机构冲突': () => _matches(agency: '03493371FFFFFFFF'),
    '站点冲突': () => _matches(station: '4112305000000122'),
    '终端位置冲突': () => _matches(terminal: '3050000001211A05'),
    '线路冲突': () => _matches(line: 2),
    '时间冲突': () => _matches(seconds: 1),
    '公交侧': () => _matches(rail: false),
    '方向冲突': () => _matches(cycle: _cycle(entry: false)),
    '其他应用': () => _matches(cycle: _cycle(app: 1)),
    '其他受理城市': () => _matches(cycle: _cycle(city: '5330')),
    '其他受理机构': () => _matches(cycle: _cycle(agency: '03845330FFFFFFFF')),
    '其他终端空间': () => _matches(cycle: _cycle(terminal: '0000300012340000')),
    '未确认位置布局': () => _matches(cycle: _cycle(field: '01211A04000001')),
    '字段短缺': () => _matches(cycle: _cycle(field: '01211A04')),
  };
  for (final variant in variants.entries) {
    test('${variant.key}不合并城际操作', () => expect(variant.value(), isFalse));
  }
}

bool _matches({
  bool entry = true,
  bool rail = true,
  String city = '3300',
  String station = '4112305000000121',
  String terminal = '3050000001211A04',
  String agency = '03493370FFFFFFFF',
  int line = 1,
  int? amount = 0,
  int seconds = 0,
  TUnionTripRecord? cycle,
}) {
  final record = cycle ?? _cycle();
  return matchesTunionJourneySide(
    isEntry: entry,
    isRail: rail,
    time: record.time.add(Duration(seconds: seconds)),
    cityCode: city,
    terminalId: terminal,
    amountFen: amount,
    stationId: station,
    lineCode: line,
    agencyId: agency,
    cycle: record,
  );
}

TUnionTripRecord _cycle({
  bool entry = true,
  int app = 0x0A,
  String city = '3370',
  String agency = '03493370FFFFFFFF',
  String? terminal,
  String? field,
}) => TUnionTripRecord(
  typeCode: entry ? 3 : 4,
  appTypeCode: app,
  time: entry
      ? DateTime(2026, 11, 4, 7, 49, 47)
      : DateTime(2026, 11, 4, 9, 41, 23),
  cityCode: city,
  acquirerId: agency,
  terminalId: terminal ?? (entry ? '4131014305290000' : '4131018830620000'),
  lineStationCode: field ?? (entry ? '01211A04000000' : '11351501000000'),
  amountFen: 0,
  balanceFen: 1500,
);
