import '../../../protocols/transit/card_parser.dart';
import '../../../protocols/transit/tunion/tunion_codec.dart';
import '../../../protocols/transit/tunion/tunion_process_parser.dart';
import 'archive_context.dart';

/// Derive money for the verified Shenyang EP layout without changing a capture.
/// Old parsers saved these two little-endian fields as big-endian integers.
/// A complete raw record, matching identity and civil time, and compatible
/// captured integers are all required; unrelated or edited data stays captured.
({int amountFen, int balanceFen})? verifiedArchivedCycleMoney(
  Map<String, dynamic> fields,
  ArchiveContext context,
) {
  if (context.systemId != CardParserIds.tunion ||
      context.applicationId != 'A000000632010105' ||
      context.currencyCode != 'CNY' ||
      context.minorUnitDigits != 2) {
    return null;
  }
  final raw = fields['rawHex'];
  if (raw is! String || !RegExp(r'^[0-9a-fA-F]{96}$').hasMatch(raw)) {
    return null;
  }
  final bytes = [
    for (var i = 0; i < raw.length; i += 2)
      int.parse(raw.substring(i, i + 2), radix: 16),
  ];
  final decoded = const TUnionProcessParser().parseCycleTrip(bytes);
  if (decoded == null ||
      (decoded.typeCode != 0x03 && decoded.typeCode != 0x04) ||
      decoded.appTypeCode != 0x01 ||
      decoded.cityCode != '2210' ||
      !decoded.terminalId.startsWith('22104131') ||
      decoded.acquirerId != '1217221000000000' ||
      fields['typeCode'] != decoded.typeCode ||
      fields['terminalId'] != decoded.terminalId ||
      fields['appTypeCode'] != decoded.appTypeCode ||
      fields['lineStationCode'] != decoded.lineStationCode ||
      fields['cityCode'] != decoded.cityCode ||
      fields['acquirerId'] != decoded.acquirerId) {
    return null;
  }

  final time = decoded.time;
  final nominal = DateTime.utc(
    time.year,
    time.month,
    time.day,
    time.hour,
    time.minute,
    time.second,
  );
  final epoch = fields['time'];
  final captured = fields['capturedTimes'];
  final representation = captured is Map ? captured['time'] : null;
  if (epoch is! int || representation is! Map) return null;
  final civil = representation['civil'];
  if (civil is! String) return null;
  final match = RegExp(
    r'^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.0{1,6})?(Z)?$',
  ).firstMatch(civil);
  if (match == null ||
      match.group(1) != nominal.toIso8601String().substring(0, 19)) {
    return null;
  }
  final utc =
      representation['basis'] == 'utc' ||
      representation['isUtc'] == true ||
      match.group(2) != null;
  final local =
      representation['basis'] == 'parser-local-unverified' ||
      representation['isUtc'] == false;
  if (utc && local) return null;
  final capturedOffset = representation['conversionOffsetMinutes'];
  final offset = capturedOffset ?? (utc ? 0 : context.timeZoneOffsetMinutes);
  if (offset is! int ||
      offset < -1440 ||
      offset > 1440 ||
      (utc && offset != 0) ||
      epoch != nominal.millisecondsSinceEpoch - offset * 60000) {
    return null;
  }

  bool matchesMoney(String key, int corrected, int start) {
    final value = fields[key];
    return value is int &&
        (value == corrected || value == TUnionCodec.beInt(bytes, start, 4));
  }

  if (!matchesMoney('amountFen', decoded.amountFen, 0x11) ||
      !matchesMoney('balanceFen', decoded.balanceFen, 0x15)) {
    return null;
  }
  return (amountFen: decoded.amountFen, balanceFen: decoded.balanceFen);
}
