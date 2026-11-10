import '../../../protocols/transit/card_parser.dart';
import '../../../protocols/transit/tunion/tunion_codec.dart';
import '../../../protocols/transit/tunion/tunion_process_parser.dart';
import '../../trips/journey_presentation.dart';
import '../application/archive_history.dart';
import 'archive_journey_identity.dart';

// v13 first persisted the verified local 0x15/0x16 direction semantics.
// Newer writers' deliberate unknowns must not be reinterpreted by this bridge.
const _firstLocalDirectionCaptureVersion = 13;

/// A saved display link is not operation proof on its own. Older captures can
/// omit a direction that is now understood, but only complete, mutually
/// consistent raw operations may supply that missing presentation role.
/// This never supplies money, a matchedProcess, or a cross-capture pairing.
JourneyEventRole? verifiedLegacyCycleRole(
  ArchiveHistoryRecord transaction,
  ArchiveHistoryRecord process, {
  required DateTime? civilTime,
}) {
  final fields = transaction.fields;
  if (transaction.kind != ArchiveRecordKind.transaction ||
      process.kind != ArchiveRecordKind.process ||
      !CardParserIds.isTUnionFamily(
        archiveJourneySystemId(transaction.context),
      ) ||
      transaction.sources.isEmpty ||
      transaction.sources.any(
        (source) =>
            source.capturedParseVersion >= _firstLocalDirectionCaptureVersion,
      ) ||
      fields['rideStatusName'] != null ||
      fields['rideStatusSource'] != null ||
      fields['matchedProcess'] != null ||
      fields['isEntry'] == true ||
      fields['consume'] != true ||
      fields['composite'] != true ||
      civilTime == null) {
    return null;
  }
  final basic = _bytes(fields['rawHex'], 23);
  final extended = _bytes(process.fields['rawHex'], 48);
  if (basic == null || extended == null || basic[9] != 0x09) return null;
  final decoded = const TUnionProcessParser().parseCycleTrip(extended);
  final basicTime = TUnionCodec.parseBcdDateTime(basic.sublist(16, 23));
  final terminal = TUnionCodec.bcdString(basic.sublist(10, 16));
  if (decoded == null || basicTime == null || terminal == null) return null;
  final captured = process.fields;
  final decodedFields = {
    'typeCode': decoded.typeCode,
    'terminalId': decoded.terminalId,
    'appTypeCode': decoded.appTypeCode,
    'lineStationCode': decoded.lineStationCode,
    'amountFen': decoded.amountFen,
    'balanceFen': decoded.balanceFen,
    'cityCode': decoded.cityCode,
    'acquirerId': decoded.acquirerId,
  };
  if (decodedFields.entries.any(
        (field) => captured[field.key] != field.value,
      ) ||
      fields['sequence'] != TUnionCodec.beInt(basic, 0, 2) ||
      fields['overdraftFen'] != TUnionCodec.beInt(basic, 2, 3) ||
      fields['amountFen'] != TUnionCodec.beInt(basic, 5, 4) ||
      fields['amountFen'] != decoded.amountFen ||
      fields['terminalId'] != terminal ||
      RegExp(r'^0+$|^F+$').hasMatch(terminal) ||
      (decoded.terminalId != '0000$terminal' &&
          decoded.terminalId != '${decoded.cityCode}$terminal') ||
      _civil(basicTime) != civilTime ||
      _civil(decoded.time) != civilTime) {
    return null;
  }
  return switch (decoded.journeyTypeCode) {
    1 ||
    3 when decoded.isRailTransit || decoded.isBus => JourneyEventRole.entry,
    2 || 4 when decoded.isRailTransit || decoded.isBus => JourneyEventRole.exit,
    _ => null,
  };
}

DateTime _civil(DateTime time) => DateTime.utc(
  time.year,
  time.month,
  time.day,
  time.hour,
  time.minute,
  time.second,
);

List<int>? _bytes(Object? value, int length) {
  if (value is! String) return null;
  final hex = value.replaceAll(RegExp(r'\s+'), '').toUpperCase();
  if (hex.length != length * 2 || !RegExp(r'^[0-9A-F]+$').hasMatch(hex)) {
    return null;
  }
  return [
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
}
