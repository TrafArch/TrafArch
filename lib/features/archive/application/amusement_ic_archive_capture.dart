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

/// Capture an already decoded game-card identity without replaying card data.
/// An incomplete read cannot create a second IDm-based archive or erase a code.
PendingCardSave? captureAmusementIcArchive(
  ScanPresentation view,
  String attemptId,
  DateTime readAt,
  List<CapturedFrame> frames,
  List<NfcMetadataIssue> metadataIssues,
) {
  final card = view.felicaResult;
  if (card == null || card.cardProductType != FelicaCardType.amusementIc) {
    return null;
  }
  final data = card.amusementIc;
  final fingerprint = CardFingerprint.buildAmusementIc(data?.accessCode);
  final issuer = data?.issuer;
  if (data == null ||
      fingerprint == null ||
      issuer == null ||
      issuer.trim().isEmpty ||
      AmusementIcData.fromJson(data.toJson()) == null) {
    return null;
  }
  final snapshot = CardSessionSnapshot(
    parseVersion: kTripParseVersion,
    context: const ArchiveContext(
      systemId: 'felica_amusement_ic',
      applicationId: 'felica-system:88B4/service:000B',
      observedFields: {
        'cardNumber': false,
        'balanceFen': false,
        'transactionCount': false,
        'accessCode': true,
        'issuerName': true,
      },
    ),
    extensions: {
      'captureAttemptId': attemptId,
      if (card.systemResults.isNotEmpty)
        'felicaSystems': captureFelicaSystems(card),
      'amusementIc': {
        'version': 1,
        'identityKind': 'amusement-ic-access-code',
        'data': data.toJson(),
        'idm': card.idm,
        'systemCodes': card.systemCodes,
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
      if (data.idBlockHex != null)
        {
          'kind': 'amusement_ic_block',
          'serviceCode': '000B',
          'block': '82',
          'rawHex': data.idBlockHex,
        },
      if (data.spad0Hex != null)
        {
          'kind': 'amusement_ic_block',
          'serviceCode': '000B',
          'block': '00',
          'rawHex': data.spad0Hex,
        },
    ],
  );
  return PendingCardSave(
    pendingSaveId: attemptId,
    readAt: readAt,
    fingerprint: fingerprint,
    identity: CardArchiveIdentity(
      cardType: CardTypes.amusementIc,
      officialName: 'Amusement IC（$issuer）',
      issuerName: issuer,
      identificationSource: CardIdentificationSources.parserOnly,
    ),
    sessionDataJson: snapshot.encode(),
  );
}
