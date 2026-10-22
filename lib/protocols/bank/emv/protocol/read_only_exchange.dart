import '../../../iso7816/apdu_exchange_engine.dart';
import '../../../transport/transport_failure.dart';
import '../transport.dart';
import 'emv_apdu.dart';

/// EMV compatibility: 6100 continues, GET RESPONSE uses CLA 00, and each
/// physical command can correct 6C once. No 6700 fallback is enabled.
Future<EmvApduResponse> exchangeReadOnly(
  EmvTransceive transceive,
  List<int> command, {
  void Function(ApduExchangeResult result)? onExchange,
}) async {
  final result = await ApduExchangeEngine(transceive)
      .exchange(CommandApdu.parse(command), policy: ExchangePolicy.emv);
  onExchange?.call(result);
  if (result.frames.any((frame) => frame.failure != null)) {
    throw ApduTransportException(result);
  }
  if (result.failure != null &&
      result.failure!.kind != TransportFailureKind.rejectedStatus) {
    throw ApduFormatException(result);
  }
  final response = result.response!;
  return EmvApduResponse(response.data, response.sw1, response.sw2);
}
