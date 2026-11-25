import '../../../protocols/transit/local/apdu_exchange.dart';
import '../../../protocols/transit/local/cards/local_wallet_session.dart';
import '../../../protocols/transit/local/cards/suzhou_card.dart';
import '../../../protocols/transit/local/cards/suzhou_cika.dart';
import '../../../protocols/transit/local/cards/tft_local_card.dart';
import '../../../protocols/transit/local/local_card_models.dart';
import '../../../protocols/transit/multiapp/application_evidence.dart';
import '../../../protocols/transport/transport_failure.dart';

/// Probes each named application independently. A lost or malformed session
/// ends the list at the last attempted application.
Future<List<ApplicationEvidence>> readRegisteredLocalWallets(
  LocalTransceive transceive, {
  void Function(String)? onStage,
}) async {
  final applications = <ApplicationEvidence>[];
  for (final (id, name, directory, readerFor) in const [
    ('suzhou_suxin', suzhouCitizenCardName, 'SUXIN.DDF01', SuzhouCard.new),
    ('suzhou_cika', '苏州·计次卡', 'SZPK_ZYY', SuzhouCika.new),
    ('tft', TftLocalCard.moduleName, 'TFT', TftLocalCard.new),
  ]) {
    onStage?.call(name);
    final session = LocalWalletSession(transceive, directory);
    final LocalWalletReader reader = readerFor(session.apdu);
    bool confirmed = false;
    try {
      session.label = 'SELECT $directory';
      confirmed = await reader.select(session.info, session.records);
      if (confirmed) {
        await reader.read(session);
      } else {
        session.failure = session.apdu.lastExchange?.failure;
      }
    } on ApduTransportException catch (e) {
      session.failure = e.failure;
    } on TransportFailure catch (e) {
      session.failure = e;
    }
    final failure = session.failure;
    final issue = failure?.stopsSession == true || session.issues.isEmpty
        ? failure
        : session.issues.join('；');
    final records = List<ApduRecord>.unmodifiable(session.records);
    final info = session.info;
    applications.add(
      ApplicationEvidence(
        appId: id,
        displayName: name,
        state: confirmed
            ? issue == null
                  ? ApplicationProbeState.readSucceeded
                  : ApplicationProbeState.partial
            : failure?.kind == TransportFailureKind.rejectedStatus ||
                  failure?.kind == TransportFailureKind.unsupportedProfile
            ? ApplicationProbeState.selectRejected
            : ApplicationProbeState.failed,
        probed: true,
        confirmed: confirmed,
        readSucceeded: confirmed && issue == null,
        cardNumber:
            info.displayCardNumber ??
            (info.cardNumber.isEmpty ? null : info.cardNumber),
        balanceFen: info.observedBalance,
        records: records,
        recordCount: records.where((record) => record.type == 2).length,
        readError: issue,
        transportFailure: failure,
        notes: List.unmodifiable(session.issues),
        payload: confirmed
            ? ReadResult(
                info: info,
                records: records,
                extras: session.extras,
                readError: issue,
                transportFailure: failure,
              )
            : null,
      ),
    );
    if (failure?.stopsSession == true) break;
  }
  return applications;
}
