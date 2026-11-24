import '../../../protocols/transit/local/apdu_exchange.dart';
import '../../../protocols/transit/local/card_aid.dart';
import '../../../protocols/transit/local/local_hex.dart';
import '../../../protocols/transit/multiapp/application_evidence.dart';

/// MOT.BMAC001 publishes a record at SFI 03, slot 1. Its layout is unknown.
class MotBmacScan {
  MotBmacScan(this.apdu);
  final ApduExchange apdu;
  static const id = 'mot_bmac';
  static const name = 'MOT.BMAC001';

  Future<ApplicationEvidence> read() async {
    var confirmed = false;
    final observations = <String, String>{};
    try {
      final fci = await apdu(CardAid.motBmac, 'SELECT $name');
      if (fci == null) return ApplicationEvidence.rejected(id, name);
      confirmed = true;
      if (fci.isNotEmpty) observations['SELECT FCI'] = LocalHex.bytesToHex(fci);
      final data = await apdu(const [
        0,
        0xB2,
        1,
        0x1C,
        0x32,
      ], '$name SFI 0x03 #1');
      if (data == null || data.isEmpty) {
        return ApplicationEvidence(
          appId: id,
          displayName: name,
          probed: true,
          confirmed: true,
          state: ApplicationProbeState.confirmed,
          observations: observations,
          notes: const ['SFI 0x03 #1 未读到数据'],
        );
      }
      observations['SFI 0x03 #1'] = LocalHex.bytesToHex(data);
      return ApplicationEvidence.succeeded(
        id,
        name,
        observations: observations,
      );
    } on ApduTransportException catch (error) {
      return ApplicationEvidence(
        appId: id,
        displayName: name,
        state: confirmed
            ? ApplicationProbeState.partial
            : ApplicationProbeState.failed,
        probed: true,
        confirmed: confirmed,
        observations: observations,
        readError: error,
        transportFailure: error.failure,
      );
    }
  }
}
