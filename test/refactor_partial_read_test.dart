import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/scan/application/bank_card_probe.dart';
import 'package:transit_card_analyzer/features/scan/application/local_card_reader.dart';
import 'package:transit_card_analyzer/protocols/bank/domain/models/bank_card_result.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/local/apdu_exchange.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_reader.dart';
import 'package:transit_card_analyzer/protocols/transport/transport_failure.dart';

// Synthetic APDU responses exercise the production readers and exchange engine.
// Only physical I/O is substituted; no parsed result is mocked.
void main() {
  for (final failedSfi in [0x16, 0x17]) {
    test(
      'TU retains public identity when SFI $failedSfi disconnects',
      () async {
        final link = _tuLink(failedSfi: failedSfi);
        final unit = CommonUnitTu(ApduExchange(transceive: link.call));
        final info = CardInfo();
        final records = <ApduRecord>[];
        expect(await unit.select(info, records), isTrue);

        await expectLater(
          unit.read(info, records),
          throwsA(
            isA<ApduTransportException>().having(
              (e) => e.failure,
              'original transport failure',
              same(_tagLost),
            ),
          ),
        );

        expect(unit.parsedCard, isNotNull);
        final partial = unit.parsedCard!;
        expect(partial.parserId, CardParserIds.tunion);
        expect(partial.info.applicationSerial, '03100000000000000001');
        expect(partial.info.issuerId, '1122334455667788');
        expect(unit.lastCardInfo!.applicationSerial, '03100000000000000001');
        expect(info.issuerCode, '1122334455667788');
        expect(info.cardNumber, isNotEmpty);
        expect(partial.info.balanceFen, isNull);
        expect(partial.transactionFileObserved, isFalse);
        expect(partial.info.cardTypeId, failedSfi == 0x17 ? '01' : isNull);
        expect(partial.selectedAidHex, 'A000000632010105');
        expect(link.callsAfterFailure, 0);
      },
    );
  }

  test(
    'TU invalid serial is not promoted after a holder-file failure',
    () async {
      final link = _tuLink(failedSfi: 0x16, invalidSerial: true);
      final unit = CommonUnitTu(ApduExchange(transceive: link.call));
      final info = CardInfo();
      final records = <ApduRecord>[];
      expect(await unit.select(info, records), isTrue);
      await expectLater(
        unit.read(info, records),
        throwsA(isA<ApduTransportException>()),
      );
      expect(unit.parsedCard, isNull);
      expect(link.callsAfterFailure, 0);
    },
  );

  test(
    'TU retains zero balance and decoded transactions after process failure',
    () async {
      final link = _tuLink(failedSfi: 0x1A);
      final unit = CommonUnitTu(ApduExchange(transceive: link.call));
      final info = CardInfo();
      final records = <ApduRecord>[];
      expect(await unit.select(info, records), isTrue);
      await expectLater(
        unit.read(info, records),
        throwsA(
          isA<ApduTransportException>().having(
            (e) => e.failure,
            'original transport failure',
            same(_tagLost),
          ),
        ),
      );
      final partial = unit.parsedCard!;
      expect(partial.info.balanceFen, 0);
      expect(partial.transactionFileObserved, isTrue);
      expect(partial.transactions.single.amountFen, 4660);
      expect(partial.transactions.single.terminalId, '123456789012');
      expect(records.single.balanceDelta, -4660);
      expect(link.callsAfterFailure, 0);
    },
  );

  for (final balance in [10000, 0]) {
    test(
      'Beijing retains observed balance $balance after extras failure',
      () async {
        final link = _beijingLink(balance: balance, failInHistory: false);
        final bank = _BankProbe();
        final result = await LocalCardReader(link.call, bankProbe: bank).read();
        expect(result, isNotNull);
        expect(result!.parsedCard!.parserId, CardParserIds.localCard);
        expect(
          result.parsedCard!.info.applicationSerial,
          '10000000000000000001',
        );
        expect(result.parsedCard!.info.balanceFen, balance);
        expect(result.readResult!.info.isBeijing, isTrue);
        expect(result.readResult!.info.balance, balance);
        expect(result.parsedCard!.localCard, same(result.readResult));
        expect(result.readResult!.transportFailure, same(_tagLost));
        expect(result.readResult!.readError, isA<ApduTransportException>());
        expect(
          bank.calls,
          0,
          reason: 'a confirmed transit card must not fall through',
        );
        expect(link.callsAfterFailure, 0);
      },
    );
  }

  test(
    'Beijing retains the observed history prefix and extras on tag loss',
    () async {
      final link = _beijingLink(balance: 10000, failInHistory: true);
      final bank = _BankProbe();
      final result = await LocalCardReader(link.call, bankProbe: bank).read();
      expect(result, isNotNull);
      final partial = result!.parsedCard!;
      expect(partial.info.balanceFen, 10000);
      final trip = partial.localCard!.trips.single;
      expect(trip.response, _localTrip);
      expect(trip.terminalHex, '100001020304');
      expect(trip.balanceDelta, -2);
      expect(trip.recordNumber, 1);
      expect(partial.localCard!.extras.dateRaw, [0x24, 0x10]);
      expect(partial.localCard!.transportFailure, same(_tagLost));
      expect(partial.localCard!.readError, isA<ApduTransportException>());
      expect(bank.calls, 0);
      expect(link.callsAfterFailure, 0);
    },
  );

  test(
    'YCT identity survives wallet failure without inventing a zero balance',
    () async {
      final link = _CardLink((command) {
        final hex = _hex(command);
        if (hex.startsWith('00A40400085041592E41505059') ||
            hex.startsWith('00A40400085041592E5449434C')) {
          return _ok([]);
        }
        if (hex == '00B0950046') {
          final bytes = List<int>.filled(70, 0);
          bytes.setRange(8, 18, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
          bytes.setRange(27, 31, [0x20, 0x30, 0x12, 0x31]);
          return _ok(bytes);
        }
        if (command[1] == 0x5C) throw _tagLost;
        return [0x6A, 0x82];
      });
      final bank = _BankProbe();
      final result = await LocalCardReader(link.call, bankProbe: bank).read();
      expect(result, isNotNull);
      expect(
        result!.parsedCard!.info.applicationSerial,
        '00010203040506070809',
      );
      expect(result.parsedCard!.info.balanceFen, isNull);
      expect(result.readResult!.info.observedBalance, isNull);
      expect(result.readResult!.transportFailure, same(_tagLost));
      expect(bank.calls, 0);
      expect(link.callsAfterFailure, 0);
    },
  );
}

const _tagLost = TransportFailure(
  kind: TransportFailureKind.tagLost,
  code: 'TAG_LOST',
  message: 'synthetic physical tag loss',
);

class _CardLink {
  _CardLink(this.respond);
  final List<int> Function(List<int>) respond;
  bool failed = false;
  int callsAfterFailure = 0;

  Future<List<int>> call(List<int> command) async {
    if (failed) {
      callsAfterFailure++;
      throw StateError('NFC continued after the failed exchange');
    }
    try {
      return respond(command);
    } on TransportFailure {
      failed = true;
      rethrow;
    }
  }
}

class _BankProbe implements BankCardProbe {
  int calls = 0;
  @override
  Future<BankCardResult?> probe(LocalTransceive transceive) async {
    calls++;
    return null;
  }
}

_CardLink _tuLink({required int failedSfi, bool invalidSerial = false}) =>
    _CardLink((command) {
      final ins = command[1];
      if (ins == 0xA4) return _ok([]);
      if (ins == 0xB0) {
        final sfi = command[2] & 0x1F;
        if (sfi == failedSfi) throw _tagLost;
        if (sfi == 0x15) {
          return _ok([
            0x11,
            0x22,
            0x33,
            0x44,
            0x55,
            0x66,
            0x77,
            0x88,
            1,
            1,
            invalidSerial ? 0x99 : 0x03,
            0x10,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            1,
            0x20,
            0x24,
            1,
            1,
            0x20,
            0x29,
            0x12,
            0x31,
            0xAA,
            0xBB,
          ]);
        }
        if (sfi == 0x16) return _ok(List<int>.filled(55, 0)..[0] = 1);
        if (sfi == 0x17) return _ok(List<int>.filled(60, 0)..[6] = 0x10);
      }
      if (ins == 0x5C) return _ok([0, 0, 0, 0]);
      if (ins == 0xB2) {
        final sfi = command[3] >> 3;
        if (sfi == failedSfi) throw _tagLost;
        if (sfi == 0x18) {
          return _ok([
            0,
            1,
            0,
            0,
            0,
            0,
            0,
            0x12,
            0x34,
            0x06,
            0x12,
            0x34,
            0x56,
            0x78,
            0x90,
            0x12,
            0x20,
            0x24,
            0x05,
            0x01,
            0x08,
            0x30,
            0,
          ]);
        }
      }
      return [0x6A, 0x82];
    });

_CardLink _beijingLink({required int balance, required bool failInHistory}) =>
    _CardLink((command) {
      switch (_hex(command)) {
        case '00B084003C':
          final bytes = List<int>.filled(60, 0)
            ..[0] = 0x10
            ..[9] = 1
            ..[24] = 0x20;
          bytes.setRange(28, 32, [0x20, 0x30, 0x12, 0x31]);
          return _ok(bytes);
        case '00B0850020':
          return _ok(List<int>.filled(32, 0));
        case '00A40000021001':
          return _ok([]);
        case '805C000204':
          return _ok([0, 0, balance >> 8, balance & 0xFF]);
        case '00B0950032':
          if (!failInHistory) throw _tagLost;
          final bytes = List<int>.filled(50, 0);
          bytes.setRange(37, 40, [0x24, 0x10, 0x21]);
          return _ok(bytes);
        case '00B201C417':
          return _ok(_localTrip);
        case '00B202C417':
          throw _tagLost;
        default:
          return [0x6A, 0x82];
      }
    });

const _localTrip = [
  0,
  1,
  0,
  0,
  0,
  0,
  0,
  0x80,
  0,
  2,
  0x10,
  0,
  1,
  2,
  3,
  4,
  0x20,
  0x26,
  0x10,
  0x21,
  0x12,
  0x30,
  0,
];

List<int> _ok(List<int> bytes) => [...bytes, 0x90, 0];
String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
