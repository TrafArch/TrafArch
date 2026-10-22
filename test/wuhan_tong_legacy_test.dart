import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/scan/application/bank_card_probe.dart';
import 'package:transit_card_analyzer/features/scan/application/local_card_reader.dart';
import 'package:transit_card_analyzer/protocols/bank/domain/models/bank_card_result.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/local/apdu_exchange.dart';
import 'package:transit_card_analyzer/protocols/transit/local/cards/wuhan_tong_card.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';
import 'package:transit_card_analyzer/protocols/transport/transport_failure.dart';

const _selectWhctc = '00A40400094150312E5748435443';

void main() {
  group('老版武汉通（WHCTC）', () {
    test('AP1.WHCTC 确认后读取卡号 / 有效期 / 余额 / SFI 24 流水，且不再探测 PBOC', () async {
      final link = _CardLink(_whctcResponse);
      final bank = _BankProbe();
      final result = await LocalCardReader(link.call, bankProbe: bank).read();

      expect(result, isNotNull);
      expect(bank.calls, 0, reason: '应用确认后不得回退到 PBOC 探测');

      final parsed = result!.parsedCard!;
      expect(parsed.parserId, CardParserIds.localCard);
      expect(parsed.parserName, '地方交通卡 · 武汉通');
      expect(parsed.info.balanceFen, 1000);

      final info = result.readResult!.info;
      expect(info.isWHCTC, isTrue);
      expect(info.isLocalCard, isTrue);
      expect(info.cardKindLabel, '武汉通');
      expect(info.cityCode, 5210);
      expect(info.cardNumber, '0102030405');
      expect(info.balance, 1000);
      expect(info.expiryDate, isNotNull);
      expect(info.expiryDate!.year, 2030);
      expect(info.expiryDate!.month, 12);
      expect(info.expiryDate!.day, 31);
      expect(info.startDate, isNotNull);
      expect(info.startDate!.year, 2024);
      expect(info.startDate!.month, 1);
      expect(info.startDate!.day, 1);

      final trip = result.readResult!.trips.single;
      expect(trip.response, _logRecord);
      expect(trip.posType, 0x06);
      expect(trip.terminalHex, '123456789012');
      expect(trip.balanceDelta, -1000);
      expect(trip.timestamp.year, 2026);
      expect(trip.timestamp.month, 10);
      expect(trip.timestamp.day, 21);
      expect(trip.timestamp.hour, 12);
      expect(trip.timestamp.minute, 30);
    });

    test('余额高位为符号位时按参考实现还原为正数', () async {
      final link = _CardLink((command) {
        if (_hex(command) == '805C000204') {
          return _ok(const [0x80, 0x00, 0x03, 0xE8]);
        }
        return _whctcResponse(command);
      });
      final info = CardInfo();
      final records = <ApduRecord>[];
      final apdu = ApduExchange(transceive: link.call);

      expect(await WuhanTongCard(apdu).probe(info, records), isTrue);
      expect(info.balance, 1000);
    });

    test('AP1.WHCTC 选择失败：不认领卡片，仍允许后续 PBOC 探测', () async {
      final link = _CardLink((command) {
        if (_hex(command) == _selectWhctc) return const [0x6A, 0x82];
        return _whctcResponse(command);
      });
      final bank = _BankProbe();
      final result = await LocalCardReader(link.call, bankProbe: bank).read();

      expect(result, isNull);
      expect(bank.calls, 1);
    });

    test('应用确认后流水读取失败仍返回本地卡结果（不落入 PBOC）', () async {
      final link = _CardLink((command) {
        if (command[1] == 0xB2) throw _tagLost;
        return _whctcResponse(command);
      });
      final bank = _BankProbe();
      final result = await LocalCardReader(link.call, bankProbe: bank).read();

      expect(result, isNotNull);
      expect(bank.calls, 0);
      expect(result!.parsedCard!.localCard!.info.isWHCTC, isTrue);
      expect(result.readResult!.info.balance, 1000);
      expect(result.readResult!.readError, isNotNull);
    });
  });
}

List<int> _whctcResponse(List<int> command) {
  switch (_hex(command)) {
    case '00A40000023F00':
      return _ok(const []);
    case '00B08A0000':
      return _ok(_serialFile);
    case '00B0850000':
      return _ok(_infoFile);
    case '805C000204':
      return _ok(const [0x00, 0x00, 0x03, 0xE8]);
    case _selectWhctc:
      return _ok(const []);
    case '00B201C500':
      return const [0x6A, 0x83]; // 不支持整文件读取，回退逐条
    case '00B201C400':
      return _ok(_logRecord);
    default:
      return const [0x6A, 0x82];
  }
}

class _CardLink {
  _CardLink(this.respond);
  final List<int> Function(List<int>) respond;
  bool failed = false;

  Future<List<int>> call(List<int> command) async {
    if (failed) throw StateError('NFC continued after the failed exchange');
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

const _tagLost = TransportFailure(
  kind: TransportFailureKind.tagLost,
  code: 'TAG_LOST',
  message: 'synthetic physical tag loss',
);

List<int> _ok(List<int> data) => [...data, 0x90, 0x00];

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

final _serialFile = List<int>.filled(27, 0)
  ..setRange(0, 5, [0x01, 0x02, 0x03, 0x04, 0x05]);

final _infoFile = List<int>.filled(27, 0)
  ..setRange(16, 20, [0x20, 0x30, 0x12, 0x31]) // 有效期 2030-12-31
  ..setRange(20, 24, [0x20, 0x24, 0x01, 0x01]) // 起始日 2024-01-01
  ..[24] = 0x02;

const _logRecord = [
  0x00, 0x01, // 00-01 序号
  0x00, 0x00, 0x00, // 02-04 透支金额
  0x00, 0x00, 0x03, 0xE8, // 05-08 交易金额 1000
  0x06, // 09 交易类型：消费
  0x12, 0x34, 0x56, 0x78, 0x90, 0x12, // 10-15 终端编号
  0x20, 0x26, 0x10, 0x21, // 16-19 日期 2026-10-21
  0x12, 0x30, // 20-21 时间 12:30
  0x00, // 22 预留
];
