library;

import '../../iso7816/apdu_exchange_engine.dart';
import '../../iso7816/ber_tlv.dart';
import '../../transport/transport_failure.dart';
import 'local_card_models.dart';

export '../../iso7816/apdu_exchange_engine.dart';

/// Sends an APDU and returns its complete response, including SW1/SW2.
typedef LocalTransceive = Future<List<int>> Function(List<int> apdu);

/// Compatibility facade; physical exchange mechanics live in one engine.
class ApduExchange {
  ApduExchange({required this.transceive, this.onExchange});
  final LocalTransceive transceive;
  final void Function(ApduExchangeResult result)? onExchange;

  /// Last bounded attempt, including rejected/malformed frames and retries.
  ApduExchangeResult? lastExchange;

  static const List<int> okSw = [0x90, 0x00];
  static const List<int> sw6700 = [0x67, 0x00];

  Future<ApduExchangeResult> exchange(
    List<int> apdu, {
    ExchangePolicy policy = ExchangePolicy.local,
  }) async {
    lastExchange = null;
    var result = await ApduExchangeEngine(transceive)
        .exchange(CommandApdu.parse(apdu), policy: policy);
    if (result.isSuccess &&
        apdu.length >= 5 &&
        apdu[1] == 0xA4 &&
        apdu[2] == 4 &&
        apdu[4] > 0 &&
        apdu.length >= 5 + apdu[4] &&
        BerTlvParser.selectedAidMatches(
              result.response!.data,
              apdu.sublist(5, 5 + apdu[4]),
            ) ==
            false) {
      result = ApduExchangeResult(
        command: result.command,
        effectiveCommand: result.effectiveCommand,
        response: result.response,
        frames: result.frames,
        failure: const TransportFailure(
          kind: TransportFailureKind.unsupportedProfile,
          message: 'SELECT 返回的应用名与请求不一致',
        ),
      );
    }
    lastExchange = result;
    onExchange?.call(result);
    // A well-framed, short optional file remains a local decode miss. A frame
    // without SW1/SW2, a broken continuation or a resource limit ends I/O.
    if (result.frames.any(
          (frame) =>
              frame.failure != null ||
              (frame.response?.length ?? 0) < 2 ||
              frame.response!.any((b) => b < 0 || b > 255),
        ) ||
        result.failure?.kind == TransportFailureKind.resourceLimit) {
      throw ApduTransportException(result);
    }
    return result;
  }

  /// TU/CU retain their nonzero-6C correction and original-CLA continuation.
  Future<List<int>> exchangeTransit(List<int> apdu) async {
    final result = await exchange(apdu, policy: ExchangePolicy.transit);
    // Never assemble a short continuation into a fabricated status word.
    return result.response?.raw ?? const [];
  }

  Future<List<int>?> call(
    List<int> apdu,
    String label, {
    bool verbose = false,
    List<ApduRecord>? records,
    bool strict = false,
    int flags = 0xC0,
  }) async {
    final result = await exchange(
      apdu,
      policy: ExchangePolicy.local.withStrictLength(strict),
    );
    final response = result.response;
    if (response == null) return null;
    final skipSwCheck = (flags & 0x40) == 0;
    if (verbose && (skipSwCheck || result.isSuccess)) {
      records?.add(
        ApduRecord()
          ..commandHex = _hexStr(result.effectiveCommand.bytes)
          ..response = response.raw
          ..label = label,
      );
    }
    return result.isSuccess ? response.data : null;
  }

  static String _hexStr(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
}
