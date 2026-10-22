import '../../protocols/transit/tunion/tunion_models.dart';
import '../reference_data/data/tunion_bus_location.dart';
import '../reference_data/domain/tunion_bus_caller.dart';

({int classification, int carrier}) _busCallerForCycle(
  TUnionTripRecord record,
) {
  final city = record.cityCode ?? '';
  final classification = TunionBusCaller.classification(
    city: city,
    terminal: record.terminalId,
    field: record.lineStationCode,
    industry: record.appTypeCode,
    type: record.typeCode,
    signedAmountFen: -record.amountFen,
    rawHex: record.rawHex,
  );
  return (
    classification: classification,
    carrier: TunionBusCaller.carrier(
      city: city,
      terminal: record.terminalId,
      field: record.lineStationCode,
      classification: classification,
    ),
  );
}

/// Standard bus records plus source-proven city/terminal industry exceptions.
/// Source carrier 13 still remains bus/BRT evidence, but cannot decode a route.
bool isTunionBusCycle(TUnionTripRecord record) {
  final caller = _busCallerForCycle(record);
  return record.isBus ||
      caller.carrier == 1 ||
      (caller.classification == 1 && caller.carrier != 13);
}

/// Original m793j city corrections before route/station lookup. The raw
/// [TUnionTripRecord.cityCode] stays intact as provenance; only this derived
/// acquirer city is normalized. Ported rules are the source-verified aliases
/// whose target has packaged station data, plus the 5230/5930 pair.
const _acquirerCityAliases = <String, String>{
  '1160': '2220',
  '2140': '3020',
  '6500': '7310',
  '7100': '7910',
};

String? normalizeTunionAcquirerCity(String? cityCode, {int? rawCity36}) {
  if (cityCode == null) return null;
  if (cityCode == '5230' && rawCity36 == 5930) return '6020';
  return _acquirerCityAliases[cityCode] ?? cityCode;
}

/// City pair from the record's own raw bytes at [offset]. The original reader
/// uses this same arithmetic, including non-BCD nibbles. Missing raw bytes
/// remain absent rather than becoming zero.
int? cycleCityPair(TUnionTripRecord record, int offset) {
  final raw = record.rawHex?.replaceAll(RegExp(r'\s+'), '');
  if (raw == null ||
      raw.length < (offset + 2) * 2 ||
      !RegExp(r'^[0-9A-Fa-f]+$').hasMatch(raw)) {
    return null;
  }
  int byte(int index) =>
      int.parse(raw.substring(index * 2, index * 2 + 2), radix: 16);
  int originalBcd(int value) => value - (value ~/ 16) * 6;
  return originalBcd(byte(offset)) * 100 + originalBcd(byte(offset + 1));
}

/// Original m764r inputs taken from this record, never from the issuing card.
/// The two city pairs use the original byte conversion arithmetic, including
/// non-BCD nibbles. Missing raw bytes remain absent rather than becoming zero.
TunionBusDecodeContext busContextForCycle(TUnionTripRecord record) {
  final shenzhenOverride =
      record.cityCode == '5840' &&
      record.terminalId.length == 16 &&
      record.terminalId.startsWith('00000002');
  final caller = _busCallerForCycle(record);
  return TunionBusDecodeContext(
    rawCity32: shenzhenOverride ? 5840 : cycleCityPair(record, 32),
    rawCity36: shenzhenOverride ? 5840 : cycleCityPair(record, 36),
    // TripReader stores the 1E consumption delta with the opposite sign to the
    // unsigned protocol amount. Several route branches compare this value.
    amountFen: -record.amountFen,
    transactionTime: record.time,
    terminalId: record.terminalId,
    carrierCode: caller.carrier,
    routeFallbackAllowed: TunionBusCaller.routeFallbackAllowed(
      caller.classification,
      caller.carrier,
    ),
  );
}
