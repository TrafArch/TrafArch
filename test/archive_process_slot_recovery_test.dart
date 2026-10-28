import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_process_parser.dart';

// Operation evidence only; no card identity files or card numbers.
const _aid = 'A000000632010105';
const _otherAid = 'A00000000386980701';
const _raw =
    '04000030008900034401080019003000000000012C0000374620261018103656'
    '100001011000FFFFFFFF000000000000';
final _differentRaw = '${_raw.substring(0, _raw.length - 2)}01';
// Exact 1E operation payloads in the supplied 2026-10-22 Shanghai report.
const _shanghaiExit =
    '04000000000836156801000800360000000000012C0000019A20260808091231'
    '290012002900FFFFFFFF000000000000';
const _shanghaiEntry =
    '030000000010571A23010010005700000000000000000002C620260808090602'
    '290012002900FFFFFFFF000000000000';

void main() {
  for (final withTransactions in [false, true]) {
    for (final reliableCapture in [false, true]) {
      test('上海${reliableCapture ? '新可靠' : '旧v5 APDU'}归档'
          '${withTransactions ? '交易4/5消费过程来源后' : '独立1E'}显示4.10且原始值不变', () {
        final payload = _shanghaiPayload(
          withTransactions: withTransactions,
          reliableCapture: reliableCapture,
        );
        final history = _history([payload]);
        final projection = presentArchiveTrips(
          history.records,
          onDiagnostics: (_) {},
        );
        final events = [
          for (final entry in projection.entries) entry.journeyEvent!,
        ];
        expect(events, hasLength(2));
        expect(
          events.map((event) => event.processPositions),
          unorderedEquals([
            {'batch-0': 1},
            {'batch-0': 2},
          ]),
        );
        if (withTransactions) {
          expect(projection.mergedRecordCount, 2);
          expect(events.map((event) => event.sequence), [5, 4]);
        }
        final journey = projectJourneys(events).single;
        expect(journey.state, JourneyState.completed);
        expect(journey.balanceAfterText, '¥ 4.10');
        expect(journey.start?.station, '天潼路');
        expect(journey.end?.station, '曲阜路');
        final processes = history.records.where(
          (record) => record.kind == ArchiveRecordKind.process,
        );
        expect(
          processes.map((record) => record.fields['balanceFen']),
          unorderedEquals([710, 410]),
        );
        expect(
          processes.map((record) => record.fields['rawHex']),
          unorderedEquals([_shanghaiEntry, _shanghaiExit]),
        );
        expect(history.batches.single.decoded.rawJson, payload);
        expect(history.batches.single.decoded.snapshot!.encode(), payload);
      });
    }
  }

  test('上海旧交易4/5只有原始1E而没有物理APDU时保持未知', () {
    final history = _history([
      _shanghaiPayload(withTransactions: true, physicalFrames: false),
    ]);
    final projection = presentArchiveTrips(
      history.records,
      onDiagnostics: (_) {},
    );
    final journey = projectJourneys([
      for (final entry in projection.entries) entry.journeyEvent!,
    ]).single;
    expect(journey.state, JourneyState.completed);
    expect(journey.balanceAfterText, isNull);
  });

  test('旧cycle原始码由同应用成功READ RECORD恢复物理槽7而非数组位置', () {
    final payload = _payload(_frames());
    final history = _history([payload]);
    expect(_positions(history), {'batch-0': 7});
    final evidence = _recordEvidence(history.records.single);
    expect(evidence['sfi'], 0x1E);
    expect(evidence['recordNumber'], 7);
    expect(evidence['recordNumberIsReliable'], isTrue);
    expect(evidence['rawHex'], _raw);
    expect(evidence['originalSource'], {'raw': '000F'});
    expect(history.batches.single.decoded.rawJson, payload);
    expect(history.batches.single.decoded.snapshot!.encode(), payload);
    expect((jsonDecode(payload) as Map)['recordProvenance'], {
      'cycle[0]': {
        'rawHex': _raw,
        'originalSource': {'raw': '000F'},
      },
    });
  });

  test('80 CLA的成功应用选择仍能证明其后的00 CLA物理读取', () {
    expect(_positions(_history([_payload(_frames(selectCla: 0x80))])), {
      'batch-0': 7,
    });
  });

  test('6C响应本身不提供槽位而同槽修正Le后的成功响应可以证明', () {
    final failed = [
      _select(0),
      _frame(1, [0, 0xB2, 7, 0xF4, 0], [0x6C, 0x30]),
    ];
    expect(_positions(_history([_payload(failed)])), isEmpty);
    expect(
      _positions(
        _history([
          _payload([
            ...failed,
            _read(2, command: [0, 0xB2, 7, 0xF4, 0x30]),
          ]),
        ]),
      ),
      {'batch-0': 7},
    );
  });

  test('同原始记录跨批次合并后只继承本批次实际捕获的APDU槽位', () {
    final history = _history([_payload(const []), _payload(_frames())]);
    expect(history.records, hasLength(1));
    expect(history.records.single.sources, hasLength(2));
    expect(_positions(history), {'batch-1': 7});
    final sources = history.records.single.sources;
    expect(
      (sources.singleWhere((s) => s.batchId == 'batch-0').provenance
          as Map)['record'],
      isNot(contains('recordNumber')),
    );
  });

  final invalidCaptures = <String, List<Map<String, dynamic>> Function()>{
    '没有应用选择': () => [_read(0)],
    '选择另一个AID': () => [_select(0, aid: _otherAid), _read(1)],
    '应用选择失败': () => [
      _select(0, response: const [0x6A, 0x82]),
      _read(1),
    ],
    '选择主文件后不沿用旧应用': () => [
      _select(0),
      _frame(1, [0, 0xA4, 0, 0, 2, 0x3F, 0, 0], [0x90, 0]),
      _read(2),
    ],
    '失败的其他SELECT也清除应用上下文': () => [
      _select(0),
      _select(1, aid: _otherAid, response: const [0x6A, 0x82]),
      _read(2),
    ],
    '跨读取会话': () => [_select(0), _read(1, session: 'other-session')],
    '帧序号有缺口': () => [_select(0), _read(2)],
    '帧序号重复': () => [_select(0), _read(0)],
    '缺少非空会话标识': () => [_select(0, session: ''), _read(1, session: '')],
    '其他传输': () => [_select(0), _read(1, transport: 'nfc-f')],
    '错误状态字': () => [
      _select(0),
      _read(1, response: [..._bytes(_raw), 0x6A, 0x83]),
    ],
    '交换失败即使残留成功字节': () => [_select(0), _read(1, errorCode: 'TAG_LOST')],
    '响应不足48字节': () => [
      _select(0),
      _read(1, response: [..._bytes(_raw).take(47), 0x90, 0]),
    ],
    '成功但原始码不同': () => [
      _select(0),
      _read(1, response: [..._bytes(_differentRaw), 0x90, 0]),
    ],
    '其他SFI': () => [
      _select(0),
      _read(1, command: [0, 0xB2, 7, 0xD4, 0]),
    ],
    '全文件读取不提供物理记录号': () => [
      _select(0),
      _read(1, command: [0, 0xB2, 7, 0xF5, 0]),
    ],
    '零记录号': () => [
      _select(0),
      _read(1, command: [0, 0xB2, 0, 0xF4, 0]),
    ],
    '缺少Le的非原始读取格式': () => [
      _select(0),
      _read(1, command: [0, 0xB2, 7, 0xF4]),
    ],
    '兼容TLV包装不能以子项顺序假装物理槽位': () => [
      _select(0),
      _read(1, response: [0x70, 0x30, ..._bytes(_raw), 0x90, 0]),
    ],
    '同槽重复成功读取': () => [_select(0), _read(1), _read(2)],
    '同槽成功但原始码冲突': () => [
      _select(0),
      _read(1),
      _read(2, response: [..._bytes(_differentRaw), 0x90, 0]),
    ],
    '相同HEX位于两个成功物理槽位': () => [
      _select(0),
      _read(1),
      _read(2, command: [0, 0xB2, 8, 0xF4, 0]),
    ],
  };
  for (final invalid in invalidCaptures.entries) {
    test('${invalid.key}不恢复旧档案槽位', () {
      expect(_positions(_history([_payload(invalid.value())])), isEmpty);
    });
  }

  for (final (label, system, aid) in [
    ('未知解析器', null, _aid),
    ('其他解析器', 'city_union', _aid),
    ('未知应用', 'tunion', null),
    ('应用与捕获SELECT不一致', 'tunion', _otherAid),
  ]) {
    test('$label不恢复物理槽位', () {
      expect(
        _positions(_history([_payload(_frames(), system: system, aid: aid)])),
        isEmpty,
      );
    });
  }

  test('上海交通联合解析器同样按独立TU应用上下文恢复', () {
    expect(
      _positions(_history([_payload(_frames(), system: 'shanghai_tunion')])),
      {'batch-0': 7},
    );
  });

  test('旧tu_process_record未声明可靠性且没有物理帧时不自行升级', () {
    expect(
      _positions(
        _history([
          _payload([
            {
              'kind': 'tu_process_record',
              'sfi': 0x1E,
              'recordNumber': 7,
              'rawHex': _raw,
            },
          ]),
        ]),
      ),
      isEmpty,
    );
  });

  test('旧来源明确不可靠或记录出处矛盾时不覆盖成可靠坐标', () {
    for (final provenance in [
      {'recordNumberIsReliable': false},
      {'sfi': 0x1A},
      {'recordNumber': 3},
      {'rawHex': _differentRaw},
    ]) {
      expect(
        _positions(_history([_payload(_frames(), provenance: provenance)])),
        isEmpty,
        reason: '$provenance',
      );
    }
  });

  test('同一cycle原始码重复出现不能任选数组项恢复', () {
    final history = _history([
      _payload(_frames(), cycleRaws: [_raw, _raw]),
    ]);
    final projection = presentArchiveTrips(
      history.records,
      onDiagnostics: (_) {},
    );
    expect(
      projection.entries.every(
        (entry) => entry.journeyEvent!.processPositions.isEmpty,
      ),
      isTrue,
    );
  });

  for (final byte in [0, 0xFF]) {
    test('全${byte.toRadixString(16)}空白记录不恢复物理槽位', () {
      final raw = List.filled(
        48,
        byte.toRadixString(16).padLeft(2, '0'),
      ).join();
      expect(
        _positions(
          _history([
            _payload(
              [
                _select(0),
                _read(1, response: [..._bytes(raw), 0x90, 0]),
              ],
              cycleRaws: [raw],
            ),
          ]),
        ),
        isEmpty,
      );
    });
  }
}

List<Map<String, dynamic>> _frames({int selectCla = 0}) => [
  _select(0, cla: selectCla),
  _read(1),
];

Map<String, dynamic> _select(
  int index, {
  String aid = _aid,
  int cla = 0,
  String session = 'capture-session',
  List<int> response = const [0x90, 0],
}) => _frame(
  index,
  [cla, 0xA4, 4, 0, aid.length ~/ 2, ..._bytes(aid), 0],
  response,
  session: session,
);

Map<String, dynamic> _read(
  int index, {
  List<int> command = const [0, 0xB2, 7, 0xF4, 0],
  List<int>? response,
  String session = 'capture-session',
  String transport = 'iso-dep',
  String? errorCode,
}) => _frame(
  index,
  command,
  response ?? [..._bytes(_raw), 0x90, 0],
  session: session,
  transport: transport,
  errorCode: errorCode,
);

Map<String, dynamic> _frame(
  int index,
  List<int> command,
  List<int> response, {
  String session = 'capture-session',
  String transport = 'iso-dep',
  String? errorCode,
}) => {
  'kind': 'physical_frame',
  'sessionId': session,
  'index': index,
  'transport': transport,
  'capturedAt': '2026-10-28T00:00:00.000Z',
  'command': command,
  'response': response,
  'errorCode': errorCode,
  'error': null,
};

String _payload(
  List<Map<String, dynamic>> evidence, {
  String? system = 'tunion',
  String? aid = _aid,
  List<String> cycleRaws = const [_raw],
  Map<String, dynamic> provenance = const {},
}) => jsonEncode({
  'v': 3,
  'parseVersion': 8,
  'context': {
    'systemId': system,
    'applicationId': aid,
    'currencyCode': 'CNY',
    'minorUnitDigits': 2,
    'clockBasis': 'device-local-card-time-unverified',
  },
  'trips': [],
  'rails': [],
  'buses': [],
  'cycle': [
    for (final raw in cycleRaws)
      {
        'typeCode': 4,
        'terminalId': '0000300089000344',
        'appTypeCode': 1,
        'lineStationCode': '08001900300000',
        'amountFen': 300,
        'balanceFen': 14150,
        'time': DateTime.utc(2026, 10, 18, 10, 36, 56).millisecondsSinceEpoch,
        'cityCode': '1000',
        'rawHex': raw,
      },
  ],
  'recordProvenance': {
    for (var index = 0; index < cycleRaws.length; index++)
      'cycle[$index]': {
        'rawHex': cycleRaws[index],
        'originalSource': {'raw': '000F'},
        ...provenance,
      },
  },
  'rawEvidence': evidence,
  'futureEnvelope': {'raw': '001000'},
});

ArchiveHistoryResult _history(List<String> payloads) => ArchiveHistory.project(
  ArchiveRows(
    card: _card,
    batches: [
      for (var index = 0; index < payloads.length; index++)
        CardReadBatch(
          id: 'batch-$index',
          cardId: _card.id,
          cardFingerprint: _card.cardFingerprint,
          readAt: index + 1,
          parseVersion:
              (jsonDecode(payloads[index]) as Map)['parseVersion'] as int,
          payloadJson: payloads[index],
        ),
    ],
  ),
);

String _shanghaiPayload({
  bool withTransactions = false,
  bool reliableCapture = false,
  bool physicalFrames = true,
}) {
  Map<String, dynamic> cycle(String raw) {
    final record = const TUnionProcessParser().parseCycleTrip(_bytes(raw))!;
    return {
      'typeCode': record.typeCode,
      'terminalId': record.terminalId,
      'appTypeCode': record.appTypeCode,
      'lineStationCode': record.lineStationCode,
      'amountFen': record.amountFen,
      'balanceFen': record.balanceFen,
      'time': record.time.millisecondsSinceEpoch,
      'capturedTimes': {
        'time': {
          'civil': record.time.toIso8601String(),
          'basis': 'parser-local-unverified',
          'isUtc': false,
        },
      },
      'cityCode': record.cityCode,
      'acquirerId': record.acquirerId,
      'rawHex': raw,
      'capturedDisplay': {
        'line': record.isEntry ? '10号线' : '8号线',
        'station': record.isEntry ? '天潼路' : '曲阜路',
        'cityName': '上海',
      },
    };
  }

  final cycles = [cycle(_shanghaiExit), cycle(_shanghaiEntry)];
  return jsonEncode({
    'v': 3,
    'parseVersion': reliableCapture ? 10 : 5,
    'context': {
      'systemId': 'shanghai_tunion',
      'applicationId': _aid,
      'currencyCode': 'CNY',
      'minorUnitDigits': 2,
      'clockBasis': 'device-local-card-time-unverified',
    },
    'trips': [
      if (withTransactions)
        for (var index = 0; index < cycles.length; index++)
          {
            'time': cycles[index]['time'],
            'capturedTimes': cycles[index]['capturedTimes'],
            'sequence': index == 0 ? 5 : 4,
            'amountFen': cycles[index]['amountFen'],
            'overdraftFen': 0,
            'consume': true,
            'composite': true,
            'typeName': '复合消费',
            'terminalId': index == 0 ? '413106143299' : '413106145391',
            'cityCode': '2900',
            'cityName': '上海',
            'lineLabel': index == 0 ? '8号线' : '10号线',
            'stationLabel': index == 0 ? '曲阜路' : '天潼路',
            'appTypeName': '城市轨道交通',
            'rideStatusName': index == 0 ? '出站' : '进站',
            'isEntry': index == 1,
            'balanceAfterFen': cycles[index]['balanceFen'],
            if (reliableCapture) 'balanceAfterIsRecorded': true,
            'matchedProcess': cycles[index],
            'rawHex': index == 0
                ? '00050000000000012C0941310614329920260808091231'
                : '0004000000000000000941310614539120260808090602',
          },
    ],
    'rails': [],
    'buses': [],
    'cycle': cycles,
    'rawEvidence': [
      if (physicalFrames) ...[
        _select(0),
        _read(
          1,
          command: [0, 0xB2, 1, 0xF4, 0],
          response: [..._bytes(_shanghaiExit), 0x90, 0],
        ),
        _read(
          2,
          command: [0, 0xB2, 2, 0xF4, 0],
          response: [..._bytes(_shanghaiEntry), 0x90, 0],
        ),
      ],
      for (var index = 0; index < cycles.length; index++)
        {
          'kind': 'tu_process_record',
          'sfi': 0x1E,
          'recordNumber': index + 1,
          'rawHex': cycles[index]['rawHex'],
        },
    ],
    'recordProvenance': {
      for (var index = 0; index < cycles.length; index++)
        'cycle[$index]': {
          'rawHex': cycles[index]['rawHex'],
          if (reliableCapture) ...{
            'sfi': 0x1E,
            'recordNumber': index + 1,
            'recordNumberIsReliable': true,
          },
        },
    },
  });
}

Map<String, int> _positions(ArchiveHistoryResult history) =>
    presentArchiveTrips(
      history.records,
      onDiagnostics: (_) {},
    ).entries.single.journeyEvent!.processPositions;

Map<dynamic, dynamic> _recordEvidence(ArchiveHistoryRecord record) =>
    (record.sources.single.provenance as Map)['record'] as Map;

List<int> _bytes(String hex) => [
  for (var index = 0; index < hex.length; index += 2)
    int.parse(hex.substring(index, index + 2), radix: 16),
];

const _card = SavedCard(
  id: 'slot-test-card',
  cardFingerprint: 'slot-test-fingerprint',
  cardType: 'china_tunion',
  identificationSource: 'test',
  createdAt: 1,
  updatedAt: 1,
);
