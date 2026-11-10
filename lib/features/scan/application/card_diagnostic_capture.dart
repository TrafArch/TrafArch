import '../../../protocols/transit/card_parser.dart';
import '../../../protocols/bank/domain/models/bank_card_result.dart';
import '../../../shared/diagnostics/raw_data_category.dart';
import '../domain/card_read_outcome.dart';
import 'response_diagnostic_capture.dart';

/// Uses already-read fields only. NFC UID/IDm never masquerades as a card number.
Map<String, Object?> captureCardInfo(CardReadOutcome result) =>
    switch (result) {
      TransitReadOutcome(:final card) => {
        'cardNumber': card.localCard?.info.cardNumber.isNotEmpty == true
            ? card.localCard!.info.cardNumber
            : card.info.displayCardNumber,
        'applicationSerialRaw': card.info.applicationSerial,
        'cardName': card.parserName,
        'cardType': card.parserId,
        'cardKindRaw': card.info.cardKind,
        'cardTypeRaw': card.info.cardTypeId,
        'parserId': card.parserId,
        'parserName': card.parserName,
        'selectedAid': card.selectedAidHex,
        'dualApplication': card.dualApplication,
        'identificationState': 'parser',
      },
      BankReadOutcome(:final card) => {
        'cardNumber': card.applications.firstOrNull?.summary.pan,
        'cardName': card.applications.firstOrNull?.application.displayLabel,
        'cardType':
            card.identifiedProtocolFamily == BankCardProtocolFamily.unknown
            ? null
            : card.identifiedProtocolFamily,
        'applications': [
          for (final application in card.applications)
            {
              'aid': application.application.aidHex,
              'cardNumber': application.summary.pan,
              'cardName': application.application.displayLabel,
              'parserId': application.parserId,
            },
        ],
        'identificationState':
            card.identifiedProtocolFamily == BankCardProtocolFamily.unknown
            ? 'unknown'
            : 'parser',
      },
      FelicaReadOutcome(:final card) => {
        'cardNumber': null,
        'idm': card.idm,
        'cardName': card.displayName,
        'cardType': card.cardType,
        'productType': card.cardProductType.name,
        'identificationState': 'parser',
      },
      UnsupportedReadOutcome() => {
        'cardNumber': null,
        'cardName': null,
        'cardType': null,
        'identificationState': 'unknown',
      },
    };

Iterable<Map<String, Object?>> captureProcessRecords(ParsedCard card) sync* {
  for (final record in card.transitProcessRecords) {
    yield {
      'application': 'transit',
      'parserId': card.parserId,
      'selectedAid': card.selectedAidHex,
      'sfi': record.sfi,
      'sfiHex': '0x${record.sfi.toRadixString(16).toUpperCase()}',
      'recordNumber': record.recordNumber,
      'recordNumberIsReliable': record.recordNumberIsReliable,
      'recordName': record.recordName,
      'category': classifyProcessRecord(record.sfi, record.recordNumber).name,
      'categoryLabel': classifyProcessRecord(
        record.sfi,
        record.recordNumber,
      ).label,
      'raw': record.raw,
      'rawHex': record.rawHex,
      'isBlank': record.isBlank,
      'isDecoded': record.isDecoded,
      'fields': record.isDecoded ? processFields(record) : null,
    };
  }
}
