import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/bank_card/presentation/bank_card_result_view.dart';
import 'package:transit_card_analyzer/features/home/presentation/bank_summary_panel.dart';
import 'package:transit_card_analyzer/features/home/presentation/result_labels.dart';
import 'package:transit_card_analyzer/features/home/recent_scan_section.dart';
import 'package:transit_card_analyzer/features/scan/application/bank_card_probe_impl.dart';
import 'package:transit_card_analyzer/features/scan/application/card_diagnostic_capture.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_service.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/protocols/bank/data/tlv/hex_codec.dart';
import 'package:transit_card_analyzer/protocols/bank/domain/interfaces/card_transport.dart';
import 'package:transit_card_analyzer/protocols/bank/domain/models/parse_issue.dart';
import 'package:transit_card_analyzer/protocols/bank/emv/discovery/application_enumerator.dart';
import 'package:transit_card_analyzer/protocols/bank/parsers/bank_card_analyzer.dart';
import 'package:transit_card_analyzer/protocols/bank/parsers/emv/emv_parser.dart';
import 'package:transit_card_analyzer/protocols/bank/parsers/pboc/pboc_parser.dart';
import 'package:transit_card_analyzer/protocols/transport/transport_failure.dart';

import 'support/test_database.dart';

const _unknownLabel = '暂无可识别卡种';
const _ppse = '00A404000E325041592E5359532E444446303100';
const _mastercard = 'A0000000041010';
const _tagLost = TransportFailure(
  kind: TransportFailureKind.tagLost,
  code: 'TAG_LOST',
  message: 'synthetic tag loss',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'no selected application is unknown even when discovery fails',
    () async {
      final link = _Transport((_) => throw _tagLost);
      final result = await (await _analyzer()).analyze(link);
      expect(result.protocolFamily, 'unknown');
      expect(result.discoveredApplications, isEmpty);
      expect(result.applications, isEmpty);
      expect(result.transportFailure?.code, 'TAG_LOST');
      expect(result.traces, hasLength(1));
      expect(link.commands, hasLength(1));
    },
  );

  test('rejected candidates do not become an EMV card', () async {
    final result = await (await _analyzer()).analyze(
      _Transport((_) => [0x6A, 0x82]),
    );
    expect(result.protocolFamily, 'unknown');
    expect(result.applications, isEmpty);
    expect(result.transportFailure, isNull);
  });

  test('unidentified probe preserves failure and raw evidence', () async {
    final probe = BankCardProbeImpl(_analyzer);
    final result = await probe.probe((_) async => throw _tagLost);
    expect(result, isNotNull);
    expect(result!.protocolFamily, 'unknown');
    expect(result.transportFailure?.code, 'TAG_LOST');
    expect(result.traces.single.errorCode, isNotNull);
    final captured = captureCardInfo(BankReadOutcome(result));
    expect(captured['cardType'], isNull);
    expect(captured['identificationState'], 'unknown');
  });

  test('a clean unsupported probe still returns no match', () async {
    expect(
      await BankCardProbeImpl(_analyzer).probe((_) async => [0x6A, 0x82]),
      isNull,
    );
  });

  test('a static candidate refusal is not directory evidence', () async {
    final result = await BankCardProbeImpl(_analyzer).probe((command) async {
      return HexCodec.encode(command) == _select(_mastercard)
          ? [0x69, 0x85]
          : [0x6A, 0x82];
    });
    expect(result, isNull);
  });

  test(
    'advertised application refusal is preserved without identifying the card',
    () async {
      final result = await BankCardProbeImpl(_analyzer).probe((command) async {
        final hex = HexCodec.encode(command);
        if (hex == _ppse) return _directoryResponse(_mastercard);
        if (hex == _select(_mastercard)) return [0x69, 0x85];
        return [0x6A, 0x82];
      });

      expect(result, isNotNull);
      final bank = result!;
      expect(bank.status, BankCardStatus.enumerationFailed);
      expect(bank.identifiedProtocolFamily, 'unknown');
      expect(bank.applications, isEmpty);
      expect(bank.discoveredApplications, isEmpty);
      expect(bank.transportFailure, isNull);
      expect(bank.issues.single.code, 'directory_select_rejected');
      expect(bank.issues.single.message, contains('6985'));
      expect(bank.issues.single.message, contains('使用条件不满足'));
      expect(
        bank.traces.every((trace) => trace.commandHex.startsWith('00A4')),
        isTrue,
      );
      expect(bankStatusText(bank, detailed: true), contains('6985'));
      final info = captureCardInfo(BankReadOutcome(bank));
      expect(info['identificationState'], 'unknown');
      expect(info['cardType'], isNull);
    },
  );

  test('invalid directory AID does not block a later valid application', () async {
    const validAid = 'A0000000041010';
    final link = _Transport((hex) {
      if (hex == _ppse) {
        return HexCodec.decode(
          '${_tlv('6F', '${_tlv('4F', '01020304')}${_tlv('4F', validAid)}')}9000',
        );
      }
      if (hex == _select(validAid)) {
        return HexCodec.decode('${_tlv('6F', _tlv('84', validAid))}9000');
      }
      return [0x6A, 0x82];
    });
    final result = await EmvApplicationEnumerator(
      (command) => link.transceive(Uint8List.fromList(command)),
    ).enumerate();
    expect(result.applications.single.aidHex, validAid);
    expect(result.transportFailure, isNull);
    expect(result.failures.single.aidHex, '01020304');
    expect(result.failures.single.reason, 'invalid_aid');
    expect(link.commands, isNot(contains(_select('01020304'))));
  });

  test('PPSE with only invalid AIDs falls back to known applications', () async {
    const visaAid = 'A0000000031010';
    const shortAid = '01020304';
    final link = _Transport((hex) {
      if (hex == _ppse) {
        return HexCodec.decode(
          '${_tlv('6F', _tlv('61', _tlv('4F', shortAid)) + _tlv('61', _tlv('4F', '')))}9000',
        );
      }
      if (hex == _select(visaAid)) {
        return HexCodec.decode('${_tlv('6F', _tlv('84', visaAid))}9000');
      }
      return [0x6A, 0x82];
    });
    final result = await EmvApplicationEnumerator(
      (command) => link.transceive(Uint8List.fromList(command)),
    ).enumerate();
    expect(result.usedFallback, isTrue);
    expect(result.applications.single.aidHex, visaAid);
    expect(result.transportFailure, isNull);
    expect(
      result.failures
          .where((failure) => failure.reason == 'invalid_aid')
          .map((failure) => failure.aidHex),
      containsAllInOrder([shortAid, '']),
    );
    expect(link.commands, isNot(contains(_select(shortAid))));
    expect(link.commands, isNot(contains(_select(''))));
  });

  test(
    'invalid PBOC-like AID keeps valid PBOC supplemental discovery',
    () async {
      const visaAid = 'A0000000031010';
      const pbocAid = 'A000000333010101';
      const oversizedAid = 'A000000333010101112233445566778899';
      final link = _Transport((hex) {
        if (hex == _ppse) {
          final entries =
              _tlv('61', _tlv('4F', oversizedAid)) +
              _tlv('61', _tlv('4F', visaAid));
          return HexCodec.decode('${_tlv('6F', entries)}9000');
        }
        if (hex == _select(visaAid)) {
          return HexCodec.decode('${_tlv('6F', _tlv('84', visaAid))}9000');
        }
        if (hex == _select(pbocAid)) {
          return HexCodec.decode('${_tlv('6F', _tlv('84', pbocAid))}9000');
        }
        return [0x6A, 0x82];
      });
      final result = await EmvApplicationEnumerator(
        (command) => link.transceive(Uint8List.fromList(command)),
      ).enumerate();
      expect(result.usedFallback, isFalse);
      expect(result.applications.map((app) => app.aidHex), [visaAid, pbocAid]);
      expect(result.transportFailure, isNull);
      expect(result.failures.single.aidHex, oversizedAid);
      expect(result.failures.single.reason, 'invalid_aid');
      expect(link.commands, isNot(contains(_select(oversizedAid))));
    },
  );

  test('unknown protocol and unsupported transit use the requested label', () {
    expect(bankFamilyText('unknown'), _unknownLabel);
    expect(bankFamilyText('unrecognized-rule'), _unknownLabel);
    expect(transitDisplayName(parserId: null), _unknownLabel);
  });

  for (final mode in ['summary', 'expert', 'legacy']) {
    testWidgets('unidentified $mode view never claims an EMV card', (
      tester,
    ) async {
      // Older callers can still carry the old default rule family. It is not
      // evidence that any application was actually selected.
      final result = BankCardResult(
        protocolFamily: 'emv',
        analyzedAt: DateTime.utc(2026, 11, 10),
        parserVersion: 'test',
        status: BankCardStatus.enumerationFailed,
        transportFailure: _tagLost,
        issues: const [
          ParseIssue(
            stage: 'enumeration',
            code: 'io_error',
            message: 'synthetic tag loss',
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: mode == 'legacy'
                  ? BankCardResultView(result: result)
                  : BankSummaryPanel(bank: result, detailed: mode == 'expert'),
            ),
          ),
        ),
      );
      expect(find.text(_unknownLabel), findsOneWidget);
      expect(find.textContaining('EMV'), findsNothing);
      expect(find.textContaining('银行卡'), findsNothing);
      if (mode != 'summary') {
        expect(find.textContaining('io_error'), findsWidgets);
      }
    });
  }

  for (final aid in ['A0000000041010', 'A000000333010101']) {
    testWidgets('selected $aid remains identified after public-read failure', (
      tester,
    ) async {
      final result = await (await _analyzer()).analyze(
        _Transport((hex) {
          if (hex == _ppse) {
            return HexCodec.decode('${_tlv('6F', _tlv('4F', aid))}9000');
          }
          if (hex == _select(aid)) {
            return HexCodec.decode('${_tlv('6F', _tlv('84', aid))}9000');
          }
          if (hex.startsWith('00A4')) return [0x6A, 0x82];
          throw _tagLost;
        }),
      );
      expect(result.protocolFamily, aid.contains('333') ? 'pboc' : 'emv');
      expect(result.discoveredApplications.single.aidHex, aid);
      expect(result.transportFailure, isNotNull);
      final info = captureCardInfo(BankReadOutcome(result));
      expect(info['identificationState'], 'parser');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BankSummaryPanel(bank: result)),
        ),
      );
      expect(find.text('银行卡（EMV / PBOC）'), findsOneWidget);
      expect(find.text(_unknownLabel), findsNothing);
    });

    test('selected $aid is retained when later discovery fails', () async {
      final result = await (await _analyzer()).analyze(
        _Transport((hex) {
          if (hex == _ppse) {
            return HexCodec.decode(
              '${_tlv('6F', '${_tlv('4F', aid)}${_tlv('4F', 'A0000000031010')}')}9000',
            );
          }
          if (hex == _select(aid)) {
            return HexCodec.decode('${_tlv('6F', _tlv('84', aid))}9000');
          }
          throw _tagLost;
        }),
      );
      expect(
        result.identifiedProtocolFamily,
        aid.contains('333') ? 'pboc' : 'emv',
      );
      expect(result.discoveredApplications.single.selected, isTrue);
      expect(result.transportFailure?.code, 'TAG_LOST');
      expect(result.applications.single.issues.single.code, 'not_read');
      expect(
        captureCardInfo(BankReadOutcome(result))['identificationState'],
        'parser',
      );
    });

    test(
      'selected $aid is retained when parsing reselect is rejected',
      () async {
        var selects = 0;
        final result = await (await _analyzer()).analyze(
          _Transport((hex) {
            if (hex == _ppse) {
              return HexCodec.decode('${_tlv('6F', _tlv('4F', aid))}9000');
            }
            if (hex == _select(aid) && ++selects == 1) {
              return HexCodec.decode('${_tlv('6F', _tlv('84', aid))}9000');
            }
            return [0x6A, 0x82];
          }),
        );
        expect(result.discoveredApplications.single.selected, isTrue);
        expect(result.applications.single.application.selected, isFalse);
        expect(
          result.identifiedProtocolFamily,
          aid.contains('333') ? 'pboc' : 'emv',
        );
        expect(
          captureCardInfo(BankReadOutcome(result))['identificationState'],
          'parser',
        );
      },
    );
  }

  for (final scenario in [
    'metadata',
    'unsupported',
    'bank-io',
    'transit-io',
    'directory-refusal',
  ]) {
    testWidgets('homepage $scenario result shows an unrecognized card', (
      tester,
    ) async {
      final app = AppDependencies(
        database: testDatabase(),
        channel: _UnknownChannel(scenario),
        bundle: MissingTestAssets(),
        logger: AppLogger(store: MemoryLogStore()),
        settingsStore: MemorySettingsStore(),
      );
      addTearDown(app.dispose);
      await tester.runAsync(() async {
        await app.init();
        await app.scanOnce();
      });
      expect(app.parsedCard, isNull);
      expect(app.pendingCardSave, isNull);
      if (scenario == 'bank-io') {
        expect(
          app.lastBankCardResult,
          isNotNull,
          reason:
              '${app.scan.outcome} / ${app.error} / ${app.apduLog.join('\n')}',
        );
        expect(app.lastBankCardResult!.transportFailure, isNotNull);
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RecentScanSection(app: app)),
        ),
      );
      expect(find.text(_unknownLabel), findsOneWidget);
      expect(find.textContaining('EMV'), findsNothing);
      expect(find.textContaining('银行卡'), findsNothing);
      if (scenario == 'directory-refusal') {
        expect(find.textContaining('6985'), findsOneWidget);
        expect(find.textContaining('使用条件不满足'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}

Future<BankCardAnalyzer> _analyzer() async => BankCardAnalyzer([
  await PbocParser.load((_) async => '{"entries":[]}'),
  await EmvParser.load((_) async => '{"entries":[]}'),
]);

String _tlv(String tag, String data) =>
    '$tag${(data.length ~/ 2).toRadixString(16).padLeft(2, '0')}$data';
List<int> _directoryResponse(String aid) => HexCodec.decode(
  '${_tlv('6F', _tlv('A5', _tlv('BF0C', _tlv('61', _tlv('4F', aid)))))}9000',
);
String _select(String aid) =>
    '00A40400${(aid.length ~/ 2).toRadixString(16).padLeft(2, '0')}${aid}00'
        .toUpperCase();

class _Transport implements CardTransport {
  _Transport(this.respond);
  final List<int> Function(String) respond;
  final List<String> commands = [];
  @override
  Future<Uint8List> transceive(Uint8List command) async {
    final hex = HexCodec.encode(command);
    commands.add(hex);
    return Uint8List.fromList(respond(hex));
  }

  @override
  Future<void> close() async {}
}

class _UnknownChannel implements NfcChannel {
  _UnknownChannel(this.scenario);
  final String scenario;
  var _ppseCount = 0;
  @override
  Future<NfcScanResult?> scanOnce() async => NfcScanResult(
    isoDepConnected: scenario != 'metadata',
    uid: '00112233',
    technologies: const ['IsoDep'],
    timestamp: DateTime.utc(2026, 11, 10),
  );

  @override
  Future<List<int>> transceive(List<int> apdu) async {
    final hex = HexCodec.encode(apdu);
    if (scenario == 'directory-refusal') {
      if (hex == _ppse) return _directoryResponse(_mastercard);
      if (hex == _select(_mastercard)) return [0x69, 0x85];
    }
    if (hex == _ppse) {
      _ppseCount++;
      // Transit detection probes PPSE first. Fail only in the dedicated bank
      // phase for bank-io; transit-io models failure before that phase.
      if (scenario == 'transit-io' ||
          (scenario == 'bank-io' && _ppseCount == 2)) {
        throw _tagLost;
      }
    }
    return [0x6A, 0x82];
  }

  @override
  Future<void> stopScan() async {}
}
