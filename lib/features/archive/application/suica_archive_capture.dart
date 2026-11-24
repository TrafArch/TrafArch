import '../../../platform/nfc/nfc_models.dart';
import '../../../protocols/felica/felica.dart';
import '../../scan/domain/captured_frame.dart';
import '../../scan/domain/scan_presentation.dart';
import '../../transit_analysis/tunion_analysis_models.dart';
import '../domain/card_archive_identity.dart';
import '../domain/card_fingerprint.dart';
import '../domain/card_session_snapshot.dart';
import '../domain/card_types.dart';
import '../domain/pending_card_save.dart';

/// Captures parsed fields and frozen display without replaying or rematching.
PendingCardSave? captureSuicaArchive(
  ScanPresentation view,
  String attemptId,
  DateTime readAt,
  List<CapturedFrame> frames,
  List<NfcMetadataIssue> metadataIssues,
) {
  final card = view.felicaResult;
  if (card == null || card.cardProductType != FelicaCardType.suica) return null;
  final fingerprint = CardFingerprint.buildSuica(card.idm);
  if (fingerprint == null) return null;
  final wallets = card.wallets.where(
    (w) =>
        w.kind == FelicaWalletKind.suicaJpy &&
        w.currency == 'JPY' &&
        w.balanceVerified,
  );
  // An ambiguous set of wallets cannot supply a reliable retained balance.
  final balance = wallets.length == 1 ? wallets.single.balanceMinorUnits : null;
  final historyObserved =
      card.transactions.isNotEmpty ||
      card.statuses.any(
        (s) => s.stage == 'Suica 历史记录' && s.state == FelicaReadState.success,
      );
  final confirmed =
      balance != null ||
      card.transactions.any((t) => t.decoded && t.suica != null);
  final packages = <String, dynamic>{
    for (final entry in view.knowledge.packageHashes.entries)
      entry.key: {
        'sha256': entry.value,
        if (view.knowledge.packageVersions[entry.key] != null)
          'contentVersion': view.knowledge.packageVersions[entry.key],
      },
  };
  final snapshot = CardSessionSnapshot(
    parseVersion: kTripParseVersion,
    context: ArchiveContext(
      systemId: 'felica_suica',
      applicationId: 'felica-service:090F',
      currencyCode: 'JPY',
      minorUnitDigits: 0,
      clockBasis: 'card-local-date-or-minute-time-unverified',
      timeZoneOffsetMinutes: null,
      referencePackages: packages,
      observedFields: {
        'cardNumber': false,
        'balanceFen': balance != null,
        'transactionCount': historyObserved,
      },
      extensions: {
        'captureDeviceOffsetMinutes': readAt.timeZoneOffset.inMinutes,
      },
    ),
    extensions: {
      'captureAttemptId': attemptId,
      if (card.systemResults.isNotEmpty)
        'felicaSystems': captureFelicaSystems(card),
      'suica': {
        'version': 1,
        'idm': fingerprint.split(':').last,
        'identityKind': 'felica-idm',
        'systemCodes': card.systemCodes,
        'historyObserved': historyObserved,
        'records': [
          for (var i = 0; i < card.transactions.length; i++)
            {
              'rawHex': card.transactions[i].rawHex,
              'blockNumber': card.transactions[i].sequence,
              'timestamp': card.transactions[i].time?.millisecondsSinceEpoch,
              'balanceYen':
                  card.transactions[i].currency == 'JPY' &&
                      card.transactions[i].amountIsBalance
                  ? card.transactions[i].amountMinorUnits
                  : null,
              'amountMinorUnits': card.transactions[i].amountMinorUnits,
              'currencyCode': card.transactions[i].currency,
              'amountIsBalance': card.transactions[i].amountIsBalance,
              'decoded': card.transactions[i].decoded,
              'type': card.transactions[i].type,
              'note': card.transactions[i].note,
              'details': card.transactions[i].suica?.toJson(),
              if (i < view.suicaTrips.length)
                'presentation': view.suicaTrips[i].toJson(),
            },
        ],
        'wallets': [
          for (final wallet in card.wallets)
            {
              'id': wallet.walletId,
              'kind': wallet.kind.name,
              'balanceMinorUnits': wallet.balanceMinorUnits,
              'currencyCode': wallet.currency,
              'minorUnitDigits': wallet.fractionDigits,
              'readState': wallet.readState.name,
              'note': wallet.note,
              'errorMessage': wallet.errorMessage,
            },
        ],
        'statuses': [
          for (final status in card.statuses)
            {
              'stage': status.stage,
              'state': status.state.name,
              'message': status.message,
              'rawResponse': status.rawResponse,
              'failure': status.transportFailure?.toString(),
            },
        ],
      },
    },
    rawEvidence: [
      for (final issue in metadataIssues)
        {
          'kind': 'native_metadata_issue',
          'sessionId': attemptId,
          ...issue.toJson(),
        },
      for (final frame in frames) frame.toJson(),
      for (final frame in card.frames)
        {
          'kind': 'felica_frame',
          'stage': frame.stage,
          'command': frame.command,
          'response': frame.response,
          'error': frame.error?.toString(),
          'failure': frame.transportFailure?.toString(),
        },
      for (final block in card.rawBlocks)
        {
          'kind': 'felica_block',
          'label': block.label,
          'bytes': block.bytes,
          'error': block.error,
        },
      for (final tx in card.transactions)
        {
          'kind': 'suica_history',
          'serviceCode': '090F',
          'blockNumber': tx.sequence,
          'rawHex': tx.rawHex,
        },
    ],
  );
  return PendingCardSave(
    pendingSaveId: attemptId,
    readAt: readAt,
    fingerprint: fingerprint,
    identity: CardArchiveIdentity(
      cardType: CardTypes.suica,
      officialName: confirmed ? 'Suica' : null,
      identificationSource: CardIdentificationSources.parserOnly,
    ),
    balanceFen: balance,
    currencyCode: balance == null ? null : 'JPY',
    transactionCount: historyObserved ? card.transactions.length : null,
    sessionDataJson: snapshot.encode(),
  );
}
