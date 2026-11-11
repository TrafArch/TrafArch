import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/features/trips/trip_cards_view.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_card.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_process_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_trip_matcher.dart';

import 'fixtures/shenyang_cycles_20261109.dart';

// The reported 1E slot 11 occurs once in transit_card_log_20261109_163523.json.
// It also occurs in the older 20261030 fixture, then at physical slot 3 and
// inside the ten-record transaction window. No card/holder identity is copied.
const _exitRaw =
    '160000413106034291010001008F000300000001C20000050A2026102512252522101217221000000000000002BC0000';
const _transactionRaw = '0245000000000001C20941310603429120261025122525';

void main() {
  test('本次日志全部30条过程记录八次保存后数量不增长且保留240个来源', () {
    final cycles = [
      for (final raw in shenyangCycles20261109)
        const TUnionProcessParser().parseCycleTrip([
          for (var i = 0; i < raw.length; i += 2)
            int.parse(raw.substring(i, i + 2), radix: 16),
        ])!,
    ];
    final payload = CardSessionSnapshot(
      parseVersion: kTripParseVersion,
      context: const ArchiveContext(
        systemId: 'tunion',
        applicationId: 'A000000632010105',
        currencyCode: 'CNY',
        minorUnitDigits: 2,
        clockBasis: 'device-local-card-time-unverified',
      ),
      cardCityCode: '1000',
      processTrips: cycles,
      recordProvenance: {
        for (var i = 0; i < cycles.length; i++)
          'cycle[$i]': {
            'sfi': 0x1E,
            'recordNumber': i + 1,
            'recordNumberIsReliable': true,
            'rawHex': shenyangCycles20261109[i],
          },
      },
    ).encode();
    final original = _history([payload]);
    final repeated = _history(List.filled(8, payload));
    ArchiveTripProjection project(ArchiveHistoryResult history) =>
        presentArchiveTrips(
          history.records,
          batches: history.batches,
          onDiagnostics: (_) {},
        );
    final one = project(original);
    final eight = project(repeated);

    expect(eight.journeys, hasLength(one.journeys.length));
    expect(eight.journeys.expand((journey) => journey.events), hasLength(240));
    expect(repeated.records, hasLength(30));
    expect(
      repeated.records.every((record) => record.sources.length == 8),
      isTrue,
    );
    expect(
      repeated.batches.map((batch) => batch.decoded.rawJson),
      everyElement(payload),
    );
    final rawCounts = <String, int>{};
    for (final event in eight.journeys.expand((journey) => journey.events)) {
      final raw = event.payload.info.rawHex!;
      rawCounts.update(raw, (count) => count + 1, ifAbsent: () => 1);
    }
    expect(rawCounts.keys.toSet(), shenyangCycles20261109.toSet());
    expect(rawCounts.values, everyElement(8));
  });

  test('真实沈阳出站的一个模拟旧余额冲突不复制其他八批相同站点', () {
    final payloads = [
      for (var i = 0; i < 8; i++) _snapshot(balance: 1290, slot: i + 3),
      // Explicitly simulated historical disagreement: the current log does
      // not contain the user's archived balance versions.
      _snapshot(balance: 1740, slot: 3),
    ];
    final history = _history(payloads);
    final before = jsonEncode([
      for (final record in history.records) record.fields,
    ]);

    final projection = presentArchiveTrips(
      history.records,
      batches: history.batches,
      onDiagnostics: (_) {},
    );

    expect(projection.journeys, hasLength(2));
    final repeated = projection.journeys.singleWhere(
      (journey) => journey.balanceAfterText == '¥ 12.90',
    );
    expect(repeated.end?.station, '铁西广场');
    expect(repeated.end?.time, DateTime.utc(2026, 10, 25, 12, 25, 25));
    expect(repeated.amountText, '-¥ 4.50');
    expect(repeated.events, hasLength(8));
    expect(repeated.events.expand((event) => event.sourceIds).toSet(), {
      for (var i = 0; i < 8; i++) 'read-$i',
    });
    expect(
      projection.journeys.expand((journey) => journey.events),
      hasLength(9),
    );
    expect(
      history.batches.map((batch) => batch.decoded.rawJson),
      payloads.reversed,
    );
    expect(
      jsonEncode([for (final record in history.records) record.fields]),
      before,
    );
    for (final payload in payloads) {
      expect(CardSessionSnapshot.decode(payload)!.encode(), payload);
    }
  });

  testWidgets('相同余额版本只渲染一张卡且详情保留八次读取来源', (tester) async {
    final history = _history([
      for (var i = 0; i < 8; i++) _snapshot(balance: 1290, slot: i + 3),
      _snapshot(balance: 1740, slot: 3),
    ]);
    final projection = presentArchiveTrips(
      history.records,
      batches: history.batches,
      onDiagnostics: (_) {},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TripCardsView(
              entries: projection.entries,
              projectedJourneys: projection.journeys,
              sourceLabels: archiveTripSourceLabels,
              summaryText: projection.summaryText,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TripEntryCard), findsNWidgets(2));
    expect(find.textContaining('12.90'), findsOneWidget);
    expect(find.textContaining('17.40'), findsOneWidget);
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is TripEntryCard &&
            widget.journey?.balanceAfterText == '¥ 12.90',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('行程记录'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(8));
    expect(tester.takeException(), isNull);
  });
}

String _snapshot({required int balance, required int slot}) {
  final cycle = const TUnionProcessParser().parseCycleTrip([
    for (var i = 0; i < _exitRaw.length; i += 2)
      int.parse(_exitRaw.substring(i, i + 2), radix: 16),
  ])!;
  return CardSessionSnapshot(
    parseVersion: kTripParseVersion,
    context: const ArchiveContext(
      systemId: 'tunion',
      applicationId: 'A000000632010105',
      currencyCode: 'CNY',
      minorUnitDigits: 2,
      clockBasis: 'device-local-card-time-unverified',
    ),
    cardCityCode: '1000',
    trips: [
      TransitTrip(
        time: cycle.time,
        amountFen: 450,
        overdraftLimitFen: 0,
        isConsume: true,
        typeName: '复合消费',
        isCompositeConsume: true,
        sequence: 581,
        terminalId: '413106034291',
        cityCode: '2210',
        cityName: '沈阳市',
        lineLabel: '1号线',
        stationLabel: '铁西广场',
        appTypeName: '城市轨道交通',
        balanceAfterFen: balance,
        balanceAfterIsRecorded: false,
        rideStatusName: '出站',
        matchedProcessTrip: cycle,
        displayProcessKey: cycleDisplayKey(cycle),
        rawHex: _transactionRaw,
      ),
    ],
    processTrips: [cycle],
    recordProvenance: {
      'cycle[0]': {
        'sfi': 0x1E,
        'recordNumber': slot,
        'recordNumberIsReliable': true,
        'rawHex': _exitRaw,
        'capturedDisplay': {
          'line': '1号线',
          'station': '铁西广场',
          'cityName': '沈阳市',
        },
      },
    },
  ).encode();
}

ArchiveHistoryResult _history(List<String> payloads) => ArchiveHistory.project(
  ArchiveRows(
    card: const SavedCard(
      id: 'synthetic-repeated-exit',
      cardFingerprint: 'synthetic-repeated-exit',
      cardType: 'china_tunion',
      identificationSource: 'test',
      cardNumber: '00000001',
      createdAt: 1,
      updatedAt: 9,
    ),
    batches: [
      for (var i = 0; i < payloads.length; i++)
        CardReadBatch(
          id: 'read-$i',
          cardId: 'synthetic-repeated-exit',
          cardFingerprint: 'synthetic-repeated-exit',
          readAt: i + 1,
          parseVersion: kTripParseVersion,
          payloadJson: payloads[i],
        ),
    ],
  ),
);
