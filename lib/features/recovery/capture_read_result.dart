import '../../protocols/bank/domain/models/tlv_node.dart';
import '../scan/domain/card_read_outcome.dart';

/// Freeze fields already produced by the reader. No protocol replay on restart.
Map<String, Object?> captureReadResult(CardReadOutcome result) =>
    switch (result) {
      TransitReadOutcome(:final card) => {
        'parserId': card.parserId,
        'parserName': card.parserName,
        'selectedAidHex': card.selectedAidHex,
        'transactionFileObserved': card.transactionFileObserved,
        'dualApplication': card.dualApplication,
        'cityUnionBalanceFen': card.cityUnionBalanceFen,
        'info': {
          'issuerId': card.info.issuerId,
          'appTypeId': card.info.appTypeId,
          'appVersion': card.info.appVersion,
          'applicationSerial': card.info.applicationSerial,
          'effectiveDate': card.info.effectiveDate?.toIso8601String(),
          'expireDate': card.info.expireDate?.toIso8601String(),
          'issuerFci': card.info.issuerFci,
          'cardTypeId': card.info.cardTypeId,
          'employeeFlag': card.info.employeeFlag,
          'holderName': card.info.holderName,
          'idNumber': card.info.idNumber,
          'idType': card.info.idType,
          'countryCode': card.info.countryCode,
          'provinceCode': card.info.provinceCode,
          'cityCode': card.info.cityCode,
          'interopCardType': card.info.interopCardType,
          'cardKind': card.info.cardKind,
          'balanceFen': card.info.balanceFen,
          'overdraftQueryRawHex': card.info.overdraftQueryRawHex,
        },
        'transactions': [
          for (final tx in card.transactions)
            {
              'sequence': tx.sequence,
              'overdraftLimitFen': tx.overdraftLimitFen,
              'amountFen': tx.amountFen,
              'rawType': tx.rawType,
              'terminalId': tx.terminalId,
              'time': tx.time.toIso8601String(),
              'recordNumber': tx.recordNumber,
              'rawHex': tx.rawHex,
            },
        ],
        'cityUnionFiles': [
          for (final file in card.cityUnionFiles) file.toJson(),
        ],
        'processRecords': [
          for (final record in card.transitProcessRecords)
            {
              'sfi': record.sfi,
              'recordNumber': record.recordNumber,
              'recordNumberIsReliable': record.recordNumberIsReliable,
              'rawHex': record.rawHex,
              'isBlank': record.isBlank,
              'isDecoded': record.isDecoded,
            },
        ],
        if (card.localCard case final local?)
          'localCard': {
            'cardNumber': local.info.cardNumber,
            'issuerCode': local.info.issuerCode,
            'issuerCode2': local.info.issuerCode2,
            'currencyCode': local.info.currencyCode,
            'balance': local.info.observedBalance,
            'rawInfo': local.info.rawInfo,
            'extras': local.extras.slots,
            'readError': local.readError?.toString(),
            'records': [
              for (final record in local.records)
                {
                  'commandHex': record.commandHex,
                  'response': record.response,
                  'label': record.label,
                  'fileSelector': record.fileSelector,
                  'recordNumber': record.recordNumber,
                  'rawBody': record.rawBody,
                  'hasError': record.hasError,
                },
            ],
          },
      },
      BankReadOutcome(:final card) => {
        ...card.toJson(),
        'applications': [
          for (final app in card.applications)
            {
              'aid': app.application.aidHex,
              'label': app.application.displayLabel,
              'parserId': app.parserId,
              'summary': [
                for (final field in app.summary.fields)
                  {
                    'tag': field.tag,
                    'label': field.label,
                    'value': field.value,
                    'rawValueHex': field.rawValueHex,
                    'sensitive': field.sensitive,
                  },
              ],
              'fci': [for (final tag in app.fciTags) _tag(tag)],
              'gpo': [for (final tag in app.gpoTags) _tag(tag)],
              'gpoHex': app.gpoHex,
              'records': [
                for (final record in app.records)
                  {
                    'sfi': record.sfi,
                    'recordNumber': record.recordNumber,
                    'rawHex': record.rawHex,
                    'parseError': record.parseError,
                    'tags': [for (final tag in record.tags) _tag(tag)],
                  },
              ],
              'issues': [for (final issue in app.issues) issue.toJson()],
            },
        ],
      },
      FelicaReadOutcome(:final card) => {
        'cardType': card.cardType,
        'productType': card.cardProductType.name,
        'idm': card.idm,
        'systemCodes': card.systemCodes,
        'scannedAt': card.scannedAt.toIso8601String(),
        'transitCapability': card.transitCapability,
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
      },
      _ => const {},
    };

Map<String, Object?> _tag(TlvNode tag) => {
  'tag': tag.tagHex,
  'length': tag.length,
  'rawValueHex': tag.rawValueHex,
  'description': tag.description,
  'decodedValue': tag.decodedValue,
  'masked': tag.masked,
  'children': [for (final child in tag.children) _tag(child)],
};
