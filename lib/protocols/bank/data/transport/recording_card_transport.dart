import 'dart:typed_data';

import '../../../transport/transport_failure.dart';

import '../../domain/interfaces/card_transport.dart';
import '../../domain/models/apdu_trace.dart';
import '../apdu/apdu_response.dart';
import '../tlv/hex_codec.dart';

/// 记录型装饰器：包裹真实/回放通道，统一采集 [ApduTrace]（原始 HEX）。
class RecordingCardTransport implements CardTransport {
  final CardTransport _inner;
  final List<ApduTrace> _traces = [];
  TransportFailure? _failure;
  TransportFailure? get failure => _failure;

  RecordingCardTransport(this._inner);

  List<ApduTrace> get traces => List.unmodifiable(_traces);

  @override
  Future<Uint8List> transceive(Uint8List command) async {
    final previousFailure = _failure;
    if (previousFailure != null) throw previousFailure;
    final sw = Stopwatch()..start();
    try {
      final resp = await _inner.transceive(command);
      sw.stop();
      int? statusWord;
      try {
        statusWord = ApduResponse.fromBytes(resp).statusWord;
      } on FormatException {
        statusWord = null;
        _failure = const TransportFailure(
          kind: TransportFailureKind.malformedFrame,
          message: 'APDU response has no complete status word',
        );
      }
      _traces.add(
        ApduTrace(
          stepName: 'APDU',
          commandHex: HexCodec.encode(command),
          responseHex: HexCodec.encode(resp),
          statusWord: statusWord,
          elapsedMs: sw.elapsedMilliseconds,
        ),
      );
      return resp;
    } catch (e, stack) {
      _failure = TransportFailure.from(e, stack);
      sw.stop();
      _traces.add(
        ApduTrace(
          stepName: 'APDU',
          commandHex: HexCodec.encode(command),
          responseHex: '',
          elapsedMs: sw.elapsedMilliseconds,
          errorCode: '$e',
        ),
      );
      rethrow;
    }
  }

  @override
  Future<void> close() => _inner.close();
}
