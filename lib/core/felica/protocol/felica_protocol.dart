library;

import '../felica_hex.dart';
import '../models/felica_models.dart';
import 'felica_command.dart';
import 'felica_response.dart';

enum FelicaFailureReason { noResponse, malformed, unexpectedCode }

/// FeliCa 协议层异常：保留阶段、原始帧与状态码，禁止静默降级。
class FelicaProtocolException implements Exception {
  final String stage;
  final String message;
  final FelicaFailureReason reason;
  final int? status;
  final List<int>? raw;

  const FelicaProtocolException(
    this.stage,
    this.message, {
    required this.reason,
    this.status,
    this.raw,
  });

  /// 协议失败到统一读取状态的映射（供适配器 / 编排层复用）。
  FelicaReadState get readState => switch (reason) {
        FelicaFailureReason.noResponse => FelicaReadState.tagLost,
        FelicaFailureReason.malformed => FelicaReadState.malformed,
        FelicaFailureReason.unexpectedCode => FelicaReadState.failed,
      };

  @override
  String toString() {
    final statusText =
        status == null ? '' : '（状态 ${FelicaHex.wordCode(status!)}）';
    return 'FeliCa $stage 失败：$message$statusText';
  }
}

/// Polling 结果。
class FelicaPollingResult {
  final List<int> idm;
  final List<int> pmm;
  final List<int> requestData;

  const FelicaPollingResult({
    required this.idm,
    required this.pmm,
    required this.requestData,
  });

  String get idmHex => FelicaHex.bytesToHex(idm);
}

/// Read Without Encryption 结果。
class FelicaBlockReadResult {
  final List<int> idm;
  final int status1;
  final int status2;
  final List<List<int>> blocks;

  const FelicaBlockReadResult({
    required this.idm,
    required this.status1,
    required this.status2,
    required this.blocks,
  });

  bool get ok => status1 == 0x00 && status2 == 0x00;

  int get statusCode => ((status1 & 0xFF) << 8) | (status2 & 0xFF);
}

/// FeliCa 协议层：只做帧构造、发送、响应校验，不解释业务字段。
class FelicaProtocol {
  FelicaProtocol(this._transceive);

  final dynamic Function(List<int> frame) _transceive;

  Future<FelicaPollingResult> polling({
    int systemCode = FelicaCommand.systemCodeWildcard,
  }) async {
    final resp = await _exchange(
      FelicaCommand.polling(systemCode: systemCode),
      'Polling',
    );
    _expectCode(resp, 0x01, 'Polling');
    if (resp.data.length < 8) {
      throw FelicaProtocolException(
        'Polling',
        'PMm 数据不足：${resp.data.length} 字节',
        reason: FelicaFailureReason.malformed,
        raw: resp.raw,
      );
    }
    return FelicaPollingResult(
      idm: resp.idm,
      pmm: resp.data.sublist(0, 8),
      requestData: resp.data.length > 8 ? resp.data.sublist(8) : const [],
    );
  }

  /// 返回卡片支持的全部系统码。
  Future<List<int>> requestSystemCode(List<int> idm) async {
    final resp = await _exchange(
      FelicaCommand.requestSystemCode(idm),
      'Request System Code',
    );
    _expectCode(resp, 0x0D, 'Request System Code');
    if (resp.data.isEmpty) {
      throw FelicaProtocolException(
        'Request System Code',
        '缺少系统码数量字段',
        reason: FelicaFailureReason.malformed,
        raw: resp.raw,
      );
    }
    final count = resp.data[0];
    final body = resp.data.sublist(1);
    if (body.length < count * 2) {
      throw FelicaProtocolException(
        'Request System Code',
        '系统码数量 $count 与数据长度 ${body.length} 不符',
        reason: FelicaFailureReason.malformed,
        raw: resp.raw,
      );
    }
    return [
      for (var i = 0; i < count; i++) (body[i * 2] << 8) | body[i * 2 + 1],
    ];
  }

  /// 返回各服务的密钥版本（每项 2 字节小端）；空列表表示服务不可用。
  Future<List<int>> requestService({
    required List<int> idm,
    required List<int> serviceCodes,
  }) async {
    final resp = await _exchange(
      FelicaCommand.requestService(idm: idm, serviceCodes: serviceCodes),
      'Request Service',
    );
    _expectCode(resp, 0x03, 'Request Service');
    if (resp.data.isEmpty) {
      throw FelicaProtocolException(
        'Request Service',
        '缺少密钥版本数量字段',
        reason: FelicaFailureReason.malformed,
        raw: resp.raw,
      );
    }
    final count = resp.data[0];
    final body = resp.data.sublist(1);
    if (body.length < count * 2) {
      throw FelicaProtocolException(
        'Request Service',
        '密钥版本数量 $count 与数据长度 ${body.length} 不符',
        reason: FelicaFailureReason.malformed,
        raw: resp.raw,
      );
    }
    return [for (var i = 0; i < count; i++) FelicaHex.readLe16(body, i * 2)];
  }

  Future<FelicaBlockReadResult> readWithoutEncryption({
    required List<int> idm,
    required List<int> serviceCodes,
    required List<int> blockListElements,
  }) async {
    final resp = await _exchange(
      FelicaCommand.readWithoutEncryption(
        idm: idm,
        serviceCodes: serviceCodes,
        blockListElements: blockListElements,
      ),
      'Read Without Encryption',
    );
    _expectCode(resp, 0x07, 'Read Without Encryption');
    if (resp.data.length < 2) {
      throw FelicaProtocolException(
        'Read Without Encryption',
        '响应缺少状态字节',
        reason: FelicaFailureReason.malformed,
        raw: resp.raw,
      );
    }
    final status1 = resp.data[0];
    final status2 = resp.data[1];
    // 非 0 状态：部分卡片只返回 2 个状态字节，不强制要求块数量字段。
    if (status1 != 0x00 || status2 != 0x00) {
      return FelicaBlockReadResult(
        idm: resp.idm,
        status1: status1,
        status2: status2,
        blocks: const [],
      );
    }
    if (resp.data.length < 3) {
      throw FelicaProtocolException(
        'Read Without Encryption',
        '成功响应缺少块数量字段',
        reason: FelicaFailureReason.malformed,
        raw: resp.raw,
      );
    }
    final count = resp.data[2];
    final body = resp.data.sublist(3);
    if (body.length < count * FelicaCommand.blockSize) {
      throw FelicaProtocolException(
        'Read Without Encryption',
        '块数量 $count 与数据长度 ${body.length} 不符',
        reason: FelicaFailureReason.malformed,
        status: (status1 << 8) | status2,
        raw: resp.raw,
      );
    }
    return FelicaBlockReadResult(
      idm: resp.idm,
      status1: status1,
      status2: status2,
      blocks: [
        for (var i = 0; i < count; i++)
          body.sublist(
            i * FelicaCommand.blockSize,
            (i + 1) * FelicaCommand.blockSize,
          ),
      ],
    );
  }

  Future<FelicaResponse> _exchange(List<int> frame, String stage) async {
    final raw = await _transceive(frame);
    if (raw.isEmpty) {
      throw FelicaProtocolException(
        stage,
        '卡片无响应（标签可能已离开）',
        reason: FelicaFailureReason.noResponse,
      );
    }
    try {
      return FelicaResponse.parse(raw);
    } on FormatException catch (e) {
      throw FelicaProtocolException(
        stage,
        e.message,
        reason: FelicaFailureReason.malformed,
        raw: raw,
      );
    }
  }

  void _expectCode(FelicaResponse resp, int expected, String stage) {
    if (resp.code != expected) {
      throw FelicaProtocolException(
        stage,
        '非预期响应码 ${FelicaHex.byteCode(resp.code)}'
        '（期望 ${FelicaHex.byteCode(expected)}）',
        reason: FelicaFailureReason.unexpectedCode,
        raw: resp.raw,
      );
    }
  }
}