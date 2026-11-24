import '../../../protocols/transport/transport_failure.dart';
import '../../../protocols/transit/local/apdu_exchange.dart';
import '../../../protocols/transit/local/cards/beijing_bmac.dart';
import '../../../protocols/transit/local/cards/beijing_local_card.dart';
import '../../../protocols/transit/local/cards/df1001_directory.dart';
import '../../../protocols/transit/local/local_card_models.dart';
import '../../../protocols/transit/local/local_hex.dart';
import '../../../protocols/transit/local/trips/trip_dedup.dart';
import '../../../protocols/transit/local/trips/trip_records.dart';
import '../../../protocols/transit/multiapp/application_evidence.dart';

/// One physical directory with multiple documented file layouts.
class BeijingDf1001Scan {
  BeijingDf1001Scan(this.apdu);
  final ApduExchange apdu;
  static const id = 'df1001';
  static const directoryName = 'DF 1001';

  Future<ApplicationEvidence> read() async {
    final directory = Df1001Directory(apdu);
    final info = CardInfo();
    final records = <ApduRecord>[];
    final extras = CardExtras();
    String? name;
    Object? issue;
    TransportFailure? failure;
    try {
      if (!await directory.select(records)) {
        return ApplicationEvidence.rejected(id, directoryName);
      }
      // MF 04's explicit legacy marker also satisfies the generic BCD serial
      // test on some cards; it identifies the ten-byte-number layout.
      if (BeijingLocalCard.identify(directory, info)) {
        name = '北京互通卡';
        final wallet = BeijingLocalCard(apdu);
        final trips = TripRecordReader(apdu);
        await wallet.readBalance(directory.basic, info, records);
        await wallet.readExtras(records, extras);
        await trips.readFile(info, records, extras, TripFile.metro);
        await trips.reconstructBalances(info, records);
        TripDeduper().process(info, records);
      } else if (BeijingBmac.identify(directory, info, extras)) {
        name = BeijingBmac.moduleName;
        await BeijingBmac(apdu).read(info, records, extras);
      }
    } on Exception catch (e) {
      issue = e;
      failure = switch (e) {
        ApduTransportException(:final failure) => failure,
        TransportFailure() => e,
        _ => null,
      };
    }
    final observations = {
      if (directory.issuer case final raw?)
        'MF SFI 0x04': LocalHex.bytesToHex(raw),
      if (directory.basic case final raw?)
        'MF SFI 0x05': LocalHex.bytesToHex(raw),
      if (directory.fci case final raw? when raw.isNotEmpty)
        'DF 1001 FCI': LocalHex.bytesToHex(raw),
    };
    if (name == null) {
      final selected = directory.fci != null;
      return ApplicationEvidence(
        appId: id,
        displayName: directoryName,
        probed: true,
        confirmed: selected,
        state: selected
            ? ApplicationProbeState.confirmed
            : ApplicationProbeState.failed,
        notes: selected ? const ['目录已选中，钱包布局未识别'] : const [],
        observations: observations,
        readError: issue,
        transportFailure: failure,
      );
    }
    if (info.observedBalance == null) issue ??= '钱包余额未读取';
    final wallet = ReadResult(
      info: info,
      records: List.unmodifiable(records),
      extras: extras,
      readError: issue,
      transportFailure: failure,
    );
    return ApplicationEvidence.succeeded(
      id,
      name,
      cardNumber: info.cardNumber,
      balanceFen: info.observedBalance,
      records: wallet.records,
      recordCount: wallet.trips.length,
      payload: wallet,
      observations: observations,
      readError: issue,
      transportFailure: failure,
    );
  }
}
