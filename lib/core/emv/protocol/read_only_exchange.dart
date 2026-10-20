import '../transport.dart';
import 'emv_apdu.dart';

/// Shared response handling for SELECT / GPO / READ RECORD. A corrected Le is
/// retried once per command, including GET RESPONSE; 00 means 256 bytes.
Future<EmvApduResponse> exchangeReadOnly(
  EmvTransceive transceive,
  List<int> command,
) async {
  Future<EmvApduResponse> send(List<int> apdu) async {
    var response = EmvApduResponse.parse(await transceive(apdu));
    if (response.wrongLe) {
      final corrected = List<int>.of(apdu);
      corrected[corrected.length - 1] = response.sw2;
      response = EmvApduResponse.parse(await transceive(corrected));
    }
    return response;
  }

  var response = await send(command);
  final data = <int>[...response.data];
  var continuations = 0;
  while (response.hasMoreData) {
    if (continuations++ >= 32) {
      throw const FormatException('GET RESPONSE 次数超过限制');
    }
    // GET RESPONSE uses the interindustry CLA, including after CLA 80 GPO.
    response = await send(EmvApdu.getResponse(response.sw2));
    data.addAll(response.data);
  }
  return EmvApduResponse(data, response.sw1, response.sw2);
}
