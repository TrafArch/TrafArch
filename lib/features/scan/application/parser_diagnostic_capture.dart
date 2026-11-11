import '../../../protocols/transit/card_parser.dart';
import '../../../protocols/bank/domain/models/tlv_node.dart';
import '../domain/card_read_outcome.dart';

/// Freeze the parser's final result at read time. These records also cover
/// fields which have no unique physical response (summaries and partial reads).
Iterable<Map<String, Object?>> captureParserRecords(
  CardReadOutcome outcome,
) sync* {
  switch (outcome) {
    case TransitReadOutcome(:final card):
      final parser = card.parserId;
      yield _record(parser, 'identity', {
        'parserName': card.parserName,
        'selectedAid': card.selectedAidHex,
        'cardNumber': card.localCard?.info.cardNumber.isNotEmpty == true
            ? card.localCard!.info.cardNumber
            : card.info.displayCardNumber,
        'applicationSerialRaw': card.info.applicationSerial,
        'issuerId': card.info.issuerId,
        'cardTypeId': card.info.cardTypeId,
        'cityCode': card.info.cityCode,
        'effectiveDate': card.info.effectiveDate?.toIso8601String(),
        'expireDate': card.info.expireDate?.toIso8601String(),
        'dualApplication': card.dualApplication,
      });
      yield _record(parser, 'balance', {
        'balanceFen': card.info.balanceFen,
        'overdraftQueryRawHex': card.info.overdraftQueryRawHex,
        'transactionFileObserved': card.transactionFileObserved,
      });
      for (final tx in card.transactions) {
        yield _record(parser, 'transactions', {
          'recordNumber': tx.recordNumber,
          'sequence': tx.sequence,
          'amountFen': tx.amountFen,
          'overdraftLimitFen': tx.overdraftLimitFen,
          'typeCode': tx.rawType,
          'typeName': tx.typeName,
          'terminalId': tx.terminalId,
          'time': tx.time.toIso8601String(),
          'rawHex': tx.rawHex,
        });
      }
      if (card.localCard case final local?) {
        yield _record(parser, 'localCardInfo', {
          'issuerCode': local.info.issuerCode,
          'issuerCode2': local.info.issuerCode2,
          'cityCode': local.info.cityCode,
          'cardKind': local.info.cardKindLabel,
          'cardTypeCode': local.info.cardTypeCode,
          'subtypeCode': local.info.subtypeCode,
          'issueDate': local.info.issueDate?.toIso8601String(),
          'expiryDate': local.info.expiryDate?.toIso8601String(),
          'rawInfo': local.info.rawInfo,
        });
        yield _record(parser, 'balance', {
          'balanceMinorUnits': local.info.observedBalance,
          'currency': local.info.currencyCode,
        });
        for (final r in local.records) {
          yield _record(parser, 'localRecords', {
            'commandHex': r.commandHex,
            'recordNumber': r.recordNumber,
            'fileSelector': r.fileSelector,
            'type': r.type,
            'typeCode': r.posType,
            'balanceDelta': r.balanceDelta,
            'balanceAfter': r.balanceAfter,
            'terminalHex': r.terminalHex,
            'time': r.timestamp.millisecondsSinceEpoch == 0
                ? null
                : r.timestamp.toIso8601String(),
            'cityCode': r.cityCode,
            'raw': r.rawBody?.toList(),
            'hasError': r.hasError,
          });
        }
      }
      // A dual-application card has a separate CU parser and wallet.
      if (parser != CardParserIds.cityUnion &&
          (card.cityUnionFiles.isNotEmpty || card.dualApplication)) {
        yield _record(CardParserIds.cityUnion, 'balance', {
          'balanceFen': card.cityUnionBalanceFen,
          'selectedAid': 'A00000000386980701',
        });
      }
      for (final file in card.cityUnionFiles) {
        yield _record(CardParserIds.cityUnion, 'files', file.toJson());
      }
    case BankReadOutcome(:final card):
      for (final app in card.applications) {
        final parser = app.parserId;
        final aid = app.application.aidHex;
        yield _record(parser, 'identity', {
          'aid': aid,
          'label': app.application.displayLabel,
          'selected': app.application.selected,
          'cardNumber': app.summary.pan,
          'panSourceTag': app.summary.panSourceTag,
          'expiry': app.summary.expiry,
          'expirySourceTag': app.summary.expirySourceTag,
        });
        for (final field in app.summary.fields) {
          yield _record(parser, 'summaryFields', {
            'aid': aid,
            'tag': field.tag,
            'label': field.label,
            'value': field.value,
            'rawHex': field.rawValueHex,
            'sensitive': field.sensitive,
          });
        }
        for (final (category, tags) in [
          ('fciTags', app.fciTags),
          ('dataTags', app.dataTags),
          ('gpoTags', app.gpoTags),
        ]) {
          if (tags.isNotEmpty) {
            yield _record(parser, category, {
              'aid': aid,
              'tags': [for (final tag in tags) _tag(tag)],
            });
          }
        }
        for (final record in app.records) {
          yield _record(parser, 'records', {
            'aid': aid,
            'sfi': record.sfi,
            'recordNumber': record.recordNumber,
            'rawHex': record.rawHex,
            'parseError': record.parseError,
            'tags': [for (final tag in record.tags) _tag(tag)],
          });
        }
        for (final issue in app.issues) {
          yield _record(parser, 'issues', {'aid': aid, ...issue.toJson()});
        }
      }
    case FelicaReadOutcome(:final card):
      final parser = 'felica.${card.cardProductType.name}';
      yield _record(parser, 'identity', {
        'cardType': card.cardType,
        'displayName': card.displayName,
        'idm': card.idm,
        'systemCodes': card.systemCodes,
        'state': card.state.name,
        'transitCapability': card.transitCapability,
      });
      for (final wallet in card.wallets) {
        yield _record(parser, 'wallets', {
          'walletId': wallet.walletId,
          'kind': wallet.kind.name,
          'name': wallet.name,
          'balanceMinorUnits': wallet.balanceVerified
              ? wallet.balanceMinorUnits
              : null,
          'currency': wallet.currency,
          'fractionDigits': wallet.fractionDigits,
          'readState': wallet.readState.name,
          'note': wallet.note,
          'errorMessage': wallet.errorMessage,
        });
      }
      for (final tx in card.transactions) {
        yield _record(parser, 'transactions', {
          'sequence': tx.sequence,
          'time': tx.time?.toIso8601String(),
          'amountMinorUnits': tx.amountMinorUnits,
          'currency': tx.currency,
          'walletKind': tx.walletKind.name,
          'type': tx.type,
          'locationCode': tx.locationCode,
          'rawHex': tx.rawHex,
          'decoded': tx.decoded,
          'amountIsBalance': tx.amountIsBalance,
          'crossBorder': tx.crossBorder,
          'note': tx.note,
        });
      }
      for (final status in card.statuses) {
        yield _record(parser, 'readStatus', {
          'stage': status.stage,
          'state': status.state.name,
          'message': status.message,
          'rawResponse': status.rawResponse,
        });
      }
      for (final block in card.rawBlocks) {
        yield _record(parser, 'rawBlocks', {
          'label': block.label,
          'raw': block.bytes,
          'error': block.error,
        });
      }
    case UnsupportedReadOutcome():
      break;
  }
}

Map<String, Object?> _record(
  String parserId,
  String category,
  Map<String, Object?> fields,
) => {'parserId': parserId, 'fieldCategory': category, 'fields': fields};

Map<String, Object?> _tag(TlvNode tag) => {
  'tag': tag.tagHex,
  'name': tag.description,
  'length': tag.length,
  'value': tag.decodedValue,
  'rawHex': tag.rawValueHex,
  'masked': tag.masked,
  'children': [for (final child in tag.children) _tag(child)],
};
