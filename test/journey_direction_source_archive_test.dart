import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';

void main() {
  test('公交已解码线路随快照保存且旧原始线路不冒充解码证据', () {
    for (final decoded in [null, '345']) {
      final trip = TransitTrip(
        time: DateTime(2026, 10, 27, 8),
        amountFen: 200,
        overdraftLimitFen: 0,
        isConsume: true,
        typeName: '消费',
        sequence: 1,
        terminalId: '000000000001',
        lineLabel: decoded ?? '0010',
        resolvedBusLineLabel: decoded,
        appTypeName: '公共汽电车',
      );
      final json = CardSessionSnapshot(
        parseVersion: kTripParseVersion,
        trips: [trip],
      ).encode();
      final restored = CardSessionSnapshot.decode(json)!;
      expect(restored.trips.single.resolvedBusLineLabel, decoded);
      expect(restored.trips.single.lineLabel, decoded ?? '0010');
      expect(restored.encode(), json);
    }
  });

  test('保存和恢复上海方向推断来源，旧快照未知来源保持null', () {
    final trip = TransitTrip(
      time: DateTime(2026, 10, 24, 23, 4, 4),
      amountFen: 400,
      overdraftLimitFen: 0,
      isConsume: true,
      typeName: '复合消费',
      sequence: 14,
      terminalId: '200011012618',
      rideStatusName: '出站',
      rideStatusSource: 'shanghai-cu-ledger-inference',
    );
    final snapshot = CardSessionSnapshot(
      parseVersion: kTripParseVersion,
      trips: [trip],
    );
    final json = snapshot.encode();
    final restored = CardSessionSnapshot.decode(json)!;
    expect(
      restored.trips.single.rideStatusSource,
      'shanghai-cu-ledger-inference',
    );
    final old = jsonDecode(json) as Map<String, dynamic>;
    (old['trips'] as List).single.remove('rideStatusSource');
    final oldText = jsonEncode(old);
    final decoded = CardSessionSnapshot.decode(oldText)!;
    expect(decoded.trips.single.rideStatusSource, isNull);
    expect(decoded.encode(), oldText);
  });
}
