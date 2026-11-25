import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';

void main() {
  test('哈尔滨重读补足同笔异地地铁的站名，旧流水与新批次共用一个展示条目', () {
    final old = _harbinRecord();
    final current = _harbinRecord(mirror: true);
    for (final payloads in [
      [old, current],
      [current, old],
    ]) {
      final history = _history(payloads);
      final journeys = presentArchiveTrips(
        history.records,
        batches: history.batches,
      ).journeys;
      expect(journeys, hasLength(1));
      final ride = journeys.single;
      expect(ride.state, JourneyState.incomplete);
      expect(ride.events.first.endpoint.station, '上海火车站');
      expect(ride.amountText, '-¥ 4.00');
      expect(ride.events.expand((event) => event.sourceIds).toSet(), {
        'read-0',
        'read-1',
      });
      expect(
        history.batches.map((b) => b.decoded.rawJson),
        unorderedEquals(payloads),
      );
    }
  });

  test('哈尔滨站名、分类、余额冲突或同批重复时保留各笔观察', () {
    final current = _harbinRecord(mirror: true);
    for (final old in [
      _harbinRecord(station: '其他站'),
      _harbinRecord(category: '轮渡'),
      _harbinRecord(balance: 8800),
    ]) {
      _expectSeparate([old, current], count: 2, events: 2, completed: 0);
    }
    _expectSeparate(
      [_harbinRecord(duplicate: true), current],
      count: 3,
      events: 3,
      completed: 0,
    );
  });

  test('分类缺失的重复交易由唯一完整行程吸收且保留原事件来源及快照', () {
    final payloads = [_snapshot(partial: true), _snapshot()];
    final history = _history(payloads);
    final before = jsonEncode(history.records.map((r) => r.fields).toList());
    final result = presentArchiveTrips(
      history.records,
      batches: history.batches,
      onDiagnostics: (_) {},
    );
    expect(result.journeys, hasLength(1));
    final journey = result.journeys.single;
    expect(journey.state, JourneyState.completed);
    expect(journey.duration, const Duration(minutes: 30));
    expect(journey.balanceAfterText, '¥ 97.00');
    expect(journey.events, hasLength(3));
    expect(
      journey.events.where((e) => e.role == JourneyEventRole.unknown),
      hasLength(1),
    );
    expect(journey.events.expand((e) => e.sourceIds).toSet(), {
      'read-0',
      'read-1',
    });
    expect(jsonEncode(history.records.map((r) => r.fields).toList()), before);
    expect(
      history.batches.map((b) => b.decoded.rawJson),
      unorderedEquals(payloads),
    );
    expect(
      history.batches.map((b) => b.decoded.snapshot!.encode()),
      unorderedEquals(payloads),
    );
  });

  test('多个完整结构候选即使只有一个余额相符也不吸收', () {
    _expectSeparate(
      [
        _snapshot(partial: true),
        _snapshot(),
        _snapshot(exitMarker: '030405', balance: 9600),
      ],
      count: 3,
      events: 5,
      completed: 2,
    );
  });

  test('同批次两个分类缺失的相同交易候选不能被完整行程消除', () {
    _expectSeparate(
      [_snapshot(partial: true, duplicate: true), _snapshot()],
      count: 3,
      events: 4,
    );
  });

  test('同批次重复原文即使事实身份不同也不能被另一批次吸收', () {
    _expectSeparate(
      [
        _snapshot(partial: true, duplicate: true, duplicateAmount: 1),
        _snapshot(),
      ],
      count: 3,
      events: 4,
    );
  });

  test('分类缺失观察与完整行程同侧余额冲突时不吸收', () {
    _expectSeparate(
      [
        _snapshot(partial: true, entryBalance: 9900),
        _snapshot(entryBalance: 10000),
      ],
      count: 2,
      events: 3,
    );
  });

  test('未知余额不能作为两个已知冲突余额的桥且结果不依赖输入顺序', () {
    final payloads = [
      _snapshot(partial: true, entryBalance: 10000),
      _snapshot(partial: true, entryBalance: 9900),
      _snapshot(),
    ];
    _expectSeparate(payloads, count: 3, events: 4);
    _expectSeparate(payloads.reversed.toList(), count: 3, events: 4);
  });

  test('记录余额和交易后余额语义冲突不吸收', () {
    _expectSeparate(
      [
        _snapshot(partial: true, entryBalance: 10000, recorded: true),
        _snapshot(entryBalance: 10000),
      ],
      count: 2,
      events: 3,
    );
  });

  for (final difference in ['raw', 'context', 'fact', 'city', 'mode', 'role']) {
    test('$difference 不同的观察不吸收', () {
      _expectSeparate(
        [_snapshot(partial: true, difference: difference), _snapshot()],
        count: 2,
        events: 3,
      );
    });
  }

  test('没有原批次完整行程时不跨批次拼接连续进出站', () {
    _expectSeparate(
      [_snapshot(onlyEntry: true), _snapshot(onlyExit: true)],
      count: 2,
      events: 2,
      completed: 0,
    );
  });
}

String _harbinRecord({
  bool mirror = false,
  bool duplicate = false,
  String? station,
  String? category,
  int balance = 8900,
}) {
  final doc = jsonDecode(_snapshot(partial: true)) as Map<String, dynamic>;
  final row = {
    'time': DateTime.utc(2026, 10, 24, 23, 4, 4).millisecondsSinceEpoch,
    'sequence': 14,
    'consume': true,
    'composite': true,
    'typeName': '复合消费',
    'rawHex': '000E001FA4000001900920001101261820261024230404',
    'terminalId': '200011012618',
    'amountFen': 400,
    'balanceAfterFen': balance,
    'balanceAfterIsRecorded': false,
    'isEntry': false,
    'stationLabel': mirror ? '上海火车站' : station,
    'appTypeName': mirror ? '城市轨道交通' : category,
    if (mirror) ...{
      'location': {'ruleId': 'cu-0x18-mirror'},
      'lineLabel': '1号线',
      'stationConfidence': 'exact',
    },
  };
  doc['context']['systemId'] = 'tunion';
  doc['context']['applicationId'] = 'A000000632010105';
  doc['context']['displayCardType'] = 'harbin_transit_union';
  doc['cityCode'] = '2610';
  doc['parseVersion'] = mirror ? 18 : 17;
  doc['trips'] = [row, if (duplicate) row];
  return jsonEncode(doc);
}

void _expectSeparate(
  List<String> payloads, {
  required int count,
  required int events,
  int completed = 1,
}) {
  final history = _history(payloads);
  final before = jsonEncode(history.records.map((r) => r.fields).toList());
  final journeys = presentArchiveTrips(
    history.records,
    batches: history.batches,
    onDiagnostics: (_) {},
  ).journeys;
  expect(journeys, hasLength(count));
  expect(journeys.expand((j) => j.events), hasLength(events));
  expect(
    journeys.where((j) => j.state == JourneyState.completed),
    hasLength(completed),
  );
  expect(jsonEncode(history.records.map((r) => r.fields).toList()), before);
  expect(
    history.batches.map((b) => b.decoded.rawJson),
    unorderedEquals(payloads),
  );
}

ArchiveHistoryResult _history(List<String> payloads) => ArchiveHistory.project(
  ArchiveRows(
    card: const SavedCard(
      id: 'synthetic',
      cardFingerprint: 'synthetic',
      cardType: 'china_tunion',
      identificationSource: 'test',
      cardNumber: '00000001',
      createdAt: 1,
      updatedAt: 2,
    ),
    batches: [
      for (var i = 0; i < payloads.length; i++)
        CardReadBatch(
          id: 'read-$i',
          cardId: 'synthetic',
          cardFingerprint: 'synthetic',
          readAt: i + 1,
          parseVersion: 12,
          payloadJson: payloads[i],
        ),
    ],
  ),
);

String _snapshot({
  bool partial = false,
  bool duplicate = false,
  int? duplicateAmount,
  int? entryBalance,
  int balance = 9700,
  bool recorded = false,
  int exitSequence = 11,
  String exitMarker = '020304',
  String? difference,
  bool onlyEntry = false,
  bool onlyExit = false,
}) {
  Map<String, Object?> transaction(bool entry) => {
    'time': DateTime.utc(
      2026,
      10,
      31,
      14,
      entry ? 0 : 30,
    ).millisecondsSinceEpoch,
    'sequence': entry ? 10 : exitSequence,
    'consume': true,
    'typeName': '复合消费',
    'terminalId': entry ? '003000010001' : '003000010002',
    'amountFen': entry ? 0 : 300,
    'rawHex': '${entry ? '010203' : exitMarker}${List.filled(20, '01').join()}',
    'cityCode': '1000',
    'cityName': '北京市',
    'balanceAfterFen': entry ? entryBalance : balance,
    'balanceAfterIsRecorded': recorded,
    'isEntry': entry && !partial,
    if (!partial) ...{
      'appTypeName': '城市轨道交通',
      'rideStatusName': entry ? '进站' : '出站',
      'stationType': '地铁',
    },
  };
  final entry = transaction(true);
  switch (difference) {
    case 'raw':
      entry['rawHex'] = '${entry['rawHex']}01';
    case 'fact':
      entry['amountFen'] = 1;
    case 'city':
      entry['cityCode'] = '3100';
    case 'mode':
      entry['appTypeName'] = '公共汽电车';
    case 'role':
      entry['appTypeName'] = '城市轨道交通';
      entry['rideStatusName'] = '出站';
  }
  return jsonEncode({
    'v': 3,
    'parseVersion': 12,
    'cityCode': '1000',
    'context': {
      'systemId': 'TU',
      'applicationId': difference == 'context' ? 'other-wallet' : 'wallet',
      'currencyCode': 'CNY',
      'minorUnitDigits': 2,
      'timeZoneOffsetMinutes': 480,
      'clockBasis': 'device-local-card-time-unverified',
    },
    'trips': [
      if (!onlyExit) entry,
      if (duplicate) {...entry, 'amountFen': ?duplicateAmount},
      if (!partial && !onlyEntry) transaction(false),
    ],
    'rails': <Object?>[],
    'buses': <Object?>[],
    'cycle': <Object?>[],
    'rawEvidence': <Object?>[],
    'recordProvenance': <String, Object?>{},
    'syntheticExtension': 'retain verbatim',
  });
}
