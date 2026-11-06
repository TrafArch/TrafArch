import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/protocols/bank/data/tlv/hex_codec.dart';
import 'package:transit_card_analyzer/protocols/bank/data/transport/recording_card_transport.dart';
import 'package:transit_card_analyzer/protocols/bank/domain/interfaces/card_parser.dart';
import 'package:transit_card_analyzer/protocols/bank/domain/interfaces/card_transport.dart';
import 'package:transit_card_analyzer/protocols/bank/emv/protocol/read_only_exchange.dart';
import 'package:transit_card_analyzer/protocols/bank/parsers/bank_card_analyzer.dart';
import 'package:transit_card_analyzer/protocols/bank/parsers/emv/emv_parser.dart';
import 'package:transit_card_analyzer/protocols/bank/parsers/pboc/pboc_parser.dart';

import 'support/replay_card_transport.dart';

const _pboc = 'A000000333010101';
const _visa = 'A0000000031010';
const _selectPboc =
    '6F2A8408A000000333010101A51E500A50424F432044454249'
    '548701019F380C9F7A019F02065F2A02DF69019000';
const _selectVisa = '6F148407A0000000031010A5095004564953418701019000';
const _ppsePboc =
    '6F30840E325041592E5359532E4444463031A51EBF0C1B6119'
    '4F08A000000333010101500A50424F432044454249548701019000';
const _pan = '700A5A0841111111111111119000';

void main() {
  for (final family in ['pboc', 'emv']) {
    test(
      '$family repeated reads preserve card ATC and never initiate a transaction',
      () async {
        final card = _CounterCard(family);
        final parser = family == 'pboc'
            ? await PbocParser.load(
                (_) =>
                    File('assets/dictionaries/pboc_tags.json').readAsString(),
              )
            : await EmvParser.load(
                (_) => File('assets/dictionaries/emv_tags.json').readAsString(),
              );
        for (var read = 0; read < 3; read++) {
          final app = await parser.parse(
            CardApplication(aidHex: card.aid),
            card,
          );
          expect(app.summary.atc, '10'); // 00 0A is binary, not BCD.
          expect(app.dataTags.single.rawValueHex, '000A');
          expect(app.summary.pan, '4111111111111111');
          expect(app.gpoTags, isEmpty);
          expect(app.gpoHex, isEmpty);
          expect(
            app.issues.any((i) => i.code == 'transaction_processing_skipped'),
            isTrue,
          );
        }
        expect(card.atc, 10);
        expect(card.commands.where((c) => c[1] == 0xCA), hasLength(3));
        expect(card.commands.any((c) => c[1] == 0xA8 || c[1] == 0xAE), isFalse);
      },
    );

    for (final response in ['6985', '6A81', '6A88', '6D00', '6E00']) {
      test(
        '$family GET DATA rejection $response never falls back to GPO',
        () async {
          final replay = ReplayCardTransport([
            family == 'pboc' ? _selectPboc : _selectVisa,
            response,
            '6985',
          ]);
          final parser = family == 'pboc'
              ? await PbocParser.load((_) async => '{"entries":[]}')
              : await EmvParser.load((_) async => '{"entries":[]}');
          final app = await parser.parse(
            CardApplication(aidHex: family == 'pboc' ? _pboc : _visa),
            replay,
          );
          expect(app.application.selected, isTrue);
          expect(app.summary.atc, isNull);
          expect(app.records, isEmpty);
          expect(replay.sent.where((c) => c[1] == 0xCA), hasLength(1));
          expect(replay.sent.any((c) => c[1] == 0xA8 || c[1] == 0xAE), isFalse);
        },
      );
    }
  }

  for (final response in [
    '9000',
    '9F3601019000',
    '9F36030000019000',
    '9F3602009000',
  ]) {
    test('malformed ATC response $response stays unknown', () async {
      final replay = ReplayCardTransport([_selectVisa, response]);
      final app = await (await EmvParser.load((_) async => '{"entries":[]}'))
          .parse(const CardApplication(aidHex: _visa), replay);
      expect(app.summary.atc, isNull);
      expect(app.dataTags, isEmpty);
      expect(app.issues.any((i) => i.code == 'invalid_atc'), isTrue);
      expect(replay.sent.any((c) => c[1] == 0xA8), isFalse);
    });
  }

  final forbidden = [
    '80A8000002830000', // GPO, including empty and zero-value PDOL.
    '80A8000008830600000000000000',
    '80AE000002000000', // GENERATE AC, including AAC.
    '80AE800002000000',
    '00200080080000000000000000', // VERIFY PIN.
    '008200000100', // EXTERNAL AUTHENTICATE.
    '00880000010000', // INTERNAL AUTHENTICATE.
    '00D600000100', // UPDATE BINARY.
    '00DC010C0100', // UPDATE RECORD.
    '80DA9F36020000', // PUT DATA.
    '80CA9F1700', // GET DATA outside the explicit ATC object.
    '00CA9F3600', // Wrong CLA.
    '80CA9F360100', // GET DATA with command data.
    '00B2010A00', // Relative record access.
    '00B2000C00', // Record zero.
    '00B201FC00', // Reserved SFI 31.
    '80B2010C00', // Wrong CLA.
    '00B2010C010000', // READ RECORD with data.
    '00A40000023F0000', // SELECT outside by-name form.
    '00A4040207A000000003101000', // SELECT next occurrence.
    '80A4040007A000000003101000', // Wrong CLA.
    '00C0010000', // Nonzero GET RESPONSE parameter.
    '80C0000000', // Wrong CLA.
    '00C00000010000', // GET RESPONSE with data.
    '00FF000000', // Unknown instruction.
  ];

  test(
    'direct GET DATA ATC takes priority over a counter in FCI or a record',
    () async {
      final replay = ReplayCardTransport([
        '6F0E8407A00000000310109F360200099000',
        '6C05',
        '9F3602000A9000',
        '70059F360200089000',
      ]);
      final parser = await EmvParser.load(
        (_) => File('assets/dictionaries/emv_tags.json').readAsString(),
      );
      final app = await parser.parse(
        const CardApplication(aidHex: _visa),
        replay,
      );
      expect(app.summary.atc, '10');
      expect(replay.sent.take(3).map(HexCodec.encode), [
        '00A4040007A000000003101000',
        '80CA9F3600',
        '80CA9F3605',
      ]);
    },
  );

  for (final command in forbidden) {
    test(
      'unsafe APDU $command is blocked before physical I/O at both boundaries',
      () async {
        final replay = ReplayCardTransport(['9000']);
        final bytes = HexCodec.decode(command);
        await expectLater(
          exchangeReadOnly(
            (c) => replay.transceive(Uint8List.fromList(c)),
            bytes,
          ),
          throwsArgumentError,
        );
        await expectLater(
          RecordingCardTransport(replay).transceive(bytes),
          throwsArgumentError,
        );
        expect(replay.sent, isEmpty);
      },
    );
  }

  test('an injected parser cannot bypass the transport guard', () async {
    final replay = ReplayCardTransport([_ppsePboc, _selectPboc]);
    final result = await BankCardAnalyzer([_UnsafeParser()]).analyze(replay);
    expect(result.status, BankCardStatus.partial);
    expect(replay.sent.map((c) => c[1]), [0xA4, 0xA4]);
    expect(
      result.traces.map((t) => t.commandHex),
      replay.sent.map(HexCodec.encode),
    );
    expect(
      result.issues.any((i) => i.stage == 'parse' && i.code == 'exception'),
      isTrue,
    );
  });
}

/// Synthetic card that would change its persistent counter on transaction start.
class _CounterCard implements CardTransport {
  _CounterCard(this.family);
  final String family;
  String get aid => family == 'pboc' ? _pboc : _visa;
  var atc = 10;
  final commands = <List<int>>[];

  @override
  Future<Uint8List> transceive(Uint8List command) async {
    commands.add(command.toList());
    if (command[1] == 0xA8 || command[1] == 0xAE) atc++;
    if (command[1] == 0xA4) {
      return HexCodec.decode(family == 'pboc' ? _selectPboc : _selectVisa);
    }
    if (command[1] == 0xCA) {
      return HexCodec.decode(
        '9F3602${atc.toRadixString(16).padLeft(4, '0')}9000',
      );
    }
    if (HexCodec.encode(command) == '00B2010C00') return HexCodec.decode(_pan);
    return HexCodec.decode('6A83');
  }

  @override
  Future<void> close() async {}
}

class _UnsafeParser implements CardParser {
  @override
  String get parserId => 'pboc';
  @override
  bool supports(CardApplication application) => true;
  @override
  Future<ParsedApplication> parse(
    CardApplication application,
    CardTransport transport,
  ) async {
    await transport.transceive(HexCodec.decode('80A8000002830000'));
    return ParsedApplication(application: application, parserId: parserId);
  }
}
