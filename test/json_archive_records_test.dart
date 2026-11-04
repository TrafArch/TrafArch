import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_records_json.dart';
import 'package:transit_card_analyzer/features/archive/application/cu_archive_projection.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/archive/domain/archive_export_options.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/reference_match.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/station_codes.dart';
import 'package:transit_card_analyzer/features/transit_analysis/cu_transaction_analysis.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_file_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_trip_matcher.dart';

void main() {
  test(
    'selected JSON contains only selected fields and no hidden card evidence',
    () {
      final encoded = encodeArchiveRecords(
        [
          {
            'card_number': '000123',
            'time': '2026-10-26T12:00:01',
            'amount': '-3.00',
            'rawHex': 'SECRET_RAW',
            'rawEvidence': {'card': 'SECRET_CARD'},
          },
        ],
        fields: {ArchiveExportField.time, ArchiveExportField.amount},
      );
      final document = jsonDecode(encoded) as Map<String, dynamic>;
      expect(document['format'], 'trafarch.records');
      expect(document['version'], 1);
      expect(document['fields'], ['time', 'amount']);
      expect(document['records'], [
        {'time': '2026-10-26T12:00:01', 'amount': '-3.00'},
      ]);
      expect(encoded, isNot(contains('000123')));
      expect(encoded, isNot(contains('SECRET_')));
      expect(encoded, isNot(contains('rawEvidence')));
    },
  );

  test(
    'record file roundtrips selected omissions, nulls, and leading zeroes',
    () {
      final encoded = encodeArchiveRecords(
        [
          {
            'card_number': '000123',
            'entry_station_code': '000A',
            'amount': null,
          },
        ],
        fields: {
          ArchiveExportField.cardNumber,
          ArchiveExportField.entryStationCode,
          ArchiveExportField.amount,
        },
        exportedAt: DateTime.utc(2026, 10, 26),
      );
      final decoded = decodeArchiveRecords(encoded);
      expect(decoded.exportedAt, DateTime.utc(2026, 10, 26));
      expect(decoded.fields, {
        ArchiveExportField.cardNumber,
        ArchiveExportField.entryStationCode,
        ArchiveExportField.amount,
      });
      expect(decoded.records.single, {
        'card_number': '000123',
        'entry_station_code': '000A',
        'amount': null,
      });
      expect(decoded.records.single, isNot(contains('card_name')));
    },
  );

  test(
    'records require selected fields while full backup permits empty selection',
    () {
      expect(() => ArchiveExportOptions(fields: {}), throwsArgumentError);
      expect(() => encodeArchiveRecords([], fields: {}), throwsArgumentError);
      expect(
        ArchiveExportOptions(
          mode: ArchiveExportMode.fullBackup,
          fields: {},
        ).mode,
        ArchiveExportMode.fullBackup,
      );
    },
  );

  test(
    'record import rejects unsupported versions, nested or undeclared values',
    () {
      final valid = <String, dynamic>{
        'format': 'trafarch.records',
        'version': 1,
        'exportedAt': '2026-10-26T00:00:00.000Z',
        'fields': ['card_number'],
        'records': [
          {'card_number': '0001'},
        ],
      };
      for (final document in [
        {...valid, 'version': 2},
        {
          ...valid,
          'fields': ['card_number', 'card_number'],
        },
        {
          ...valid,
          'fields': ['unknown_field'],
        },
        {
          ...valid,
          'records': [
            {'card_number': 1},
          ],
        },
        {
          ...valid,
          'records': [
            {
              'card_number': {'nested': 'value'},
            },
          ],
        },
        {
          ...valid,
          'records': [
            {'card_number': '0001', 'amount': '99'},
          ],
        },
        {
          ...valid,
          'rawEvidence': {'private': 'hidden'},
        },
        {...valid, 'exportedAt': 'not-a-date'},
        {...valid, 'exportedAt': '2026-10-26T12:00:00'},
      ]) {
        expect(
          () => decodeArchiveRecords(jsonEncode(document)),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'TU civil time, identifiers, signed amount and captured entry side survive',
    () {
      final record = _record(ArchiveRecordKind.transaction, {
        'time': 1,
        'capturedTimes': {
          'time': {'civil': '2026-10-26T12:30:45'},
        },
        'amountFen': 315,
        'consume': true,
        'typeName': '消费',
        'isEntry': true,
        'rideStatusName': '进站',
        'stationLabel': '保存站名',
        'lineLabel': '保存线路',
        'location': {'stationCode': '000A', 'lineCode': '0010'},
        'terminalId': '000000123456',
        'balanceAfterFen': 12345,
      });
      final row = projectArchiveRecords([
        _history([record]),
      ]).single;
      expect(row['card_number'], '000123');
      expect(row['time'], '2026-10-26T12:30:45');
      expect(row['time_basis'], 'card_local_unverified');
      expect(row['entry_time'], row['time']);
      expect(row['exit_time'], isNull);
      expect(row['entry_station'], '保存站名');
      expect(row['entry_station_code'], '000A');
      expect(row['entry_line_code'], '0010');
      expect(row['amount'], '-3.15');
      expect(row['amount_raw'], '315');
      expect(row['currency'], 'CNY');
      expect(row['balance'], '123.45');
    },
  );

  test(
    'unknown TU side stays unsided and unknown currency never becomes CNY',
    () {
      final record = _record(ArchiveRecordKind.transaction, {
        'time': 0,
        'amountFen': 100,
        'consume': true,
        'isEntry': false,
        'typeName': '其他',
        'stationLabel': '记录站点',
        'location': {'stationCode': '0002'},
      }, context: const ArchiveContext(minorUnitDigits: 2));
      final row = projectArchiveRecords([
        _history([record]),
      ]).single;
      expect(row['station'], '记录站点');
      expect(row['entry_station'], isNull);
      expect(row['exit_station'], isNull);
      expect(row['time'], '1970-01-01T00:00:00.000Z');
      expect(row['time_basis'], 'stored_epoch_unverified');
      expect(row['amount'], isNull);
      expect(row['currency'], isNull);
      expect(row['amount_raw'], '100');
    },
  );

  test(
    'paired 1E is merged once and unmatched process records remain independent',
    () {
      final process = <String, dynamic>{
        'typeCode': 2,
        'terminalId': '000123',
        'appTypeCode': 1,
        'lineStationCode': '00010002000000',
        'amountFen': 300,
        'balanceFen': 1200,
        'time': 1000,
        'rawHex': 'AABB',
      };
      final rows = projectArchiveRecords([
        _history([
          _record(ArchiveRecordKind.transaction, {
            'time': 1000,
            'amountFen': 300,
            'consume': true,
            'matchedProcess': process,
            'rideStatusName': '出站',
          }),
          _record(ArchiveRecordKind.process, process),
          _record(ArchiveRecordKind.process, {
            ...process,
            'time': 2000,
            'rawHex': 'CCDD',
          }),
        ]),
      ]);
      expect(rows, hasLength(2));
      expect(rows.where((r) => r['source'] == 'TU 0x1E'), hasLength(1));
      expect(rows.where((r) => r['source'] == 'TU 0x18 + 0x1E'), hasLength(1));
    },
  );

  test('1A pair exports both sides and never invents different line names', () {
    final record = _record(ArchiveRecordKind.rail, {
      'entryTime': 1000,
      'exitTime': 2000,
      'entryStationName': '起点',
      'exitStationName': '终点',
      'entryStationId': '0001',
      'exitStationId': '0002',
      'entryLineCode': 1,
      'exitLineCode': 2,
      'lineName': '无法区分侧的旧标签',
      'transactionAmountFen': 300,
    });
    final row = projectArchiveRecords([
      _history([record]),
    ]).single;
    expect(row['entry_station'], '起点');
    expect(row['exit_station'], '终点');
    expect(row['entry_station_code'], '0001');
    expect(row['entry_line_code'], '1');
    expect(row['exit_line_code'], '2');
    expect(row['line'], '无法区分侧的旧标签');
    expect(row['entry_line'], isNull);
    expect(row['exit_line'], isNull);
  });

  test(
    'linked 1A side enriches transaction without dropping its other side',
    () {
      final application = _record(ArchiveRecordKind.rail, {
        'entryTime': 1000,
        'exitTime': 2000,
        'entryStationName': '起点',
        'exitStationName': '终点',
        'entryStationId': '0001',
        'exitStationId': '0002',
        'entryTerminalId': '0011',
        'exitTerminalId': '0022',
        'rawHex': 'AABB',
      });
      final key = tunionDisplayKey(
        '1A-rail-true',
        DateTime.fromMillisecondsSinceEpoch(1000),
        '0011',
        'AABB',
      );
      final rows = projectArchiveRecords([
        _history([
          _record(ArchiveRecordKind.transaction, {
            'time': 1000,
            'isEntry': true,
            'displayApplicationKey': key,
          }),
          application,
        ]),
      ]);
      expect(rows, hasLength(2));
      final transaction = rows.firstWhere(
        (r) => (r['source'] as String).startsWith('TU 0x18'),
      );
      final unlinked = rows.firstWhere((r) => r['source'] == 'TU 0x1A');
      expect(transaction['entry_station'], '起点');
      expect(transaction['exit_station'], isNull);
      expect(unlinked['entry_station'], isNull);
      expect(unlinked['exit_station'], '终点');
    },
  );

  test(
    'CU frozen location stays unsided, raw amount and HEX terminal stay exact',
    () {
      final view = CuTransactionView(
        record: CityUnionFileParser.parseWalletRecord(
          0x06,
          [
            0,
            1,
            0,
            0,
            0,
            0,
            0,
            0,
            1,
            6,
            0x20,
            0,
            0x11,
            0x0A,
            1,
            0,
            0x20,
            0x24,
            9,
            0x20,
            0x12,
            0,
            0,
          ],
          kind: CityUnionTransactionKind.foreignConsumption,
          recordNumber: 5,
        ),
        transactionTime: DateTime.utc(2024, 9, 20, 4),
        regionCode: '2000',
        location: ReferenceMatch(ReferenceMatchStatus.matched, const [
          StationCodeEntry(
            code: '000A',
            type: '地铁',
            line: '保存线路',
            station: '保存站名',
            lineCode: '0010',
            stationCode: '0002',
          ),
        ]),
      );
      final raw = CardSessionSnapshot(
        extensions: {
          'cuProjection': captureCuProjection([view]),
        },
      ).encode();
      final history = ArchiveHistoryResult(
        card: _card,
        batches: [
          ArchiveBatchEvidence(
            id: 'cu',
            readAt: 1,
            storedParseVersion: 1,
            origin: 'capture',
            timeSource: 'read_at',
            decoded: CardSessionSnapshot.decodeResult(raw),
            issues: const [],
          ),
        ],
      );
      final row = projectArchiveRecords([history]).single;
      expect(row['source'], 'CU 0x06');
      expect(row['terminal'], '2000110A0100');
      expect(row['station'], '保存站名');
      expect(row['line_code'], '0010');
      expect(row['entry_station'], isNull);
      expect(row['exit_station'], isNull);
      expect(row['time'], '2024-09-20T12:00:00+08:00');
      expect(row['amount'], isNull);
      expect(row['amount_raw'], '1');
      expect(row['currency'], isNull);
    },
  );

  test(
    'linked exit leaves an entry row without repeating its completed fare',
    () {
      final key = tunionDisplayKey(
        '1A-bus-false',
        DateTime.fromMillisecondsSinceEpoch(2000),
        '0022',
        'AABB',
      );
      final rows = projectArchiveRecords([
        _history([
          _record(ArchiveRecordKind.transaction, {
            'time': 2000,
            'amountFen': 300,
            'consume': true,
            'rideStatusName': '下车',
            'displayApplicationKey': key,
          }),
          _record(ArchiveRecordKind.bus, {
            'entryTime': 1000,
            'exitTime': 2000,
            'amountFen': 300,
            'entryStationCode': '0001',
            'exitStationCode': '0002',
            'entryTerminalId': '0011',
            'exitTerminalId': '0022',
            'rawHex': 'AABB',
          }),
        ]),
      ]);
      expect(rows, hasLength(2));
      final unlinked = rows.firstWhere((r) => r['source'] == 'TU 0x1A');
      expect(unlinked['entry_station_code'], '0001');
      expect(unlinked['exit_station_code'], isNull);
      expect(unlinked['amount'], isNull);
      expect(unlinked['amount_raw'], isNull);
      expect(rows.where((row) => row['amount'] == '-3.00'), hasLength(1));
    },
  );

  test(
    'entry process retains raw amount without inventing a received fare',
    () {
      final rows = projectArchiveRecords([
        _history([
          _record(ArchiveRecordKind.process, {
            'typeCode': 1,
            'terminalId': '000123',
            'appTypeCode': 1,
            'lineStationCode': '00010002000000',
            'amountFen': 300,
            'balanceFen': 1200,
            'time': 1000,
          }),
        ]),
      ]);
      expect(rows.single['entry_time'], isNotNull);
      expect(rows.single['amount'], isNull);
      expect(rows.single['amount_raw'], '300');
    },
  );

  test(
    'standalone cycle snapshot exports standard raw line and station codes',
    () {
      final fields = _cycleFields();
      expect(fields.containsKey('location'), isFalse);
      final row = projectArchiveRecords([
        _history([_record(ArchiveRecordKind.process, fields)]),
      ]).single;
      expect(row['line_code'], '0001');
      expect(row['station_code'], '0002');
      expect(row['exit_line_code'], '0001');
      expect(row['exit_station_code'], '0002');
      expect(row['line'], isNull);
      expect(row['station'], isNull);
      expect(row['exit_line'], isNull);
      expect(row['exit_station'], isNull);
    },
  );

  test(
    'cycle codes reject unknown layouts and preserve saved location priority',
    () {
      for (final code in [
        '0001',
        '000100020000',
        'unknown-layout',
        '0001000200000000',
      ]) {
        final row = projectArchiveRecords([
          _history([
            _record(
              ArchiveRecordKind.process,
              _cycleFields(lineStationCode: code),
            ),
          ]),
        ]).single;
        expect(row['line_code'], isNull, reason: code);
        expect(row['station_code'], isNull, reason: code);
        expect(row['exit_line_code'], isNull, reason: code);
        expect(row['exit_station_code'], isNull, reason: code);
      }
      final row = projectArchiveRecords([
        _history([
          _record(ArchiveRecordKind.process, {
            ..._cycleFields(),
            'location': {'lineCode': '00A1', 'stationCode': '00B2'},
          }),
        ]),
      ]).single;
      expect(row['exit_line_code'], '00A1');
      expect(row['exit_station_code'], '00B2');
    },
  );

  test('unknown TU18 type retains raw amount without inventing recharge', () {
    final row = projectArchiveRecords([
      _history([
        _record(ArchiveRecordKind.transaction, {
          'time': 1000,
          'amountFen': 300,
          'consume': false,
          'typeName': '其他(0xFE)',
        }),
      ]),
    ]).single;
    expect(row['amount'], isNull);
    expect(row['amount_raw'], '300');
    expect(row['currency'], 'CNY');
    expect(row['amount_unit'], '10^-2 CNY');
  });

  test('unknown 1E type retains raw amount without inventing recharge', () {
    final row = projectArchiveRecords([
      _history([
        _record(ArchiveRecordKind.process, _cycleFields(typeCode: 0xFE)),
      ]),
    ]).single;
    expect(row['amount'], isNull);
    expect(row['amount_raw'], '300');
    expect(row['currency'], 'CNY');
  });

  test('confirmed TU consumption and recharge keep their amount direction', () {
    final rows = projectArchiveRecords([
      _history([
        _record(ArchiveRecordKind.transaction, {
          'time': 1000,
          'amountFen': 300,
          'consume': true,
          'typeName': '消费',
        }),
        _record(ArchiveRecordKind.transaction, {
          'time': 1000,
          'amountFen': 300,
          'consume': false,
          'typeName': '充值',
        }),
        _record(ArchiveRecordKind.process, _cycleFields(typeCode: 2)),
        _record(ArchiveRecordKind.process, _cycleFields(typeCode: 9)),
        _record(ArchiveRecordKind.process, _cycleFields(typeCode: 10)),
      ]),
    ]);
    expect(rows.map((row) => row['amount']), [
      '-3.00',
      '3.00',
      '-3.00',
      '3.00',
      '3.00',
    ]);
    expect(rows.every((row) => row['amount_raw'] == '300'), isTrue);
  });

  test('沈阳地方15和16原码保留且规范化JSON分别输出进站和出站字段', () {
    // Exact 1E bodies from the supplied logs; these archive maps are synthetic.
    final records = [
      _shenyangRecord(
        type: 0x15,
        terminal: '0000413101760747',
        lineStation: '0001009F000300',
        amount: 0,
        balance: 1550,
        time: DateTime.utc(2026, 9, 30, 17, 19, 30),
        raw: '150000413101760747010001009F000300000000000000060E2026093017193022101217221000000000000002BC0000',
      ),
      _shenyangRecord(
        type: 0x16,
        terminal: '0000413101760738',
        lineStation: '0001009F000300',
        amount: 450,
        balance: 1550,
        time: DateTime.utc(2026, 9, 30, 12, 52, 42),
        raw: '160000413101760738010001009F000300000001C20000060E2026093012524222101217221000000000000002BC0000',
      ),
    ];
    final originals = [for (final record in records) jsonEncode(record.fields)];
    final rows = projectArchiveRecords([_history(records)]);

    expect(rows[0]['record_type'], '进站');
    expect(rows[0]['amount'], isNull);
    expect(rows[0]['entry_time'], '2026-09-30T17:19:30.000');
    expect(rows[0]['entry_line_code'], '0001');
    expect(rows[0]['entry_station_code'], '009F');
    expect(rows[0]['exit_time'], isNull);
    expect(rows[1]['record_type'], '出站');
    expect(rows[1]['amount'], '-4.50');
    expect(rows[1]['exit_time'], '2026-09-30T12:52:42.000');
    expect(rows[1]['exit_line_code'], '0001');
    expect(rows[1]['exit_station_code'], '009F');
    expect(rows[1]['entry_time'], isNull);
    expect(records.map((record) => record.fields['typeCode']), [0x15, 0x16]);
    expect(records.map((record) => jsonEncode(record.fields)), originals);
  });

  for (final conflicting in <String, dynamic>{
    'cityCode': '1000',
    'acquirerId': '1217221000000001',
    'terminalId': '0000300000000001',
    'appTypeCode': 2,
  }.entries) {
    test('沈阳地方类型导出缺少${conflicting.key}证据时不猜进出站', () {
      final record = _shenyangRecord(
        type: 0x16,
        terminal: '0000413101760738',
        lineStation: '0001009F000300',
        amount: 450,
        balance: 1550,
        time: DateTime.utc(2026, 9, 30, 12, 52, 42),
        raw: '160000413101760738010001009F000300000001C20000060E2026093012524222101217221000000000000002BC0000',
        overrides: {conflicting.key: conflicting.value},
      );
      final original = jsonEncode(record.fields);
      final row = projectArchiveRecords([
        _history([record]),
      ]).single;

      expect(row['record_type'], '过程记录');
      expect(row['amount'], isNull);
      expect(row['entry_time'], isNull);
      expect(row['exit_time'], isNull);
      expect(jsonEncode(record.fields), original);
    });
  }

  test('旧沈阳EP异常金额仅修正规范化JSON且amount_raw保留捕获整数', () {
    final record = _shenyangRecord(
      type: 4,
      terminal: '2210413106036382',
      lineStation: '000200D7000300',
      amount: 234946560,
      balance: 235274240,
      time: DateTime.utc(2026, 9, 30, 17, 56, 17),
      raw: '04221041310603638201000200D70003000E0100000E0600002026093017561722101217221000000000000002BC0000',
    );
    final original = jsonEncode(record.fields);
    final row = projectArchiveRecords([
      _history([record]),
    ]).single;

    expect(row['amount'], '-2.70');
    expect(row['balance'], '15.50');
    expect(row['amount_raw'], '234946560');
    expect(row['amount_unit'], '10^-2 CNY');
    expect(row['currency'], 'CNY');
    expect(jsonEncode(record.fields), original);
  });

  test('沈阳EP导出原文与捕获金额冲突时保留独立修改的金额和余额', () {
    final record = _shenyangRecord(
      type: 4,
      terminal: '2210413106036382',
      lineStation: '000200D7000300',
      amount: 12345,
      balance: 235274240,
      time: DateTime.utc(2026, 9, 30, 17, 56, 17),
      raw: '04221041310603638201000200D70003000E0100000E0600002026093017561722101217221000000000000002BC0000',
    );
    final original = jsonEncode(record.fields);
    final row = projectArchiveRecords([
      _history([record]),
    ]).single;

    expect(row['amount'], '-123.45');
    expect(row['balance'], '2352742.40');
    expect(row['amount_raw'], '12345');
    expect(jsonEncode(record.fields), original);
  });
}

ArchiveHistoryRecord _shenyangRecord({
  required int type,
  required String terminal,
  required String lineStation,
  required int amount,
  required int balance,
  required DateTime time,
  required String raw,
  Map<String, dynamic> overrides = const {},
}) => _record(
  ArchiveRecordKind.process,
  {
    'typeCode': type,
    'terminalId': terminal,
    'appTypeCode': 1,
    'lineStationCode': lineStation,
    'amountFen': amount,
    'balanceFen': balance,
    'time': time.millisecondsSinceEpoch,
    'capturedTimes': {
      'time': {
        // Use a portable clock-face coordinate for this synthetic archive.
        'civil': time.toIso8601String().replaceFirst(RegExp(r'Z$'), ''),
        'basis': 'parser-local-unverified',
        'conversionOffsetMinutes': 0,
      },
    },
    'cityCode': '2210',
    'acquirerId': '1217221000000000',
    'rawHex': raw,
    ...overrides,
  },
  context: const ArchiveContext(
    systemId: CardParserIds.tunion,
    applicationId: 'A000000632010105',
    currencyCode: 'CNY',
    minorUnitDigits: 2,
    clockBasis: 'device-local-card-time-unverified',
  ),
);

Map<String, dynamic> _cycleFields({
  int typeCode = 2,
  String lineStationCode = '00010002000000',
}) {
  final snapshot = CardSessionSnapshot(
    processTrips: [
      TUnionTripRecord(
        typeCode: typeCode,
        terminalId: '0000000000000123',
        appTypeCode: 1,
        lineStationCode: lineStationCode,
        amountFen: 300,
        balanceFen: 1200,
        time: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
        cityCode: '3701',
        acquirerId: '0000000000000001',
      ),
    ],
  );
  final document = jsonDecode(snapshot.encode()) as Map<String, dynamic>;
  return (document['cycle'] as List).single as Map<String, dynamic>;
}

const _card = SavedCard(
  id: 'card',
  cardFingerprint: 'fingerprint',
  cardType: 'china_tunion',
  customName: '我的卡',
  cardNumber: '000123',
  identificationSource: 'test',
  createdAt: 1,
  updatedAt: 1,
);

ArchiveHistoryResult _history(List<ArchiveHistoryRecord> records) =>
    ArchiveHistoryResult(card: _card, records: records);

ArchiveHistoryRecord _record(
  ArchiveRecordKind kind,
  Map<String, dynamic> fields, {
  ArchiveContext context = const ArchiveContext(
    currencyCode: 'CNY',
    minorUnitDigits: 2,
  ),
}) => ArchiveHistoryRecord(
  kind: kind,
  fields: fields,
  context: context,
  sources: const [ArchiveRecordSource('batch', 'record', 6, null)],
);
