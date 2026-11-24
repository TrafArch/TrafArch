import 'felica_models.dart';

/// Frozen, system-bound evidence shared by both history and recovery. Older
/// single-system captures have no systemResults key.
Map<String, Object?> captureFelicaSystems(FelicaScanResult card) => {
  for (final entry in card.systemResults.entries)
    entry.key.toRadixString(16).toUpperCase().padLeft(4, '0'):
        captureFelicaResult(entry.value, includeFrames: true),
};

Map<String, Object?> captureFelicaResult(
  FelicaScanResult card, {
  bool includeFrames = false,
}) => {
  'cardType': card.cardType,
  'displayName': card.displayName,
  'state': card.state.name,
  'stateText': card.state.label,
  if (card.systemResults.isNotEmpty)
    'systemResults': captureFelicaSystems(card),
  if (includeFrames)
    'frames': [
      for (final frame in card.frames)
        {
          'stage': frame.stage,
          'command': frame.command,
          'response': frame.response,
          'error': frame.error?.toString(),
          'failure': frame.transportFailure?.kind.name,
        },
    ],
  'productType': card.cardProductType.name,
  'idm': card.idm,
  'systemCodes': card.systemCodes,
  'scannedAt': card.scannedAt.toIso8601String(),
  'transitCapability': card.transitCapability,
  if (card.amusementIc case final data?) 'amusementIc': data.toJson(),
  'wallets': [
    for (final wallet in card.wallets)
      {
        'id': wallet.walletId,
        'kind': wallet.kind.name,
        'name': wallet.name,
        'balanceMinorUnits': wallet.balanceMinorUnits,
        'currency': wallet.currency,
        'fractionDigits': wallet.fractionDigits,
        'readState': wallet.readState.name,
        'balanceText': wallet.balanceText,
        'note': wallet.note,
        'errorMessage': wallet.errorMessage,
      },
  ],
  'transactions': [
    for (final tx in card.transactions)
      {
        'time': tx.time?.toIso8601String(),
        'amountMinorUnits': tx.amountMinorUnits,
        'currency': tx.currency,
        'type': tx.type,
        'locationCode': tx.locationCode,
        'rawHex': tx.rawHex,
        'decoded': tx.decoded,
        'sequence': tx.sequence,
        'note': tx.note,
        'walletKind': tx.walletKind.name,
        'amountIsBalance': tx.amountIsBalance,
        if (tx.suica != null) 'suica': tx.suica!.toJson(),
        'crossBorder': tx.crossBorder,
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
  'rawBlocks': [
    for (final block in card.rawBlocks)
      {'label': block.label, 'bytes': block.bytes, 'error': block.error},
  ],
  if (card.crossBorder case final info?)
    'crossBorder': {
      'sourceCurrency': info.sourceCurrency,
      'targetCurrency': info.targetCurrency,
      'numerator': info.exchangeRateNumerator,
      'denominator': info.exchangeRateDenominator,
      'updatedAt': info.rateUpdatedAt?.toIso8601String(),
      'expiresAt': info.rateExpiresAt?.toIso8601String(),
    },
};
