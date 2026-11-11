import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/scan/application/response_diagnostic_capture.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/features/recovery/capture_read_result.dart';
import 'package:transit_card_analyzer/features/settings/application/diagnostic_export.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/protocols/bank/domain/models/bank_card_result.dart';
import 'package:transit_card_analyzer/protocols/bank/domain/models/card_application.dart';
import 'package:transit_card_analyzer/protocols/bank/domain/models/card_record.dart';
import 'package:transit_card_analyzer/protocols/bank/domain/models/tlv_node.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_file_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_process_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';
import 'package:transit_card_analyzer/protocols/felica/models/felica_models.dart';
import 'package:transit_card_analyzer/protocols/felica/models/felica_card_type.dart';
import 'package:transit_card_analyzer/shared/diagnostics/diagnostic_event.dart';

const _tu = 'A000000632010105';
const _cu = 'A00000000386980701';
List<int> _bytes(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];
Map<String, Object?> _frame(
  int index,
  String aid,
  List<int> command,
  List<int>? body, {
  int sw = 0x9000,
  String? stage,
}) => {
  'index': index,
  'selectedApplication': aid,
  'protocolStage': stage,
  'transport': 'iso-dep',
  'command': command,
  'response': body == null ? null : [...body, sw >> 8, sw & 255],
};

void main() {
  test('完整导出response为冻结解析字段，raw与原始日志不变', () async {
    final logger = AppLogger(store: MemoryLogStore())..enabled = true;
    addTearDown(logger.close);
    final source = _frame(0, _tu, [0x80, 0x5C, 0, 2, 4], [0, 0, 0x27, 0x10]);
    const result = TransitReadOutcome(
      ParsedCard(
        parserId: CardParserIds.tunion,
        parserName: 'TU',
        info: TUnionCardInfo(balanceFen: 10000),
        transactions: [],
      ),
    );
    final sink = logger.startSession('freeze');
    sink.event('physical_frame', data: source);
    sink.event(
      'response_fields',
      data: captureResponseFields(result, [source]).single,
    );
    sink.end(DiagnosticOutcome.success);
    final session = (await logger.readSessions()).single;
    final text = buildFullDiagnostics([session], DateTime.utc(2026));
    final document = jsonDecode(text);
    expect(document['version'], 4);
    final exported = document['sessions'][0];
    final frames = (exported['apduGroups'] as List).expand(
      (g) => g['frames'] as List,
    );
    final frame = frames.single;
    expect(frame['response'], {
      'parserId': 'tunion',
      'state': 'decoded',
      'statusWord': '9000',
      'fields': {'balanceFen': 10000, 'role': 'wallet_observation'},
    });
    expect(frame['raw'], [0, 0, 0x27, 0x10, 0x90, 0]);
    expect(exported['events'][1]['data']['response'], frame['response']);
    expect(RegExp(r'"response":\s*\{\s*\n').hasMatch(text), isFalse);
    expect(RegExp(r'"raw":\s*\[\s*\n').hasMatch(text), isFalse);
    expect(exported['rawJsonl'], session.raw);
    expect(session.events[1].data['response'], source['response']);
  });

  test('地方卡消费自身记录字段，FeliCa使用帧和产品字段', () {
    final local = ReadResult(
      info: CardInfo()..isLNT = true,
      records: [
        ApduRecord()
          ..type = 2
          ..recordNumber = 3
          ..fileSelector = 0xC4
          ..rawBody = Uint8List.fromList([1, 2, 3])
          ..balanceDelta = -100
          ..posType = 6,
      ],
      extras: CardExtras(),
    );
    final result = TransitReadOutcome(
      ParsedCard(
        parserId: CardParserIds.lingnanTong,
        parserName: 'LNT',
        info: const TUnionCardInfo(),
        transactions: const [],
        localCard: local,
      ),
    );
    final decoded = captureResponseFields(result, [
      _frame(
        0,
        '5041592E5449434C',
        [0, 0xB2, 3, 0xC4, 23],
        [1, 2, 3],
        stage: '岭南通',
      ),
      _frame(1, _tu, [0, 0xB2, 3, 0xC4, 23], [1, 2, 3], stage: '交通联合'),
    ]).toList();
    expect(decoded[0]['parserId'], 'lingnan_tong');
    expect((decoded[0]['fields'] as Map)['balanceDelta'], -100);
    expect((decoded[0]['fields'] as Map)['secondsKnown'], isFalse);
    expect(decoded[1]['state'], 'unparsed');
    final block = List<int>.generate(16, (i) => i);
    final response = [29, 7, ...List<int>.filled(8, 1), 0, 0, 1, ...block];
    final felica = FelicaReadOutcome(
      FelicaScanResult(
        cardType: 'Suica',
        displayName: 'Suica',
        cardProductType: FelicaCardType.suica,
        idm: '0101010101010101',
        scannedAt: DateTime.utc(2026),
        transactions: [
          FelicaTransaction(
            rawHex: block
                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                .join(),
            decoded: true,
            amountMinorUnits: 500,
            amountIsBalance: true,
            currency: 'JPY',
          ),
        ],
      ),
    );
    final frame = {
      'index': 0,
      'transport': 'nfc-f',
      'command': [6, 6],
      'response': response,
    };
    final fields = captureResponseFields(felica, [frame]).single;
    expect(fields['parserId'], 'felica.suica');
    expect((fields['fields'] as Map)['records'][0]['amountMinorUnits'], 500);
    expect((fields['fields'] as Map)['records'][0]['currency'], 'JPY');
  });

  test('同一0x15按当次TU/CU应用输出各自字段且不能借用最终解析器', () {
    final body = _bytes(
      '112229000000000001010031047700000000000120240101202912310000',
    );
    final cuFile = CityUnionFileParser.parse(0x15, body);
    final result = TransitReadOutcome(
      ParsedCard(
        parserId: CardParserIds.shanghaiTunion,
        parserName: '双应用',
        info: const TUnionCardInfo(),
        transactions: const [],
        cityUnionFiles: [cuFile],
      ),
    );
    final decoded = captureResponseFields(result, [
      _frame(0, _tu, [0, 0xB0, 0x95, 0, 30], body),
      _frame(1, _cu, [0, 0xB0, 0x95, 0, 30], body),
      _frame(2, '', [0, 0xB0, 0x95, 0, 30], body),
      _frame(3, _tu, [0, 0xB0, 0x95, 5, 30], body),
    ]).toList();
    expect(decoded[0]['parserId'], CardParserIds.shanghaiTunion);
    final tuFields = decoded[0]['fields'] as Map;
    expect(tuFields['issuerId'], '1122290000000000');
    expect(tuFields['applicationSerial'], '00310477000000000001');
    expect(tuFields['effectiveDate'], startsWith('2024-01-01'));
    expect(decoded[1]['parserId'], 'city_union');
    expect(decoded[1]['fields'], cuFile.toJson());
    expect((decoded[1]['fields'] as Map)['fields'], isA<List>());
    expect(decoded[2]['state'], 'unparsed');
    expect(decoded[3]['state'], 'unparsed');
  });

  test('0x1A在TU下为轨道字段，在CU下为异地交易字段', () {
    final raw = List<int>.filled(23, 0)..[0] = 1;
    final rail = const TUnionProcessParser().parseRailTransit(1, raw);
    final file = CityUnionFileParser.parseWalletRecord(
      0x1A,
      raw,
      kind: CityUnionTransactionKind.foreignConsumption,
      recordNumber: 1,
    );
    final result = TransitReadOutcome(
      ParsedCard(
        parserId: CardParserIds.shanghaiTunion,
        parserName: '双应用',
        info: const TUnionCardInfo(),
        transactions: const [],
        cityUnionFiles: [file],
        transitProcessRecords: [
          TUnionProcessRecord(
            sfi: 0x1A,
            recordNumber: 1,
            recordName: 'rail',
            raw: raw,
            railTransit: rail,
          ),
        ],
      ),
    );
    final decoded = captureResponseFields(result, [
      _frame(0, _tu, [0, 0xB2, 1, 0xD4, 85], raw),
      _frame(1, _cu, [0, 0xB2, 1, 0xD4, 85], raw),
    ]).toList();
    expect((decoded[0]['fields'] as Map)['statusCode'], 1);
    expect((decoded[0]['fields'] as Map), contains('entryStationId'));
    expect(decoded[1]['fields'], file.toJson());
    expect(
      (decoded[1]['fields'] as Map).containsKey('entryStationId'),
      isFalse,
    );
  });

  test('沈阳1E金额直接消费已解析的小端结果，不在日志重算', () {
    final raw = _bytes(
      '0322104131000000010101000200000000E8030000D00700002026103012300022101217221000000000000000000000',
    );
    final trip = const TUnionProcessParser().parseCycleTrip(raw)!;
    final result = TransitReadOutcome(
      ParsedCard(
        parserId: CardParserIds.tunion,
        parserName: 'TU',
        info: const TUnionCardInfo(),
        transactions: const [],
        transitProcessRecords: [
          TUnionProcessRecord(
            sfi: 0x1E,
            recordNumber: 4,
            recordName: 'cycle',
            raw: raw,
            trip: trip,
          ),
        ],
      ),
    );
    final decoded = captureResponseFields(result, [
      _frame(0, _tu, [0, 0xB2, 4, 0xF4, 48], raw),
    ]).single;
    expect((decoded['fields'] as Map)['amountFen'], trip.amountFen);
    expect(trip.amountFen, 1000);
    expect((decoded['fields'] as Map)['recordBalanceFen'], 2000);
  });

  test('银行应用切换后沿用各自EMV/PBOC标签，不串字典', () {
    final raw = _bytes('5A021234');
    final apps = [
      for (final parser in ['emv', 'pboc'])
        ParsedApplication(
          application: CardApplication(
            aidHex: parser == 'emv' ? 'A0000000031010' : 'A000000333010101',
          ),
          parserId: parser,
          records: [
            CardRecord(
              sfi: 1,
              recordNumber: 1,
              rawHex: '5A021234',
              tags: [
                TlvNode(
                  tagHex: '5A',
                  length: 2,
                  rawValue: Uint8List.fromList([0x12, 0x34]),
                  description: '$parser卡号',
                  decodedValue: '1234',
                ),
              ],
            ),
          ],
        ),
    ];
    final result = BankReadOutcome(
      BankCardResult(
        protocolFamily: 'mixed',
        analyzedAt: DateTime.utc(2026),
        parserVersion: 'test',
        status: BankCardStatus.success,
        applications: apps,
      ),
    );
    final decoded = captureResponseFields(result, [
      for (var i = 0; i < apps.length; i++)
        _frame(i, apps[i].application.aidHex, [0, 0xB2, 1, 0x0C, 0], raw),
    ]).toList();
    expect(decoded.map((e) => e['parserId']), ['emv', 'pboc']);
    expect((decoded[0]['fields'] as Map)['tags'][0]['name'], 'emv卡号');
    expect((decoded[1]['fields'] as Map)['tags'][0]['name'], 'pboc卡号');
  });

  test('GET DATA 的 ATC 保留到恢复捕获和匹配的应用诊断，不借用其他响应', () {
    const aid = 'A000000333010101';
    final result = BankReadOutcome(
      BankCardResult(
        protocolFamily: 'pboc',
        analyzedAt: DateTime.utc(2026),
        parserVersion: '0.3.0',
        status: BankCardStatus.partial,
        applications: [
          ParsedApplication(
            application: const CardApplication(aidHex: aid),
            parserId: 'pboc',
            dataTags: [
              TlvNode(
                tagHex: '9F36',
                length: 2,
                rawValue: Uint8List.fromList([0, 10]),
                description: '应用交易计数器',
                decodedValue: '10',
              ),
            ],
          ),
        ],
      ),
    );
    final frames = captureResponseFields(result, [
      _frame(0, aid, _bytes('80CA9F3600'), _bytes('9F3602000A')),
      _frame(1, aid, _bytes('80CA9F3600'), _bytes('9F3602000B')),
      _frame(2, 'A0000000031010', _bytes('80CA9F3600'), _bytes('9F3602000A')),
    ]).toList();
    expect(frames.first['parserId'], 'pboc');
    expect((frames.first['fields'] as Map)['tags'][0]['rawHex'], '000A');
    expect((frames.first['fields'] as Map)['tags'][0]['value'], '10');
    expect(frames.skip(1).every((f) => f['state'] != 'decoded'), isTrue);
    final captured = captureReadResult(result);
    expect(
      (captured['applications'] as List).single['data'][0]['rawValueHex'],
      '000A',
    );
  });

  test('失败、空帧和61链式片段不伪造解析成功；旧日志不重新解析', () async {
    final result = const TransitReadOutcome(
      ParsedCard(
        parserId: CardParserIds.tunion,
        parserName: 'TU',
        info: TUnionCardInfo(),
        transactions: [],
      ),
    );
    final frames = [
      _frame(0, _tu, [0, 0xB0, 0x95, 0, 30], null),
      _frame(1, _tu, [0, 0xB0, 0x95, 0, 30], [1, 2], sw: 0x6101),
      {
        'index': 2,
        'transport': 'iso-dep',
        'command': <int>[],
        'response': <int>[],
      },
    ];
    final frozen = captureResponseFields(result, frames).toList();
    expect(frozen.map((f) => f['state']), [
      'no_response',
      'status_only',
      'empty_response',
    ]);
    final logger = AppLogger(store: MemoryLogStore())..enabled = true;
    addTearDown(logger.close);
    final sink = logger.startSession('captured');
    for (var i = 0; i < frames.length; i++) {
      sink.event('physical_frame', data: frames[i]);
      sink.event('response_fields', data: frozen[i]);
    }
    sink.end(DiagnosticOutcome.partial);
    final session = (await logger.readSessions()).single;
    final text = buildFullDiagnostics([session], DateTime.utc(2026));
    expect(RegExp(r'"raw":\s*\[\s*\n').hasMatch(text), isFalse);
    final exported = jsonDecode(text)['sessions'][0];
    final projected = (exported['apduGroups'] as List)
        .expand((g) => g['frames'] as List)
        .toList();
    expect(projected[0]['response']['state'], 'no_response');
    expect(projected[1]['response']['statusWord'], '6101');
    expect(exported['rawJsonl'], session.raw);
  });
}
