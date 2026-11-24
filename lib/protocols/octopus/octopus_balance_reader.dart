library;

import '../felica/protocol/felica_command.dart';
import '../felica/protocol/felica_response.dart';
import 'octopus_balance.dart';

/// Read-only Octopus wallet balance over FeliCa.
///
/// The frame flow was recovered from `com.yeahh.octopus` 1.0.13 (Dart AOT)
/// and confirmed against the user's own card on 2026-11-17:
///
/// 1. Poll FeliCa system `8008` (request code `01`, time slot `17`).
/// 2. Read service `0117`, block list element `8000` without encryption.
/// 3. The 16-byte block holds the balance in tenths of HKD at bytes 2..3;
///    `(raw - 350) / 10` is the balance in HKD.
///
/// This reader only sends the two observed read-only frames. It never writes,
/// authenticates, or opens a network connection.
class OctopusBalanceReader {
  const OctopusBalanceReader();

  static const pollingFrame = <int>[0x06, 0x00, 0x80, 0x08, 0x01, 0x17];
  static const readResponseCode = 0x07;
  static const serviceCode = 0x0117;
  static const blockListElement = 0x8000;
  static const blockSize = 16;
  static const balanceOffset = 2;
  static const balanceExponent = 10;
  static const balanceAdjustment = 350;
  static const blockDataLength = 2 + 1 + blockSize;

  Future<OctopusBalanceResult> execute({
    required Future<List<int>> Function(List<int>) transceiveFelica,
    required bool Function() isCancelled,
    String? expectedCardIdm,
  }) async {
    final expectedIdm = expectedCardIdm?.trim().toUpperCase();
    if (expectedIdm != null && !isValidIdm(expectedIdm)) {
      throw const OctopusBalanceException('本次卡片标识无效，请重新读卡。', code: 'identity');
    }

    final polling = _parse(
      await _exchange(transceiveFelica, isCancelled, pollingFrame),
    );
    if (polling.code != 0x01) {
      throw const OctopusBalanceException(
        '八达通 Polling 响应无效。',
        code: 'invalid_response',
      );
    }
    if (polling.data.length < 8) {
      throw const OctopusBalanceException(
        '八达通 Polling 响应缺少卡片数据。',
        code: 'invalid_response',
      );
    }
    final idm = polling.idmHex;
    if (!isValidIdm(idm)) {
      throw const OctopusBalanceException('八达通返回的卡片标识无效。', code: 'identity');
    }
    if (expectedIdm != null && idm != expectedIdm) {
      throw const OctopusBalanceException(
        '请贴上与本次读取相同的同一张八达通卡。',
        code: 'identity',
      );
    }

    final command = FelicaCommand.readWithoutEncryption(
      idm: polling.idm,
      serviceCodes: const [serviceCode],
      blockListElements: const [blockListElement],
    );
    final read = _parse(
      await _exchange(transceiveFelica, isCancelled, command),
    );
    if (read.code != readResponseCode) {
      throw const OctopusBalanceException(
        '八达通读取余额响应无效。',
        code: 'invalid_response',
      );
    }
    if (read.idmHex != idm) {
      throw const OctopusBalanceException('返回余额与本次卡片身份不一致。', code: 'identity');
    }

    final data = read.data;
    if (data.length < 2) {
      throw const OctopusBalanceException(
        '八达通响应缺少状态字节。',
        code: 'invalid_response',
      );
    }
    final status = (data[0] << 8) | data[1];
    if (status != 0) {
      throw OctopusBalanceException(
        '八达通拒绝读取余额（状态 0x${status.toRadixString(16).padLeft(4, '0').toUpperCase()}）。',
        code: 'protocol',
      );
    }
    if (data.length != blockDataLength || data[2] != 1) {
      throw const OctopusBalanceException(
        '八达通余额块数量无效。',
        code: 'invalid_response',
      );
    }

    return OctopusBalanceResult(
      balanceMinor: decodeBalanceBlock(data.sublist(3)),
      idmHex: idm,
      readAt: DateTime.now(),
    );
  }

  static bool isValidIdm(String idm) =>
      RegExp(r'^[0-9A-F]{16}$').hasMatch(idm) && idm != '0000000000000000';

  static int decodeBalanceBlock(List<int> block) {
    if (block.length != blockSize) {
      throw const OctopusBalanceException(
        '八达通余额块长度无效。',
        code: 'invalid_response',
      );
    }
    final raw = (block[balanceOffset] << 8) | block[balanceOffset + 1];
    return (raw - balanceAdjustment) * balanceExponent;
  }

  Future<List<int>> _exchange(
    Future<List<int>> Function(List<int>) transceiveFelica,
    bool Function() isCancelled,
    List<int> frame,
  ) async {
    if (isCancelled()) throw _cancelled;
    final response = await transceiveFelica(List<int>.unmodifiable(frame));
    if (isCancelled()) throw _cancelled;
    return List<int>.unmodifiable(response);
  }

  FelicaResponse _parse(List<int> frame) {
    try {
      return FelicaResponse.parse(frame);
    } on FormatException catch (error) {
      throw OctopusBalanceException(error.message, code: 'invalid_response');
    }
  }
}

extension on FelicaResponse {
  String get idmHex => idm
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
}

const _cancelled = OctopusBalanceException('本次操作已取消。', code: 'cancelled');
