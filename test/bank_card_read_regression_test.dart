import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:transit_card_analyzer/protocols/bank/data/apdu/apdu_command.dart';
import 'package:transit_card_analyzer/protocols/bank/data/tlv/hex_codec.dart';
import 'package:transit_card_analyzer/protocols/bank/domain/interfaces/card_transport.dart';
import 'package:transit_card_analyzer/protocols/bank/emv/data/aid_registry.dart';
import 'package:transit_card_analyzer/protocols/bank/parsers/bank_card_analyzer.dart';
import 'package:transit_card_analyzer/protocols/bank/parsers/emv/emv_parser.dart';
import 'package:transit_card_analyzer/protocols/bank/parsers/pboc/pboc_parser.dart';
import 'package:transit_card_analyzer/features/bank_card/presentation/application_detail_page.dart';
import 'package:transit_card_analyzer/features/bank_card/presentation/bank_card_result_view.dart';

import 'support/replay_card_transport.dart';

const _emptyDictionary =
    '{"schemaVersion":1,"dictionaryId":"test","entries":[]}';
const _visa = 'A0000000031010';
const _mastercard = 'A0000000041010';
const _mastercardChina = 'A0000000108888';
const _amex = 'A00000002501';
const _amexChina = 'A00000079001';
const _pboc = 'A000000333010101';
const _getAtc = '80CA9F3600';
const _ppseSelect = '00A404000E325041592E5359532E444446303100';
const _atcResponse = '9F360200019000';
final _recordEnd = List.filled(30, '6A83');

// All account/track values below are synthetic fixtures, never card captures.
void main() {
  test('GET DATA reads ATC without transaction input', () {
    expect(
      HexCodec.encode(ApduCommand.getApplicationTransactionCounter()),
      _getAtc,
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
          _atcResponse,
          '${_tlv('70', c.tags)}9000',
        ]);
        final app = await (await EmvParser.load((_) async => _emptyDictionary))
            .parse(const CardApplication(aidHex: _visa), replay);
        expect(app.summary.pan, c.pan);
        expect(app.summary.panTail, c.pan?.substring(c.pan!.length - 4));
      });
    }

    test('PAN in FCI survives when direct reads are refused', () async {
      final replay = ReplayCardTransport([
        '${_tlv('6F', _tlv('84', _visa) + _tlv('57', '4111111111111111D291220100000F'))}9000',
        '6985',
      ]);
      final app = await (await EmvParser.load((_) async => _emptyDictionary))
          .parse(const CardApplication(aidHex: _visa), replay);
      expect(app.summary.pan, '4111111111111111');
      expect(app.gpoTags, isEmpty);
      expect(app.gpoHex, isEmpty);
      expect(replay.sent.any((c) => c[1] == 0xA8), isFalse);
    });

    test(
      'display dictionary cannot turn malformed PAN into valid digits',
      () async {
        final replay = ReplayCardTransport([
          _fci(_visa),
          _atcResponse,
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

    test(
      'valid later PAN and expiry are recovered from public records',
      () async {
        final malformed =
            _tlv('5A', '4111A11111111111') + _tlv('5F24', '271332');
        final firstValid =
            _tlv('5A', '4111111111111111') + _tlv('5F24', '271231');
        final alternate =
            _tlv('5A', '4012888888881881') + _tlv('5F24', '281231');
        final replay = ReplayCardTransport([
          _fci(_visa),
          _atcResponse,
          for (final tags in [malformed, firstValid, alternate])
            '${_tlv('70', tags)}9000',
          ..._recordEnd,
        ]);
        final app = await (await EmvParser.load((_) async => _emptyDictionary))
            .parse(const CardApplication(aidHex: _visa), replay);
        expect(app.summary.pan, '4111111111111111');
        expect(app.summary.panSourceTag, '5A');
        expect(app.summary.expiry, '2027-12-31');
        expect(app.summary.expirySourceTag, '5F24');
        expect(app.summary.byTag('5A')?.rawValueHex, '4111111111111111');
        expect(app.summary.byTag('5F24')?.rawValueHex, '271231');
        expect(app.records.first.rawHex, _tlv('70', malformed));
        expect(app.records.last.rawHex, _tlv('70', alternate));
      },
    );
  });

  group('read-only APDU replay', () {
    test('exact physical commands reach the PAN without GPO', () async {
      final replay = _CheckedReplay([
        (_select(_visa), _fci(_visa)),
        (_getAtc, _atcResponse),
        ('00B2010C00', _panRecord),
        ..._checkedRecordEnd(),
      ]);
      final app = await (await EmvParser.load((_) async => _emptyDictionary))
          .parse(const CardApplication(aidHex: _visa), replay);
      expect(app.summary.pan, '4111111111111111');
      replay.verifyComplete();
    });

    test('6100 continues GET DATA with GET RESPONSE Le 00', () async {
      final replay = ReplayCardTransport([
        _fci(_visa),
        '9F36026100',
        '00019000',
        _panRecord,
      ]);
      final app = await (await EmvParser.load((_) async => _emptyDictionary))
          .parse(const CardApplication(aidHex: _visa), replay);
      expect(app.summary.pan, '4111111111111111');
      expect(app.dataTags.single.rawValueHex, '0001');
      expect(HexCodec.encode(replay.sent[2]), '00C0000000');
    });

    test('6C00 retries READ RECORD with Le 00', () async {
      final replay = ReplayCardTransport([
        _fci(_visa),
        _atcResponse,
        '6C00',
        _panRecord,
      ]);
      final app = await (await EmvParser.load((_) async => _emptyDictionary))
          .parse(const CardApplication(aidHex: _visa), replay);
      expect(app.summary.pan, '4111111111111111');
      expect(HexCodec.encode(replay.sent[3]), '00B2010C00');
    });

    test('GET RESPONSE itself handles corrected Le', () async {
      final replay = ReplayCardTransport([
        _fci(_visa),
        _atcResponse,
        '6101',
        '6C0C',
        _panRecord,
      ]);
      final app = await (await EmvParser.load((_) async => _emptyDictionary))
          .parse(const CardApplication(aidHex: _visa), replay);
      expect(app.summary.pan, '4111111111111111');
      expect(replay.sent.skip(3).take(2).map(HexCodec.encode), [
        '00C0000001',
        '00C000000C',
      ]);
    });

    test(
      'refused file stops at its first record and later SFIs are read',
      () async {
        final replay = ReplayCardTransport([
          _fci(_visa),
          _atcResponse,
          '6985',
          _panRecord,
        ]);
        final app = await (await EmvParser.load((_) async => _emptyDictionary))
            .parse(const CardApplication(aidHex: _visa), replay);
        expect(app.summary.pan, '4111111111111111');
        expect(app.records.single.sfi, 2);
        expect(
          replay.sent.where((c) => c[1] == 0xB2).take(3).map(HexCodec.encode),
          ['00B2010C00', '00B2011400', '00B2021400'],
        );
      },
    );

    test('record 33 is readable without starting a transaction', () async {
      final replay = ReplayCardTransport([
        _fci(_visa),
        _atcResponse,
        ...List.filled(32, _panRecord),
        _expiryRecord,
      ]);
      final app = await (await EmvParser.load((_) async => _emptyDictionary))
          .parse(const CardApplication(aidHex: _visa), replay);
      expect(app.records.last.recordNumber, 33);
      expect(app.summary.expiry, '2027-12-31');
    });

    test('single application read attempts remain bounded', () async {
      final replay = ReplayCardTransport([
        _fci(_visa),
        _atcResponse,
        ...List.filled(254, _panRecord),
      ]);
      final app = await (await EmvParser.load((_) async => _emptyDictionary))
          .parse(const CardApplication(aidHex: _visa), replay);
      expect(replay.sent.where((c) => c[1] == 0xB2), hasLength(254));
      expect(app.issues.any((i) => i.code == 'record_limit'), isTrue);
    });

    test('failed record attempts share the application budget', () async {
      final replay = ReplayCardTransport([
        _fci(_visa),
        _atcResponse,
        '6A83',
        ...List.filled(253, _panRecord),
      ]);
      final app = await (await EmvParser.load((_) async => _emptyDictionary))
          .parse(const CardApplication(aidHex: _visa), replay);
      expect(replay.sent.where((c) => c[1] == 0xB2), hasLength(254));
      expect(app.records, hasLength(253));
      expect(app.issues.any((i) => i.code == 'record_limit'), isTrue);
    });

    test(
      'later record transport failure preserves PAN and stops I/O',
      () async {
        final replay = _CheckedReplay([
          (_select(_visa), _fci(_visa)),
          (_getAtc, _atcResponse),
          ('00B2010C00', _panRecord),
          ('00B2020C00', StateError('synthetic transport failure')),
        ]);
        final app = await (await EmvParser.load((_) async => _emptyDictionary))
            .parse(const CardApplication(aidHex: _visa), replay);
        expect(app.summary.pan, '4111111111111111');
        expect(app.issues.any((i) => i.code == 'nfc_io_error'), isTrue);
        replay.verifyComplete();
      },
    );

    test('GET DATA transport failure retains FCI and stops I/O', () async {
      final replay = _CheckedReplay([
        (_select(_visa), _fci(_visa)),
        (_getAtc, StateError('synthetic transport failure')),
      ]);
      final app = await (await EmvParser.load((_) async => _emptyDictionary))
          .parse(const CardApplication(aidHex: _visa), replay);
      expect(app.application.selected, isTrue);
      expect(app.fciTags, isNotEmpty);
      expect(
        app.issues.any(
          (i) => i.stage == 'get_data' && i.code == 'nfc_io_error',
        ),
        isTrue,
      );
      replay.verifyComplete();
    });

    test('malformed PDOL is retained as evidence and never used', () async {
      final replay = ReplayCardTransport([
        '${_tlv('6F', _tlv('84', _visa) + _tlv('A5', _tlv('9F38', '9F')))}9000',
        _atcResponse,
      ]);
      final app = await (await EmvParser.load((_) async => _emptyDictionary))
          .parse(const CardApplication(aidHex: _visa), replay);
      expect(app.fciTags, isNotEmpty);
      expect(app.dataTags.single.tagHex, '9F36');
      expect(replay.sent.any((c) => c[1] == 0xA8), isFalse);
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
          _atcResponse,
          _panRecord,
          ..._recordEnd,
          _fci(_pboc),
          _atcResponse,
          _panRecord,
          ..._recordEnd,
        ]);
        // Deliberately reverse registration order: EMV is a fallback parser.
        final result = await (await _analyzer(emvFirst: true)).analyze(replay);
        expect(result.applications.map((a) => a.parserId), ['emv', 'pboc']);
        expect(result.protocolFamily, 'mixed');
        expect(result.applications.every((a) => a.summary.pan != null), isTrue);
        expect(
          replay.sent.every((c) => [0xA4, 0xCA, 0xB2, 0xC0].contains(c[1])),
          isTrue,
        );
      });
    }

    for (final card in [
      (brand: '美国运通', international: _amex, domestic: _amexChina),
      (brand: '万事网联', international: _mastercard, domestic: _mastercardChina),
    ]) {
      test('${card.brand}双应用卡：PPSE 只列出国际应用时补充读取境内 PBOC 应用', () async {
        final replay = ReplayCardTransport([
          _directory([card.international]),
          _fci(card.international),
          // 按补充探测顺序：命中国内清算网络的 PBOC 应用
          ...kPbocSupplementalAids.map(
            (aid) => aid == card.domestic ? _fci(card.domestic) : '6A82',
          ),
          _fci(card.international),
          _atcResponse,
          _expiryRecord,
          ..._recordEnd,
          _fci(card.domestic),
          _atcResponse,
          _expiryRecord,
          ..._recordEnd,
        ]);
        final result = await (await _analyzer()).analyze(replay);
        expect(result.applications.map((a) => a.application.aidHex), [
          card.international,
          card.domestic,
        ]);
        expect(result.applications.map((a) => a.parserId), ['emv', 'pboc']);
        expect(result.protocolFamily, BankCardProtocolFamily.mixed);
        expect(result.status, BankCardStatus.partial);
        expect(
          result.applications.every((a) => a.summary.expiry == '2027-12-31'),
          isTrue,
        );
      });
    }

    test('境内 PBOC 应用族识别覆盖万事网联与连通/美国运通', () {
      for (final aid in [
        _pboc,
        'A000000333010106',
        'A0000003330101',
        _mastercardChina,
        _amexChina,
        'D156000101',
      ]) {
        expect(isPbocAid(aid), isTrue, reason: aid);
      }
      expect(isPbocAid(_amex), isFalse);
      expect(isPbocAid(_mastercard), isFalse);
      expect(isPbocAid(_visa), isFalse);
    });

    test('PPSE 只列出 Visa 时补充探测并读取 PBOC 应用', () async {
      final replay = ReplayCardTransport([
        _directory([_visa]),
        _fci(_visa), // 枚举 Visa
        // 按补充探测顺序：仅银联借记 AID 命中
        ...kPbocSupplementalAids.map(
          (aid) => aid == _pboc ? _fci(_pboc) : '6A82',
        ),
        _fci(_visa), // 解析 Visa
        _atcResponse,
        _panRecord,
        ..._recordEnd,
        _fci(_pboc), // 解析 PBOC
        _atcResponse,
        _panRecord,
        ..._recordEnd,
      ]);
      final result = await (await _analyzer()).analyze(replay);
      expect(result.applications.map((a) => a.application.aidHex), [
        _visa,
        _pboc,
      ]);
      expect(result.applications.map((a) => a.parserId), ['emv', 'pboc']);
      expect(result.applications.every((a) => a.summary.pan != null), isTrue);
      expect(result.protocolFamily, BankCardProtocolFamily.mixed);
      expect(result.status, BankCardStatus.partial);
    });

    test(
      'one rejected directory application makes the surviving result partial',
      () async {
        final replay = ReplayCardTransport([
          _directory([_mastercard, _pboc]),
          '6A82',
          _fci(_pboc),
          _fci(_pboc),
          _atcResponse,
          _panRecord,
          ..._recordEnd,
        ]);
        final result = await (await _analyzer()).analyze(replay);
        expect(result.applications.single.summary.pan, '4111111111111111');
        expect(result.status, BankCardStatus.partial);
        expect(
          result.issues.any(
            (i) =>
                i.stage == 'enumeration' &&
                i.code == 'directory_select_rejected',
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
          _atcResponse,
          _panRecord,
          ..._recordEnd,
          _fci(_pboc),
          _atcResponse,
          _panRecord,
          ..._recordEnd,
        ]);
        final result = await (await _analyzer()).analyze(replay);
        expect(result.applications, hasLength(2));
        expect(result.applications.every((a) => a.summary.pan != null), isTrue);
        expect(result.status, BankCardStatus.partial);
      },
    );

    test('later application I/O failure retains earlier PAN and stops physical I/O', () async {
      final replay = _CheckedReplay([
        (_ppseSelect, _directory([_mastercard, _pboc])),
        (_select(_mastercard), _fci(_mastercard)),
        (_select(_pboc), _fci(_pboc)),
        (_select(_mastercard), _fci(_mastercard)),
        (_getAtc, _atcResponse),
        ('00B2010C00', _panRecord),
        ..._checkedRecordEnd(),
        (_select(_pboc), StateError('synthetic transport failure')),
      ]);
      final result = await (await _analyzer()).analyze(replay);
      expect(
        result.applications.any((a) => a.summary.pan == '4111111111111111'),
        isTrue,
      );
      expect(result.status, BankCardStatus.partial);
      expect(result.applications, hasLength(2));
      expect(result.transportFailure, isNotNull);
      replay.verifyComplete();
    });
  });

  testWidgets('mixed application view keeps both applications navigable', (
    tester,
  ) async {
    final replay = ReplayCardTransport([
      _directory([_mastercard, _pboc]),
      _fci(_mastercard),
      _fci(_pboc),
      _fci(_mastercard),
      _atcResponse,
      _panRecord,
      ..._recordEnd,
      _fci(_pboc),
      _atcResponse,
      _panRecord,
      ..._recordEnd,
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
    'selected Visa with two public certificate records shows missing fields',
    (tester) async {
      final fci =
          '${_tlv('6F', _tlv('84', _visa) + _tlv('A5', _tlv('50', '56495341204445424954') + _tlv('9F38', '9F6604')))}9000';
      final replay = _CheckedReplay([
        (_ppseSelect, _directory([_visa])),
        (_select(_visa), fci),
        for (final aid in kPbocSupplementalAids) (_select(aid), '6A82'),
        (_select(_visa), fci),
        (_getAtc, '9F360200069000'),
        ('00B2010C00', '6A83'),
        ('00B2011400', '6A83'),
        ('00B2011C00', '${_tlv('70', _tlv('90', '0102'))}9000'),
        ('00B2021C00', '70078F01019F3201039000'),
        ('00B2031C00', '6A83'),
        for (var sfi = 4; sfi <= 30; sfi++)
          (HexCodec.encode(ApduCommand.readRecord(sfi, 1)), '6A83'),
      ]);
      final result = await (await _analyzer()).analyze(replay);
      final app = result.applications.single;
      expect(result.identifiedProtocolFamily, 'emv');
      expect(result.status, BankCardStatus.partial);
      expect(app.application.selected, isTrue);
      expect(app.records.map((r) => (r.sfi, r.recordNumber)), [(3, 1), (3, 2)]);
      expect(app.summary.pan, isNull);
      expect(app.summary.expiry, isNull);
      expect(app.dataTags.single.rawValueHex, '0006');
      replay.verifyComplete();

      await tester.pumpWidget(
        MaterialApp(home: ApplicationDetailPage(application: app)),
      );
      expect(find.text('卡号 (PAN)'), findsOneWidget);
      expect(find.text('有效期'), findsOneWidget);
      expect(find.text('未读到'), findsNWidgets(2));
      expect(find.text('卡号来源'), findsNothing);
    },
  );

  testWidgets(
    'track-only application shows extracted PAN separately in details',
    (tester) async {
      final replay = ReplayCardTransport([
        _fci(_mastercard),
        _atcResponse,
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
const _expiryRecord = '70105A0841111111111111115F24032712319000';

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

List<(String, Object)> _checkedRecordEnd() => [
  ('00B2020C00', '6A83'),
  for (var sfi = 2; sfi <= 30; sfi++)
    (HexCodec.encode(ApduCommand.readRecord(sfi, 1)), '6A83'),
];
