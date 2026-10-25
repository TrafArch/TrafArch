import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/protocols/transit/local/apdu_exchange.dart';
import 'package:transit_card_analyzer/protocols/transit/local/cards/macau_pass_card.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';

void main() {
  test('selects Macau Pass only with the wallet-name FCI evidence', () async {
    final info = CardInfo();
    final card = MacauPassCard(
      ApduExchange(
        transceive: (_) async => [
          0x6F,
          0x42,
          0x84,
          0x0A,
          ...MacauPassCard.walletName,
          0xA5,
          0x34,
          0x9F,
          0x08,
          0x01,
          0x02,
          0x9F,
          0x0C,
          0x2D,
          0x00,
          0x01,
          0x08,
          0x53,
          0x00,
          0x00,
          0x00,
          0x00,
          0x01,
          0x01,
          0x00,
          0x00,
          0xEF,
          0x90,
          0xC3,
          0xC9,
          0xF5,
          0x13,
          0x35,
          0x76,
          0x20,
          0x24,
          0x01,
          0x26,
          0x20,
          0x24,
          0x10,
          0x31,
          0x55,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x61,
          0x32,
          0x76,
          0x62,
          0x47,
          0x01,
          0x00,
          0x00,
          0x00,
          0x00,
          0x90,
          0x00,
        ],
      ),
    );

    expect(await card.select(info, []), isTrue);
    expect(info.isMacauPass, isTrue);
    expect(info.cardKindLabel, '澳门通');
    expect(info.currencyCode, 'MOP');
    expect(info.cardNumber, '6132766247');
  });

  test('rejects a successful SELECT without Macau Pass FCI evidence', () async {
    final card = MacauPassCard(
      ApduExchange(transceive: (_) async => [0x6F, 0x00, 0x90, 0x00]),
    );
    expect(await card.select(CardInfo(), []), isFalse);
  });

  test('reads big-endian balance and strict BCD transaction time', () async {
    final responses = <List<int>>[
      [0x00, 0x00, 0x00, 0xA5, 0x90, 0x00],
      [
        0x01,
        0x5F,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x0F,
        0x09,
        0x00,
        0x00,
        0x00,
        0x04,
        0x29,
        0x98,
        0x20,
        0x26,
        0x07,
        0x18,
        0x13,
        0x16,
        0x28,
        0x90,
        0x00,
      ],
      [0x6A, 0x83],
    ];
    final card = MacauPassCard(
      ApduExchange(transceive: (_) async => responses.removeAt(0)),
    );
    final info = CardInfo()..isMacauPass = true;
    final records = <ApduRecord>[];

    await card.readBalanceAndRecords(info, records);

    expect(info.observedBalance, 165);
    expect(records, hasLength(1));
    expect(records.single.rawBody, hasLength(23));
    expect(records.single.timestamp, DateTime(2026, 7, 18, 13, 16, 28));
    expect(records.single.type, 0);
  });

  test('keeps invalid timestamp raw without inventing a date', () async {
    final responses = <List<int>>[
      [0x00, 0x00, 0x00, 0x00, 0x90, 0x00],
      [...List<int>.filled(16, 0), 0x20, 0x26, 0x13, 0x40, 0, 0, 0, 0x90, 0x00],
      [0x6A, 0x83],
    ];
    final records = <ApduRecord>[];
    await MacauPassCard(
      ApduExchange(transceive: (_) async => responses.removeAt(0)),
    ).readBalanceAndRecords(CardInfo(), records);

    expect(records.single.rawBody, hasLength(23));
    expect(records.single.timestamp.millisecondsSinceEpoch, 0);
  });
}
