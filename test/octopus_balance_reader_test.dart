import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/protocols/octopus/octopus_balance.dart';
import 'package:transit_card_analyzer/protocols/octopus/octopus_balance_reader.dart';

/// Frames captured from the user's own Octopus card with `com.yeahh.octopus`
/// 1.0.13 on 2026-11-17 (HK$50.00).
const _idm = [0x01, 0x01, 0x13, 0x01, 0xE2, 0x22, 0x3F, 0x08];
const _pollingResponse = [
  0x14, 0x01, //
  0x01, 0x01, 0x13, 0x01, 0xE2, 0x22, 0x3F, 0x08,
  0x04, 0x3B, 0x46, 0x85, 0x84, 0x82, 0xCC, 0xFF, 0x80, 0x08,
];
const _readBalanceCommand = [
  0x10, 0x06, //
  0x01, 0x01, 0x13, 0x01, 0xE2, 0x22, 0x3F, 0x08,
  0x01, 0x17, 0x01, //
  0x01, 0x80, 0x00,
];
const _readResponse = [
  0x1D, 0x07, //
  0x01, 0x01, 0x13, 0x01, 0xE2, 0x22, 0x3F, 0x08,
  0x00, 0x00, 0x01, //
  0x00, 0x00, 0x03, 0x52, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05,
];

void main() {
  test('实卡帧：Polling 后按 0117/8000 只读余额并解出 HK\$50.00', () async {
    final frames = <List<int>>[];
    final result = await _reader().execute(
      transceiveFelica: (frame) async {
        frames.add(List<int>.of(frame));
        return frames.length == 1 ? _pollingResponse : _readResponse;
      },
      isCancelled: () => false,
    );

    expect(frames, [OctopusBalanceReader.pollingFrame, _readBalanceCommand]);
    expect(result.idmHex, '01011301E2223F08');
    expect(result.balanceMinor, 5000);
    expect(result.readAt, isA<DateTime>());
  });

  test('预期标识与卡片不一致时不进行余额读取', () async {
    final frames = <List<int>>[];
    await expectLater(
      _reader().execute(
        transceiveFelica: (frame) async {
          frames.add(List<int>.of(frame));
          return _pollingResponse;
        },
        isCancelled: () => false,
        expectedCardIdm: '0102030405060708',
      ),
      throwsA(
        isA<OctopusBalanceException>().having(
          (e) => e.code,
          'code',
          'identity',
        ),
      ),
    );
    expect(frames, [OctopusBalanceReader.pollingFrame]);
  });

  test('预期标识命中时继续读取', () async {
    final result = await _reader().execute(
      transceiveFelica: (frame) async =>
          frame.length == OctopusBalanceReader.pollingFrame.length
          ? _pollingResponse
          : _readResponse,
      isCancelled: () => false,
      expectedCardIdm: ' 01011301e2223f08 ',
    );
    expect(result.balanceMinor, 5000);
  });

  test('余额响应标识与 Polling 不一致时拒绝发布', () async {
    final wrongIdm = List<int>.of(_idm)..[7] = 0x09;
    await expectLater(
      _reader().execute(
        transceiveFelica: (frame) async =>
            frame.length == OctopusBalanceReader.pollingFrame.length
            ? _pollingResponse
            : _readResponseWith(idm: wrongIdm),
        isCancelled: () => false,
      ),
      throwsA(
        isA<OctopusBalanceException>().having(
          (e) => e.code,
          'code',
          'identity',
        ),
      ),
    );
  });

  test('状态字节非零时不把块内容当作余额', () async {
    await expectLater(
      _reader().execute(
        transceiveFelica: (frame) async =>
            frame.length == OctopusBalanceReader.pollingFrame.length
            ? _pollingResponse
            : _readResponseWith(status: const [0x00, 0xA8]),
        isCancelled: () => false,
      ),
      throwsA(
        isA<OctopusBalanceException>()
            .having((e) => e.code, 'code', 'protocol')
            .having((e) => e.message, 'message', contains('0x00A8')),
      ),
    );
  });

  test('块数量不是 1 时拒绝读取', () async {
    for (final count in [0, 2]) {
      await expectLater(
        _reader().execute(
          transceiveFelica: (frame) async =>
              frame.length == OctopusBalanceReader.pollingFrame.length
              ? _pollingResponse
              : _readResponseWith(count: count),
          isCancelled: () => false,
        ),
        throwsA(
          isA<OctopusBalanceException>().having(
            (e) => e.code,
            'code',
            'invalid_response',
          ),
        ),
      );
    }
  });

  test('声明长度、响应码和截断响应均被拒绝', () async {
    final malformed = <List<int>>[
      [0x1E, ..._readResponse],
      [0x1D, 0x02, ..._readResponse.sublist(2)],
      _readResponse.sublist(0, 14),
      const [],
    ];
    for (final response in malformed) {
      await expectLater(
        _reader().execute(
          transceiveFelica: (frame) async =>
              frame.length == OctopusBalanceReader.pollingFrame.length
              ? _pollingResponse
              : response,
          isCancelled: () => false,
        ),
        throwsA(
          isA<OctopusBalanceException>().having(
            (e) => e.code,
            'code',
            'invalid_response',
          ),
        ),
      );
    }
  });

  test('取消后不再发送下一帧', () async {
    var cancelled = false;
    final frames = <List<int>>[];
    await expectLater(
      _reader().execute(
        transceiveFelica: (frame) async {
          frames.add(List<int>.of(frame));
          cancelled = true;
          return _pollingResponse;
        },
        isCancelled: () => cancelled,
      ),
      throwsA(
        isA<OctopusBalanceException>().having(
          (e) => e.code,
          'code',
          'cancelled',
        ),
      ),
    );
    expect(frames, [OctopusBalanceReader.pollingFrame]);
  });

  test('开始前已取消时不发起任何交换', () async {
    var calls = 0;
    await expectLater(
      _reader().execute(
        transceiveFelica: (frame) async {
          calls++;
          return _pollingResponse;
        },
        isCancelled: () => true,
      ),
      throwsA(
        isA<OctopusBalanceException>().having(
          (e) => e.code,
          'code',
          'cancelled',
        ),
      ),
    );
    expect(calls, 0);
  });

  test('余额只取块字节 2..3，前导字节不参与金额', () async {
    final result = await _reader().execute(
      transceiveFelica: (frame) async =>
          frame.length == OctopusBalanceReader.pollingFrame.length
          ? _pollingResponse
          : _readResponseWith(leading: const [0x12, 0x34]),
      isCancelled: () => false,
    );
    expect(result.balanceMinor, 5000);
  });

  test('Polling 响应缺少 PMm 数据时拒绝读取', () async {
    await expectLater(
      _reader().execute(
        transceiveFelica: (frame) async => [0x0A, 0x01, ..._idm],
        isCancelled: () => false,
      ),
      throwsA(
        isA<OctopusBalanceException>().having(
          (e) => e.code,
          'code',
          'invalid_response',
        ),
      ),
    );
  });

  test('余额按第十位港币精确换算，包含零与负值', () async {
    for (final (raw, cents) in [
      (350, 0),
      (850, 5000),
      (355, 50),
      (0, -3500),
      (65535, 651850),
    ]) {
      final result = await _reader().execute(
        transceiveFelica: (frame) async =>
            frame.length == OctopusBalanceReader.pollingFrame.length
            ? _pollingResponse
            : _readResponseWith(raw: raw),
        isCancelled: () => false,
      );
      expect(result.balanceMinor, cents, reason: 'raw=$raw');
    }
  });

  test('预期标识格式无效时不发起任何交换', () async {
    for (final idm in ['', '0102', 'ZZ011301E2223F08', '0000000000000000']) {
      var calls = 0;
      await expectLater(
        _reader().execute(
          transceiveFelica: (frame) async {
            calls++;
            return _pollingResponse;
          },
          isCancelled: () => false,
          expectedCardIdm: idm,
        ),
        throwsA(
          isA<OctopusBalanceException>().having(
            (e) => e.code,
            'code',
            'identity',
          ),
        ),
      );
      expect(calls, 0, reason: 'idm=$idm');
    }
  });
}

OctopusBalanceReader _reader() => const OctopusBalanceReader();

List<int> _readResponseWith({
  List<int> idm = _idm,
  List<int> status = const [0x00, 0x00],
  int count = 1,
  int raw = 850,
  List<int> leading = const [0x00, 0x00],
}) {
  final block = <int>[
    ...leading,
    (raw >> 8) & 0xFF,
    raw & 0xFF,
    ...List<int>.filled(12, 0),
  ];
  final payload = <int>[0x07, ...idm, ...status, count, ...block];
  return [payload.length + 1, ...payload];
}
