import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/protocols/transit/local/apdu_exchange.dart';
import 'package:transit_card_analyzer/protocols/transit/local/cards/beijing_local_card.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';

void main() {
  test(
    'strict READ BINARY rejects successful but truncated card responses',
    () async {
      final apdu = ApduExchange(transceive: (_) async => [0x10, 0, 0x90, 0]);
      expect(
        await apdu([0, 0xB0, 0x84, 0, 0x3C], 'file04', strict: true),
        isNull,
      );
    },
  );

  test(
    'unrelated short file04 cannot crash Beijing probe before bank discovery',
    () async {
      final apdu = ApduExchange(transceive: (_) async => [0x10, 0, 0x90, 0]);
      expect(
        await BeijingLocalCard(apdu).probe(CardInfo(), <ApduRecord>[]),
        isFalse,
      );
    },
  );

  test('non-strict SELECT accepts an empty successful FCI', () async {
    final apdu = ApduExchange(transceive: (_) async => [0x90, 0]);
    expect(await apdu([0, 0xA4, 0, 0, 2, 0x3F, 0], 'MF'), isEmpty);
  });

  test('strict length uses the corrected Le after 6C retry', () async {
    var attempts = 0;
    final apdu = ApduExchange(
      transceive: (cmd) async {
        if (attempts++ == 0) return [0x6C, 2];
        expect(cmd.last, 2);
        return [0x10, 0, 0x90, 0];
      },
    );
    expect(await apdu([0, 0xB0, 0x84, 0, 0x3C], 'file04', strict: true), [
      0x10,
      0,
    ]);
  });
}
