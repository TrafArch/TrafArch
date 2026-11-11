import '../../../protocols/bank/domain/models/tlv_node.dart';
import '../../../protocols/felica/protocol/felica_response.dart';
import '../../../protocols/transit/card_parser.dart';
import '../../../protocols/transit/city_union/city_union_models.dart';
import '../../../protocols/transit/local/local_card_models.dart';
import '../../../protocols/transit/tunion/tunion_models.dart';
import '../../../protocols/transit/tunion/tunion_reader.dart';
import '../../../shared/diagnostics/raw_data_category.dart';
import '../domain/card_read_outcome.dart';

/// Freeze decoder-owned fields while the acquisition result is still alive.
/// No current parser or reference data is consulted when an old log is exported.
Iterable<Map<String, Object?>> captureResponseFields(
  CardReadOutcome result,
  List<Map<String, Object?>> frames,
) sync* {
  for (final frame in frames) {
    final response = frame['response'] as List<int>?;
    final command = frame['command'] as List<int>;
    final felica = frame['transport'] == 'nfc-f';
    final sw = !felica && response != null && response.length >= 2
        ? (response[response.length - 2] << 8) | response.last
        : null;
    final base = <String, Object?>{
      'index': frame['index'],
      'command': command,
      'raw': response,
      'parserId': null,
      'fields': null,
      'state': response == null
          ? 'no_response'
          : response.isEmpty
          ? 'empty_response'
          : !felica && sw == null
          ? 'malformed'
          : !felica && sw != 0x9000
          ? 'status_only'
          : 'unparsed',
      if (!felica)
        'statusWord': sw?.toRadixString(16).padLeft(4, '0').toUpperCase(),
    };
    if (response == null || response.isEmpty || !felica && sw != 0x9000) {
      yield base;
      continue;
    }
    final body = felica ? response : response.sublist(0, response.length - 2);
    try {
      final decoded = switch (result) {
        TransitReadOutcome(:final card) => _transit(card, frame, body, command),
        BankReadOutcome() => _bank(result, frame, body, command),
        FelicaReadOutcome() => _felica(result, body, command),
        UnsupportedReadOutcome() => null,
      };
      yield {...base, ...?decoded};
    } catch (_) {
      // Diagnostics cannot turn a valid card read into a failure.
      yield {...base, 'state': 'unparsed'};
    }
  }
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
String _compact(String? value) =>
    (value ?? '').replaceAll(RegExp(r'\s'), '').toUpperCase();
bool _sameHex(List<int> bytes, String? hex) =>
    hex != null && _hex(bytes) == _compact(hex);
Map<String, Object?> _decoded(
  String parser,
  Map<String, Object?> fields, {
  String state = 'decoded',
}) => {'parserId': parser, 'state': state, 'fields': fields};

Map<String, Object?>? _transit(
  ParsedCard card,
  Map<String, Object?> frame,
  List<int> body,
  List<int> command,
) {
  if (frame['transport'] == 'nfc-f') return null;
  final coordinate = classifyRawCommand(command);
  final sfi = coordinate.sfi;
  final aid = _compact(frame['selectedApplication'] as String?);
  final stage = frame['protocolStage'] as String?;
  final tu = aid.startsWith('A0000006320101');
  final cu = aid == 'A00000000386980701';
  if (cu) {
    final matches = card.cityUnionFiles
        .where(
          (file) =>
              file.sfi == sfi &&
              _sameHex(body, file.rawHex) &&
              (file is! CityUnionWalletTransaction ||
                  file.recordNumber == coordinate.recordNumber),
        )
        .toList();
    if (matches.length == 1) {
      final file = matches.single;
      return _decoded(
        CardParserIds.cityUnion,
        file.toJson(),
        state: file.fields.isEmpty
            ? 'unparsed'
            : file.errors.isEmpty
            ? 'decoded'
            : 'partial',
      );
    }
    return null;
  }
  if (tu && CardParserIds.isTUnionFamily(card.parserId)) {
    // Only whole transparent files use these layouts; offset/chained chunks
    // cannot be interpreted as complete files.
    if (command.length >= 4 && command[1] == 0xB0 && command[3] == 0) {
      if (sfi == 0x15 && body.length >= 30 ||
          sfi == 0x16 && body.length >= 55 ||
          sfi == 0x17 && body.length >= 11) {
        final info = CommonUnitTu.decodeCardInfo(
          sfi == 0x15 ? body : null,
          sfi == 0x16 ? body : null,
          sfi == 0x17 ? body : null,
        );
        return _decoded(card.parserId, _tuInfo(info, sfi!));
      }
    }
    final processes = card.transitProcessRecords
        .where(
          (r) =>
              r.sfi == sfi &&
              r.recordNumber == coordinate.recordNumber &&
              _sameHex(body, r.rawHex),
        )
        .toList();
    if (command.length > 3 &&
        command[1] == 0xB2 &&
        (command[3] & 7) == 4 &&
        processes.length == 1) {
      final record = processes.single;
      return _decoded(
        card.parserId,
        processFields(record),
        state: record.isBlank
            ? 'blank'
            : record.isDecoded
            ? 'decoded'
            : 'unparsed',
      );
    }
    final transactions = card.transactions
        .where(
          (r) =>
              sfi == 0x18 &&
              r.recordNumber == coordinate.recordNumber &&
              _sameHex(body, r.rawHex),
        )
        .toList();
    if (command.length > 3 &&
        command[1] == 0xB2 &&
        (command[3] & 7) == 4 &&
        transactions.length == 1) {
      final r = transactions.single;
      return _decoded(card.parserId, {
        'sequence': r.sequence,
        'overdraftLimitFen': r.overdraftLimitFen,
        'amountFen': r.amountFen,
        'typeCode': r.rawType,
        'typeName': r.typeName,
        'terminalId': r.terminalId,
        'time': r.time.toIso8601String(),
      });
    }
    // Same pure numeric decoder as the TU reader. Do not infer currency or
    // conflate the separate overdraft observation with wallet balance.
    if (command.length >= 4 &&
        command[1] == 0x5C &&
        body.length == 4 &&
        command[2] == 0) {
      final value = body.fold<int>(0, (v, b) => (v << 8) | b);
      return _decoded(card.parserId, {
        'balanceFen': value,
        'role': 'wallet_observation',
      });
    }
    return null;
  }
  final local = card.localCard;
  if (local == null) return null;
  // Local parsers differ even when they share a file number. Match their own
  // retained bytes, command and stage, never the final parser alone.
  final expectedStage = local.info.isLNT
      ? '岭南通'
      : local.info.isBmac
      ? '北京市政交通一卡通（BMAC）'
      : local.info.isSZT
      ? '深圳通（PAY.SZT）'
      : null;
  if (tu || cu || expectedStage != null && stage != expectedStage) return null;
  final parser = local.info.isLNT
      ? CardParserIds.lingnanTong
      : local.info.isBmac
      ? CardParserIds.beijingBmac
      : CardParserIds.localCard;
  final records = local.records
      .where(
        (r) =>
            r.rawBody != null &&
            _sameHex(body, _hex(r.rawBody!)) &&
            (r.commandHex != null ||
                r.recordNumber > 0 && r.fileSelector > 0) &&
            (r.commandHex == null || _compact(r.commandHex) == _hex(command)) &&
            (r.recordNumber == 0 ||
                r.recordNumber == coordinate.recordNumber) &&
            (r.fileSelector == 0 ||
                command.length > 3 && r.fileSelector == command[3]),
      )
      .toList();
  if (records.length == 1 && records.single.type == 2) {
    return _decoded(parser, _localRecord(records.single, local));
  }
  final slots = local.extras.slots;
  if (local.info.isBmac) {
    if (command.length >= 4 && command[1] == 0xB0 && command[3] == 0) {
      if (_sameHex(body, slots['bmac.basicRaw'] as String?)) {
        return _decoded(parser, {
          'overdraftRaw': slots['bmac.overdraftRaw'],
          'transactionCount': slots['bmac.transactionCount'],
        });
      }
      if (_sameHex(body, slots['bmac.busRaw'] as String?)) {
        return _decoded(parser, {'bus': slots['bmac.bus']});
      }
    }
    if (command.length >= 4 &&
        command[1] == 0x5C &&
        _sameHex(body, slots['bmac.balanceRaw'] as String?)) {
      return _decoded(parser, {
        'balanceMinorUnits': local.info.observedBalance,
        'currency': local.info.currencyCode,
      });
    }
    final recharges = (slots['bmac.recharges'] as List? ?? const [])
        .where(
          (r) =>
              r is Map &&
              r['recordNumber'] == coordinate.recordNumber &&
              _sameHex(body, r['rawHex'] as String?),
        )
        .toList();
    if (command.length >= 4 &&
        command[1] == 0xB2 &&
        command[3] == 0x9C &&
        recharges.length == 1) {
      return _decoded(
        parser,
        Map<String, Object?>.from(recharges.single as Map),
      );
    }
  }
  if (local.info.isLNT &&
      command.length >= 4 &&
      command[1] == 0x5C &&
      slots['lnt.balanceRaw'] is List &&
      _hex(body) == _hex((slots['lnt.balanceRaw'] as List).cast<int>())) {
    return _decoded(parser, {
      'balanceMinorUnits': local.info.observedBalance,
      'currency': local.info.currencyCode,
    });
  }
  if (command.length >= 4 &&
      command[1] == 0xB0 &&
      local.info.rawInfo != null &&
      _sameHex(body, _hex(local.info.rawInfo!))) {
    final info = local.info;
    return _decoded(parser, {
      'cardNumber': info.cardNumber,
      'cardKind': info.cardKindLabel,
      'issuerCode': info.issuerCode,
      'issueDate': info.issueDate?.toIso8601String(),
      'expiryDate': info.expiryDate?.toIso8601String(),
    });
  }
  return null;
}

Map<String, Object?> _tuInfo(TUnionCardInfo info, int sfi) => switch (sfi) {
  0x15 => {
    'issuerId': info.issuerId,
    'appTypeId': info.appTypeId,
    'appVersion': info.appVersion,
    'applicationSerial': info.applicationSerial,
    'cardNumber': info.displayCardNumber,
    'effectiveDate': info.effectiveDate?.toIso8601String(),
    'expireDate': info.expireDate?.toIso8601String(),
    'issuerFci': info.issuerFci,
  },
  0x16 => {
    'cardTypeId': info.cardTypeId,
    'employeeFlag': info.employeeFlag,
    'holderNameHex': info.holderName,
    'idNumberHex': info.idNumber,
    'idType': info.idType,
  },
  _ => {
    'countryCode': info.countryCode,
    'provinceCode': info.provinceCode,
    'cityCode': info.cityCode,
    'interopCardType': info.interopCardType,
    'cardKind': info.cardKind,
  },
};

Map<String, Object?> processFields(TUnionProcessRecord record) {
  final trip = record.trip;
  final rail = record.railTransit;
  final bus = record.busTransit;
  return {
    'recordNumber': record.recordNumber,
    'recordNumberIsReliable': record.recordNumberIsReliable,
    if (trip != null) ...{
      'typeCode': trip.typeCode,
      'typeName': trip.typeName,
      'terminalId': trip.terminalId,
      'appTypeCode': trip.appTypeCode,
      'appTypeName': trip.appTypeName,
      'lineStationCode': trip.lineStationCode,
      'amountFen': trip.amountFen,
      'recordBalanceFen': trip.balanceFen,
      'time': trip.time.toIso8601String(),
      'cityCode': trip.cityCode,
      'acquirerId': trip.acquirerId,
    },
    if (rail != null) ...{
      'statusCode': rail.statusCode,
      'statusName': rail.statusName,
      'entryCityCode': rail.entryCityCode,
      'exitCityCode': rail.exitCityCode,
      'entryAgencyId': rail.entryAgencyId,
      'exitAgencyId': rail.exitAgencyId,
      'entryStationId': rail.entryStationId,
      'exitStationId': rail.exitStationId,
      'entryTerminalId': rail.entryTerminalId,
      'exitTerminalId': rail.exitTerminalId,
      'entryTime': rail.entryTime?.toIso8601String(),
      'exitTime': rail.exitTime?.toIso8601String(),
      'entryTimeBcd': rail.entryTimeBcd,
      'exitTimeBcd': rail.exitTimeBcd,
      'entryLineCode': rail.entryLineCode,
      'exitLineCode': rail.exitLineCode,
      'entryAmountFen': rail.entryAmountFen,
      'entryBalanceFen': rail.entryBalanceFen,
      'exitAmountFen': rail.exitAmountFen,
      'annotateAmountFen': rail.annotateAmountFen,
      'issuerCustom': rail.issuerCustom,
    },
    if (bus != null) ...{
      'statusCode': bus.statusCode,
      'statusName': bus.statusName,
      'entryCityCode': bus.entryCityCode,
      'exitCityCode': bus.exitCityCode,
      'entryAgencyId': bus.entryAgencyId,
      'exitAgencyId': bus.exitAgencyId,
      'entryOperatorCode': bus.entryOperatorCode,
      'exitOperatorCode': bus.exitOperatorCode,
      'entryLineCode': bus.entryLineCode,
      'exitLineCode': bus.exitLineCode,
      'entryStationCode': bus.entryStationCode,
      'exitStationCode': bus.exitStationCode,
      'entryTerminalId': bus.entryTerminalId,
      'exitTerminalId': bus.exitTerminalId,
      'entryVehicleId': bus.entryVehicleId,
      'exitVehicleId': bus.exitVehicleId,
      'entryTime': bus.entryTime?.toIso8601String(),
      'exitTime': bus.exitTime?.toIso8601String(),
      'entryTimeBcd': bus.entryTimeBcd,
      'exitTimeBcd': bus.exitTimeBcd,
      'annotateAmountFen': bus.annotateAmountFen,
      'transactionAmountFen': bus.transactionAmountFen,
      'directionCode': bus.directionCode,
      'directionName': bus.directionName,
      'mileage': bus.mileage,
      'issuerCustomHex': bus.issuerCustomHex,
    },
  };
}

Map<String, Object?> _localRecord(ApduRecord r, ReadResult result) => {
  'recordNumber': r.recordNumber,
  'typeCode': r.posType,
  'balanceDelta': r.balanceDelta,
  'terminalHex': r.terminalHex,
  'time': r.timestamp.millisecondsSinceEpoch == 0
      ? null
      : r.timestamp.toIso8601String(),
  'isMetro': r.isMetro,
  'isBus': r.isBus,
  if (result.info.isLNT) ...{
    'yearInferred': true,
    'secondsKnown': false,
    'metadata': [
      for (final value
          in result.extras.slots['lnt.transactions'] as List? ?? const [])
        if (value is Map && value['recordNumber'] == r.recordNumber) value,
    ],
  },
};

Map<String, Object?>? _bank(
  BankReadOutcome result,
  Map<String, Object?> frame,
  List<int> body,
  List<int> command,
) {
  final aid = _compact(frame['selectedApplication'] as String?);
  final c = classifyRawCommand(command);
  final matches = <Map<String, Object?>>[];
  for (final app in result.card.applications) {
    if (command.length >= 5 &&
        command[1] == 0xA4 &&
        command[2] == 4 &&
        command.length >= 5 + command[4] &&
        _hex(command.sublist(5, 5 + command[4])) ==
            _compact(app.application.aidHex) &&
        app.fciTags.isNotEmpty &&
        _sameHex(body, app.application.directoryFciHex)) {
      matches.add(
        _decoded(app.parserId, {
          'tags': [for (final tag in app.fciTags) _tag(tag)],
        }),
      );
    }
    if (aid != _compact(app.application.aidHex)) continue;
    if (command.length == 5 &&
        command[0] == 0x80 &&
        command[1] == 0xCA &&
        command[2] == 0x9F &&
        command[3] == 0x36 &&
        app.dataTags.length == 1 &&
        _hex(body) == '9F3602${app.dataTags.single.rawValueHex}') {
      matches.add(
        _decoded(app.parserId, {
          'tags': [for (final tag in app.dataTags) _tag(tag)],
        }),
      );
    }
    if (command.length >= 2 &&
        command[1] == 0xA8 &&
        _sameHex(body, app.gpoHex)) {
      matches.add(
        _decoded(app.parserId, {
          'tags': [for (final tag in app.gpoTags) _tag(tag)],
        }),
      );
    }
    for (final r in app.records) {
      if (r.sfi == c.sfi &&
          r.recordNumber == c.recordNumber &&
          _sameHex(body, r.rawHex)) {
        matches.add(
          _decoded(app.parserId, {
            'tags': [for (final tag in r.tags) _tag(tag)],
            'parseError': r.parseError,
          }, state: r.parseError == null ? 'decoded' : 'partial'),
        );
      }
    }
  }
  return matches.length == 1 ? matches.single : null;
}

Map<String, Object?> _tag(TlvNode node) => {
  'tag': node.tagHex,
  'length': node.length,
  'name': node.description,
  'value': node.decodedValue,
  'rawHex': node.rawValueHex,
  'children': [for (final child in node.children) _tag(child)],
};

Map<String, Object?>? _felica(
  FelicaReadOutcome result,
  List<int> response,
  List<int> command,
) {
  final parsed = FelicaResponse.parse(response);
  if (command.length < 2 || parsed.code != command[1] + 1) return null;
  if (result.card.idm != null &&
      _compact(result.card.idm) != _hex(parsed.idm)) {
    return null;
  }
  // Product data needs a proven block association; retain protocol header for
  // other frames rather than guessing a product field from a byte offset.
  return _decoded('felica.${result.card.cardProductType.name}', {
    'responseCode': parsed.code,
    'idm': _hex(parsed.idm),
    'payloadHex': _hex(parsed.data),
    'records': [
      for (final tx in result.card.transactions)
        if (parsed.code == 7 &&
            response.length >= 13 &&
            response[10] == 0 &&
            response[11] == 0 &&
            response.length == 13 + response[12] * 16 &&
            tx.decoded &&
            _compact(tx.rawHex).length == 32 &&
            [
              for (
                var offset = 13;
                offset + 16 <= response.length;
                offset += 16
              )
                _hex(response.sublist(offset, offset + 16)),
            ].contains(_compact(tx.rawHex)))
          {
            'sequence': tx.sequence,
            'time': tx.time?.toIso8601String(),
            'amountMinorUnits': tx.amountMinorUnits,
            'currency': tx.currency,
            'type': tx.type,
            'locationCode': tx.locationCode,
            'amountIsBalance': tx.amountIsBalance,
          },
    ],
  });
}
