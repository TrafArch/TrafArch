import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/card_identification_service.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_types.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/scan/application/local_card_reader.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/local/apdu_exchange.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';
import 'package:transit_card_analyzer/protocols/transit/multiapp/application_evidence.dart';
import 'package:transit_card_analyzer/protocols/transport/transport_failure.dart';

// Reuse the real attachment bytes, not the permissive transport in that test.
import 'lingnan_tong_test.dart' show realInfo, realFares;

const _mf = '00A40000023F0000';
const _tuSelect = '00A4040008A00000063201010500';
const _tuCashSelect = '00A4040008A00000063201010600';
const _cuSelect = '00A4040009A0000000038698070100';
const _appy = '00A40400085041592E4150505900';
const _ticl = '00A40400085041592E5449434C00';
List<_Step> _rejectAppy() => [
  _Step.reject(_appy),
  _Step.reject(_appy.substring(0, _appy.length - 2)),
  _Step.reject(_ticl),
  _Step.reject(_ticl.substring(0, _ticl.length - 2)),
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
  _Step.reject('00B202C400'),
  ..._rejectCu(),
  _Step(_mf),
  _Step(_tuSelect),
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

List<_Step> _remainingWallets() => [
  _Step.reject(_tuCashSelect),
  _Step.reject('00A404000AB0C4C3C5CDA8C7AEB0FC00'),
  _Step.reject('00A40400075041592E535A54'),
  _Step.reject('00A40000023F00'), // Wuhan MF
  _Step.reject('00A40400094150312E5748435443'), // AP1.WHCTC by name
  _Step.reject('00A40000023F00'), // Beijing MF
  _Step.reject('00A40000021001'), // DF 1001
  _Step.reject('00A404001091560000144D4F542E424D4143303031'), // MOT.BMAC001
  _Step.reject('00A404000B535558494E2E4444463031'),
  _Step.reject('00A4040008535A504B5F5A5959'),
  _Step.reject('00A404000DD156000015B9ABB9B2D3A6D3C3'),
];

List<_Step> _noTuLocalPrefix() => [
  _Step(_mf),
  _Step.reject(_tuSelect),
  _Step.reject('80A4040008A00000063201010500'),
  ..._rejectCu(),
  ..._remainingWallets(),
];

List<ApduRecord> _trips(ReadResult result) =>
    result.records.where((r) => r.type == 2).toList();

void _expectTu(LocalReadOutcome outcome, String serial) {
  final card = outcome.parsedCard;
  expect(card.info.applicationSerial, serial);
  expect(card.info.issuerId, '0200290012345678');
  expect(card.info.balanceFen, 10000);
  expect(card.selectedAidHex, 'A000000632010105');
  expect(card.transactionFileObserved, isTrue);
  expect(card.transactions.single.rawHex, _tuFare);
  expect(
    outcome.readResult.info.cardNumber,
    serial.replaceFirst(RegExp(r'^0+'), ''),
  );
  expect(outcome.readResult.info.observedBalance, 10000);
  expect(_trips(outcome.readResult).single.balanceDelta, -200);
  expect(
    outcome.applications.singleWhere((a) => a.appId == 'tu').confirmed,
    isTrue,
  );
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
  test('TICL-only purse has a balance and no APPY identity', () async {
    final replay = _Replay([
      ..._rejectAppy().take(2),
      _Step(_ticl),
      _Step.reject('00B2014416'),
      _Step('805C000204', '0000012C'),
      _Step.lost('00B201C417'),
    ]);
    final scan = await LocalCardReader(replay.call).scan();
    final wallet = scan.applications.singleWhere((a) => a.appId == 'lingnan');
    expect(wallet.balanceFen, 300);
    expect(wallet.cardNumber, isNull);
    expect(wallet.state, ApplicationProbeState.partial);
    expect(
      scan.applications.singleWhere((a) => a.appId == 'lingnan_appy').state,
      ApplicationProbeState.selectRejected,
    );
    expect(scan.result!.parsedCard.info.applicationSerial, isNull);
    expect(scan.result!.parsedCard.info.balanceFen, 300);
    replay.verify();
  });

  test(
    'loss selecting TICL preserves only the confirmed APPY identity',
    () async {
      final replay = _Replay([..._lnt().take(3), _Step.lost(_ticl)]);
      final scan = await LocalCardReader(replay.call).scan();
      final appy = scan.applications.singleWhere(
        (a) => a.appId == 'lingnan_appy',
      );
      final ticl = scan.applications.singleWhere((a) => a.appId == 'lingnan');
      expect(appy.state, ApplicationProbeState.readSucceeded);
      expect(appy.cardNumber, '9534635882');
      expect(appy.balanceFen, isNull);
      expect(ticl.state, ApplicationProbeState.failed);
      expect(ticl.confirmed, isFalse);
      expect(scan.result!.parsedCard.info.applicationSerial, '9534635882');
      expect(scan.result!.parsedCard.info.balanceFen, isNull);
      replay.verify();
    },
  );

  test(
    'Shenzhen TU summary uses PAY.SZT even when both Lingnan directories exist',
    () async {
      final suffix = _remainingWallets();
      final sztIndex = suffix.indexWhere(
        (s) => s.command == '00A40400075041592E535A54',
      );
      final replay = _Replay([
        ..._lnt(),
        ..._tu(serial: '00310487049534635882'),
        ...suffix.take(sztIndex),
        _Step('00A40400075041592E535A54'),
        _Step.reject('00B0950020'),
        _Step('805C000204', '0000000A'),
        _Step.lost('00B201C400'),
      ]);
      final result = (await LocalCardReader(replay.call).scan()).result!;
      expect(result.parsedCard.parserId, CardParserIds.shenzhenTunion);
      expect(result.parsedCard.localCard!.info.isSZT, isTrue);
      expect(result.parsedCard.localCard!.info.observedBalance, 10);
      expect(
        result.applications.singleWhere((a) => a.appId == 'lingnan').balanceFen,
        3840,
      );
      replay.verify();
    },
  );

  test('stateful card locks APPY/TICL after MF or TU selection; early LNT survives', () async {
    final replay = _Replay([..._lnt(), ..._tu(), ..._remainingWallets()]);
    var locked = false;
    Future<List<int>> call(List<int> command) async {
      final hex = _hex(command);
      if (hex == _mf || hex == _tuSelect) {
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
    _expectLnt(result.parsedCard.localCard!);
    _expectTu(result, _serial);
    replay.verify();
    // The same state rejects the former post-TU SELECT order.
    expect(await call(_bytes(_appy)), _bytes('6A82'));
    expect(await call(_bytes(_ticl)), _bytes('6A82'));
  });

  test(
    'Case 4 APPY status rejection permits exactly one Case 3 fallback',
    () async {
      final replay = _Replay([
        _Step.reject(_appy),
        _Step(_appy.substring(0, _appy.length - 2)),
        ..._lnt().skip(1),
        ..._tu(),
        ..._remainingWallets(),
      ]);
      final result = (await LocalCardReader(replay.call).read())!;
      _expectLnt(result.parsedCard.localCard!);
      final evidence =
          result.parsedCard.localCard!.extras.slots['lnt.appySelect'] as List;
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
      ..._remainingWallets(),
    ]);
    final result = (await LocalCardReader(replay.call).read())!;
    _expectLnt(result.parsedCard.localCard!);
    expect(
      result.parsedCard.localCard!.extras.slots['lnt.ticlConfirmed'],
      isTrue,
    );
    replay.verify();
  });

  for (final serial in ['00310000000000000001', '00310477000000000001']) {
    test(
      'confirmed LNT with non-target TU $serial never mixes Shanghai/CU',
      () async {
        final replay = _Replay([
          ..._lnt(),
          ..._tu(serial: serial),
          ..._remainingWallets(),
        ]);
        final result = (await LocalCardReader(replay.call).read())!;
        expect(result.parsedCard.parserId, CardParserIds.tunion);
        _expectTu(result, serial);
        _expectLnt(result.parsedCard.localCard!);
        expect(
          result.applications.where((a) => a.confirmed).map((a) => a.appId),
          ['lingnan_appy', 'lingnan', 'tu'],
        );
        replay.verify();
      },
    );
  }

  for (final prefix in ['31048703', '31048709', '31048710', '31048724']) {
    test(
      'confirmed TU $prefix probes APP Y once and isolates both applications',
      () async {
        final serial = '00${prefix}9534635882';
        final replay = _Replay([
          ..._lnt(),
          ..._tu(serial: serial),
          ..._remainingWallets(),
        ]);
        final result = (await LocalCardReader(replay.call).read())!;
        expect(result.parsedCard.parserId, CardParserIds.lingnanTunion);
        _expectTu(result, serial);
        final local = result.parsedCard.localCard!;
        _expectLnt(local);
        expect(local.extras.slots['lnt.appyConfirmed'], isTrue);
        expect(result.readResult.readError, isNull);
        expect(local.readError, isNull);
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
      'ordinary TU $serial rejects early APPY then probes CU/Macau and reuses TU',
      () async {
        final replay = _Replay([
          ..._rejectAppy(),
          ..._tu(serial: serial),
          ..._remainingWallets(),
        ]);
        final result = (await LocalCardReader(replay.call).read())!;
        expect(result.parsedCard.parserId, CardParserIds.tunion);
        expect(result.parsedCard.localCard, isNull);
        _expectTu(result, serial);
        ApplicationEvidence ev(String id) =>
            result.applications.firstWhere((a) => a.appId == id);
        expect(ev('cu').state, ApplicationProbeState.selectRejected);
        expect(ev('macau').state, ApplicationProbeState.selectRejected);
        replay.verify();
      },
    );
  }

  test('Shanghai TU uses the same physical sequence as ordinary TU', () async {
    final replay = _Replay([
      ..._rejectAppy(),
      ..._tu(serial: '00310477000000000001'),
      ..._remainingWallets(),
    ]);
    final result = (await LocalCardReader(replay.call).read())!;
    expect(result.parsedCard.parserId, CardParserIds.tunion);
    expect(
      result.applications.singleWhere((a) => a.appId == 'tu').confirmed,
      isTrue,
    );
    expect(result.parsedCard.localCard, isNull);
    expect(replay.commands.where((c) => c == _appy), hasLength(1));
    replay.verify();
  });

  for (final transportError in [false, true]) {
    test(
      'APPY rejection leaves TU as the confirmed application (transport=$transportError)',
      () async {
        final replay = _Replay([
          if (transportError) _Step.lost(_appy) else ..._rejectAppy(),
          if (!transportError) ...[..._tu(), ..._remainingWallets()],
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
        expect(result.parsedCard.parserId, CardParserIds.tunion);
        expect(result.parsedCard.localCard, isNull);
        expect(
          result.applications.where((a) => a.appId == 'tu').single.confirmed,
          isTrue,
        );
        expect(
          result.readResult.transportFailure,
          transportError ? same(_tagLost) : isNull,
        );
        replay.verify();
      },
    );
  }

  test(
    'late LNT terminal failure preserves both sides with zero subsequent I/O',
    () async {
      final replay = _Replay([
        ..._lnt(),
        ..._tu().takeWhile((step) => step.command != '00B201D400'),
        _Step.lost('00B201D400'),
      ]);
      final result = (await LocalCardReader(replay.call).read())!;
      _expectTu(result, _serial);
      final local = result.parsedCard.localCard!;
      _expectLnt(local);
      expect(local.transportFailure, isNull);
      expect(local.readError, isNull);
      expect(result.readResult.transportFailure, same(_tagLost));
      expect(result.readResult.readError, isA<ApduTransportException>());
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
        final result = (await LocalCardReader(replay.call).read())!;
        expect(result.parsedCard.parserId, CardParserIds.lingnanTong);
        expect(result.parsedCard.info.applicationSerial, '9534635882');
        expect(result.parsedCard.info.balanceFen, 3840);
        expect(result.parsedCard.localCard, same(result.readResult));
        _expectLnt(result.readResult);
        expect(
          result.readResult.transportFailure,
          lost ? same(_tagLost) : isNull,
        );
        replay.verify();
      },
    );
  }

  test(
    'archive uses the same stable TU fingerprint regardless of LNT outcome',
    () async {
      final service = CardIdentificationService(KnowledgeBase.empty());
      final fingerprints = <String>[];
      for (final appyConfirmed in [false, true]) {
        final suffix = appyConfirmed ? _lnt() : _rejectAppy();
        final replay = _Replay([...suffix, ..._tu(), ..._remainingWallets()]);
        final card = (await LocalCardReader(replay.call).read())!.parsedCard;
        final identified = service.identify(card)!;
        expect(
          identified.identity.cardType,
          appyConfirmed ? CardTypes.lingnanTunion : CardTypes.chinaTunion,
        );
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
