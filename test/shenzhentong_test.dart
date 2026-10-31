import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/card_identification_service.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_types.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/scan/application/bank_card_probe.dart';
import 'package:transit_card_analyzer/features/scan/application/local_card_reader.dart';
import 'package:transit_card_analyzer/protocols/bank/domain/models/bank_card_result.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/local/apdu_exchange.dart';
import 'package:transit_card_analyzer/protocols/transit/local/cards/shenzhentong.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';
import 'package:transit_card_analyzer/protocols/transport/transport_failure.dart';

void main() {
  test('深圳 TU 身份门控要求已确认应用和精确数字前缀', () {
    for (final serial in ['03104870400000000001', '00310487040000000001']) {
      expect(
        Shenzhentong.matchesTuIdentity(confirmed: true, cardNumber: serial),
        isTrue,
      );
      expect(
        Shenzhentong.matchesTuIdentity(confirmed: false, cardNumber: serial),
        isFalse,
      );
    }
    for (final serial in [null, '', '31048703', '31048704ABC', '02215840']) {
      expect(
        Shenzhentong.matchesTuIdentity(confirmed: true, cardNumber: serial),
        isFalse,
      );
    }
  });

  for (final serial in ['03104870400000000001', '03100000000000000001']) {
    test('TU 精确号段触发地方应用 serial=$serial', () async {
      final link = _TuLink(serial: serial);
      final bank = _BankProbe();
      final outcome = (await LocalCardReader(
        link.call,
        bankProbe: bank,
      ).read())!;
      final isShenzhen = serial.startsWith('031048704');
      final card = outcome.parsedCard!;
      expect(
        card.parserId,
        isShenzhen ? CardParserIds.shenzhenTunion : CardParserIds.tunion,
      );
      expect(CardParserIds.isTUnionFamily(card.parserId), isTrue);
      expect(link.sztSelects, isShenzhen ? 1 : 0);
      expect(link.cuSelects, 0);
      expect(link.tuReads, 1);
      expect(bank.calls, 0);
      expect(card.info.balanceFen, 500);
      if (isShenzhen) {
        final service = CardIdentificationService(KnowledgeBase.empty());
        final identified = service.identify(card)!;
        final ordinary = service.identify(
          ParsedCard(
            parserId: CardParserIds.tunion,
            parserName: '交通联合',
            info: card.info,
            transactions: card.transactions,
          ),
        )!;
        expect(identified.identity.cardType, CardTypes.shenzhenTunion);
        expect(identified.fingerprint, ordinary.fingerprint);
        expect(card.localCard!.info.observedBalance, 12345);
        expect(card.localCard!.info.cardNumber, '4045620583');
        expect(card.localCard!.trips, hasLength(2));
        expect(outcome.readResult!.info.cardNumber, isNot('4045620583'));
        expect(outcome.readResult!.trips, isEmpty);
        expect(card.localCard!.extras.slots['szt.confirmed'], isTrue);
        expect(card.dualApplication, isFalse, reason: '该字段专指 TU+CU，不冒充 CU');
      }
    });
  }

  for (final failSelect in [false, true]) {
    test('TU 余额拒绝仍触发 PAY.SZT，地方选择失败保留 TU failSelect=$failSelect', () async {
      final link = _TuLink(rejectTuBalance: true, failSztSelect: failSelect);
      final outcome = (await LocalCardReader(link.call).read())!;
      expect(outcome.parsedCard!.parserId, CardParserIds.shenzhenTunion);
      expect(outcome.parsedCard!.info.balanceFen, isNull);
      expect(link.sztSelects, 1);
      final local = outcome.parsedCard!.localCard!;
      expect(local.info.isSZT, !failSelect);
      expect(local.extras.slots['szt.confirmed'], !failSelect);
    });
  }

  for (final failAt in ['805C000204', '00B201C400']) {
    test('双应用中断保留独立部分结果且不继续 APDU at=$failAt', () async {
      final link = _TuLink(failAt: failAt);
      final bank = _BankProbe();
      final outcome = (await LocalCardReader(
        link.call,
        bankProbe: bank,
      ).read())!;
      expect(outcome.parsedCard!.parserId, CardParserIds.shenzhenTunion);
      expect(
        outcome.readResult!.transportFailure!.kind,
        TransportFailureKind.tagLost,
      );
      expect(link.afterFailure, 0);
      expect(bank.calls, 0);
      expect(link.sztSelects, failAt == '805C000204' ? 0 : 1);
      expect(
        outcome.parsedCard!.localCard!.extras.slots['szt.probed'],
        failAt != '805C000204',
      );
      if (failAt == '00B201C400') {
        expect(outcome.parsedCard!.info.balanceFen, 500);
        expect(outcome.parsedCard!.localCard!.info.observedBalance, 12345);
      }
    });
  }

  test('PAY.SZT 独立识别并按 Wiki 偏移读取，不进入通用文件或银行探测', () async {
    final commands = <String>[];
    final bank = _BankProbe();
    final result = await LocalCardReader((command) async {
      commands.add(_hex(command));
      return _respond(command);
    }, bankProbe: bank).read();
    expect(result, isNotNull);
    expect(bank.calls, 0);
    final info = result!.readResult!.info;
    expect(info.isSZT, isTrue);
    expect(info.cardNumber, '4045620583');
    expect(info.startDate, DateTime(2024, 1, 2));
    expect(result.parsedCard!.info.effectiveDate, DateTime(2024, 1, 2));
    expect(info.expiryDate, DateTime(2030, 12, 31));
    expect(info.observedBalance, 12345);
    expect(info.rawInfo, _basic());
    final trips = result.readResult!.trips;
    expect(trips, hasLength(2));
    expect(trips[0].balanceDelta, -300);
    expect(trips[1].balanceDelta, 300);
    expect(trips[0].timestamp, DateTime(2026, 10, 31, 12, 34, 56));
    expect(trips[0].terminalHex, '001234567890');
    expect(trips[0].identity!.take(2), [0x00, 0x17]);
    expect(trips[0].fileSelector, 0xC4);
    final selected = commands.indexOf('00A40400075041592E535A54');
    expect(selected, greaterThanOrEqualTo(0));
    expect(commands.sublist(selected + 1), [
      '00B0950020',
      '805C000204',
      '00B201C400',
      '00B202C400',
      '00B203C400',
    ]);
  });

  test('未知交易类型不猜收支，非法 BCD 和日历日期保留原文', () async {
    final records = <ApduRecord>[];
    final info = CardInfo();
    final basic = _basic()..setRange(20, 24, [0x20, 0x25, 0x02, 0x29]);
    final invalid = _log(0x09)..[22] = 0x6A;
    final unknown = _log(0x06);
    final reader = Shenzhentong(
      ApduExchange(
        transceive: (cmd) async {
          switch (_hex(cmd)) {
            case '00B0950020':
              return _ok(basic);
            case '00B201C400':
              return _ok(invalid);
            case '00B202C400':
              return _ok(unknown);
            default:
              return [0x6A, 0x83];
          }
        },
      ),
    );
    await reader.read(info, records);
    expect(info.startDate, isNull);
    expect(info.observedBalance, isNull);
    final logs = records.where((r) => r.fileSelector == 0xC4).toList();
    expect(logs[0].hasError, isTrue);
    expect(logs[0].timestamp.millisecondsSinceEpoch, 0);
    expect(logs[0].rawBody, invalid);
    expect(logs[1].posType, 0x06);
    expect(logs[1].type, 0);
    expect(logs[1].balanceDelta, 0);
    expect(logs[1].rawBody, unknown);
  });

  test('截短信息不解析卡号，畸形记录保留并继续读取下一条', () async {
    final info = CardInfo();
    final records = <ApduRecord>[];
    final reader = Shenzhentong(
      ApduExchange(
        transceive: (cmd) async {
          switch (_hex(cmd)) {
            case '00B0950020':
              return _ok(_basic().sublist(0, 28));
            case '00B201C400':
              return _ok([1, 2, 3]);
            case '00B202C400':
              return _ok(_log(0x02));
            default:
              return [0x6A, 0x83];
          }
        },
      ),
    );
    await reader.read(info, records);
    expect(info.cardNumber, isEmpty);
    expect(info.rawInfo, hasLength(28));
    expect(records.where((r) => r.hasError).single.rawBody, [1, 2, 3]);
    expect(records.where((r) => r.type == 2).single.balanceDelta, 300);
  });

  test('SELECT 失败不认领，允许银行探测', () async {
    final bank = _BankProbe();
    final result = await LocalCardReader(
      (_) async => [0x6A, 0x82],
      bankProbe: bank,
    ).read();
    expect(result, isNull);
    expect(bank.calls, 1);
  });

  test('应用确认后移卡保留深圳通身份及已读资料，不继续发送 APDU', () async {
    final bank = _BankProbe();
    var lost = false;
    final result = await LocalCardReader((cmd) async {
      expect(lost, isFalse);
      if (_hex(cmd) == '00B201C400') {
        lost = true;
        throw const TransportFailure(
          kind: TransportFailureKind.tagLost,
          code: 'TAG_LOST',
          message: 'synthetic tag loss',
        );
      }
      return _respond(cmd);
    }, bankProbe: bank).read();
    expect(result!.readResult!.info.isSZT, isTrue);
    expect(result.readResult!.info.cardNumber, '4045620583');
    expect(result.readResult!.readError, isNotNull);
    expect(bank.calls, 0);
  });

  test('循环记录读取有界，保留相同内容的不同槽位', () async {
    var calls = 0;
    final records = <ApduRecord>[];
    await Shenzhentong(
      ApduExchange(
        transceive: (cmd) async {
          if (cmd[1] == 0xB2) {
            calls++;
            return _ok(_log(0x09));
          }
          return [0x6A, 0x82];
        },
      ),
    ).read(CardInfo(), records);
    expect(calls, 20);
    expect(records.where((r) => r.type == 2), hasLength(20));
  });
}

List<int> _respond(List<int> cmd) {
  switch (_hex(cmd)) {
    case '00A40400075041592E535A54':
      return _ok([]);
    case '00B0950020':
      return _ok(_basic());
    case '805C000204':
      return _ok([0, 0, 0x30, 0x39]);
    case '00B201C400':
      return _ok(_log(0x09));
    case '00B202C400':
      return _ok(_log(0x02));
    default:
      return [0x6A, 0x82];
  }
}

List<int> _basic() => List<int>.filled(32, 0)
  ..setRange(16, 20, [0x67, 0x45, 0x23, 0xF1])
  ..setRange(20, 24, [0x20, 0x24, 0x01, 0x02])
  ..setRange(24, 28, [0x20, 0x30, 0x12, 0x31]);

List<int> _log(int kind) => [
  0x00,
  0x17,
  0,
  0,
  0,
  0,
  0,
  0x01,
  0x2C,
  kind,
  0x00,
  0x12,
  0x34,
  0x56,
  0x78,
  0x90,
  0x20,
  0x26,
  0x10,
  0x31,
  0x12,
  0x34,
  0x56,
];
List<int> _ok(List<int> bytes) => [...bytes, 0x90, 0x00];
String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

class _TuLink {
  _TuLink({
    this.serial = '03104870400000000001',
    this.rejectTuBalance = false,
    this.failSztSelect = false,
    this.failAt,
  });
  final String serial;
  final bool rejectTuBalance;
  final bool failSztSelect;
  final String? failAt;
  String? selected;
  int sztSelects = 0;
  int cuSelects = 0;
  int tuReads = 0;
  bool failed = false;
  int afterFailure = 0;

  Future<List<int>> call(List<int> command) async {
    final hex = _hex(command);
    if (failed) afterFailure++;
    if (hex == failAt && (failAt != '00B201C400' || selected == 'SZT')) {
      failed = true;
      throw const TransportFailure(
        kind: TransportFailureKind.tagLost,
        code: 'TAG_LOST',
        message: 'synthetic tag loss',
      );
    }
    if (hex == '00A40000023F0000') {
      selected = null;
      return _ok([]);
    }
    if (hex.contains('A000000632010105')) {
      selected = 'TU';
      return _ok([]);
    }
    if (hex.contains('A00000000386980701')) cuSelects++;
    if (hex == '00A40400075041592E535A54') {
      sztSelects++;
      if (failSztSelect) return [0x6A, 0x82];
      selected = 'SZT';
      return _ok([]);
    }
    if (selected == 'TU') {
      if (hex == '00B0950000') {
        tuReads++;
        final data = '02215840123456780101${serial}2024010120291231AABB';
        return _ok([
          for (var i = 0; i < data.length; i += 2)
            int.parse(data.substring(i, i + 2), radix: 16),
        ]);
      }
      if (hex == '805C000204') {
        return rejectTuBalance ? [0x69, 0x85] : _ok([0, 0, 1, 0xF4]);
      }
    }
    if (selected == 'SZT') return _respond(command);
    return [0x6A, 0x82];
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
