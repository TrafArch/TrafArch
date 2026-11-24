import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/scan/application/local_card_reader.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/multiapp/application_evidence.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_cash_log.dart';
import 'package:transit_card_analyzer/protocols/transport/transport_failure.dart';

// 一芯多应用卡只读取交通应用，APDU 由离线夹具重放。
void main() {
  test(
    'Unrelated DF echoed by a successful local SELECT cannot claim that wallet',
    () async {
      final link = _ChipLink(tuPresent: false);
      final scan = await LocalCardReader((cmd) async {
        if (cmd.length > 5 && cmd[1] == 0xA4 && cmd[2] == 4) {
          return _bytes('6F0584035455559000');
        }
        return link.call(cmd);
      }).scan();
      expect(scan.result, isNull);
      expect(scan.applications.where((a) => a.confirmed), isEmpty);
      expect(scan.applications.last.probed, isTrue);
    },
  );

  test('TU and CU do not consume the third transport wallet', () async {
    final link = _ChipLink(cuPresent: true, macauPresent: true);
    final result = (await LocalCardReader(link.call).read())!;
    final confirmed = result.applications.where((a) => a.confirmed);
    expect(confirmed.map((a) => a.appId), containsAll(['tu', 'cu', 'macau']));
    expect(confirmed.singleWhere((a) => a.appId == 'cu').balanceFen, 500);
    expect(confirmed.singleWhere((a) => a.appId == 'macau').balanceFen, 165);
    expect(result.parsedCard.info.balanceFen, 10000);
    _expectNoBankCommands(link);
  });

  test('Every registered transit application is physically selected when all reject', () async {
    final names = <String>{};
    final scan = await LocalCardReader((command) async {
      if (command.length >= 5 && command[1] == 0xA4 && command[4] > 0) {
        names.add(_hex(command.sublist(5, 5 + command[4])));
      }
      return [0x6A, 0x82];
    }).scan();
    expect(names, {
      '3F00',
      '5041592E41505059',
      '5041592E5449434C',
      'A000000632010105',
      'A00000000386980701',
      'A000000632010106',
      'B0C4C3C5CDA8C7AEB0FC',
      '5041592E535A54',
      '4150312E5748435443',
      '1001',
      '91560000144D4F542E424D4143303031',
      '535558494E2E4444463031',
      '535A504B5F5A5959',
      'D156000015B9ABB9B2D3A6D3C3',
    });
    expect(scan.result, isNull);
    expect(scan.applications.every((a) => a.probed && !a.confirmed), isTrue);
  });

  test('Only the bank app is available: transit detection never selects it or its directories', () async {
    final link = _ChipLink(tuPresent: false, bankInPse: true);

    expect(await LocalCardReader(link.call).read(), isNull);
    _expectNoBankCommands(link);
  });

  test(
    'An independently confirmed cash log survives a missing TU wallet',
    () async {
      final link = _ChipLink(tuPresent: false, cashPresent: true);
      final result = (await LocalCardReader(link.call).read())!;
      expect(result.parsedCard.parserId, CardParserIds.tunionCash);
      expect(result.parsedCard.info.balanceFen, isNull);
      expect(result.parsedCard.info.applicationSerial, isNull);
      expect(
        result.applications.where((a) => a.confirmed).map((a) => a.appId),
        ['tuCash'],
      );
      expect(
        result.applications.singleWhere((a) => a.appId == 'tuCash').recordCount,
        1,
      );
      _expectNoBankCommands(link);
    },
  );

  test(
    'Truncated first response stops the session and preserves probe states',
    () async {
      var calls = 0;
      final scan = await LocalCardReader((_) async {
        calls++;
        return [0x90];
      }).scan();
      expect(calls, 1);
      expect(scan.result, isNull);
      expect(scan.terminalError, isNotNull);
      expect(
        scan.applications.first.transportFailure?.kind,
        TransportFailureKind.malformedFrame,
      );
      expect(scan.applications.skip(1).every((a) => !a.probed), isTrue);
    },
  );

  test('TU reads the known transit cash log AID directly', () async {
    final link = _ChipLink(cashPresent: true);
    final outcome = (await LocalCardReader(link.call).read())!;

    expect(outcome.parsedCard.transactions.single.amountFen, 200);
    final cash = outcome.applications.singleWhere(
      (app) => app.appId == 'tuCash',
    );
    expect(cash.confirmed, isTrue);
    expect(cash.recordCount, 1);
    final restored = ApplicationEvidence.tryParse(cash.toJson())!;
    final record = (restored.payload as TUnionCashLog).records.single;
    expect(record.amountFen, 180);
    expect(record.time, DateTime(2026, 11, 14, 20, 38, 1));
    expect(
      cash.toJson()['payload']['records'].single,
      containsPair('amountFen', 180),
    );
    expect(
      link.commands,
      containsAllInOrder([_cashSelect, _cashFormat, _cashRecord]),
    );
    _expectNoBankCommands(link);
    expect(link.commands.where((c) => c == _cashSelect), hasLength(1));
  });

  test(
    'Incomplete TU cash log format keeps raw records and the TU wallet',
    () async {
      final link = _ChipLink(
        cashPresent: true,
        cashFormat: '9F4F039F0206',
        cashFci: '6F118408A000000632010106A5059F4D020B01',
      );
      final outcome = (await LocalCardReader(link.call).read())!;
      expect(outcome.parsedCard.transactions, hasLength(1));
      final cash = outcome.applications.singleWhere(
        (app) => app.appId == 'tuCash',
      );
      final records = cash.toJson()['payload']['records'] as List;
      expect(records.single['rawHex'], isNotEmpty);
      expect(records.single['amountFen'], isNull);
      expect(records.single['time'], isNull);
      expect(link.pseSelects, 0);
    },
  );

  test('TU with a bank application still reads the transit cash log', () async {
    final link = _ChipLink(cashPresent: true, bankInPse: true);
    final result = (await LocalCardReader(link.call).read())!;

    expect(result.parsedCard.parserId, CardParserIds.tunion);
    expect(result.applications.any((app) => app.appId == 'bank'), isFalse);
    expect(
      result.applications.singleWhere((app) => app.appId == 'tuCash').confirmed,
      isTrue,
    );
    expect(
      link.commands,
      containsAllInOrder([_cashSelect, _cashFormat, _cashRecord]),
    );
    _expectNoBankCommands(link);
  });

  test(
    'Terminal loss during TU cash read preserves its prefix and stops I/O',
    () async {
      final link = _ChipLink(
        cashPresent: true,
        bankInPse: true,
        cashFci: '6F148408A000000632010106A508BF0C059F4D020B02',
        interruptCash: true,
      );
      final result = (await LocalCardReader(link.call).read())!;
      final cash = result.applications.singleWhere((a) => a.appId == 'tuCash');
      expect(cash.state, ApplicationProbeState.partial);
      expect(cash.transportFailure?.kind, TransportFailureKind.tagLost);
      expect((cash.payload as TUnionCashLog).records.single.amountFen, 180);
      expect(result.parsedCard.transactions, hasLength(1));
      expect(link.commands.last, _secondCashRecord);
      _expectNoBankCommands(link);
    },
  );

  test('普通 TU + CU：合并双应用卡并保留逐应用证据', () async {
    final link = _ChipLink(cuPresent: true);
    final result = (await LocalCardReader(link.call).read())!;

    final card = result.parsedCard;
    expect(card.parserId, CardParserIds.tunion);
    expect(card.dualApplication, isTrue);
    expect(card.info.balanceFen, 10000);
    expect(card.cityUnionBalanceFen, 500);
    expect(card.cityUnionFiles, isNotEmpty);
    expect(result.readResult.info.isTU, isTrue);
    expect(result.readResult.info.isCU, isTrue);

    ApplicationEvidence app(String id) =>
        result.applications.firstWhere((a) => a.appId == id);
    expect(app('tu').state, ApplicationProbeState.readSucceeded);
    expect(app('tu').balanceFen, 10000);
    expect(app('lingnan').state, ApplicationProbeState.selectRejected);
    expect(app('cu').confirmed, isTrue);
    expect(app('cu').state, ApplicationProbeState.readSucceeded);
    expect(app('cu').balanceFen, 500);
    expect(app('macau').state, ApplicationProbeState.selectRejected);
    expect(link.macauSelects, 1);
    _expectNoBankCommands(link);
    expect(
      link.commands,
      containsAllInOrder([
        '00A4040008A00000063201010500',
        '00A4040009A0000000038698070100',
        '00A4040008A00000063201010500',
        _cashSelect,
        _ChipLink._macauSelect,
      ]),
    );
  });

  test('澳门通 + TU：TU 保持主卡，澳门通钱包证据独立保留', () async {
    final link = _ChipLink(macauPresent: true);
    final result = (await LocalCardReader(link.call).read())!;

    final card = result.parsedCard;
    expect(card.parserId, CardParserIds.tunion);
    expect(card.dualApplication, isFalse, reason: '澳门通不冒充 CU 双应用');
    expect(card.localCard, isNull);

    ApplicationEvidence app(String id) =>
        result.applications.firstWhere((a) => a.appId == id);
    expect(app('tu').confirmed, isTrue);
    expect(app('cu').state, ApplicationProbeState.selectRejected);
    final macau = app('macau');
    expect(macau.state, ApplicationProbeState.readSucceeded);
    expect(macau.confirmed, isTrue);
    expect(macau.balanceFen, 165);
    expect(macau.recordCount, 1);
    expect(link.macauSelects, 1);
  });

  test('CU with a bank application only reads CU', () async {
    final link = _ChipLink(tuPresent: false, cuPresent: true, bankInPse: true);
    final result = (await LocalCardReader(link.call).read())!;

    expect(result.parsedCard.parserId, CardParserIds.cityUnion);
    expect(result.parsedCard.cityUnionFiles, isNotEmpty);
    expect(
      result.applications.singleWhere((app) => app.appId == 'cu').confirmed,
      isTrue,
    );
    expect(result.applications.any((app) => app.appId == 'bank'), isFalse);
    _expectNoBankCommands(link);
  });

  test('TU cash reads no log data from a mismatched AID or SFI', () async {
    for (final cashFci in [
      '6F148408A000000333010101A508BF0C059F4D020B01',
      '6F148408A000000632010106A508BF0C059F4D020C01',
    ]) {
      final link = _ChipLink(cashPresent: true, cashFci: cashFci);
      final result = (await LocalCardReader(link.call).read())!;

      expect(result.parsedCard.transactions, hasLength(1));
      expect(link.commands, contains(_cashSelect));
      expect(link.commands, isNot(contains(_cashFormat)));
      expect(link.commands, isNot(contains(_cashRecord)));
    }
  });
}

void _expectNoBankCommands(_ChipLink link) {
  expect(link.pseSelects, 0);
  expect(link.ppseSelects, 0);
  expect(link.commands, isNot(contains(_unionPaySelect)));
}

class _ChipLink {
  _ChipLink({
    this.tuPresent = true,
    this.cuPresent = false,
    this.macauPresent = false,
    this.cashPresent = false,
    this.cashFormat = '9F4F0D9A039F21039F02065F2A029C01',
    this.cashFci = '6F148408A000000632010106A508BF0C059F4D020B01',
    this.bankInPse = false,
    this.interruptCash = false,
  });

  final bool tuPresent;
  final bool cuPresent;
  final bool macauPresent;
  final bool cashPresent;
  final String cashFormat;
  final String cashFci;
  final bool bankInPse;
  final bool interruptCash;

  String? selected;
  int cuSelects = 0;
  int ppseSelects = 0;
  int pseSelects = 0;
  int macauSelects = 0;
  final commands = <String>[];

  static const _mf = '00A40000023F0000';
  static const _tuAid = 'A000000632010105';
  static const _cuAid = 'A00000000386980701';
  static const _macauSelect = '00A404000AB0C4C3C5CDA8C7AEB0FC00';
  static const _ppse = '00A404000E325041592E5359532E444446303100';
  static const _pse = '00A404000E315041592E5359532E444446303100';
  static const _serial = '03100000000000000001';

  Future<List<int>> call(List<int> apdu) async {
    final hex = _hex(apdu);
    commands.add(hex);
    if (hex == _mf) {
      selected = null;
      return _ok('');
    }
    if (hex.contains(_tuAid)) {
      if (!tuPresent) return [0x6A, 0x82];
      selected = 'tu';
      return _ok('');
    }
    if (hex.contains(_cuAid)) {
      cuSelects++;
      if (!cuPresent) return [0x6A, 0x82];
      selected = 'cu';
      return _ok('');
    }
    if (hex == _ppse) {
      ppseSelects++;
      return [0x6A, 0x82];
    }
    if (hex == _pse) {
      pseSelects++;
      if (bankInPse) {
        selected = 'pse';
        return _ok('6F05A503880101');
      }
      return [0x6A, 0x82];
    }
    if (bankInPse && hex == _unionPaySelect) {
      selected = 'bank';
      return _ok('6F0A8408A000000333010101');
    }
    if (selected == 'pse' && hex == '00B2010C00') {
      return _ok('700C610A4F08A000000333010101');
    }
    if (selected == 'pse' && hex == '00B2020C00') return [0x6A, 0x83];
    if (hex == _macauSelect) {
      macauSelects++;
      if (!macauPresent) return [0x6A, 0x82];
      selected = 'macau';
      return _ok(_hex(MacauPassFci.walletNameFci));
    }
    if (cashPresent && hex == _cashSelect) {
      selected = 'tuCash';
      return _ok(cashFci);
    }
    if (selected == 'tuCash') {
      if (hex == _cashFormat) return _ok(cashFormat);
      if (hex == _cashRecord) return _ok('261114203801000000000180015600');
      if (hex == _secondCashRecord && interruptCash) {
        throw const TransportFailure(
          kind: TransportFailureKind.tagLost,
          message: 'fixture lost tag',
        );
      }
    }
    if (selected == 'tu') {
      if (hex == '00B0950000') {
        return _ok('02002900123456780101${_serial}2024010120291231AABB');
      }
      if (hex == '00B0960000') {
        return _ok(_hex(List<int>.filled(55, 0)..[0] = 1));
      }
      if (hex == '00B0970000') {
        return _ok(_hex(List<int>.filled(60, 0)..[6] = 0x31));
      }
      if (apdu[1] == 0x5C) return _ok('00002710');
      if (hex == '00B201C500') return _ok(_tuFare);
      return [0x6A, 0x82];
    }
    if (selected == 'cu') {
      if (hex == '00B095001E') {
        return _ok('86223000${'00' * 26}');
      }
      if (apdu[1] == 0x5C) return _ok('000001F4');
      return [0x6A, 0x83];
    }
    if (selected == 'macau') {
      if (apdu[1] == 0x5C) return _ok('000000A5');
      if (hex == '00B201C400') return _ok(_macauRecord);
      return [0x6A, 0x83];
    }
    return [0x6A, 0x82];
  }

  static List<int> _ok(String hex) => [..._bytes(hex), 0x90, 0x00];
}

/// 澳门通 FCI：只保留可让 [MacauPassCard.select] 认领的钱包名标签。
abstract final class MacauPassFci {
  static final List<int> walletNameFci = [
    0x6F,
    0x0C,
    0x84,
    0x0A,
    ...walletName,
  ];

  static const List<int> walletName = [
    0xB0,
    0xC4,
    0xC3,
    0xC5,
    0xCD,
    0xA8,
    0xC7,
    0xAE,
    0xB0,
    0xFC,
  ];
}

const _tuFare = '0001000000000000C80612345678901220240501083000';
const _cashSelect = '00A4040008A00000063201010600';
const _cashFormat = '80CA9F4F00';
const _cashRecord = '00B2015C00';
const _secondCashRecord = '00B2025C00';
const _unionPaySelect = '00A4040008A00000033301010100';

const _macauRecord = '00170000000000012C0900123456789020261031123456';

List<int> _bytes(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
