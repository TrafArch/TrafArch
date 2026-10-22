library;

import '../felica_hex.dart';
import '../transport.dart';
import 'felica_command.dart';
import 'felica_frame_evidence.dart';
import 'felica_response.dart';

enum FelicaFailureReason {
  noResponse,
  malformed,
  unexpectedCode,
  mismatchedRequest,
  transport,
}

/// Wire failure with the original request, response and transport error.
class FelicaProtocolException implements Exception {
  final String stage;
  final String message;
  final FelicaFailureReason reason;
  final int? status;
  final List<int>? raw;
  final List<int>? request;
  final TransportFailure? transportFailure;
  final Object? cause;
  final StackTrace? stackTrace;

  const FelicaProtocolException(
    this.stage,
    this.message, {
    required this.reason,
    this.status,
    this.raw,
    this.request,
    this.transportFailure,
    this.cause,
    this.stackTrace,
  });

  bool get stopsSession =>
      reason == FelicaFailureReason.noResponse ||
      reason == FelicaFailureReason.mismatchedRequest ||
      (transportFailure?.stopsSession ?? false);

  @override
  String toString() {
    final statusText = status == null
        ? ''
        : '（状态 ${FelicaHex.wordCode(status!)}）';
    return 'FeliCa $stage 失败：$message$statusText';
  }
}

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

class FelicaBlockReadResult {
  final List<int> idm;
  final int status1;
  final int status2;
  final List<List<int>> blocks;
  final List<int> raw;
  const FelicaBlockReadResult({
    required this.idm,
    required this.status1,
    required this.status2,
    required this.blocks,
    this.raw = const [],
  });
  bool get ok => status1 == 0 && status2 == 0;
  int get statusCode => ((status1 & 0xFF) << 8) | (status2 & 0xFF);
}

/// A scan-local frame port. No Flutter dependency or card/product state lives
/// here. All physical traffic is retained, including mismatched responses.
class FelicaProtocol {
  FelicaProtocol(this._transceive);
  final FelicaTransceive _transceive;
  final _frames = <FelicaFrameEvidence>[];
  var _responseBytes = 0;
  var _attempts = 0;
  static const maxFrames = 256;
  static const maxResponseBytes = 65536;
  List<FelicaFrameEvidence> get frames => List.unmodifiable(_frames);

  Future<FelicaPollingResult> polling({
    int systemCode = FelicaCommand.systemCodeWildcard,
  }) => _exchange(
    FelicaCommand.polling(systemCode: systemCode),
    'Polling',
    expectedCode: 0x01,
    decode: (resp) {
      // Keep optional request data as raw evidence; do not infer a product.
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
        pmm: List.unmodifiable(resp.data.sublist(0, 8)),
        requestData: List.unmodifiable(resp.data.sublist(8)),
      );
    },
  );

  Future<List<int>> requestSystemCode(List<int> idm) => _exchange(
    FelicaCommand.requestSystemCode(idm),
    'Request System Code',
    expectedCode: 0x0D,
    expectedIdm: idm,
    decode: (resp) {
      final count = _count(resp, 0, 'Request System Code');
      if (resp.data.length != 1 + count * 2) {
        throw FelicaProtocolException(
          'Request System Code',
          '系统码数量 $count 与数据长度 ${resp.data.length - 1} 不符',
          reason: FelicaFailureReason.malformed,
          raw: resp.raw,
        );
      }
      return List<int>.unmodifiable([
        for (var i = 0; i < count; i++)
          (resp.data[1 + i * 2] << 8) | resp.data[2 + i * 2],
      ]);
    },
  );

  Future<List<int>> requestService({
    required List<int> idm,
    required List<int> serviceCodes,
  }) {
    final services = List<int>.unmodifiable(serviceCodes);
    return _exchange(
      FelicaCommand.requestService(idm: idm, serviceCodes: services),
      'Request Service',
      expectedCode: 0x03,
      expectedIdm: idm,
      decode: (resp) {
        final count = _count(resp, 0, 'Request Service');
        if (count != services.length || resp.data.length != 1 + count * 2) {
          throw FelicaProtocolException(
            'Request Service',
            '密钥版本数量 $count（期望 ${services.length}）'
                '与数据长度 ${resp.data.length - 1} 不符',
            reason: FelicaFailureReason.malformed,
            raw: resp.raw,
          );
        }
        return List<int>.unmodifiable([
          for (var i = 0; i < count; i++)
            FelicaHex.readLe16(resp.data, 1 + i * 2),
        ]);
      },
    );
  }

  Future<FelicaBlockReadResult> readWithoutEncryption({
    required List<int> idm,
    required List<int> serviceCodes,
    required List<int> blockListElements,
  }) {
    final services = List<int>.unmodifiable(serviceCodes);
    final elements = List<int>.unmodifiable(blockListElements);
    return _exchange(
      FelicaCommand.readWithoutEncryption(
        idm: idm,
        serviceCodes: services,
        blockListElements: elements,
      ),
      'Read Without Encryption',
      expectedCode: 0x07,
      expectedIdm: idm,
      decode: (resp) {
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
        // Rejected reads may contain only two status bytes. Keep any additional
        // bytes in raw, without treating them as successfully read blocks.
        if (status1 != 0 || status2 != 0) {
          return FelicaBlockReadResult(
            idm: resp.idm,
            status1: status1,
            status2: status2,
            blocks: const [],
            raw: resp.raw,
          );
        }
        final count = _count(resp, 2, 'Read Without Encryption');
        if (count != elements.length ||
            resp.data.length != 3 + count * FelicaCommand.blockSize) {
          throw FelicaProtocolException(
            'Read Without Encryption',
            '块数量 $count（期望 ${elements.length}）'
                '与数据长度 ${resp.data.length - 3} 不符',
            reason: FelicaFailureReason.malformed,
            status: 0,
            raw: resp.raw,
          );
        }
        return FelicaBlockReadResult(
          idm: resp.idm,
          status1: status1,
          status2: status2,
          raw: resp.raw,
          blocks: List<List<int>>.unmodifiable([
            for (var i = 0; i < count; i++)
              List<int>.unmodifiable(
                resp.data.sublist(
                  3 + i * FelicaCommand.blockSize,
                  3 + (i + 1) * FelicaCommand.blockSize,
                ),
              ),
          ]),
        );
      },
    );
  }

  int _count(FelicaResponse resp, int offset, String stage) {
    if (resp.data.length <= offset) {
      throw FelicaProtocolException(
        stage,
        '响应缺少数量字段',
        reason: FelicaFailureReason.malformed,
        raw: resp.raw,
      );
    }
    return resp.data[offset];
  }

  Future<T> _exchange<T>(
    List<int> frame,
    String stage, {
    required int expectedCode,
    List<int>? expectedIdm,
    required T Function(FelicaResponse response) decode,
  }) async {
    final request = List<int>.unmodifiable(frame);
    final idm = expectedIdm == null ? null : List<int>.of(expectedIdm);
    if (_attempts >= maxFrames || _responseBytes > maxResponseBytes) {
      throw FelicaProtocolException(
        stage,
        'FeliCa 交换预算已耗尽',
        reason: FelicaFailureReason.transport,
        request: request,
        transportFailure: const TransportFailure(
          kind: TransportFailureKind.resourceLimit,
          message: 'FeliCa 交换预算已耗尽',
        ),
      );
    }
    _attempts++;
    List<int>? raw;
    FelicaProtocolException? failure;
    try {
      try {
        raw = List<int>.unmodifiable(await _transceive(List<int>.of(request)));
      } catch (error, stack) {
        final transport = TransportFailure.from(error, stack);
        throw FelicaProtocolException(
          stage,
          transport.toString(),
          reason: FelicaFailureReason.transport,
          request: request,
          transportFailure: transport,
          cause: error,
          stackTrace: stack,
        );
      }
      _responseBytes += raw.length;
      if (_responseBytes > maxResponseBytes) {
        throw FelicaProtocolException(
          stage,
          'FeliCa 响应字节数超过限制',
          reason: FelicaFailureReason.transport,
          raw: raw,
          request: request,
          transportFailure: const TransportFailure(
            kind: TransportFailureKind.resourceLimit,
            message: 'FeliCa 响应字节数超过限制',
          ),
        );
      }
      if (raw.isEmpty) {
        throw FelicaProtocolException(
          stage,
          '卡片无响应',
          reason: FelicaFailureReason.noResponse,
          raw: raw,
          request: request,
        );
      }
      final response = FelicaResponse.parse(raw);
      if (idm != null && !_sameBytes(idm, response.idm)) {
        throw FelicaProtocolException(
          stage,
          '响应 IDm ${FelicaHex.bytesToHex(response.idm)}'
          '与请求 ${FelicaHex.bytesToHex(idm)} 不符',
          reason: FelicaFailureReason.mismatchedRequest,
          raw: raw,
          request: request,
        );
      }
      if (response.code != expectedCode) {
        throw FelicaProtocolException(
          stage,
          '非预期响应码 ${FelicaHex.byteCode(response.code)}'
          '（期望 ${FelicaHex.byteCode(expectedCode)}）',
          reason: FelicaFailureReason.unexpectedCode,
          raw: raw,
          request: request,
        );
      }
      return decode(response);
    } on FormatException catch (error, stack) {
      failure = FelicaProtocolException(
        stage,
        error.message,
        reason: FelicaFailureReason.malformed,
        raw: raw,
        request: request,
        cause: error,
        stackTrace: stack,
      );
      throw failure;
    } on FelicaProtocolException catch (error) {
      failure = error;
      rethrow;
    } finally {
      _frames.add(
        FelicaFrameEvidence(
          stage: stage,
          command: request,
          response: raw,
          error: failure,
          transportFailure: failure?.transportFailure,
        ),
      );
    }
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
