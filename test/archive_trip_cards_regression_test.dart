import 'dart:convert';

import 'package:transit_card_analyzer/features/archive/application/card_records_export.dart';

import 'package:transit_card_analyzer/features/archive/presentation/archive_record_presenter.dart';

import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_identity.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_types.dart';

import 'support/test_database.dart';

void main() {
  test('old cached balances derive from raw process on every projection', () {
    for (final (type, expected) in [
      (6, 100),
      (9, 100),
      (10, 100),
      (255, 100),
      (255, 0),
    ]) {
      final process = {
        ..._process,
        'typeCode': type,
        'amountFen': 100,
        'balanceFen': expected,
        'rawHex': 'ABCD',
      };
      final fields = {
        ..._transaction(),
        'balanceAfterFen': 999,
        'matchedProcess': process,
      };
      final original = jsonEncode(_snapshot(trips: [fields]));
      var restored = CardSessionSnapshot.decode(original)!;
      for (var i = 0; i < 3; i++) {
        expect(restored.trips.single.balanceAfterFen, expected);
        expect(restored.trips.single.matchedProcessTrip!.balanceFen, expected);
        expect(restored.encode(), original);
        restored = CardSessionSnapshot.decode(restored.encode())!;
        for (final kind in [
          ArchiveRecordKind.transaction,
          ArchiveRecordKind.process,
        ]) {
          final record = ArchiveHistoryRecord(
            kind: kind,
            fields: Map<String, dynamic>.from(
              kind == ArchiveRecordKind.transaction ? fields : process,
            ),
            context: const ArchiveContext(
              currencyCode: 'CNY',
              minorUnitDigits: 2,
            ),
            sources: const [],
          );
          final info = presentArchiveTrips([
            record,
          ], onDiagnostics: (_) {}).entries.single.info;
          expect(info.subText, '记录余额 ${record.context.formatAmount(expected)}');
          expect(
            info.fields.where((f) => f.$1 == '记录余额').single.$2,
            record.context.formatAmount(expected),
          );
          expect(
            archiveRecordText(record),
            contains('记录余额 ${record.context.formatAmount(expected)}'),
          );
          if (kind == ArchiveRecordKind.process && (type == 9 || type == 10)) {
            expect(info.amountText, startsWith('+'));
            expect(info.isConsume, isFalse);
          }
        }
      }
      expect(fields['balanceAfterFen'], 999);
      expect(process['balanceFen'], expected);
      expect(process['rawHex'], 'ABCD');
      expect(jsonEncode(_snapshot(trips: [fields])), original);
    }
    final unmatched = CardSessionSnapshot.decode(
      jsonEncode(_snapshot(trips: [_transaction()])),
    )!;
    expect(unmatched.trips.single.balanceAfterFen, 1234);
  });
  test('v6 balance labels distinguish reconstructed from recorded', () {
    const context = ArchiveContext(currencyCode: 'CNY', minorUnitDigits: 2);
    ArchiveHistoryRecord record(Map<String, dynamic> fields, int parser) =>
        ArchiveHistoryRecord(
          kind: ArchiveRecordKind.transaction,
          fields: fields,
          context: context,
          sources: [ArchiveRecordSource('b1', 'trips[0]', parser, null)],
        );

    final computed = {..._transaction(), 'balanceAfterFen': 9000};
    final computedRecord = record(computed, 6);
    expect(archiveRecordBalanceFen(computedRecord), 9000);
    expect(archiveRecordBalanceIsRecorded(computedRecord), isFalse);
    expect(archiveRecordText(computedRecord), contains('交易后余额 ¥ 90.00'));
    final computedInfo = presentArchiveTrips([
      computedRecord,
    ], onDiagnostics: (_) {}).entries.single.info;
    expect(computedInfo.fields, contains(('交易后余额', '¥ 90.00')));
    expect(computedInfo.subText, '交易后余额 ¥ 90.00');

    final process = {..._process, 'balanceFen': 100};
    final recordedRecord = record({
      ..._transaction(),
      'balanceAfterFen': 100,
      'matchedProcess': process,
    }, 6);
    expect(archiveRecordBalanceFen(recordedRecord), 100);
    expect(archiveRecordBalanceIsRecorded(recordedRecord), isTrue);
    expect(archiveRecordText(recordedRecord), contains('记录余额 ¥ 1.00'));

    // v5 没有倒推口径：保存值仍按记录余额展示。
    final legacyRecord = record(computed, 5);
    expect(archiveRecordBalanceIsRecorded(legacyRecord), isTrue);
    expect(archiveRecordText(legacyRecord), contains('记录余额 ¥ 90.00'));
  });
  test('v6 snapshot keeps the saved reconstructed balance', () {
    final fields = {
      ..._transaction(),
      'balanceAfterFen': 9000,
      'matchedProcess': {..._process, 'balanceFen': 100},
    };
    final original = jsonEncode({
      ..._snapshot(trips: [fields]),
      'parseVersion': 6,
    });
    final restored = CardSessionSnapshot.decode(original)!;
    expect(restored.trips.single.balanceAfterFen, 9000);
    expect(restored.trips.single.balanceAfterIsRecorded, isFalse);
    expect(restored.encode(), original);
  });
  test(
    'v6 unknown balance stays unknown in snapshot, detail and export',
    () async {
      final repository = CardRepository(testDatabase());
      addTearDown(repository.db.close);
      final fields = {
        ..._transaction(),
        'balanceAfterFen': null,
        'matchedProcess': _process,
      };
      final payload = {
        ..._snapshot(trips: [fields]),
        'parseVersion': 6,
      };
      final original = jsonEncode(payload);
      final restored = CardSessionSnapshot.decode(original)!;
      expect(restored.trips.single.balanceAfterFen, isNull);
      expect(restored.trips.single.balanceAfterIsRecorded, isNull);
      expect(restored.trips.single.matchedProcessTrip!.balanceFen, 1000);
      expect(restored.encode(), original);

      final id = await _save(repository, payload);
      final history = await ArchiveHistory(repository).load(id);
      final record = history.records.single;
      expect(archiveRecordBalanceFen(record), isNull);
      expect(archiveRecordBalanceIsRecorded(record), isFalse);
      expect(archiveRecordText(record), isNot(contains('余额')));
      final info = presentArchiveTrips([
        record,
      ], onDiagnostics: (_) {}).entries.single.info;
      expect(info.subText ?? '', isNot(contains('余额')));
      expect(info.fields.where((f) => f.$1.contains('余额')), isEmpty);
      final exported = buildArchiveHistoryExport([history]);
      expect(exported, isNot(contains('记录余额 HK\$ 10.00')));
      expect(exported, isNot(contains('交易后余额 HK\$ 10.00')));
      expect(exported, contains(history.batches.single.decoded.rawJson));
      expect(record.fields['balanceAfterFen'], isNull);
      expect(record.fields['matchedProcess'], _process);

      final legacy = CardSessionSnapshot.decode(
        jsonEncode({...payload, 'parseVersion': 5}),
      )!;
      expect(legacy.trips.single.balanceAfterFen, 1000);
      expect(legacy.trips.single.balanceAfterIsRecorded, isTrue);
    },
  );

  test(
    'history groups only conflicting transaction balance semantics at v6',
    () async {
      for (final versions in [
        [4, 5, 6, 7],
        [7, 6, 5, 4],
      ]) {
        final repository = CardRepository(testDatabase());
        addTearDown(repository.db.close);
        final trips = [
          {
            ..._transaction(),
            'balanceAfterFen': null,
            'matchedProcess': _process,
          },
          {..._transaction(), 'sequence': 43, 'matchedProcess': _process},
          {..._transaction(), 'sequence': 44},
          {
            ..._transaction(),
            'sequence': 45,
            'balanceAfterFen': 1000,
            'matchedProcess': _process,
          },
          {..._transaction(), 'sequence': 46, 'balanceAfterFen': null},
        ];
        late String id;
        for (var i = 0; i < versions.length; i++) {
          id = await _save(repository, {
            ..._snapshot(
              trips: trips,
              rails: [_rail],
              buses: [_bus],
              cycle: [_process],
            ),
            'parseVersion': versions[i],
          }, day: 20 + i);
        }
        final history = await ArchiveHistory(repository).load(id);
        expect(history.records, hasLength(11));
        for (final sequence in [42, 43, 44]) {
          final records = history.records.where(
            (r) =>
                r.kind == ArchiveRecordKind.transaction &&
                r.fields['sequence'] == sequence,
          );
          expect(records, hasLength(2));
          for (final record in records) {
            final modern = record.sources.first.capturedParseVersion >= 6;
            expect(record.sources, hasLength(2));
            expect(
              record.sources.every(
                (s) => (s.capturedParseVersion >= 6) == modern,
              ),
              isTrue,
            );
            expect(
              archiveRecordBalanceFen(record),
              sequence == 42
                  ? (modern ? null : 1000)
                  : sequence == 43
                  ? (modern ? 1234 : 1000)
                  : 1234,
            );
            expect(archiveRecordBalanceIsRecorded(record), !modern);
          }
        }
        for (final record in history.records.where(
          (r) =>
              r.kind != ArchiveRecordKind.transaction ||
              [45, 46].contains(r.fields['sequence']),
        )) {
          expect(record.sources, hasLength(4));
        }
      }
    },
  );

  test('archived 1A never assigns entry balance to exit or unknown side', () {
    for (final hasTimes in [true, false]) {
      final fields = <String, dynamic>{..._rail, 'entryBalanceFen': 2500};
      if (!hasTimes) {
        fields.remove('entryTime');
        fields.remove('exitTime');
      }
      final entries = presentArchiveTrips([
        ArchiveHistoryRecord(
          kind: ArchiveRecordKind.rail,
          fields: fields,
          context: const ArchiveContext(
            currencyCode: 'CNY',
            minorUnitDigits: 2,
          ),
          sources: const [],
        ),
      ], onDiagnostics: (_) {}).entries;
      expect(
        entries.where((e) => e.info.subText != null).length,
        hasTimes ? 1 : 0,
      );
      if (hasTimes) {
        expect(
          entries.singleWhere((e) => e.info.subText != null).info.subText,
          '余额 ¥ 25.00',
        );
      }
      expect(fields['entryBalanceFen'], 2500);
    }
  });
}

Map<String, Object?> _transaction() => {
  'time': 1792454280000,
  'capturedTimes': {
    'time': {'civil': '2026-10-19T23:58:00', 'isUtc': false},
  },
  'amountFen': 450,
  'consume': true,
  'sequence': 42,
  'terminalId': '000000004200',
  'typeName': '消费',
  'rideStatusName': '出站',
  'stationLabel': '苏洋',
  'lineLabel': '2号线',
  'cityCode': '3910',
  'cityName': '福州市',
  'appTypeName': '城市轨道交通',
  'balanceAfterFen': 1234,
  'currency': 'HKD',
  'rawHex': '000042AB',
};

const _rail = {
  'status': 2,
  'entryTime': 1792450000000,
  'exitTime': 1792451000000,
  'entryStationId': '0001',
  'exitStationId': '0002',
  'entryStationName': '人民广场',
  'exitStationName': '世纪大道',
  'entryCityCode': '2000',
  'exitCityCode': '2000',
  'lineName': '2号线',
  'entryAmountFen': 0,
  'exitAmountFen': 300,
};
const _bus = {
  'status': 1,
  'entryTime': 1792440000000,
  'exitTime': 1792441000000,
  'entryCityCode': '3910',
  'exitCityCode': '3910',
  'entryLineCode': '0008',
  'exitLineCode': '0008',
  'entryStationCode': '01',
  'exitStationCode': '02',
  'amountFen': 200,
  'mileage': 5,
  'directionCode': 0,
};
const _process = {
  'time': 1792442000000,
  'typeCode': 3,
  'terminalId': '000000000009',
  'appTypeCode': 2,
  'lineStationCode': '00080001',
  'amountFen': 0,
  'balanceFen': 1000,
  'cityCode': '3910',
};

Map<String, Object?> _snapshot({
  List<Object?> trips = const [],
  List<Object?> rails = const [],
  List<Object?> buses = const [],
  List<Object?> cycle = const [],
  String currency = 'HKD',
  int digits = 2,
  String marker = 'first capture',
}) => {
  'v': 3,
  'parseVersion': 1,
  'cityCode': '2000',
  'context': {
    'systemId': 'TU',
    'applicationId': 'wallet-01',
    'currencyCode': currency,
    'minorUnitDigits': digits,
    'timeZoneOffsetMinutes': 480,
    'clockBasis': 'card-civil',
  },
  'trips': trips,
  'rails': rails,
  'buses': buses,
  'cycle': cycle,
  'rawEvidence': [],
  'recordProvenance': {},
  'captureMarker': marker,
};

Future<String> _save(
  CardRepository repository,
  Map<String, Object?> payload, {
  int day = 20,
}) async {
  await repository.saveIdentity(
    fingerprint: 'archive-trip-card-offline',
    identity: const CardArchiveIdentity(
      cardType: CardTypes.chinaTunion,
      officialName: '离线通勤卡',
    ),
    cardNumber: '00000042',
    balanceFen: 9000,
    currencyCode: 'CNY',
    sessionDataJson: jsonEncode(payload),
    readAt: DateTime.utc(2026, 10, day),
  );
  return (await repository.getAllCards()).single.id;
}
