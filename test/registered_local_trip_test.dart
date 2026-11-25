import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/protocols/transit/local/apdu_exchange.dart';
import 'package:transit_card_analyzer/protocols/transit/local/card_aid.dart';
import 'package:transit_card_analyzer/protocols/transit/local/cards/suzhou_card.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_hex.dart';
import 'package:transit_card_analyzer/protocols/transit/local/trips/trip_records.dart';

void main() {
  test(
    'balance reconstruction uses only the observed wallet and never probes CU',
    () async {
      final info = CardInfo()
        ..balance = -100
        ..isCU = true
        ..lastSeenRecordIndex = 0;
      final trip = ApduRecord()
        ..type = 2
        ..isMetro = true
        ..balanceDelta = -120
        ..response = List.filled(23, 0);
      final reader = TripRecordReader(
        ApduExchange(
          transceive: (cmd) async {
            fail('Unexpected APDU during balance reconstruction: $cmd');
          },
        ),
      );
      await reader.reconstructBalances(info, [trip]);
      expect(trip.balanceAfter, -100);
      expect(trip.balanceDelta, -120);
    },
  );
  test('SUXIN selection verifies the default 123456 PIN', () async {
    final commands = <List<int>>[];
    final exchange = ApduExchange(
      transceive: (command) async {
        commands.add(command);
        return [0x90, 0];
      },
    );
    expect(await SuzhouCard(exchange).select(CardInfo(), []), isTrue);
    expect(commands, [CardAid.suxin, CardAid.suzhouPinVerify]);
    expect(CardAid.suzhouPinVerify, [
      0x00,
      0x20,
      0x00,
      0x00,
      0x03,
      0x12,
      0x34,
      0x56,
    ]);
  });

  test('SUXIN rejected PIN leaves the application unconfirmed', () async {
    final commands = <List<int>>[];
    final info = CardInfo();
    final exchange = ApduExchange(
      transceive: (command) async {
        commands.add(command);
        return command[1] == 0xA4 ? [0x90, 0] : [0x63, 0xC2];
      },
    );
    expect(await SuzhouCard(exchange).select(info, []), isFalse);
    expect(commands, [CardAid.suxin, CardAid.suzhouPinVerify]);
    expect(info.isSuzhou, isFalse);
    expect(info.isSuxin, isFalse);
  });

  for (final entry in {
    'suxin': [291, -291],
    'cika': [-291, 291],
    'tft': [-291, 291],
  }.entries) {
    test(
      '${entry.key} standard record retains amount, direction and seconds',
      () async {
        final bytes = LocalHex.hexToBytes(
          '0203000000000001230111223344556620261124173859',
        );
        final second = [...bytes]..[9] = 0x12;
        final invalidDate = [...bytes]..[18] = 0x1A;
        final responses = [bytes, second, invalidDate];
        final records = <ApduRecord>[];
        final info = CardInfo()
          ..isSuzhou = entry.key != 'tft'
          ..isSuxin = entry.key == 'suxin'
          ..isCika = entry.key == 'cika'
          ..isTFT = entry.key == 'tft';
        await TripRecordReader(
          ApduExchange(
            transceive: (cmd) async {
              final index = cmd[2] - 1;
              return index < responses.length
                  ? [...responses[index], 0x90, 0]
                  : [0x6A, 0x83];
            },
          ),
        ).readFile(info, records, CardExtras(), TripFile.metro);
        final trips = records.where((r) => r.type == 2).toList();
        if (info.isCika) {
          expect(trips.take(2).map((r) => r.balanceDelta), [0, 0]);
          expect(trips.take(2).map((r) => r.tripDelta), entry.value);
        } else {
          expect(trips.take(2).map((r) => r.balanceDelta), entry.value);
          expect(trips.first.tripDelta, isNull);
        }
        expect(trips.first.timestamp.second, 59);
        expect(trips.first.statusCode, 515);
        expect(trips.last.timestamp.millisecondsSinceEpoch, 0);
      },
    );
  }
}
