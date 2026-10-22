import '../transport/transport_failure.dart';
import 'apdu.dart';
import 'exchange_policy.dart';

export 'apdu.dart';
export 'exchange_policy.dart';

typedef ApduTransceive = Future<List<int>> Function(List<int> command);

class ApduFrameEvidence {
  ApduFrameEvidence({
    required List<int> command,
    List<int>? response,
    this.failure,
  }) : command = List<int>.unmodifiable(command),
       response = response == null ? null : List<int>.unmodifiable(response);
  final List<int> command;
  final List<int>? response;
  final TransportFailure? failure;
}

class ApduExchangeResult {
  ApduExchangeResult({
    required this.command,
    required this.effectiveCommand,
    required this.response,
    required List<ApduFrameEvidence> frames,
    this.failure,
  }) : frames = List<ApduFrameEvidence>.unmodifiable(frames);
  final CommandApdu command;
  final CommandApdu effectiveCommand;

  /// Last fully assembled response. On a failed continuation this is partial
  /// and must be interpreted together with [failure] and [frames].
  final ResponseApdu? response;
  final List<ApduFrameEvidence> frames;
  final TransportFailure? failure;
  bool get isSuccess => failure == null && response?.isSuccess == true;
}

/// Transport failures retain the entire attempt, including earlier responses.
class ApduTransportException implements Exception {
  const ApduTransportException(this.result);
  final ApduExchangeResult result;
  TransportFailure get failure => result.failure!;
  @override
  String toString() => 'APDU transport: $failure';
}

/// Existing EMV clients catch FormatException; retain that API and add evidence.
class ApduFormatException extends FormatException {
  ApduFormatException(this.result) : super(result.failure!.message);
  final ApduExchangeResult result;
}

class ApduExchangeEngine {
  const ApduExchangeEngine(this.transceive);
  final ApduTransceive transceive;

  Future<ApduExchangeResult> exchange(
    CommandApdu command, {
    ExchangePolicy policy = ExchangePolicy.local,
  }) async {
    if (policy.maxContinuations < 0 ||
        policy.maxExchanges < 1 ||
        policy.maxResponseBytes < 2) {
      throw ArgumentError('Invalid APDU exchange budget');
    }
    final frames = <ApduFrameEvidence>[];
    var effective = command;
    ResponseApdu? assembled;
    TransportFailure? failure;
    var receivedBytes = 0;

    Future<ResponseApdu?> send(CommandApdu cmd) async {
      if (frames.length >= policy.maxExchanges) {
        failure = const TransportFailure(
          kind: TransportFailureKind.resourceLimit,
          message: 'APDU 交换次数超过限制',
        );
        return null;
      }
      final List<int> raw;
      try {
        raw = await transceive(List<int>.of(cmd.bytes));
      } catch (error, stack) {
        failure = TransportFailure.from(error, stack);
        frames.add(ApduFrameEvidence(command: cmd.bytes, failure: failure));
        return null;
      }
      // Record even an oversized or malformed response before rejecting it.
      frames.add(ApduFrameEvidence(command: cmd.bytes, response: raw));
      receivedBytes += raw.length;
      if (receivedBytes > policy.maxResponseBytes) {
        failure = const TransportFailure(
          kind: TransportFailureKind.resourceLimit,
          message: 'APDU 响应字节数超过限制',
        );
        return null;
      }
      try {
        return ResponseApdu.parse(raw);
      } on FormatException catch (error, stack) {
        failure = TransportFailure(
          kind: TransportFailureKind.malformedFrame,
          message: error.message,
          cause: error,
          stackTrace: stack,
        );
        return null;
      }
    }

    CommandApdu? correction(CommandApdu cmd, ResponseApdu resp) {
      if (!cmd.hasLe) return null;
      if (resp.sw1 == 0x6C && (resp.sw2 != 0 || policy.correct6c00)) {
        return cmd.correctedLe(resp.sw2);
      }
      if (resp.statusWord == 0x6700 && policy.retry6700 && cmd.encodedLe != 0) {
        return cmd.withEncodedLe(0);
      }
      return null;
    }

    Future<ResponseApdu?> sendCorrected(
      CommandApdu cmd, {
      required bool initial,
    }) async {
      var response = await send(cmd);
      if (response == null) return null;
      final corrected = correction(cmd, response);
      if (corrected != null) {
        if (initial) effective = corrected;
        response = await send(corrected);
      }
      return response;
    }

    Future<ResponseApdu?> follow(ResponseApdu? first) async {
      if (first == null) return null;
      var response = first;
      final data = <int>[...response.data];
      var continuations = 0;
      assembled = first;
      while (response.sw1 == 0x61 && (response.sw2 != 0 || policy.follow6100)) {
        if (continuations++ >= policy.maxContinuations) {
          failure = const TransportFailure(
            kind: TransportFailureKind.resourceLimit,
            message: 'GET RESPONSE 次数超过限制',
          );
          return assembled;
        }
        final next = CommandApdu.parse([
          policy.continuationCla ?? command.cla,
          0xC0,
          0,
          0,
          response.sw2,
        ]);
        final part = policy.correctContinuationLe
            ? await sendCorrected(next, initial: false)
            : await send(next);
        if (part == null) return assembled;
        data.addAll(part.data);
        response = part;
        assembled = ResponseApdu(data, response.sw1, response.sw2);
      }
      return assembled;
    }

    if (policy.correctionTiming == LeCorrectionTiming.beforeContinuation) {
      assembled = await follow(await sendCorrected(command, initial: true));
    } else {
      assembled = await follow(await send(command));
      if (failure == null && assembled != null) {
        final corrected = correction(command, assembled!);
        if (corrected != null) {
          effective = corrected;
          assembled = await follow(await send(corrected));
        }
      }
    }
    final response = assembled;
    if (failure == null && response != null) {
      final le = effective.expectedLength;
      final checkLength =
          policy.strictLength &&
          le != null &&
          !(policy.zeroLeIsOpenLength && effective.encodedLe == 0);
      if (checkLength && response.data.length < le) {
        failure = const TransportFailure(
          kind: TransportFailureKind.malformedFrame,
          message: 'APDU 响应短于最终命令 Le',
        );
      } else if (!response.isSuccess) {
        failure = TransportFailure(
          kind: TransportFailureKind.rejectedStatus,
          message: 'APDU 状态字 ${response.statusWord.toRadixString(16)}',
          details: response.statusWord,
        );
      }
    }
    return ApduExchangeResult(
      command: command,
      effectiveCommand: effective,
      response: response,
      frames: frames,
      failure: failure,
    );
  }
}
