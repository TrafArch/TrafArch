import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/scan/application/parser_diagnostic_capture.dart';
import 'package:transit_card_analyzer/features/qr/application/qr_controller.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/features/settings/application/diagnostic_export.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/protocols/bank/domain/models/bank_card_result.dart';
import 'package:transit_card_analyzer/protocols/bank/domain/models/card_application.dart';
import 'package:transit_card_analyzer/protocols/felica/models/felica_card_type.dart';
import 'package:transit_card_analyzer/protocols/felica/models/felica_models.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/shared/diagnostics/diagnostic_event.dart';

void main() {
  test('双应用与地方解析器分别按字段归档，并保留同次响应证据', () async {
    final logger = AppLogger(store: MemoryLogStore())..enabled = true;
    addTearDown(logger.close);
    final sink = logger.startSession('dual');
    final outcome = TransitReadOutcome(
      ParsedCard(
        parserId: CardParserIds.shanghaiTunion,
        parserName: '上海交通卡',
        info: const TUnionCardInfo(balanceFen: 120, applicationSerial: '123'),
        transactions: const [],
        dualApplication: true,
        cityUnionBalanceFen: 200,
      ),
    );
    for (final record in captureParserRecords(outcome)) {
      sink.event('parser_record', data: record);
    }
    sink.event(
      'response_fields',
      data: {
        'parserId': CardParserIds.cityUnion,
        'index': 1,
        'command': [0, 0xB2, 1, 0xD4, 0],
        'raw': [1, 0x90, 0],
        'state': 'decoded',
        'fields': {'issuerCode': '0012'},
      },
    );
    sink.end(DiagnosticOutcome.success);
    final session = (await logger.readSessions()).single;
    final json = jsonDecode(
      buildFullDiagnostics([session], DateTime.utc(2026)),
    );
    final groups = (json['sessions'][0]['parserGroups'] as List).cast<Map>();
    expect(json['version'], 4);
    expect(groups.map((g) => g['parserId']), [
      CardParserIds.shanghaiTunion,
      CardParserIds.cityUnion,
    ]);
    final tu = (groups.first['fieldGroups'] as List).cast<Map>();
    expect(
      tu.singleWhere(
        (g) => g['category'] == 'balance',
      )['records'][0]['fields']['balanceFen'],
      120,
    );
    final cu = (groups.last['fieldGroups'] as List).cast<Map>();
    expect(
      cu.singleWhere(
        (g) => g['category'] == 'balance',
      )['records'][0]['fields']['balanceFen'],
      200,
    );
    expect(
      cu.singleWhere(
        (g) => g['category'] == 'response.file1A',
      )['records'][0]['fields']['issuerCode'],
      '0012',
    );
    expect(json['sessions'][0]['rawJsonl'], session.raw);
  });

  test('银行卡每个 EMV/PBOC 应用和 FeliCa 钱包/流水均可导出', () async {
    final bank = BankReadOutcome(
      BankCardResult(
        protocolFamily: 'mixed',
        analyzedAt: DateTime.utc(2026),
        parserVersion: 'test',
        status: BankCardStatus.success,
        applications: const [
          ParsedApplication(
            application: CardApplication(aidHex: 'A1', selected: true),
            parserId: 'emv',
          ),
          ParsedApplication(
            application: CardApplication(aidHex: 'A2', selected: true),
            parserId: 'pboc',
          ),
        ],
      ),
    );
    final felica = FelicaReadOutcome(
      FelicaScanResult(
        cardType: 'suica',
        displayName: 'Suica',
        cardProductType: FelicaCardType.suica,
        scannedAt: DateTime.utc(2026),
        wallets: const [
          FelicaWallet(
            walletId: 'suica.sf',
            name: 'SF',
            currency: 'JPY',
            balanceMinorUnits: 500,
            readState: FelicaWalletReadState.success,
          ),
        ],
        transactions: const [
          FelicaTransaction(rawHex: '01', decoded: true, amountMinorUnits: 100),
        ],
      ),
    );
    final logger = AppLogger(store: MemoryLogStore())..enabled = true;
    addTearDown(logger.close);
    for (final (id, result) in <(String, CardReadOutcome)>[
      ('bank', bank),
      ('felica', felica),
    ]) {
      final sink = logger.startSession(id);
      for (final record in captureParserRecords(result)) {
        sink.event('parser_record', data: record);
      }
      sink.end(DiagnosticOutcome.success);
    }
    final sessions = await logger.readSessions();
    final exported = jsonDecode(
      buildFullDiagnostics(sessions, DateTime.utc(2026)),
    );
    final parserIds = (exported['sessions'] as List)
        .expand((s) => s['parserGroups'] as List)
        .map((g) => g['parserId'])
        .toSet();
    expect(parserIds, {'emv', 'pboc', 'felica.suica'});
    final felicaGroups =
        (exported['sessions'] as List).firstWhere(
              (s) => s['sessionId'] == 'felica',
            )['parserGroups'][0]['fieldGroups']
            as List;
    expect(
      felicaGroups.map((g) => g['category']),
      containsAll(['wallets', 'transactions']),
    );
  });

  test('旧会话仅依据已冻结字段分类，不从原始帧重新解析', () async {
    final logger = AppLogger(store: MemoryLogStore())..enabled = true;
    addTearDown(logger.close);
    final sink = logger.startSession('old');
    sink.event('card_info', data: {'parserId': 'lingnan_tunion'});
    sink.event(
      'physical_frame',
      data: {
        'index': 0,
        'command': [0, 0x5C, 0, 2, 4],
        'response': [1, 0x90, 0],
      },
    );
    sink.end(DiagnosticOutcome.success);
    final session = (await logger.readSessions()).single;
    final group = jsonDecode(
      buildFullDiagnostics([session], DateTime.utc(2026)),
    )['sessions'][0]['parserGroups'][0];
    expect(group['parserId'], 'lingnan_tunion');
    expect(group['fieldGroups'], isEmpty);
    expect(session.raw, contains('physical_frame'));
  });

  test('二维码失败保留原始字节并按解析器分类导出', () async {
    final logger = AppLogger(store: MemoryLogStore())..enabled = true;
    addTearDown(logger.close);
    final qr = QrController(log: (_) {}, diagnostics: logger);
    addTearDown(qr.dispose);
    expect(qr.parseQrBytes([0x80, 0, 1]), isFalse);
    final session = (await logger.readSessions()).single;
    expect(session.isQr, isTrue);
    final exported = jsonDecode(
      buildFullDiagnostics([session], DateTime.utc(2026)),
    )['sessions'][0];
    final parser = (exported['parserGroups'] as List).single;
    expect(parser['parserId'], 'jt_t1179_qr');
    expect(
      (parser['fieldGroups'] as List).map((g) => g['category']),
      containsAll(['source', 'issues']),
    );
    expect((parser['fieldGroups'] as List).first['records'][0]['raw'], [
      0x80,
      0,
      1,
    ]);
    expect(exported['rawJsonl'], session.raw);
  });
}
