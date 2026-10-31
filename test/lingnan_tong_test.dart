import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/protocols/transit/local/apdu_exchange.dart';
import 'package:transit_card_analyzer/protocols/transit/local/cards/lingnan_tong.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';

const realInfo =
    'FFFFFFFFFFFFFFFF5100009534635882030002FFFFFFFF202406212034123120240621438188010100000000052B000101015100009534635882030000000000FF8000FFFFFF';
const realFares = [
  '000B000000000000640601003006868700641027211308',
  '000A000000000000640601003000878000641027203357',
  '0009000000000000640601003006810200641027194808',
  '00080000000000008C0901003005324200C80823144018',
  '0007000000000002580901000022891902580823125617',
  '0006000000000000000901000022889800000823124011',
  '0004000000000007D00288012003262807D00823122814',
  '00050000000000008C0901003005358000C80823105759',
  '0004000000000001180901003005201601900823101017',
  '0003000000000000640901000022029500640816134817',
  '0002000000000001F40901000022193101F40812132617',
  '0001000000000000000901000022193700000812125011',
];
List<int> hex(String s) => [
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
];
String key(List<int> b) =>
    b.map((v) => v.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

class Fixture {
  Fixture({
    this.info = realInfo,
    this.fares = realFares,
    this.balance = '00000F00',
    this.stats = '18140024080100000000000000000000000000000000',
  });
  final String info;
  final List<String> fares;
  final String balance;
  final String stats;
  final commands = <String>[];
  String? throwOn;
  String? rejectOn;
  String? shortOn;
  final summary = CardInfo();
  final records = <ApduRecord>[];
  final extras = CardExtras();
  late final card = LingnanTong(
    ApduExchange(
      transceive: (command) async {
        final cmd = key(command);
        commands.add(cmd);
        if (cmd == throwOn) throw StateError('tag lost');
        if (cmd == rejectOn || '${cmd}00' == rejectOn) return [0x6A, 0x82];
        if (cmd == shortOn) return [0x90];
        if (command[1] == 0xA4) return [0x90, 0];
        if (command[1] == 0xB0) return [...hex(info), 0x90, 0];
        if (cmd == '00B2014416') return [...hex(stats), 0x90, 0];
        if (cmd == '805C000204') return [...hex(balance), 0x90, 0];
        if (command[1] == 0xB2 && command[3] == 0xC4) {
          final n = command[2];
          return n <= fares.length
              ? [...hex(fares[n - 1]), 0x90, 0]
              : [0x6A, 0x83];
        }
        fail('Unexpected command $cmd');
      },
    ),
    today: () => DateTime.utc(2026, 10, 31),
  );
  Future<void> read() => card.read(summary, records, extras);
  List<ApduRecord> get trips => records.where((r) => r.type == 2).toList();
}

void main() {
  test('TU gate requires confirmation, decimal identity, and explicit product prefix', () {
    for (final prefix in ['31048703', '31048709', '31048724']) {
      expect(
        LingnanTong.matchesTuIdentity(
          confirmed: true,
          cardNumber: '000${prefix}9534635882',
        ),
        isTrue,
      );
      expect(
        LingnanTong.matchesTuIdentity(
          confirmed: false,
          cardNumber: '${prefix}9534635882',
        ),
        isFalse,
      );
    }
    for (final number in [
      null,
      '',
      '000',
      '31048701',
      '31048799',
      '581031048703',
      ' 31048703',
      '+31048703',
      '31048703A',
      '３１０４８７０３',
    ]) {
      expect(
        LingnanTong.matchesTuIdentity(confirmed: true, cardNumber: number),
        isFalse,
        reason: '$number',
      );
    }
  });

  test('successful APPY selection confirms even an empty FCI', () async {
    final f = Fixture();
    expect(await f.card.selectAppy(f.records), isTrue);
    expect(f.commands.single, '00A40400085041592E4150505900');
    final rejected = Fixture()..rejectOn = f.commands.single;
    expect(await rejected.card.selectAppy(rejected.records), isFalse);
  });

  test(
    'TICL Le rejection falls back once and records selection evidence',
    () async {
      final f = Fixture()..rejectOn = '00A40400085041592E5449434C00';
      await f.read();
      expect(f.commands.where((c) => c.startsWith('00A404')), [
        '00A40400085041592E5449434C00',
        '00A40400085041592E5449434C',
      ]);
      expect(f.extras.slots['lnt.ticlConfirmed'], isFalse);
      expect(f.commands, isNot(contains('805C000204')));
    },
  );

  test('SELECT transport fault has no compatibility retry', () async {
    for (final command in [
      '00A40400085041592E4150505900',
      '00A40400085041592E5449434C00',
    ]) {
      final f = Fixture()..throwOn = command;
      await expectLater(
        command.contains('41505059')
            ? f.card.selectAppy(f.records, f.extras)
            : f.read(),
        throwsA(isA<ApduTransportException>()),
      );
      expect(f.commands.last, command);
      expect(f.commands.where((c) => c.startsWith('00A404')), [command]);
    }
  });

  test(
    'attachment real card: metadata, four-byte balance and unshifted fares',
    () async {
      final f = Fixture();
      await f.read();
      expect(f.summary.isYCT, isTrue);
      expect(f.summary.isLNT, isTrue);
      expect(f.summary.currencyCode, 'CNY');
      expect(f.summary.cardNumber, '9534635882');
      expect(f.summary.issuerCode, '01015100');
      expect(f.summary.issueDate, DateTime.utc(2024, 6, 21));
      expect(f.summary.expiryDate, DateTime.utc(2034, 12, 31));
      expect(f.summary.balance, 3840);
      expect(f.trips, hasLength(12));
      expect(f.trips.first.balanceDelta, -100);
      expect(f.trips[3].balanceDelta, -140);
      expect(f.trips[6].balanceDelta, 2000);
      expect(f.trips.first.timestamp, DateTime.utc(2024, 10, 27, 21, 13));
      expect(f.trips.last.timestamp, DateTime.utc(2024, 8, 12, 12, 50));
      expect(f.trips.first.terminalHex, '010030068687');
      expect(
        f.trips.every((r) => r.cityCode == 0 && r.balanceAfter == 0),
        isTrue,
      );
      expect(f.trips[4].isMetro, isTrue);
      expect(f.trips[5].isMetro, isTrue);
      expect(f.trips[3].isMetro, isFalse);
      expect(f.trips.first.rawBody, hex(realFares.first));
      expect(f.trips.first.fileSelector, 0xC4);
      expect(f.trips.first.recordNumber, 1);
      final meta = f.extras.slots['lnt.transactions'] as List;
      expect(meta.first['subtype'], 0x08);
      expect(meta.first['secondsKnown'], isFalse);
      expect(meta.first['yearBasis'], 'statistics-month-match');
    },
  );

  test(
    'cross-year uses physical record order, not transaction counters',
    () async {
      String fare(String mmdd) =>
          '${realFares.first.substring(0, 36)}${mmdd}211308';
      final f = Fixture(
        fares: [fare('0102'), fare('1231')],
        stats: '000000241200',
      );
      await f.read();
      expect(f.trips[0].timestamp, DateTime.utc(2025, 1, 2, 21, 13));
      expect(f.trips[1].timestamp, DateTime.utc(2024, 12, 31, 21, 13));
    },
  );

  test(
    'unanchored dates respect today, issue lower bound and invalid dates',
    () async {
      final invalid = hex(realFares.first)..[18] = 0x02;
      invalid[19] = 0x30;
      final f = Fixture(stats: '', fares: [realFares.first, key(invalid)]);
      await f.read();
      expect(f.trips.first.timestamp.year, 2026);
      expect(f.trips.last.timestamp.millisecondsSinceEpoch, 0);
      final meta = f.extras.slots['lnt.transactions'] as List;
      expect(meta.last['invalidOrUnboundedDate'], isTrue);
      final future = hex(realInfo);
      future.setRange(23, 27, hex('20271001'));
      final impossible = Fixture(info: key(future), fares: [realFares.first]);
      await impossible.read();
      expect(impossible.trips.single.timestamp.millisecondsSinceEpoch, 0);
    },
  );

  test('balance uses all four bytes and attachment flag heuristic', () async {
    for (final entry in {
      '01020304': 0x01020304,
      '800006E0': 1760,
      'FFF00000': -1048576,
    }.entries) {
      final f = Fixture(balance: entry.key, fares: []);
      await f.read();
      expect(f.summary.balance, entry.value);
    }
    final short = Fixture(balance: '010203', info: 'FF', fares: []);
    await short.read();
    expect(short.summary.observedBalance, isNull);
    expect(short.summary.cardNumber, isEmpty);
    expect(short.commands.where((c) => c.startsWith('00B0')), hasLength(1));
  });

  test(
    'status fallback is bounded and monthly statistics can be read in TICL',
    () async {
      final f = Fixture()..rejectOn = '00B0950046';
      await f.read();
      expect(f.commands.take(2), ['00B0950046', '00B0954046']);
      final g = Fixture()..rejectOn = '00B2014416';
      await g.read();
      expect(g.commands.where((c) => c == '00B2014416'), hasLength(2));
      expect(g.summary.balance, 3840);
    },
  );

  test(
    'short transaction and failed status end the read, maximum is 30',
    () async {
      final short = Fixture(fares: [realFares.first, '010203', realFares.last]);
      await short.read();
      expect(short.trips, hasLength(1));
      expect(short.commands.last, '00B202C417');
      final bounded = Fixture(fares: List.filled(31, realFares.first));
      await bounded.read();
      expect(bounded.trips, hasLength(30));
      expect(bounded.commands.last, '00B21EC417');
    },
  );

  test('transport errors stop all subsequent I/O and preserve partial observations', () async {
    for (final cmd in [
      '00B0950046',
      '00B2014416',
      '805C000204',
      '00B202C417',
    ]) {
      final f = Fixture()..throwOn = cmd;
      await expectLater(f.read(), throwsA(isA<ApduTransportException>()));
      expect(f.commands.last, cmd);
      if (cmd == '00B202C417') {
        expect(f.trips, hasLength(1));
        expect(f.summary.balance, 3840);
        expect(f.trips.first.timestamp.year, 2024);
      }
    }
  });

  test('malformed info response does not trigger fallback probes', () async {
    final f = Fixture()..shortOn = '00B0950046';
    await f.read();
    expect(f.commands.where((c) => c.startsWith('00B0')), hasLength(1));
  });
}
