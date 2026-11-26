import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_types.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';
import 'package:transit_card_analyzer/features/archive/domain/archive_context.dart';

void main() {
  test('历史过程余额与1A进站余额扣8元，金额和原始证据不变', () {
    final process = _processRecord();
    final rail = ArchiveHistoryRecord(
      kind: ArchiveRecordKind.rail,
      fields: {
        'status': 1,
        'entryTime': DateTime.utc(2026, 10, 28, 10).millisecondsSinceEpoch,
        'entryCityCode': '1000',
        'entryBalanceFen': 650,
        'entryAmountFen': 0,
        'rawHex': '0123',
      },
      context: _shanghaiContext,
      cardCityCode: '2900',
      sources: const [],
    );
    final original = jsonEncode([process.fields, rail.fields]);
    ArchiveHistoryRecord? diagnostics;
    final projection = presentArchiveTrips(
      [process, rail],
      includeShanghaiOverdraft: false,
      onDiagnostics: (record) => diagnostics = record,
    );
    final processEntry = projection.entries
        .where((entry) => entry.source == ArchiveRecordKind.process)
        .single;
    expect(processEntry.info.fields, contains(('记录余额', '¥ -5.00')));
    expect(processEntry.info.amountText, '-¥ 2.00');
    final evidence = processEntry.journeyEvent!.processBalance!;
    expect(evidence.recordedFen, 300);
    expect(evidence.amountFen, 200);
    expect(evidence.balanceOffsetFen, -800);
    expect(evidence.format(300), '¥ -5.00');
    final railEntry = projection.entries
        .where((entry) => entry.source == ArchiveRecordKind.rail)
        .single;
    expect(railEntry.info.fields, contains(('进站时余额', '¥ -1.50')));
    expect(railEntry.info.fields, contains(('进入时金额', '¥ 0.00')));
    processEntry.onDiagnostics!();
    expect(diagnostics, same(process));
    expect(jsonEncode([process.fields, rail.fields]), original);

    // A standalone formatter call keeps its previous raw display contract.
    final unchanged = presentArchiveTrips([process], onDiagnostics: (_) {});
    expect(unchanged.entries.single.info.fields, contains(('记录余额', '¥ 3.00')));
  });

  test('历史调整保留CU原始余额并遵循币种精度，未知余额保持未知', () {
    for (final (system, city, currency, digits, expected) in [
      ('city_union', '2000', 'CNY', 2, '¥ 3.00'),
      ('city_union', '1000', 'CNY', 2, '¥ 3.00'),
      ('tunion', '2000', 'CNY', 2, '¥ 3.00'),
      ('shanghai_tunion', '2900', 'HKD', 2, 'HK\$ 3.00'),
      ('shanghai_tunion', '2900', 'CNY', 0, '¥ 300'),
    ]) {
      final record = _processRecord(
        system: system,
        city: city,
        currency: currency,
        digits: digits,
      );
      final result = presentArchiveTrips(
        [record],
        includeShanghaiOverdraft: false,
        onDiagnostics: (_) {},
      );
      expect(result.entries.single.info.fields, contains(('记录余额', expected)));
    }
    final unknown = ArchiveHistoryRecord(
      kind: ArchiveRecordKind.transaction,
      fields: {
        'time': 1793190000000,
        'sequence': 20,
        'consume': true,
        'amountFen': 200,
        'balanceAfterFen': null,
        'balanceAfterIsRecorded': false,
      },
      context: _shanghaiContext,
      cardCityCode: '2900',
      sources: const [ArchiveRecordSource('batch', 'trips[0]', 8, null)],
    );
    final result = presentArchiveTrips(
      [unknown],
      includeShanghaiOverdraft: false,
      onDiagnostics: (_) {},
    );
    expect(
      result.entries.single.info.fields.where(
        (field) => field.$1.contains('余额'),
      ),
      isEmpty,
    );
  });

  test('历史记录的CU来源优先于保存的上海TU卡型，余额和金额均保持原值', () {
    for (final system in ['city_union', 'shanghai_tunion']) {
      final record = _processRecord(
        system: system,
        city: '2000',
        applicationId: 'A00000000386980701',
      );
      final original = jsonEncode(record.fields);
      final result = presentArchiveTrips(
        [record],
        cardType: CardTypes.shanghaiTransitUnion,
        includeShanghaiOverdraft: false,
        onDiagnostics: (_) {},
      );
      final entry = result.entries.single;
      expect(entry.info.fields, contains(('记录余额', '¥ 3.00')));
      expect(entry.info.amountText, '-¥ 2.00');
      expect(entry.journeyEvent!.processBalance!.recordedFen, 300);
      expect(entry.journeyEvent!.processBalance!.balanceOffsetFen, 0);
      expect(jsonEncode(record.fields), original);
    }
  });
}

const _shanghaiContext = ArchiveContext(
  systemId: 'shanghai_tunion',
  applicationId: 'A000000632010105',
  currencyCode: 'CNY',
  minorUnitDigits: 2,
);

ArchiveHistoryRecord _processRecord({
  String system = 'shanghai_tunion',
  String city = '2900',
  String currency = 'CNY',
  int digits = 2,
  String applicationId = 'A000000632010105',
}) => ArchiveHistoryRecord(
  kind: ArchiveRecordKind.process,
  fields: {
    'time': 1793190000000,
    'typeCode': 4,
    'terminalId': '000000000001',
    'appTypeCode': 1,
    'lineStationCode': '00020002',
    'amountFen': 200,
    'balanceFen': 300,
    'cityCode': '1000',
    'rawHex': 'ABCD',
  },
  context: ArchiveContext(
    systemId: system,
    applicationId: applicationId,
    currencyCode: currency,
    minorUnitDigits: digits,
  ),
  cardCityCode: city,
  sources: const [
    ArchiveRecordSource('batch', 'cycle[0]', 8, {
      'record': {
        'sfi': 0x1E,
        'recordNumber': 1,
        'recordNumberIsReliable': true,
        'rawHex': 'ABCD',
      },
    }),
  ],
);
