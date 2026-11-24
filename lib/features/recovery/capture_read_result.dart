import '../../protocols/felica/models/felica_capture.dart';
import '../../protocols/transit/multiapp/local_application_capture.dart';
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
            'displayCardNumber': ?local.info.displayCardNumber,
            if (local.info.isCika) 'countWallet': true,
            'remainingTrips': ?local.info.observedRemainingTrips,
            'expiryDate': ?local.info.expiryDate?.toIso8601String(),
            'issuerCode': local.info.issuerCode,
            'issuerCode2': local.info.issuerCode2,
            'currencyCode': local.info.currencyCode,
            'balance': local.info.observedBalance,
            'rawInfo': local.info.rawInfo,
            'extras': captureLocalObservations(local.extras.slots),
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
      FelicaReadOutcome(:final card) => captureFelicaResult(card),
      UnsupportedReadOutcome() => const {},
    };
