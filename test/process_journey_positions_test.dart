import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/transit_analysis/process_journey_positions.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

void main() {
  test('过程原始槽号保留未知和空槽造成的缺口而不按列表重编号', () {
    final exit = _record(1, type: 4);
    final entry = _record(3, type: 3);
    final positions = buildProcessJourneyPositions([exit, _unknown(2), entry]);
    expect(positions[exit.trip], {'live': 1});
    expect(positions[entry.trip], {'live': 3});
    expect(positions, hasLength(2));
  });

  test('来源批次显式传入且结果保持原trip对象身份', () {
    final record = _record(17, type: 3);
    final positions = buildProcessJourneyPositions([
      record,
    ], sourceId: 'read-a');
    expect(positions.keys.single, same(record.trip));
    expect(positions[record.trip], {'read-a': 17});
  });

  test('未知类型仍保留原始槽号以阻断过滤后的跨记录配对', () {
    final record = _record(2, type: 0x7F);
    final positions = buildProcessJourneyPositions([record]);
    expect(positions[record.trip], {'live': 2});
  });

  for (final invalid in [
    _record(0, type: 3),
    _record(-1, type: 3),
    _record(1, type: 3, sfi: 0x1A),
    _record(1, type: 3, reliable: false),
  ]) {
    test(
      '未证明原始槽位的记录不提供位置 ${invalid.sfi}/${invalid.recordNumber}/${invalid.recordNumberIsReliable}',
      () {
        expect(buildProcessJourneyPositions([invalid]), isEmpty);
      },
    );
  }

  test('重复槽号包括未解码占位都会使该槽证据失效', () {
    final first = _record(1, type: 3);
    final second = _record(1, type: 4);
    expect(buildProcessJourneyPositions([first, second]), isEmpty);
    expect(buildProcessJourneyPositions([first, _unknown(1)]), isEmpty);
  });

  test('相同trip对象或相同原码的多个槽位不任选其一', () {
    final first = _record(1, type: 3);
    final sameObject = TUnionProcessRecord(
      sfi: 0x1E,
      recordNumber: 2,
      recordName: '循环记录2',
      raw: first.raw,
      trip: first.trip,
    );
    expect(buildProcessJourneyPositions([first, sameObject]), isEmpty);
    final sameRaw = _record(2, type: 3, raw: first.raw);
    expect(buildProcessJourneyPositions([first, sameRaw]), isEmpty);
  });

  test('空来源与空白原始记录不产生顺序证据', () {
    expect(
      buildProcessJourneyPositions([_record(1, type: 3)], sourceId: ''),
      isEmpty,
    );
    expect(
      buildProcessJourneyPositions([
        _record(1, type: 3, raw: List.filled(48, 0)),
      ]),
      isEmpty,
    );
  });
}

TUnionProcessRecord _record(
  int number, {
  required int type,
  int sfi = 0x1E,
  bool reliable = true,
  List<int>? raw,
}) => TUnionProcessRecord(
  sfi: sfi,
  recordNumber: number,
  recordNumberIsReliable: reliable,
  recordName: '循环记录 $number',
  raw: raw ?? [type, number, ...List.filled(46, 1)],
  trip: TUnionTripRecord(
    typeCode: type,
    terminalId: '0000000000000001',
    appTypeCode: 1,
    lineStationCode: '00010001000100',
    amountFen: 0,
    balanceFen: 9000,
    time: DateTime(2026, 10, 27, 8),
    cityCode: '2500',
  ),
);

TUnionProcessRecord _unknown(int number) => TUnionProcessRecord(
  sfi: 0x1E,
  recordNumber: number,
  recordName: '未知记录',
  raw: [0x7F, number],
);
