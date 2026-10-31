import 'dart:convert';

import 'package:transit_card_analyzer/features/archive/application/card_records_export.dart';

import 'package:transit_card_analyzer/features/archive/presentation/archive_record_presenter.dart';

import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_identity.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_types.dart';
import 'package:transit_card_analyzer/features/archive/presentation/card_detail_page.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_card.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_details.dart';
import 'package:transit_card_analyzer/features/trips/trip_stream_view.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';

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
  testWidgets(
    'saved history opens offline as trip cards and readable details',
    (tester) async {
      final db = testDatabase();
      final repository = CardRepository(db);
      final id = await _save(repository, _snapshot(trips: [_transaction()]));

      // A new repository, with no AppDependencies, scan controller or resolver.
      await _open(tester, CardRepository(db), id);
      expect(find.byType(TripEntryCard), findsOneWidget);
      expect(find.textContaining('苏洋'), findsOneWidget);
      expect(find.text('-HK\$ 4.50'), findsOneWidget);
      expect(find.text('2026年10月19日'), findsOneWidget);
      expect(find.textContaining('批次 ·'), findsNothing);
      expect(find.text('查看完整原始快照'), findsNothing);
      _expectNoJson();

      await tester.tap(find.byType(TripEntryCard));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(TripDetailRow), findsWidgets);
      expect(find.text('交易序号'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('交易时间'), findsOneWidget);
      expect(find.textContaining('2026-10-19 23:58:00'), findsWidgets);
      expect(find.text('原始数据（HEX）'), findsNothing);
      _expectNoJson();
      await _close(tester);
    },
  );

  testWidgets('all saved sources share cards and source plus mode filtering', (
    tester,
  ) async {
    final repository = CardRepository(testDatabase());
    final id = await _save(
      repository,
      _snapshot(
        trips: [_transaction()],
        rails: [_rail],
        buses: [_bus],
        cycle: [_process],
      ),
    );
    await _open(tester, repository, id);
    expect(find.byType(TripEntryCard), findsNWidgets(4));
    expect(find.textContaining('人民广场'), findsWidgets);
    expect(find.textContaining('世纪大道'), findsWidgets);
    expect(find.text('交易 1 条 · 过程及应用记录 3 条'), findsOneWidget);

    await _filter(tester, '0x1E 过程');
    expect(find.byType(TripEntryCard), findsOneWidget);
    expect(
      tester.widget<TripEntryCard>(find.byType(TripEntryCard)).journey!.start,
      isNotNull,
    );
    await _filter(tester, '城市轨道交通');
    expect(find.byType(TripEntryCard), findsNothing);
    expect(find.text('当前筛选条件下没有记录'), findsOneWidget);
    await _filter(tester, '全部方式');
    await _filter(tester, '0x1A 轨道');
    // 同一 1A 两侧展示为一张行程票，详情仍保留两个原始事件。
    expect(find.byType(TripEntryCard), findsOneWidget);
    expect(
      tester.widget<TripEntryCard>(find.byType(TripEntryCard)).journey!.events,
      hasLength(2),
    );
    await _filter(tester, '全部来源');
    await _filter(tester, '公共汽电车');
    expect(find.byType(TripEntryCard), findsNWidgets(2));
    await _filter(tester, '全部方式');
    expect(find.byType(TripEntryCard), findsNWidgets(4));
    _expectNoJson();
    await _close(tester);
  });

  testWidgets('linked rail 0x1E and 0x1A merge into the 0x18 card', (
    tester,
  ) async {
    final repository = CardRepository(testDatabase());
    final time = DateTime(2026, 10, 19, 23, 58);
    final process = {
      'typeCode': 4,
      'terminalId': '000000004200',
      'appTypeCode': 1,
      'lineStationCode': '02310000000000',
      'amountFen': 450,
      'balanceFen': 1234,
      'time': time.millisecondsSinceEpoch,
      'cityCode': '3910',
      'rawHex': '1E01',
    };
    final id = await _save(
      repository,
      _snapshot(
        trips: [
          {
            ..._transaction(),
            'time': time.millisecondsSinceEpoch,
            'matchedProcess': process,
            'balanceAfterFen': 1234,
          },
        ],
        rails: [
          {
            'status': 2,
            'entryTime': DateTime(2026, 10, 19, 23, 50).millisecondsSinceEpoch,
            'exitTime': time.millisecondsSinceEpoch,
            'entryCityCode': '3910',
            'exitCityCode': '3910',
            'entryTerminalId': '000000000000000A',
            'exitTerminalId': '000000004200',
            'entryAmountFen': 0,
            'exitAmountFen': 450,
            'rawHex': '1A01',
          },
        ],
        cycle: [process],
      ),
    );
    await _open(tester, repository, id);
    expect(find.byType(TripEntryCard), findsNWidgets(2));
    expect(find.text('交易 1 条 · 过程及应用记录 1 条（1 条已并入 0x18 交易）'), findsOneWidget);
    await _filter(tester, '0x18 交易');
    await tester.tap(find.byType(TripEntryCard));
    await tester.pumpAndSettle();
    expect(find.textContaining('保存时已关联 0x1E 过程记录'), findsOneWidget);
    _expectNoJson();
    await _close(tester);
  });

  testWidgets('cross-batch duplicates retain attribution and wallet contexts', (
    tester,
  ) async {
    final repository = CardRepository(testDatabase());
    final trip = _transaction()
      ..remove('currency')
      // Complete 0x18 body: sequence 42, 450 minor units, terminal 4200,
      // and the captured civil timestamp. Truncated HEX is not a witness.
      ..['rawHex'] = '002A000000000001C20600000000420020261019235800';
    final id = await _save(repository, _snapshot(trips: [trip]));
    await _save(
      repository,
      _snapshot(trips: [trip], marker: 'second capture'),
      day: 21,
    );
    await _save(
      repository,
      _snapshot(trips: [trip], currency: 'JPY', digits: 0),
      day: 22,
    );
    final history = await ArchiveHistory(repository).load(id);
    expect(history.records, hasLength(2));
    expect(history.records.map((r) => r.sources.length), containsAll([1, 2]));
    final journeys = presentArchiveTrips(
      history.records,
      batches: history.batches,
      onDiagnostics: (_) {},
    ).journeys;
    expect(journeys, hasLength(2));
    final hkdJourney = journeys.singleWhere(
      (journey) => journey.amountText == '-HK\$ 4.50',
    );
    expect(hkdJourney.events, hasLength(2));
    expect(
      hkdJourney.events.expand((event) => event.sourceIds).toSet(),
      history.batches
          .where(
            (batch) => batch.decoded.snapshot!.context.currencyCode == 'HKD',
          )
          .map((batch) => batch.id)
          .toSet(),
    );
    final before = (await repository.getArchiveRows(id)).batches;

    await _open(tester, repository, id);
    expect(find.byType(TripEntryCard), findsNWidgets(2));
    expect(find.text('-HK\$ 4.50'), findsOneWidget);
    expect(find.text('-JPY 450'), findsOneWidget);
    await tester.tap(
      find.ancestor(
        of: find.text('-HK\$ 4.50'),
        matching: find.byType(TripEntryCard),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('行程记录'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(2));
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('1 个批次'), findsOneWidget);
    _expectNoJson();
    await tester.scrollUntilVisible(
      find.text('诊断与原始证据'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('诊断与原始证据'));
    await tester.pumpAndSettle();
    expect(find.textContaining('"sources"'), findsOneWidget);
    expect(find.textContaining('"batchId"'), findsOneWidget);
    expect(find.textContaining('trips[0]'), findsOneWidget);
    expect(
      (await repository.getArchiveRows(id)).batches.map((b) => b.payloadJson),
      before.map((b) => b.payloadJson),
    );
    await _close(tester);
  });

  for (final version in [1, 2]) {
    testWidgets('legacy v$version keeps unknown currency and clock readable', (
      tester,
    ) async {
      final repository = CardRepository(testDatabase());
      final legacy = _transaction()
        ..remove('currency')
        ..remove('capturedTimes');
      final id = await _save(repository, {
        'v': version,
        'trips': [legacy],
        if (version == 1) 'rail': _rail,
        if (version == 2) ...{
          'rails': [_rail],
          'buses': <Object>[],
          'cycle': <Object>[],
        },
      });
      await _open(tester, repository, id);
      expect(find.byType(TripEntryCard), findsNWidgets(3));
      expect(find.text('-币种未知 4.50'), findsOneWidget);
      expect(find.textContaining('时区未知'), findsWidgets);
      expect(find.textContaining('人民广场'), findsOneWidget);
      expect(find.textContaining('批次 ·'), findsNothing);
      expect(find.text('查看完整原始快照'), findsNothing);
      _expectNoJson();
      await _close(tester);
    });
  }

  testWidgets(
    'unsupported batch stays diagnostic while valid trips remain usable',
    (tester) async {
      final repository = CardRepository(testDatabase());
      final id = await _save(repository, _snapshot(trips: [_transaction()]));
      await _save(repository, {'v': 99, 'future': 'kept verbatim'}, day: 21);
      await _open(tester, repository, id);
      expect(find.byType(TripEntryCard), findsOneWidget);
      expect(find.textContaining('部分历史记录无法完整显示'), findsOneWidget);
      expect(find.textContaining('unsupported'), findsNothing);
      expect(find.textContaining('future'), findsNothing);
      await tester.ensureVisible(find.text('批次诊断与原始快照'));
      await tester.tap(find.text('批次诊断与原始快照'));
      await tester.pumpAndSettle();
      expect(find.textContaining('unsupported'), findsOneWidget);
      await tester.tap(find.textContaining('unsupported'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看完整原始快照').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('kept verbatim'), findsOneWidget);
      await _close(tester);
    },
  );

  testWidgets('unknown legacy amounts remain readable on a phone width', (
    tester,
  ) async {
    final repository = CardRepository(testDatabase());
    final trip = _transaction()..remove('currency');
    final id = await _save(repository, {
      'v': 1,
      'trips': [trip],
    });
    await _open(tester, repository, id, size: const Size(390, 1100));
    expect(tester.takeException(), isNull);
    expect(find.text('-币种未知 4.50'), findsOneWidget);
    await tester.tap(find.byType(TripEntryCard));
    await tester.pumpAndSettle();
    expect(find.text('记录余额'), findsOneWidget);
    expect(find.text('币种未知 12.34'), findsOneWidget);
    await _close(tester);
  });

  testWidgets(
    'live trip stream retains shared filtering and readable details',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final app = AppDependencies(database: testDatabase());
      addTearDown(app.dispose);
      final stream = buildTripStream(
        trips: [
          for (final (sequence, station, mode) in [
            (1, '实时轨道站', '城市轨道交通'),
            (2, '实时公交站', '公共汽电车'),
          ])
            TransitTrip(
              time: DateTime(2026, 10, 20, 12),
              amountFen: 200,
              overdraftLimitFen: 0,
              isConsume: true,
              typeName: '消费',
              sequence: sequence,
              terminalId: '000000000001',
              stationLabel: station,
              appTypeName: mode,
            ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TripStreamView(
                stream: stream,
                app: app,
                isRemote: (_) => false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TripEntryCard), findsNWidgets(2));
      await _filter(tester, '公共汽电车');
      expect(find.byType(TripEntryCard), findsOneWidget);
      // 单次扣款公交票不显示未建立进出站关系的站点，原站点留在详情。
      expect(find.textContaining('实时公交站'), findsNothing);
      await _filter(tester, '0x1E 过程');
      expect(find.byType(TripEntryCard), findsNothing);
      await _filter(tester, '全部来源');
      await tester.tap(find.byType(TripEntryCard));
      await tester.pumpAndSettle();
      expect(find.byType(TripDetailRow), findsWidgets);
      expect(find.text('交易序号'), findsOneWidget);
      expect(find.textContaining('实时公交站'), findsWidgets);
      _expectNoJson();
      await _close(tester);
    },
  );
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

Future<void> _open(
  WidgetTester tester,
  CardRepository repository,
  String id, {
  Size size = const Size(800, 2000),
}) async {
  // Enough height to exercise all source cards without lazy-list ambiguity.
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: CardDetailPage(repository: repository, cardId: id),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _filter(WidgetTester tester, String label) async {
  // 下拉单选：来源下拉含「全部来源」与 0x1x 标签，其余归属方式下拉。
  final isSource = label == '全部来源' || label.startsWith('0x1');
  final fields = find.byType(MenuAnchor);
  final field = fields.at(isSource ? 0 : 1);
  expect(tester.widget<MenuAnchor>(field).animated, isTrue);
  await tester.ensureVisible(field);
  await tester.tap(
    find.descendant(of: field, matching: find.byType(InputDecorator)),
  );
  await tester.pump();
  final arrow = find.descendant(
    of: field,
    matching: find.byType(AnimatedRotation),
  );
  expect(tester.widget<AnimatedRotation>(arrow).turns, 0.5);
  expect(tester.binding.hasScheduledFrame, isTrue);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(MenuItemButton, label).hitTestable());
  await tester.pumpAndSettle();
  expect(tester.widget<AnimatedRotation>(arrow).turns, 0);
  expect(tester.testTextInput.isVisible, isFalse);
  expect(tester.takeException(), isNull);
}

void _expectNoJson() {
  expect(find.textContaining('"context"'), findsNothing);
  expect(find.textContaining('"record"'), findsNothing);
  expect(find.textContaining('"sources"'), findsNothing);
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}
