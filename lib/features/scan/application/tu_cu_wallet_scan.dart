import '../../../protocols/transit/card_parser.dart';
import '../../../protocols/transit/city_union/city_union_reader.dart';
import '../../../protocols/transit/local/apdu_exchange.dart';
import '../../../protocols/transit/local/local_card_models.dart';
import '../../../protocols/transit/multiapp/application_evidence.dart';
import '../../../protocols/transit/tunion/tunion_reader.dart';
import '../../../protocols/transport/transport_failure.dart';

/// The card, protocol records and probe status all belong to one selected AID.
class TransitWalletRead {
  TransitWalletRead._({
    required this.evidence,
    required this.card,
    required this.readResult,
  });

  final ApplicationEvidence evidence;
  final ParsedCard? card;
  final ReadResult readResult;
}

class TuCuWalletScanResult {
  const TuCuWalletScanResult(this.tu, this.cu);
  final TransitWalletRead tu;
  final TransitWalletRead cu;
}

class TuCuWalletScan {
  TuCuWalletScan(this.apdu, {this.onStage});

  final ApduExchange apdu;
  final void Function(String stage)? onStage;

  Future<TuCuWalletScanResult> read() async {
    final tu = _WalletAttempt('tu', CommonUnitTu.moduleName);
    final cu = _WalletAttempt('cu', CommonUnitCu.moduleName);
    final tuReader = CommonUnitTu(apdu);
    final cuReader = CommonUnitCu(apdu);

    Future<void> readCu(ParsedCard? tuPrefix) async {
      onStage?.call(cu.name);
      cu.probed = true;
      try {
        cu.confirmed = await cuReader.select(cu.info, cu.records);
        if (cu.confirmed) {
          await cuReader.read(
            cu.info,
            cu.records,
            readBalance: true,
            tuWallet: tuPrefix,
          );
        }
      } on Exception catch (error) {
        cu.error = error;
      }
      cu.observations.addAll(cuReader.observations);
      final parsed = cuReader.parsedCard;
      if (parsed != null &&
          (parsed.cityUnionFiles.isNotEmpty ||
              parsed.info.balanceFen != null)) {
        cu.card = parsed;
      }
      if (cuReader.balanceResponses.isNotEmpty) {
        cu.extras.slots['cu.balanceResponses'] = Map.of(
          cuReader.balanceResponses,
        );
        if (parsed?.info.balanceFen == null) {
          cu.notes.add(
            'CU 余额未确定，选择子原始响应：${cuReader.balanceResponses.entries.map((e) => '${e.key}=${e.value}').join('，')}',
          );
        }
      }
      if (cuReader.stalePublicFile) {
        cu.notes.add('CU 公共文件仍返回同次 TU 身份，未认领钱包数据');
      }
    }

    onStage?.call(tu.name);
    tu.probed = true;
    try {
      tu.confirmed = await tuReader.select(tu.info, tu.records);
      if (tu.confirmed) {
        await tuReader.read(
          tu.info,
          tu.records,
          beforeProcessRecords: (prefix) async {
            await readCu(prefix);
            if (cu.failure?.stopsSession == true) {
              return TuProcessReadAction.stopSession;
            }
            onStage?.call(tu.name);
            return TuProcessReadAction.restoreApplication;
          },
        );
      }
    } on Exception catch (error) {
      tu.error = error;
    }
    tu.observations.addAll(tuReader.observations);
    tu.card = tuReader.parsedCard;
    if (tuReader.processRecordsSkipped) {
      tu.notes.add('CU 读取终止，TU 过程记录未读取');
    }
    if (!cu.probed && tu.failure?.stopsSession != true) await readCu(null);
    return TuCuWalletScanResult(tu.finish(), cu.finish());
  }
}

class _WalletAttempt {
  _WalletAttempt(this.id, this.name);

  final String id;
  final String name;
  final info = CardInfo();
  final records = <ApduRecord>[];
  final extras = CardExtras();
  final notes = <String>[];
  final observations = <String, String>{};
  bool probed = false;
  bool confirmed = false;
  ParsedCard? card;
  Object? error;

  TransportFailure? get failure => switch (error) {
    ApduTransportException(:final failure) => failure,
    TransportFailure e => e,
    _ => null,
  };

  TransitWalletRead finish() {
    if (card != null && info.observedBalance == null && notes.isEmpty) {
      notes.add('钱包余额未读取');
    }
    final state = switch ((probed, confirmed, card != null, error != null)) {
      (false, _, _, _) => ApplicationProbeState.notProbed,
      (_, false, _, false) => ApplicationProbeState.selectRejected,
      (_, _, false, true) => ApplicationProbeState.failed,
      (_, true, false, false) => ApplicationProbeState.confirmed,
      _ when error != null || notes.isNotEmpty => ApplicationProbeState.partial,
      _ => ApplicationProbeState.readSucceeded,
    };
    final read = ReadResult(
      info: info,
      records: List.unmodifiable(records),
      extras: extras,
      readError: error,
      transportFailure: failure,
    );
    return TransitWalletRead._(
      card: card,
      readResult: read,
      evidence: ApplicationEvidence(
        appId: id,
        displayName: name,
        state: state,
        probed: probed,
        confirmed: confirmed,
        readSucceeded: state == ApplicationProbeState.readSucceeded,
        cardNumber:
            card?.info.displayCardNumber ??
            (info.cardNumber.isEmpty ? null : info.cardNumber),
        balanceFen: info.observedBalance,
        records: read.records,
        recordCount: read.trips.length,
        notes: List.unmodifiable(notes),
        observations: Map.unmodifiable(observations),
        readError: error,
        transportFailure: failure,
        payload: card,
      ),
    );
  }
}
