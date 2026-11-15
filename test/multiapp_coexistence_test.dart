import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/scan/application/bank_card_probe.dart';
import 'package:transit_card_analyzer/features/scan/application/local_card_reader.dart';
import 'package:transit_card_analyzer/protocols/bank/domain/models/card_application.dart';
import 'package:transit_card_analyzer/protocols/bank/domain/models/bank_card_result.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/local/apdu_exchange.dart';
import 'package:transit_card_analyzer/protocols/transit/multiapp/application_evidence.dart';

// 一芯多应用默认目录探测：普通 TU+CU、澳门通+TU、TU+PBOC、CU+PBOC。
// 只有物理 APDU 传输被替换，解析结果全部来自真实读取路径。
void main() {
  test('普通 TU + CU：合并双应用卡并保留逐应用证据', () async {
    final link = _ChipLink(cuPresent: true);
    final bank = _BankProbe(null);
    final result = (await LocalCardReader(
      link.call,
      bankProbe: bank,
    ).read())!;

    final card = result.parsedCard!;
    expect(card.parserId, CardParserIds.tunion);
    expect(card.dualApplication, isTrue);
    expect(card.info.balanceFen, 10000);
    expect(card.cityUnionBalanceFen, 500);
    expect(card.cityUnionFiles, isNotEmpty);
    expect(result.readResult!.info.isTU, isTrue);
    expect(result.readResult!.info.isCU, isTrue);

    ApplicationEvidence app(String id) =>
        result.applications.firstWhere((a) => a.appId == id);
    expect(app('tu').state, ApplicationProbeState.readSucceeded);
    expect(app('tu').balanceFen, 10000);
    expect(app('lingnan').state, ApplicationProbeState.selectRejected);
    expect(app('cu').confirmed, isTrue);
    expect(app('cu').state, ApplicationProbeState.readSucceeded);
    expect(app('cu').balanceFen, 500);
    expect(
      result.applications.where((a) => a.appId == 'macau'),
      isEmpty,
      reason: 'CU 已确认的卡不再重复探测澳门通钱包',
    );
    expect(app('bank').state, ApplicationProbeState.selectRejected);
    expect(bank.calls, 0, reason: '支付目录未披露银行应用时不探测内置候选');
    expect(link.ppseSelects, 1);
    expect(
      link.commands.where((c) => c == '00A40000023F0000').length,
      1,
      reason: 'TU 已确认后的快速 CU 探测不再重置 MF',
    );
  });

  test('澳门通 + TU：TU 保持主卡，澳门通钱包证据独立保留', () async {
    final link = _ChipLink(macauPresent: true);
    final result = (await LocalCardReader(link.call).read())!;

    final card = result.parsedCard!;
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
    expect(
      link.commands.where((c) => c == '00A40000023F0000').length,
      1,
    );
  });

  test('TU + PBOC：交通主卡在同一会话内探测银行应用', () async {
    final link = _ChipLink(ppsePresent: true);
    final bank = _BankProbe(
      BankCardResult(
        protocolFamily: BankCardProtocolFamily.pboc,
        analyzedAt: DateTime(2026, 11, 14),
        parserVersion: '0.3.2',
        status: BankCardStatus.partial,
        discoveredApplications: const [
          CardApplication(aidHex: 'A000000333010101', selected: true),
        ],
      ),
    );
    final result = (await LocalCardReader(
      link.call,
      bankProbe: bank,
    ).read())!;

    final card = result.parsedCard!;
    expect(card.parserId, CardParserIds.tunion);
    expect(card.dualApplication, isFalse);
    final bankEvidence = result.applications.firstWhere(
      (a) => a.appId == 'bank',
    );
    expect(bank.calls, 1);
    expect(bankEvidence.confirmed, isTrue);
    expect(bankEvidence.state, ApplicationProbeState.readSucceeded);
    expect(bankEvidence.payload, isA<BankCardResult>());
    expect(link.ppseSelects, 1);
  });

  test('CU + PBOC：普通 CU 主卡后可继续探测银行应用', () async {
    final link = _ChipLink(
      tuPresent: false,
      cuPresent: true,
      ppsePresent: true,
    );
    final bank = _BankProbe(
      BankCardResult(
        protocolFamily: BankCardProtocolFamily.pboc,
        analyzedAt: DateTime(2026, 11, 14),
        parserVersion: '0.3.2',
        status: BankCardStatus.partial,
        discoveredApplications: const [
          CardApplication(aidHex: 'A000000333010101', selected: true),
        ],
      ),
    );
    final result = (await LocalCardReader(
      link.call,
      bankProbe: bank,
    ).read())!;

    expect(result.parsedCard!.parserId, CardParserIds.cityUnion);
    expect(result.parsedCard!.cityUnionFiles, isNotEmpty);
    final cu = result.applications.firstWhere((a) => a.appId == 'cu');
    expect(cu.confirmed, isTrue);
    final bankEvidence = result.applications.firstWhere(
      (a) => a.appId == 'bank',
    );
    expect(bank.calls, 1);
    expect(bankEvidence.confirmed, isTrue);
  });

}

class _ChipLink {
  _ChipLink({
    this.tuPresent = true,
    this.cuPresent = false,
    this.macauPresent = false,
    this.ppsePresent = false,
  });

  final bool tuPresent;
  final bool cuPresent;
  final bool macauPresent;
  final bool ppsePresent;

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
      return ppsePresent ? _ok('') : [0x6A, 0x82];
    }
    if (hex == _pse) {
      pseSelects++;
      return ppsePresent ? _ok('') : [0x6A, 0x82];
    }
    if (hex == _macauSelect) {
      macauSelects++;
      if (!macauPresent) return [0x6A, 0x82];
      selected = 'macau';
      return _ok(_hex(MacauPassFci.walletNameFci));
    }
    if (selected == 'tu') {
      if (hex == '00B0950000') {
        return _ok(
          '02002900123456780101${_serial}2024010120291231AABB',
        );
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

const _macauRecord =
    '00170000000000012C0900123456789020261031123456';

class _BankProbe implements BankCardProbe {
  _BankProbe(this.result);
  final BankCardResult? result;
  int calls = 0;

  @override
  Future<BankCardResult?> probe(LocalTransceive transceive) async {
    calls++;
    return result;
  }
}

List<int> _bytes(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

String _hex(List<int> bytes) => bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join()
    .toUpperCase();
