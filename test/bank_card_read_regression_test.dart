import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:transit_card_analyzer/features/bank_card/data/apdu/apdu_command.dart';
import 'package:transit_card_analyzer/features/bank_card/data/pdol/pdol_data_builder.dart';
import 'package:transit_card_analyzer/features/bank_card/data/tlv/hex_codec.dart';
import 'package:transit_card_analyzer/features/bank_card/domain/interfaces/card_transport.dart';
import 'package:transit_card_analyzer/features/bank_card/parsers/bank_card_analyzer.dart';
import 'package:transit_card_analyzer/features/bank_card/parsers/emv/emv_parser.dart';
import 'package:transit_card_analyzer/features/bank_card/parsers/pboc/pboc_parser.dart';
import 'package:transit_card_analyzer/features/bank_card/presentation/application_detail_page.dart';
import 'package:transit_card_analyzer/features/bank_card/presentation/bank_card_result_view.dart';
import 'package:transit_card_analyzer/features/bank_card/test_support/replay_card_transport.dart';

const _emptyDictionary =
    '{"schemaVersion":1,"dictionaryId":"test","entries":[]}';
const _visa = 'A0000000031010';
const _mastercard = 'A0000000041010';
const _amex = 'A00000002501';
const _pboc = 'A000000333010101';
const _emptyGpo = '80A8000002830000';
const _ppseSelect = '00A404000E325041592E5359532E444446303100';
const _oneRecordGpo = '80060000080101009000';

// All account/track values below are synthetic fixtures, never card captures.
void main() {
  group('GPO command framing', () {
    test('empty PDOL includes Lc and trailing Le', () {
      expect(HexCodec.encode(ApduCommand.getProcessingOptions()), _emptyGpo);
    });

    test('long PDOL uses BER length inside a short APDU', () {
      final command = ApduCommand.getProcessingOptions(
        pdolData: List.filled(128, 0),
      );
      expect(command.take(8), [0x80, 0xA8, 0, 0, 131, 0x83, 0x81, 128]);
      expect(command.length, 137);
      expect(command.last, 0);
    });

    test('PDOL too long for short APDU is rejected, never truncated', () {
      expect(
        () => ApduCommand.getProcessingOptions(pdolData: List.filled(253, 0)),
        throwsArgumentError,
      );
    });

    test('truncated PDOL tag or missing length is rejected', () {
      for (final hex in ['9F', '9F38']) {
        expect(
          () => PdolDataBuilder.build(HexCodec.decode(hex)),
          throwsFormatException,
        );
      }
    });

    test(
      'PDOL consumes continued tag bytes before reading the value length',
      () {
        final data = PdolDataBuilder.build(HexCodec.decode('DF8101019F0206'));
        expect(data, List.filled(7, 0));
      },
    );
  });

  group('PAN extraction from independent card evidence', () {
    final cases = <({String name, String tags, String? pan})>[
      (
        name: '5A even digits',
        tags: _tlv('5A', '4111111111111111'),
        pan: '4111111111111111',
      ),
      (
        name: '5A odd digits removes terminal F',
        tags: _tlv('5A', '378282246310005F'),
        pan: '378282246310005',
      ),
      (
        name: '5A leading zeroes survive',
        tags: _tlv('5A', '0000123456789012'),
        pan: '0000123456789012',
      ),
      (
        name: '57 without 5A',
        tags: _tlv('57', '4111111111111111D291220100000F'),
        pan: '4111111111111111',
      ),
      (
        name: '9F6B without 5A',
        tags: _tlv('9F6B', '5555555555554444D291220100000F'),
        pan: '5555555555554444',
      ),
      (
        name: '5A takes precedence over track PAN',
        tags:
            _tlv('5A', '378282246310005F') +
            _tlv('57', '4111111111111111D291220100000F'),
        pan: '378282246310005',
      ),
      (
        name: 'malformed 5A falls back to valid 57',
        tags:
            _tlv('5A', '4111A11111111111') +
            _tlv('57', '4111111111111111D291220100000F'),
        pan: '4111111111111111',
      ),
      (
        name: 'non-decimal 5A is not silently repaired',
        tags: _tlv('5A', '4111A11111111111'),
        pan: null,
      ),
      (
        name: '57 without separator is not a PAN',
        tags: _tlv('57', '411111111111111129122010000000'),
        pan: null,
      ),
      (
        name: '57 with truncated expiry and service code is rejected',
        tags: _tlv('57', '4111111111111111D29F'),
        pan: null,
      ),
    ];
    for (final c in cases) {
      test(c.name, () async {
        final replay = ReplayCardTransport([
          _fci(_visa),
          _oneRecordGpo,
          '${_tlv('70', c.tags)}9000',
        ]);
        final app = await (await EmvParser.load((_) async => _emptyDictionary))
            .parse(const CardApplication(aidHex: _visa), replay);
        expect(app.summary.pan, c.pan);
        expect(app.summary.panTail, c.pan?.substring(c.pan!.length - 4));
      });
    }

    test('PAN in GPO survives without AFL', () async {
      final replay = ReplayCardTransport([
        _fci(_visa),
        '${_tlv('77', '82020000${_tlv('57', '4111111111111111D291220100000F')}')}9000',
      ]);
      final app = await (await EmvParser.load((_) async => _emptyDictionary))
          .parse(const CardApplication(aidHex: _visa), replay);
      expect(app.summary.pan, '4111111111111111');
      expect(replay.sent.where((c) => c[1] == 0xB2), isEmpty);
    });

    test(
      'display dictionary cannot turn malformed PAN into valid digits',
      () async {
        final replay = ReplayCardTransport([
          _fci(_visa),
          _oneRecordGpo,
          '700A5A084111A111111111119000',
        ]);
        final parser = await EmvParser.load(
          (_) async => '{"entries":[{"tag":"5A","decoder":"numeric_bcd"}]}',
        );
        final app = await parser.parse(
          const CardApplication(aidHex: _visa),
          replay,
        );
        expect(app.summary.pan, isNull);
      },
    );
  });

  group('read-only APDU replay', () {
    test('real command validation reaches the PAN record', () async {
      final replay = _CheckedReplay([
        (_select(_visa), _fci(_visa)),
        (_emptyGpo, _oneRecordGpo),
        ('00B2010C00', _panRecord),
      ]);
      final app = await (await EmvParser.load((_) async => _emptyDictionary))
          .parse(const CardApplication(aidHex: _visa), replay);
      expect(app.summary.pan, '4111111111111111');
      replay.verifyComplete();
    });

    test('6100 is followed with GET RESPONSE Le 00', () async {
      final replay = ReplayCardTransport([
        _fci(_visa),
        '800600006100',
        '080101009000',
        _panRecord,
      ]);
      final app = await (await EmvParser.load((_) async => _emptyDictionary))
          .parse(const CardApplication(aidHex: _visa), replay);
      expect(app.summary.pan, '4111111111111111');
      expect(HexCodec.encode(replay.sent[2]), '00C0000000');
    });

    test('6C00 retries with Le 00', () async {
      final replay = ReplayCardTransport([
        _fci(_visa),
        _oneRecordGpo,
        '6C00',
        _panRecord,
      ]);
      final app = await (await EmvParser.load((_) async => _emptyDictionary))
          .parse(const CardApplication(aidHex: _visa), replay);
      expect(app.summary.pan, '4111111111111111');
      expect(HexCodec.encode(replay.sent.last), '00B2010C00');
    });

    test('GET RESPONSE itself handles corrected Le', () async {
      final replay = ReplayCardTransport([
        _fci(_visa),
        _oneRecordGpo,
        '6101',
        '6C0C',
        _panRecord,
      ]);
      final app = await (await EmvParser.load((_) async => _emptyDictionary))
          .parse(const CardApplication(aidHex: _visa), replay);
      expect(app.summary.pan, '4111111111111111');
      expect(replay.sent.skip(3).map(HexCodec.encode), [
        '00C0000001',
        '00C000000C',
      ]);
    });

    test('AFL rejects invalid entries and reads later valid entries once', () async {
      final replay = ReplayCardTransport([
        _fci(_visa),
        '${_tlv('77', '82020000${_tlv('94', 'F801010009010100080101020801010008010100')}')}9000',
        _panRecord,
      ]);
      final app = await (await EmvParser.load((_) async => _emptyDictionary))
          .parse(const CardApplication(aidHex: _visa), replay);
      expect(app.summary.pan, '4111111111111111');
      expect(replay.sent.where((c) => c[1] == 0xB2).map(HexCodec.encode), [
        '00B2010C00',
      ]);
      expect(app.issues.any((i) => i.code == 'invalid_afl'), isTrue);
    });

    test('records after the former per-entry cap remain readable', () async {
      final replay = ReplayCardTransport([
        _fci(_visa),
        '80060000080121009000',
        ...List.filled(32, '6A83'),
        _panRecord,
      ]);
      final app = await (await EmvParser.load((_) async => _emptyDictionary))
          .parse(const CardApplication(aidHex: _visa), replay);
      expect(app.summary.pan, '4111111111111111');
      expect(app.records.single.recordNumber, 33);
    });

    test(
      'failed record attempts still count toward the overall read limit',
      () async {
        final replay = ReplayCardTransport([
          _fci(_visa),
          '800A00000801FF001001FF009000',
        ]);
        final app = await (await EmvParser.load((_) async => _emptyDictionary))
            .parse(const CardApplication(aidHex: _visa), replay);
        expect(
          replay.sent.where((c) => c[1] == 0xB2).length,
          lessThanOrEqualTo(254),
        );
        expect(app.issues.any((i) => i.code == 'record_limit'), isTrue);
      },
    );

    test('a later record transport failure preserves an earlier PAN', () async {
      final replay = _CheckedReplay([
        (_select(_visa), _fci(_visa)),
        (_emptyGpo, '80060000080102009000'),
        ('00B2010C00', _panRecord),
        ('00B2020C00', StateError('synthetic transport failure')),
      ]);
      final app = await (await EmvParser.load((_) async => _emptyDictionary))
          .parse(const CardApplication(aidHex: _visa), replay);
      expect(app.summary.pan, '4111111111111111');
      expect(app.issues.any((i) => i.code == 'nfc_io_error'), isTrue);
    });

    test('GPO transport failure preserves selected FCI evidence', () async {
      final replay = _CheckedReplay([
        (_select(_visa), _fci(_visa)),
        (_emptyGpo, StateError('synthetic transport failure')),
      ]);
      final app = await (await EmvParser.load((_) async => _emptyDictionary))
          .parse(const CardApplication(aidHex: _visa), replay);
      expect(app.application.selected, isTrue);
      expect(app.fciTags, isNotEmpty);
      expect(
        app.issues.any((i) => i.stage == 'gpo' && i.code == 'nfc_io_error'),
        isTrue,
      );
    });

    test('malformed PDOL retains FCI without sending a guessed GPO', () async {
      final replay = ReplayCardTransport([
        '${_tlv('6F', _tlv('84', _visa) + _tlv('A5', _tlv('9F38', '9F')))}9000',
      ]);
      final app = await (await EmvParser.load((_) async => _emptyDictionary))
          .parse(const CardApplication(aidHex: _visa), replay);
      expect(app.fciTags, isNotEmpty);
      expect(replay.sent, hasLength(1));
      expect(app.issues.any((i) => i.code == 'invalid_pdol'), isTrue);
    });

    test('failed reselection is represented as not selected', () async {
      final replay = ReplayCardTransport(['6A82']);
      final app = await (await EmvParser.load((_) async => _emptyDictionary))
          .parse(const CardApplication(aidHex: _visa, selected: true), replay);
      expect(app.application.selected, isFalse);
      expect(app.hasData, isFalse);
      expect(replay.sent, hasLength(1));
    });
  });

  group('per-application dispatch and failure isolation', () {
    for (final international in [_mastercard, _amex]) {
      test('EMV and PBOC applications coexist for $international', () async {
        final replay = ReplayCardTransport([
          _directory([international, _pboc]),
          _fci(international),
          _fci(_pboc),
          _fci(international),
          _oneRecordGpo,
          _panRecord,
          _fci(_pboc),
          _oneRecordGpo,
          _panRecord,
        ]);
        // Deliberately reverse registration order: EMV is a fallback parser.
        final result = await (await _analyzer(emvFirst: true)).analyze(replay);
        expect(result.applications.map((a) => a.parserId), ['emv', 'pboc']);
        expect(result.protocolFamily, 'mixed');
        expect(result.applications.every((a) => a.summary.pan != null), isTrue);
        expect(
          replay.sent.every((c) => [0xA4, 0xA8, 0xB2, 0xC0].contains(c[1])),
          isTrue,
        );
      });
    }

    test(
      'one rejected directory application makes the surviving result partial',
      () async {
        final replay = ReplayCardTransport([
          _directory([_mastercard, _pboc]),
          '6A82',
          _fci(_pboc),
          _fci(_pboc),
          _oneRecordGpo,
          _panRecord,
        ]);
        final result = await (await _analyzer()).analyze(replay);
        expect(result.applications.single.summary.pan, '4111111111111111');
        expect(result.status, BankCardStatus.partial);
        expect(
          result.issues.any(
            (i) => i.stage == 'enumeration' && i.code == 'select_rejected',
          ),
          isTrue,
        );
      },
    );

    test(
      'malformed optional FCI does not remove a selected application',
      () async {
        final replay = ReplayCardTransport([
          _directory([_mastercard, _pboc]),
          '6F028400019000',
          _fci(_pboc),
          _fci(_mastercard),
          _oneRecordGpo,
          _panRecord,
          _fci(_pboc),
          _oneRecordGpo,
          _panRecord,
        ]);
        final result = await (await _analyzer()).analyze(replay);
        expect(result.applications, hasLength(2));
        expect(result.applications.every((a) => a.summary.pan != null), isTrue);
        expect(result.status, BankCardStatus.partial);
      },
    );

    test(
      'one application I/O failure does not discard another application',
      () async {
        final replay = _CheckedReplay([
          (_ppseSelect, _directory([_mastercard, _pboc])),
          (_select(_mastercard), _fci(_mastercard)),
          (_select(_pboc), _fci(_pboc)),
          (_select(_mastercard), StateError('synthetic transport failure')),
          (_select(_pboc), _fci(_pboc)),
          (_emptyGpo, _oneRecordGpo),
          ('00B2010C00', _panRecord),
        ]);
        final result = await (await _analyzer()).analyze(replay);
        expect(
          result.applications.any((a) => a.summary.pan == '4111111111111111'),
          isTrue,
        );
        expect(result.status, BankCardStatus.partial);
        replay.verifyComplete();
      },
    );
  });

  testWidgets('mixed application view keeps both applications navigable', (
    tester,
  ) async {
    final replay = ReplayCardTransport([
      _directory([_mastercard, _pboc]),
      _fci(_mastercard),
      _fci(_pboc),
      _fci(_mastercard),
      _oneRecordGpo,
      _panRecord,
      _fci(_pboc),
      _oneRecordGpo,
      _panRecord,
    ]);
    final result = await (await _analyzer()).analyze(replay);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BankCardResultView(result: result),
          ),
        ),
      ),
    );
    expect(find.textContaining('EMV + PBOC'), findsOneWidget);
    await tester.tap(find.text(_mastercard));
    await tester.pumpAndSettle();
    expect(find.byType(ApplicationDetailPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text(_pboc));
    await tester.pumpAndSettle();
    expect(find.byType(ApplicationDetailPage), findsOneWidget);
  });

  testWidgets(
    'track-only application shows extracted PAN separately in details',
    (tester) async {
      final replay = ReplayCardTransport([
        _fci(_mastercard),
        _oneRecordGpo,
        '${_tlv('70', _tlv('9F6B', '5555555555554444D291220100000F'))}9000',
      ]);
      final app = await (await EmvParser.load((_) async => _emptyDictionary))
          .parse(const CardApplication(aidHex: _mastercard), replay);
      await tester.pumpWidget(
        MaterialApp(home: ApplicationDetailPage(application: app)),
      );
      expect(find.text('5555555555554444'), findsOneWidget);
      expect(find.textContaining('9F6B'), findsWidgets);
    },
  );
}

Future<BankCardAnalyzer> _analyzer({bool emvFirst = false}) async {
  final emv = await EmvParser.load((_) async => _emptyDictionary);
  final pboc = await PbocParser.load((_) async => _emptyDictionary);
  return BankCardAnalyzer(emvFirst ? [emv, pboc] : [pboc, emv]);
}

String _tlv(String tag, String value) {
  final length = value.length ~/ 2;
  assert(value.length.isEven);
  final encoded = length.toRadixString(16).padLeft(2, '0');
  return '$tag${length < 128 ? encoded : '81$encoded'}$value'.toUpperCase();
}

String _select(String aid) =>
    '00A40400${(aid.length ~/ 2).toRadixString(16).padLeft(2, '0')}${aid}00'
        .toUpperCase();
String _fci(String aid) => '${_tlv('6F', _tlv('84', aid))}9000';
String _directory(List<String> aids) =>
    '${_tlv('6F', '${_tlv('84', '325041592E5359532E4444463031')}${_tlv('A5', _tlv('BF0C', aids.map((a) => _tlv('61', _tlv('4F', a))).join()))}')}9000';
const _panRecord = '700A5A0841111111111111119000';

/// Strict command/response replay at the card boundary. A malformed command is
/// rejected as a card would reject it; parsing and all transport wrappers are real.
class _CheckedReplay implements CardTransport {
  _CheckedReplay(this.steps);
  final List<(String, Object)> steps;
  final List<String> sent = [];

  @override
  Future<Uint8List> transceive(Uint8List command) async {
    final index = sent.length;
    final hex = HexCodec.encode(command);
    sent.add(hex);
    if (index >= steps.length || hex != steps[index].$1) {
      return HexCodec.decode('6700');
    }
    final response = steps[index].$2;
    if (response is! String) throw response;
    return HexCodec.decode(response);
  }

  void verifyComplete() => expect(sent, steps.map((s) => s.$1).toList());

  @override
  Future<void> close() async {}
}
