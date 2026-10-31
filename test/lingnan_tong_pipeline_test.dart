import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/card_identification_service.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_types.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/scan/application/bank_card_probe.dart';
import 'package:transit_card_analyzer/features/scan/application/local_card_reader.dart';
import 'package:transit_card_analyzer/protocols/bank/domain/models/bank_card_result.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/local/apdu_exchange.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';
import 'package:transit_card_analyzer/protocols/transit/local/cards/shanghai_transit_union_card.dart';
import 'package:transit_card_analyzer/protocols/transport/transport_failure.dart';

// Reuse the real attachment bytes, not the permissive transport in that test.
import 'lingnan_tong_test.dart' show realInfo, realFares;

const _mf = '00A40000023F0000';
const _tuSelect = '00A4040008A00000063201010500';
const _cuSelect = '00A4040009A0000000038698070100';
const _appy = '00A40400085041592E4150505900';
const _ticl = '00A40400085041592E5449434C00';
List<_Step> _rejectAppy() => [
  _Step.reject(_appy),
  _Step.reject(_appy.substring(0, _appy.length - 2)),
];
const _tuFare = '0001000000000000C80612345678901220240501083000';
const _serial = '00310487039534635882';
const _tagLost = TransportFailure(
  kind: TransportFailureKind.tagLost,
  code: 'TAG_LOST',
  message: 'pipeline fixture card removed',
);

List<int> _bytes(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];
String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

class _Step {
  _Step(this.command, [String data = '']) : response = '${data}9000';
  _Step.reject(this.command) : response = '6A82';
  _Step.lost(this.command) : response = null;
  final String command;
  final String? response;
}

// A finite ordered transcript: even unexpected SELECTs or reads after failure
// fail the test. No catch-all command matcher or success/rejection fallback.
class _Replay {
  _Replay(this.steps);
  final List<_Step> steps;
  final commands = <String>[];
  int cursor = 0;
  bool stopped = false;
  int callsAfterFailure = 0;

  Future<List<int>> call(List<int> apdu) async {
    final command = _hex(apdu);
    commands.add(command);
    if (stopped) callsAfterFailure++;
    expect(cursor, lessThan(steps.length), reason: 'Extra APDU $command');
    final step = steps[cursor++];
    expect(command, step.command, reason: 'APDU #$cursor');
    if (step.response == null) {
      stopped = true;
      throw _tagLost;
    }
    return _bytes(step.response!);
  }

  void verify() {
    expect(cursor, steps.length, reason: 'Transcript must be exhausted');
    expect(callsAfterFailure, 0);
    expect(commands, steps.map((s) => s.command).toList());
  }
}

List<_Step> _tu({String serial = _serial}) => [
  _Step(_mf),
  _Step(_tuSelect),
  _Step('00B0950000', '02002900123456780101${serial}2024010120291231AABB'),
  _Step('00B0960000', _hex(List<int>.filled(55, 0)..[0] = 1)),
  _Step('00B0970000', _hex(List<int>.filled(60, 0)..[6] = 0x31)),
  _Step('805C000204', '00002710'),
  _Step('00B201C500', _tuFare),
  _Step.reject('00B201D400'),
  _Step.reject('00B201D500'),
  _Step.reject('00B201F500'),
  _Step.reject('00B201F400'),
];

List<_Step> _lnt({bool lost = false}) => [
  _Step(_appy),
  _Step('00B0950046', realInfo),
  _Step('00B2014416', '18140024080100000000000000000000000000000000'),
  _Step(_ticl),
  _Step('805C000204', '00000F00'),
  _Step('00B201C417', realFares.first),
  if (lost) _Step.lost('00B202C417') else _Step.reject('00B202C417'),
];

List<_Step> _rejectCu() => [
  _Step(_mf),
  _Step.reject(_cuSelect),
  _Step.reject('00A4040009A00000000386980701'),
  _Step.reject('80A4040009A0000000038698070100'),
  _Step.reject('80A4040009A00000000386980701'),
];

List<_Step> _noTuLocalPrefix() => [
  _Step(_mf),
  for (final directory in [null, '1PAY.SYS.DDF01', '2PAY.SYS.DDF01']) ...[
    if (directory != null)
      _Step.reject('00A404000E${_hex(directory.codeUnits)}00'),
    for (final aid in ['A000000632010105', 'A000000632010106'])
      for (final cla in ['00', '80']) _Step.reject('${cla}A4040008${aid}00'),
  ],
];

class _BankProbe implements BankCardProbe {
  int calls = 0;
  @override
  Future<BankCardResult?> probe(LocalTransceive transceive) async {
    calls++;
    fail('A confirmed transit card must not fall back to bank probing');
  }
}

List<ApduRecord> _trips(ReadResult result) =>
    result.records.where((r) => r.type == 2).toList();

void _expectTu(LocalReadOutcome outcome, String serial) {
  final card = outcome.parsedCard!;
  expect(card.info.applicationSerial, serial);
  expect(card.info.issuerId, '0200290012345678');
  expect(card.info.balanceFen, 10000);
  expect(card.selectedAidHex, 'A000000632010105');
  expect(card.transactionFileObserved, isTrue);
  expect(card.transactions.single.rawHex, _tuFare);
  expect(
    outcome.readResult!.info.cardNumber,
    serial.replaceFirst(RegExp(r'^0+'), ''),
  );
  expect(outcome.readResult!.info.observedBalance, 10000);
  expect(_trips(outcome.readResult!).single.balanceDelta, -200);
  expect(outcome.shanghai, isNull);
}

void _expectLnt(ReadResult local) {
  expect(local.info.isLNT, isTrue);
  expect(local.info.cardNumber, '9534635882');
  expect(local.info.issuerCode, '01015100');
  expect(local.info.observedBalance, 3840);
  final fare = _trips(local).single;
  expect(fare.rawBody, _bytes(realFares.first));
  expect(fare.balanceDelta, -100);
  expect(fare.balanceAfter, 0, reason: 'No legacy balance reconstruction');
  expect(fare.cityCode, 0);
  expect(fare.timestamp, DateTime.utc(2024, 10, 27, 21, 13));
}

void main() {
  test(
    'stateful card locks APPY/TICL after MF/TU/PSE; early LNT survives',
    () async {
      final replay = _Replay([..._lnt(), ..._tu()]);
      var locked = false;
      Future<List<int>> call(List<int> command) async {
        final hex = _hex(command);
        if (hex == _mf || hex == _tuSelect || hex.contains('5041592E535953')) {
          locked = true;
        }
        if (locked &&
            (hex.startsWith(_appy.substring(0, 26)) ||
                hex.startsWith(_ticl.substring(0, 26)))) {
          return _bytes('6A82');
        }
        return replay.call(command);
      }

      final result = (await LocalCardReader(call).read())!;
      _expectLnt(result.parsedCard!.localCard!);
      _expectTu(result, _serial);
      replay.verify();
      // The same state rejects the former post-TU SELECT order.
      expect(await call(_bytes(_appy)), _bytes('6A82'));
      expect(await call(_bytes(_ticl)), _bytes('6A82'));
    },
  );

  test(
    'Case 4 APPY status rejection permits exactly one Case 3 fallback',
    () async {
      final replay = _Replay([
        _Step.reject(_appy),
        _Step(_appy.substring(0, _appy.length - 2)),
        ..._lnt().skip(1),
        ..._tu(),
      ]);
      final result = (await LocalCardReader(replay.call).read())!;
      _expectLnt(result.parsedCard!.localCard!);
      final evidence =
          result.parsedCard!.localCard!.extras.slots['lnt.appySelect'] as List;
      expect(evidence[0]['statusWord'], 0x6A82);
      expect(evidence[1]['selected'], isTrue);
      replay.verify();
    },
  );

  test('TICL status fallback succeeds once without reselecting APPY', () async {
    final lnt = _lnt();
    final replay = _Replay([
      ...lnt.take(3),
      _Step.reject(_ticl),
      _Step(_ticl.substring(0, _ticl.length - 2)),
      ...lnt.skip(4),
      ..._tu(),
    ]);
    final result = (await LocalCardReader(replay.call).read())!;
    _expectLnt(result.parsedCard!.localCard!);
    expect(
      result.parsedCard!.localCard!.extras.slots['lnt.ticlConfirmed'],
      isTrue,
    );
    replay.verify();
  });

  for (final serial in ['00310000000000000001', '00310477000000000001']) {
    test(
      'confirmed LNT with non-target TU $serial never mixes Shanghai/CU',
      () async {
        final replay = _Replay([..._lnt(), ..._tu(serial: serial)]);
        final bank = _BankProbe();
        final result = (await LocalCardReader(
          replay.call,
          bankProbe: bank,
        ).read())!;
        expect(result.parsedCard!.parserId, CardParserIds.lingnanTong);
        _expectLnt(result.readResult!);
        expect(result.shanghai, isNull);
        expect(result.readResult!.extras.slots['lnt.tuCard'], isNotNull);
        expect(bank.calls, 0);
        replay.verify();
      },
    );
  }

  for (final prefix in ['31048703', '31048709', '31048724']) {
    test(
      'confirmed TU $prefix probes APP Y once and isolates both applications',
      () async {
        final serial = '00${prefix}9534635882';
        final replay = _Replay([..._lnt(), ..._tu(serial: serial)]);
        final bank = _BankProbe();
        final result = (await LocalCardReader(
          replay.call,
          bankProbe: bank,
        ).read())!;
        expect(result.parsedCard!.parserId, CardParserIds.lingnanTunion);
        _expectTu(result, serial);
        final local = result.parsedCard!.localCard!;
        _expectLnt(local);
        expect(local.extras.slots['lnt.appyConfirmed'], isTrue);
        expect(result.readResult!.readError, isNull);
        expect(local.readError, isNull);
        expect(bank.calls, 0);
        replay.verify();
      },
    );
  }

  for (final serial in [
    '00310000000000000001',
    '00310487019534635882',
    '00310487999534635882',
  ]) {
    test(
      'ordinary TU $serial rejects early APPY then reuses TU without CU or rereads',
      () async {
        final replay = _Replay([..._rejectAppy(), ..._tu(serial: serial)]);
        final result = (await LocalCardReader(replay.call).read())!;
        expect(result.parsedCard!.parserId, CardParserIds.tunion);
        expect(result.parsedCard!.localCard, isNull);
        _expectTu(result, serial);
        replay.verify();
      },
    );
  }

  test(
    'Shanghai TU rejects early APPY then remains in Shanghai pipeline',
    () async {
      final replay = _Replay([
        ..._rejectAppy(),
        ..._tu(serial: '00310477000000000001'),
        ..._rejectCu(),
      ]);
      final result = (await LocalCardReader(replay.call).read())!;
      expect(result.parsedCard!.parserId, CardParserIds.shanghaiTunion);
      expect(result.shanghai!.tu.confirmed, isTrue);
      expect(result.parsedCard!.localCard, isNull);
      expect(replay.commands.where((c) => c == _appy), hasLength(1));
      replay.verify();
    },
  );

  for (final transportError in [false, true]) {
    test('APP Y failure retains TU (transport=$transportError)', () async {
      final replay = _Replay([
        if (transportError) _Step.lost(_appy) else ..._rejectAppy(),
        if (!transportError) ..._tu(),
      ]);
      if (transportError) {
        await expectLater(
          LocalCardReader(replay.call).read(),
          throwsA(isA<ApduTransportException>()),
        );
        replay.verify();
        return;
      }
      final result = (await LocalCardReader(replay.call).read())!;
      _expectTu(result, _serial);
      expect(result.parsedCard!.parserId, CardParserIds.lingnanTunion);
      final local = result.parsedCard!.localCard!;
      expect(local.extras.slots['lnt.appyConfirmed'], isFalse);
      expect(local.info.observedBalance, isNull);
      expect(_trips(local), isEmpty);
      expect(
        result.readResult!.transportFailure,
        transportError ? same(_tagLost) : isNull,
      );
      replay.verify();
    });
  }

  test(
    'late LNT terminal failure preserves both sides with zero subsequent I/O',
    () async {
      final replay = _Replay([
        ..._lnt(),
        ..._tu().take(7),
        _Step.lost('00B201D400'),
      ]);
      final bank = _BankProbe();
      final result = (await LocalCardReader(
        replay.call,
        bankProbe: bank,
      ).read())!;
      _expectTu(result, _serial);
      final local = result.parsedCard!.localCard!;
      _expectLnt(local);
      expect(local.transportFailure, isNull);
      expect(local.readError, isNull);
      expect(result.readResult!.transportFailure, same(_tagLost));
      expect(result.readResult!.readError, isA<ApduTransportException>());
      expect(bank.calls, 0);
      replay.verify();
    },
  );

  for (final lost in [false, true]) {
    test(
      'no TU: local LNT retains observed balance without legacy rebuild (lost=$lost)',
      () async {
        final replay = _Replay([
          ..._lnt(lost: lost),
          if (!lost) ..._noTuLocalPrefix(),
        ]);
        final bank = _BankProbe();
        final result = (await LocalCardReader(
          replay.call,
          bankProbe: bank,
        ).read())!;
        expect(result.parsedCard!.parserId, CardParserIds.lingnanTong);
        expect(result.parsedCard!.info.applicationSerial, '9534635882');
        expect(result.parsedCard!.info.balanceFen, 3840);
        expect(result.parsedCard!.localCard, same(result.readResult));
        _expectLnt(result.readResult!);
        expect(
          result.readResult!.transportFailure,
          lost ? same(_tagLost) : isNull,
        );
        expect(bank.calls, 0);
        replay.verify();
      },
    );
  }

  test(
    'archive uses the same stable TU fingerprint regardless of LNT outcome',
    () async {
      final service = CardIdentificationService(KnowledgeBase.empty());
      final baselineReplay = _Replay(_tu());
      final baseline = (await ShanghaiTransitUnionCardParser(
        baselineReplay.call,
      ).read()).tu.card!;
      final baselineIdentity = service.identify(baseline)!;
      baselineReplay.verify();
      final fingerprints = <String>[];
      for (final suffix in [_rejectAppy(), _lnt()]) {
        final replay = _Replay([...suffix, ..._tu()]);
        final card = (await LocalCardReader(replay.call).read())!.parsedCard!;
        expect(
          service.identify(card)!.fingerprint,
          baselineIdentity.fingerprint,
        );
        final identified = service.identify(card)!;
        expect(identified.identity.cardType, CardTypes.lingnanTunion);
        expect(identified.cardNumber, '310487039534635882');
        fingerprints.add(identified.fingerprint);
        replay.verify();
      }
      expect(fingerprints.toSet(), {
        'tunion:0200290012345678:310487039534635882',
      });
    },
  );
}
