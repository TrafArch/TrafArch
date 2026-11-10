import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_process_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_trip_matcher.dart';

// Exact 1E bodies from physical slots 11 and 12 of the reported
// transit_card_log_20261109_163523.json; status words are omitted.
// The attachment contains no archive JSON. Every parseVersion 12 archive,
// transaction body and card identity below is an explicit synthetic reproduction
// of the pre-444b351 writer, not a copy of the user's actual saved archive.
const _exitRaw =
    '160000413106034291010001008F000300000001C20000050A2026102512252522101217221000000000000002BC0000';
const _entryRaw =
    '150000413106034010010001007900030000000000000006CC2026102511565122101217221000000000000002BC0000';

void main() {
  test('模拟v12未知交易与后续独立沈阳16出站只展示一次且保留两批原文', () {
    final payloads = [_oldPayload(), _newPayload()];
    final history = _history(payloads);
    final before = _savedFields(history);

    final projection = _present(history);

    expect(projection.journeys, hasLength(1));
    final journey = projection.journeys.single;
    expect(journey.state, JourneyState.incomplete);
    expect(journey.end?.time, DateTime.utc(2026, 10, 25, 12, 25, 25));
    expect(journey.end?.station, '铁西广场');
    expect(journey.amountText, '-¥ 4.50');
    expect(journey.events, hasLength(2));
    expect(journey.events.map((event) => event.role).toSet(), {
      JourneyEventRole.exit,
    });
    expect(journey.events.map((event) => event.payload.source).toSet(), {
      ArchiveRecordKind.transaction,
      ArchiveRecordKind.process,
    });
    expect(journey.events.expand((event) => event.sourceIds).toSet(), {
      'read-0',
      'read-1',
    });
    _expectRoleOnlyRecovery(projection, history);
    _expectUnchanged(history, payloads, before);
  });

  test('模拟v12未知出站观察可被后续真实11和12槽完成行程吸收而不重写旧快照', () {
    final payloads = [_oldPayload(), _newPayload(withEntry: true)];
    final history = _history(payloads);
    final before = _savedFields(history);

    final projection = _present(history);

    expect(projection.journeys, hasLength(1));
    final journey = projection.journeys.single;
    expect(journey.state, JourneyState.completed);
    expect(journey.start?.time, DateTime.utc(2026, 10, 25, 11, 56, 51));
    expect(journey.end?.time, DateTime.utc(2026, 10, 25, 12, 25, 25));
    expect(journey.duration, const Duration(minutes: 28, seconds: 34));
    expect(journey.amountText, '-¥ 4.50');
    expect(journey.events, hasLength(3));
    expect(journey.events.expand((event) => event.sourceIds).toSet(), {
      'read-0',
      'read-1',
    });
    expect(
      journey.events.where(
        (event) => event.payload.source == ArchiveRecordKind.transaction,
      ),
      hasLength(1),
    );
    _expectRoleOnlyRecovery(projection, history);
    _expectUnchanged(history, payloads, before);
  });

  test('模拟旧交易已保存完整matchedProcess时继续按16原码恢复出站身份', () {
    final payloads = [_oldPayload(withMatchedProcess: true), _newPayload()];
    final history = _history(payloads);
    final before = _savedFields(history);

    final projection = _present(history);

    expect(projection.journeys, hasLength(1));
    expect(projection.journeys.single.events, hasLength(2));
    expect(
      projection.journeys.single.events.map((event) => event.role).toSet(),
      {JourneyEventRole.exit},
    );
    _expectUnchanged(history, payloads, before);
  });

  for (final difference in ['time', 'amount', 'terminal', 'city']) {
    test('模拟旧displayProcessKey的$difference不符不能提升为相同操作见证', () {
      final exit = _cycle(_exitRaw);
      final payloads = [
        _oldPayload(
          transactionTime: difference == 'time'
              ? exit.time.add(const Duration(seconds: 1))
              : null,
          amountFen: difference == 'amount' ? 451 : 450,
          terminalId: difference == 'terminal'
              ? '413106034292'
              : '413106034291',
          cityCode: difference == 'city' ? '2211' : '2210',
        ),
        _newPayload(),
      ];
      final history = _history(payloads);
      final before = _savedFields(history);

      final projection = _present(history);

      expect(projection.journeys, hasLength(2), reason: difference);
      for (final journey in projection.journeys) {
        expect(
          journey.events.expand((event) => event.sourceIds).toSet(),
          hasLength(1),
          reason: '$difference不符的保存展示关联不能成为跨批次操作身份',
        );
      }
      expect(
        projection.journeys
            .expand((journey) => journey.events)
            .singleWhere(
              (event) => event.payload.source == ArchiveRecordKind.transaction,
            )
            .role,
        JourneyEventRole.unknown,
      );
      _expectUnchanged(history, payloads, before);
    });
  }

  test('模拟同批次两个相同1E候选不能任取一个为未知旧交易提供身份', () {
    final payloads = [_oldPayload(processCount: 2), _newPayload()];
    final history = _history(payloads);
    final before = _savedFields(history);

    final projection = _present(history);

    final transaction = projection.journeys
        .expand((journey) => journey.events)
        .singleWhere(
          (event) => event.payload.source == ArchiveRecordKind.transaction,
        );
    expect(transaction.role, JourneyEventRole.unknown);
    expect(transaction.sourceIds, {'read-0'});
    expect(
      projection.journeys.any(
        (journey) => journey.state == JourneyState.completed,
      ),
      isFalse,
    );
    final old = history.batches.singleWhere((batch) => batch.id == 'read-0');
    expect(old.decoded.snapshot!.processTrips, hasLength(2));
    _expectUnchanged(history, payloads, before);
  });

  test('模拟同批次两条交易指向一个1E时不能为任一未知交易授予见证', () {
    final payloads = [_oldPayload(transactionCount: 2), _newPayload()];
    final history = _history(payloads);
    final before = _savedFields(history);

    final projection = _present(history);

    expect(projection.journeys, hasLength(3));
    final transactions = projection.journeys
        .expand((journey) => journey.events)
        .where((event) => event.payload.source == ArchiveRecordKind.transaction)
        .toList();
    expect(transactions, hasLength(2));
    expect(
      transactions.map((event) => event.role),
      everyElement(JourneyEventRole.unknown),
    );
    expect(
      transactions.every((event) => event.sourceIds.single == 'read-0'),
      isTrue,
    );
    _expectUnchanged(history, payloads, before);
  });

  test('模拟旧交易明确写入相反进站方向时不得被16出站覆盖或跨批次配对', () {
    final payloads = [
      _oldPayload(rideStatusName: '进站', isEntry: true),
      _newPayload(),
    ];
    final history = _history(payloads);
    final before = _savedFields(history);

    final projection = _present(history);

    expect(projection.journeys, hasLength(2));
    expect(
      projection.journeys.any(
        (journey) => journey.state == JourneyState.completed,
      ),
      isFalse,
    );
    final transaction = projection.journeys
        .expand((journey) => journey.events)
        .singleWhere(
          (event) => event.payload.source == ArchiveRecordKind.transaction,
        );
    expect(transaction.role, JourneyEventRole.entry);
    expect(transaction.sourceIds, {'read-0'});
    _expectUnchanged(history, payloads, before);
  });

  final inconsistentCaptures = <String, void Function(Map<String, dynamic>)>{
    '交易原文截短': (payload) {
      final fields = _fields(payload, 'trips');
      fields['rawHex'] = (fields['rawHex'] as String).substring(0, 44);
    },
    '过程原文截短': (payload) {
      final fields = _fields(payload, 'cycle');
      fields['rawHex'] = (fields['rawHex'] as String).substring(0, 94);
    },
    '交易序号字段与原文不符': (payload) {
      _fields(payload, 'trips')['sequence'] = 501;
    },
    '交易原文序号与字段不符': (payload) {
      final fields = _fields(payload, 'trips');
      fields['rawHex'] = _replaceRawByte(fields['rawHex'] as String, 1, 0xF5);
    },
    '透支字段与原文不符': (payload) {
      _fields(payload, 'trips')['overdraftFen'] = 1;
    },
    '原文透支与字段不符': (payload) {
      final fields = _fields(payload, 'trips');
      fields['rawHex'] = _replaceRawByte(fields['rawHex'] as String, 4, 1);
    },
    '交易原类型不是复合消费': (payload) {
      final fields = _fields(payload, 'trips');
      fields['rawHex'] = _replaceRawByte(fields['rawHex'] as String, 9, 6);
    },
    '交易原文金额与捕获金额不符': (payload) {
      final fields = _fields(payload, 'trips');
      fields['rawHex'] = _replaceRawByte(fields['rawHex'] as String, 8, 0xC3);
    },
    '交易民用时间与原文不符': (payload) {
      final captured =
          _fields(payload, 'trips')['capturedTimes'] as Map<String, dynamic>;
      (captured['time'] as Map<String, dynamic>)['civil'] =
          '2026-10-25T12:25:26.000';
    },
    '过程民用时间与原文不符': (payload) {
      final captured =
          _fields(payload, 'cycle')['capturedTimes'] as Map<String, dynamic>;
      (captured['time'] as Map<String, dynamic>)['civil'] =
          '2026-10-25T12:25:26.000';
    },
    '交易epoch与过程epoch不符': (payload) {
      final fields = _fields(payload, 'trips');
      fields['time'] = (fields['time'] as int) + 1000;
    },
    '过程epoch与交易epoch不符': (payload) {
      final fields = _fields(payload, 'cycle');
      fields['time'] = (fields['time'] as int) + 1000;
    },
    '相反轨道应用分类': (payload) {
      _fields(payload, 'trips')['appTypeName'] = '城际铁路';
    },
    '已有方向推断来源': (payload) {
      _fields(payload, 'trips')['rideStatusSource'] =
          'synthetic-existing-direction-evidence';
    },
  };
  for (final mutation in inconsistentCaptures.entries) {
    test('模拟旧档案${mutation.key}时不得授予恢复角色', () {
      _expectUnknownUnmerged([
        _changedPayload(_oldPayload(), mutation.value),
        _newPayload(),
      ]);
    });
  }

  for (final field in <String, Object>{
    'typeCode': 0x02,
    'terminalId': '0000413106034292',
    'appTypeCode': 0x0A,
    'lineStationCode': '00010090000300',
    'amountFen': 451,
    'balanceFen': 1291,
    'cityCode': '2211',
    'acquirerId': '1217221000000001',
  }.entries) {
    test('模拟旧过程${field.key}与完整48字节原文不符时不得授予恢复角色', () {
      _expectUnknownUnmerged([
        _changedPayload(_oldPayload(), (payload) {
          _fields(payload, 'cycle')[field.key] = field.value;
        }),
        _newPayload(),
      ]);
    });
  }

  for (final field in [
    'systemId',
    'applicationId',
    'currencyCode',
    'minorUnitDigits',
    'clockBasis',
  ]) {
    test('模拟旧档案缺少$field上下文时不得授予恢复角色', () {
      _expectUnknownUnmerged([
        _changedPayload(_oldPayload(), (payload) {
          (payload['context'] as Map<String, dynamic>)[field] = null;
        }),
        _newPayload(),
      ]);
    });
  }

  for (final version in {13, kTripParseVersion, 99}) {
    test('模拟解析版本$version未保存方向时保持原样而不套用旧writer恢复', () {
      _expectUnknownUnmerged([
        _oldPayload(parseVersion: version),
        _newPayload(),
      ]);
    });
  }

  test('模拟旧交易公交分类继续保留single语义而不被轨道出站见证改写', () {
    final payloads = [
      _changedPayload(_oldPayload(), (payload) {
        _fields(payload, 'trips')['appTypeName'] = '公共汽电车';
      }),
      _newPayload(),
    ];
    final history = _history(payloads);
    final before = _savedFields(history);

    final projection = _present(history);

    final transaction = projection.journeys
        .expand((journey) => journey.events)
        .singleWhere(
          (event) => event.payload.source == ArchiveRecordKind.transaction,
        );
    expect(transaction.role, JourneyEventRole.single);
    expect(transaction.sourceIds, {'read-0'});
    expect(projection.journeys.length, greaterThanOrEqualTo(2));
    _expectUnchanged(history, payloads, before);
  });

  test('模拟另一城市1000标准EC轨道出站也能从完整同批次原文恢复操作见证', () {
    final raw = _syntheticStandardExitRaw();
    final payloads = [
      _oldPayload(
        processRaw: raw,
        terminalId: '300001000099',
        cityCode: '1000',
      ),
      _newPayload(processRaw: raw),
    ];
    final history = _history(payloads);
    final before = _savedFields(history);

    final projection = _present(history);

    expect(projection.journeys, hasLength(1));
    final journey = projection.journeys.single;
    expect(journey.events, hasLength(2));
    expect(journey.events.map((event) => event.role).toSet(), {
      JourneyEventRole.exit,
    });
    expect(journey.events.map((event) => event.cityCode).toSet(), {'1000'});
    expect(journey.events.expand((event) => event.sourceIds).toSet(), {
      'read-0',
      'read-1',
    });
    expect(journey.amountText, '-¥ 4.50');
    expect(_cycle(raw).typeCode, 0x02);
    _expectRoleOnlyRecovery(projection, history);
    _expectUnchanged(history, payloads, before);
  });
}

String _oldPayload({
  DateTime? transactionTime,
  int amountFen = 450,
  String terminalId = '413106034291',
  String cityCode = '2210',
  String? rideStatusName,
  bool isEntry = false,
  bool withMatchedProcess = false,
  int transactionCount = 1,
  int processCount = 1,
  int parseVersion = 12,
  String processRaw = _exitRaw,
}) {
  final exit = _cycle(processRaw);
  final time = transactionTime ?? exit.time;
  return _snapshot(
    parseVersion: parseVersion,
    trips: [
      for (var i = 0; i < transactionCount; i++)
        TransitTrip(
          time: time,
          amountFen: amountFen,
          overdraftLimitFen: 0,
          isConsume: true,
          typeName: '复合消费',
          isCompositeConsume: true,
          sequence: 500 + i,
          terminalId: terminalId,
          cityCode: cityCode,
          cityName: cityCode == '2210'
              ? '沈阳市'
              : cityCode == '1000'
              ? '北京市'
              : null,
          lineLabel: '1号线',
          stationLabel: cityCode == '2210' ? '铁西广场' : '模拟终站',
          appTypeName: '城市轨道交通',
          rideStatusName: rideStatusName,
          isEntry: isEntry,
          displayProcessKey: cycleDisplayKey(exit),
          matchedProcessTrip: withMatchedProcess ? exit : null,
          rawHex: _syntheticTransactionRaw(
            sequence: 500 + i,
            time: time,
            amountFen: amountFen,
            terminalId: terminalId,
          ),
        ),
    ],
    processes: [for (var i = 0; i < processCount; i++) exit],
    slots: [for (var i = 0; i < processCount; i++) 11 + i],
  );
}

String _newPayload({bool withEntry = false, String processRaw = _exitRaw}) =>
    _snapshot(
      parseVersion: kTripParseVersion,
      processes: [_cycle(processRaw), if (withEntry) _cycle(_entryRaw)],
      slots: [11, if (withEntry) 12],
    );

String _snapshot({
  required int parseVersion,
  List<TransitTrip> trips = const [],
  required List<TUnionTripRecord> processes,
  required List<int> slots,
}) => CardSessionSnapshot(
  parseVersion: parseVersion,
  context: const ArchiveContext(
    systemId: 'tunion',
    applicationId: 'A000000632010105',
    currencyCode: 'CNY',
    minorUnitDigits: 2,
    clockBasis: 'device-local-card-time-unverified',
  ),
  cardCityCode: '1000',
  trips: trips,
  processTrips: processes,
  extensions: const {
    'syntheticEvidence':
        'Simulated legacy archive; supplied attachment contains APDU logs only',
  },
  recordProvenance: {
    for (var i = 0; i < processes.length; i++)
      'cycle[$i]': {
        'sfi': 0x1E,
        'recordNumber': slots[i],
        'recordNumberIsReliable': true,
        'rawHex': processes[i].rawHex,
        'capturedDisplay': {
          'line': '1号线',
          if (!processes[i].isEntry)
            'station': processes[i].cityCode == '2210' ? '铁西广场' : '模拟终站',
          'cityName': processes[i].cityCode == '2210' ? '沈阳市' : '北京市',
        },
      },
  },
).encode();

TUnionTripRecord _cycle(String raw) =>
    const TUnionProcessParser().parseCycleTrip(_bytes(raw))!;

// This second city's entire 48-byte record is synthetic. It uses the ordinary
// EC exit type, BE money and a zero-padded matching 12-digit basic terminal.
String _syntheticStandardExitRaw() {
  final raw = List<int>.filled(48, 0);
  raw[0] = 0x02;
  raw.setRange(1, 9, _bytes('0000300001000099'));
  raw[9] = 0x01;
  raw.setRange(10, 17, _bytes('00010001000100'));
  raw.setRange(17, 32, _bytes('000001C20000050A20261025122525'));
  raw.setRange(32, 34, _bytes('1000'));
  raw.setRange(34, 42, _bytes('01011000FFFFFFFF'));
  return _hex(raw);
}

Map<String, dynamic> _fields(Map<String, dynamic> payload, String section) =>
    (payload[section] as List).single as Map<String, dynamic>;

String _changedPayload(
  String original,
  void Function(Map<String, dynamic>) change,
) {
  final payload = jsonDecode(original) as Map<String, dynamic>;
  change(payload);
  return jsonEncode(payload);
}

String _replaceRawByte(String original, int offset, int value) {
  final raw = _bytes(original);
  raw[offset] = value;
  return _hex(raw);
}

String _hex(List<int> raw) => raw
    .map((value) => value.toRadixString(16).padLeft(2, '0'))
    .join()
    .toUpperCase();

void _expectUnknownUnmerged(List<String> payloads) {
  final history = _history(payloads);
  final before = _savedFields(history);

  final projection = _present(history);

  final transactionJourney = projection.journeys.singleWhere(
    (journey) => journey.events.any(
      (event) => event.payload.source == ArchiveRecordKind.transaction,
    ),
  );
  final transaction = transactionJourney.events.singleWhere(
    (event) => event.payload.source == ArchiveRecordKind.transaction,
  );
  expect(transaction.role, JourneyEventRole.unknown);
  expect(transaction.sourceIds, {'read-0'});
  expect(transactionJourney.events.expand((event) => event.sourceIds).toSet(), {
    'read-0',
  });
  expect(projection.journeys.length, greaterThanOrEqualTo(2));
  _expectUnchanged(history, payloads, before);
}

void _expectRoleOnlyRecovery(
  ArchiveTripProjection projection,
  ArchiveHistoryResult history,
) {
  final transaction = projection.journeys
      .expand((journey) => journey.events)
      .singleWhere(
        (event) => event.payload.source == ArchiveRecordKind.transaction,
      );
  expect(transaction.role, JourneyEventRole.exit);
  expect(transaction.processBalance, isNull);
  expect(transaction.balanceAfterText, isNull);
  expect(transaction.confirmedBalanceFen, isNull);
  final old = history.batches.singleWhere((batch) => batch.id == 'read-0');
  final original = jsonDecode(old.decoded.rawJson) as Map<String, dynamic>;
  final fields = _fields(original, 'trips');
  expect(fields['matchedProcess'], isNull);
  expect(fields['balanceAfterFen'], isNull);
  expect(fields['rideStatusName'], isNull);
  expect(fields['isEntry'], isFalse);
}

String _syntheticTransactionRaw({
  required int sequence,
  required DateTime time,
  required int amountFen,
  required String terminalId,
}) {
  final raw = List<int>.filled(23, 0);
  raw[0] = sequence >> 8;
  raw[1] = sequence & 0xFF;
  for (var i = 0; i < 4; i++) {
    raw[5 + i] = (amountFen >> (8 * (3 - i))) & 0xFF;
  }
  raw[9] = 0x09;
  raw.setRange(10, 16, _bytes(terminalId));
  final civil = [
    time.year.toString().padLeft(4, '0'),
    for (final value in [
      time.month,
      time.day,
      time.hour,
      time.minute,
      time.second,
    ])
      value.toString().padLeft(2, '0'),
  ].join();
  raw.setRange(16, 23, _bytes(civil));
  return raw
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
}

List<int> _bytes(String raw) => [
  for (var i = 0; i < raw.length; i += 2)
    int.parse(raw.substring(i, i + 2), radix: 16),
];

ArchiveTripProjection _present(ArchiveHistoryResult history) =>
    presentArchiveTrips(
      history.records,
      batches: history.batches,
      onDiagnostics: (_) {},
    );

ArchiveHistoryResult _history(List<String> payloads) => ArchiveHistory.project(
  ArchiveRows(
    card: const SavedCard(
      id: 'synthetic-legacy-process-witness',
      cardFingerprint: 'synthetic-legacy-process-witness',
      cardType: 'china_tunion',
      identificationSource: 'synthetic-test',
      cardNumber: '00000001',
      createdAt: 1,
      updatedAt: 2,
    ),
    batches: [
      for (var i = 0; i < payloads.length; i++)
        CardReadBatch(
          id: 'read-$i',
          cardId: 'synthetic-legacy-process-witness',
          cardFingerprint: 'synthetic-legacy-process-witness',
          readAt: i + 1,
          parseVersion:
              (jsonDecode(payloads[i]) as Map<String, dynamic>)['parseVersion']
                  as int,
          payloadJson: payloads[i],
        ),
    ],
  ),
);

String _savedFields(ArchiveHistoryResult history) =>
    jsonEncode([for (final record in history.records) record.fields]);

void _expectUnchanged(
  ArchiveHistoryResult history,
  List<String> payloads,
  String before,
) {
  expect(_savedFields(history), before);
  expect(history.batches, hasLength(payloads.length));
  for (final batch in history.batches) {
    final index = int.parse(batch.id.split('-').last);
    expect(batch.decoded.rawJson, payloads[index]);
    expect(batch.decoded.snapshot!.encode(), payloads[index]);
  }
  final old = history.batches.singleWhere((batch) => batch.id == 'read-0');
  final original = jsonDecode(old.decoded.rawJson) as Map<String, dynamic>;
  final transactions = original['trips'] as List;
  for (final value in transactions) {
    final fields = value as Map<String, dynamic>;
    expect(fields['displayProcessKey'], isNotNull);
    // These assertions inspect the exact preserved simulated old payload,
    // independent of any derived role or operation witnesses in the UI.
    if (fields['rideStatusName'] == null && fields['matchedProcess'] == null) {
      expect(fields['isEntry'], isFalse);
    }
  }
}
