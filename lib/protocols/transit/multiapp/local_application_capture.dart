import 'dart:typed_data';

import '../../transport/transport_failure.dart';

import '../local/local_card_models.dart';

/// Capture the local wallet's own identity, observations and records. The
/// raw application number stays separate from its human-facing number.
Map<String, dynamic> captureLocalApplication(ReadResult wallet) {
  final info = wallet.info;
  return {
    'kind': 'read_result',
    'isLocalCard': info.isLocalCard,
    'profiles': [
      if (info.isSuzhou) 'suzhou',
      if (info.isCika) 'cika',
      if (info.isSuxin) 'suxin',
      if (info.isTFT) 'tft',
      if (info.isLNT) 'lingnan',
      if (info.isSZT) 'shenzhen',
      if (info.isBeijing) 'beijing',
      if (info.isBmac) 'bmac',
      if (info.isMacauPass) 'macau',
      if (info.isWHCTC) 'wuhan',
      if (info.isYCT) 'yangcheng',
    ],
    if (info.cardNumber.isNotEmpty) 'cardNumber': info.cardNumber,
    'displayCardNumber': ?info.displayCardNumber,
    'balanceFen': ?info.observedBalance,
    'currencyCode': ?info.currencyCode,
    if (info.issuerCode.isNotEmpty) 'issuerCode': info.issuerCode,
    'remainingTrips': ?info.observedRemainingTrips,
    'issueDate': ?info.issueDate?.toIso8601String(),
    'expiryDate': ?info.expiryDate?.toIso8601String(),
    'rawInfo': ?info.rawInfo,
    if (wallet.extras.slots.isNotEmpty)
      'observations': captureLocalObservations(wallet.extras.slots),
    'records': [
      for (final record in wallet.records) captureLocalRecord(record),
    ],
  };
}

Map<String, Object?> captureLocalObservations(Map<String, Object?> slots) => {
  for (final e in slots.entries) e.key: _freezeSlots(e.value),
};

Object? _freezeSlots(Object? value) => switch (value) {
  DateTime date => date.toIso8601String(),
  Map map => {
    for (final e in map.entries) e.key.toString(): _freezeSlots(e.value),
  },
  List values => [for (final v in values) _freezeSlots(v)],
  _ => value,
};

Map<String, dynamic> captureLocalRecord(ApduRecord record) => {
  'directory': ?record.directory,
  'commandHex': ?record.commandHex,
  'label': ?record.label,
  'fileSelector': record.fileSelector,
  'recordNumber': record.recordNumber,
  'rawBody': ?(record.rawBody ?? record.response),
  if (record.rawBody != null &&
      record.response != null &&
      !_sameBytes(record.rawBody!, record.response!))
    'response': record.response,
  'type': record.type,
  'statusCode': record.statusCode,
  'posType': record.posType,
  'balanceDelta': record.balanceDelta,
  'tripDelta': ?record.tripDelta,
  'timestamp': record.timestamp.millisecondsSinceEpoch,
  if (record.timestamp.isUtc) 'utc': true,
  'cityCode': record.cityCode,
  'terminalHex': ?record.terminalHex,
  if (record.isMetro) 'isMetro': true,
  if (record.isBus) 'isBus': true,
  if (record.isFerry) 'isFerry': true,
  if (record.isOtherA) 'isOtherA': true,
  if (record.isOtherB) 'isOtherB': true,
  if (record.hasError) 'hasError': true,
};

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

ReadResult? restoreLocalApplication(
  Object? data, {
  Object? readError,
  TransportFailure? transportFailure,
}) {
  if (data is! Map || data['kind'] != 'read_result') return null;
  final info = CardInfo();
  if (data['cardNumber'] case final String n) info.cardNumber = n;
  if (data['displayCardNumber'] case final String n) info.displayCardNumber = n;
  if (data['currencyCode'] case final String c) info.currencyCode = c;
  if (data['issuerCode'] case final String c) info.issuerCode = c;
  if (data['balanceFen'] case final int n) info.balance = n;
  if (data['remainingTrips'] case final int n) info.remainingTrips = n;
  if (data['expiryDate'] case final String d) {
    info.expiryDate = DateTime.tryParse(d);
  }
  if (data['issueDate'] case final String d) {
    info.issueDate = DateTime.tryParse(d);
  }
  info.rawInfo = _bytes(data['rawInfo']);
  final extras = CardExtras();
  if (data['observations'] case final Map values) {
    for (final entry in values.entries) {
      if (entry.key case final String key) extras.slots[key] = entry.value;
    }
  }
  final profiles = data['profiles'];
  if (profiles is List) {
    info
      ..isSuzhou = profiles.contains('suzhou')
      ..isCika = profiles.contains('cika')
      ..isSuxin = profiles.contains('suxin')
      ..isTFT = profiles.contains('tft')
      ..isLNT = profiles.contains('lingnan')
      ..isSZT = profiles.contains('shenzhen')
      ..isBeijing = profiles.contains('beijing')
      ..isBmac = profiles.contains('bmac')
      ..isMacauPass = profiles.contains('macau')
      ..isWHCTC = profiles.contains('wuhan')
      ..isYCT = profiles.contains('yangcheng');
  }
  return ReadResult(
    info: info,
    extras: extras,
    readError: readError,
    transportFailure: transportFailure,
    records: [
      if (data['records'] case final List rows)
        for (final row in rows.whereType<Map>()) restoreApplicationRecord(row),
    ],
  );
}

ApduRecord restoreApplicationRecord(Map row) {
  String? text(String key) => row[key] is String ? row[key] as String : null;
  int number(String key) => row[key] is int ? row[key] as int : 0;
  final raw = _bytes(row['rawBody']);
  final timestamp = number('timestamp');
  return ApduRecord()
    ..directory = text('directory')
    ..commandHex = text('commandHex')
    ..label = text('label')
    ..fileSelector = number('fileSelector')
    ..recordNumber = number('recordNumber')
    ..type = number('type')
    ..statusCode = number('statusCode')
    ..posType = number('posType')
    ..balanceDelta = number('balanceDelta')
    ..tripDelta = row['tripDelta'] is int ? row['tripDelta'] as int : null
    ..cityCode = number('cityCode')
    ..terminalHex = text('terminalHex')
    ..isMetro = row['isMetro'] == true
    ..isBus = row['isBus'] == true
    ..isFerry = row['isFerry'] == true
    ..isOtherA = row['isOtherA'] == true
    ..isOtherB = row['isOtherB'] == true
    ..hasError = row['hasError'] == true
    ..timestamp = DateTime.fromMillisecondsSinceEpoch(
      timestamp.abs() <= 8640000000000000 ? timestamp : 0,
      isUtc: row['utc'] == true,
    )
    ..rawBody = raw
    ..response = _bytes(row['response']) ?? raw;
}

Uint8List? _bytes(Object? data) {
  if (data is! List || !data.every((b) => b is int && b >= 0 && b <= 255)) {
    return null;
  }
  return Uint8List.fromList(data.cast<int>());
}
