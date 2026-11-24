import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/home/presentation/felica_summary_panel.dart';
import 'package:transit_card_analyzer/features/home/presentation/summary_formatters.dart';
import 'package:transit_card_analyzer/features/reference_data/data/suica_station_repository.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/features/scan/domain/scan_presentation.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/features/trips/suica_trip_list.dart';
import 'package:transit_card_analyzer/features/trips/suica_trip_presenter.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_card.dart';
import 'package:transit_card_analyzer/features/trips/trip_filters.dart';
import 'package:transit_card_analyzer/protocols/felica/models/felica_card_type.dart';
import 'package:transit_card_analyzer/protocols/felica/models/felica_models.dart';
import 'package:transit_card_analyzer/protocols/felica/models/suica_transaction_details.dart';
import 'package:transit_card_analyzer/protocols/felica/parsers/suica_record_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final balance in [0, 900]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'saved rail balance $balance remains visible without amount at scale $scale',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(320, 740);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final live = presentSuicaTrips([
            _rail(balance: balance, change: null),
          ]).single;
          final restored = SuicaTripPresentation.fromJson(live.toJson())!;
          expect(restored.entry.info.amountText, isNull);
          expect(restored.journey.balanceAfterText, 'JP￥$balance');
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: SuicaTripList(trips: [restored]),
                ),
              ),
            ),
          );
          expect(find.text('行程后余额 JP￥$balance'), findsOneWidget);
          expect(find.textContaining('余额差'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  test('a Suica scan exposes yen to shared currency consumers', () {
    final presentation = ScanPresentation(
      FelicaReadOutcome(
        FelicaScanResult(
          cardType: 'suica',
          displayName: 'Suica',
          cardProductType: FelicaCardType.suica,
          scannedAt: DateTime(2025, 10, 20),
        ),
      ),
      KnowledgeBase.empty(),
    );
    expect(presentation.cardCurrency.code, 'JPY');
    expect(presentation.cardCurrency.symbol, 'JP￥');
    expect(presentation.cardCurrency.unit, '日元');
  });

  testWidgets(
    'Japanese rail footer follows domestic amount layout without seats',
    (tester) async {
      for (final (change, expectedAmount) in [
        (-100, '-JP￥100'),
        (0, 'JP￥0'),
        (100, '+JP￥100'),
      ]) {
        final live = presentSuicaTrips([_rail(change: change)]).single;
        final stored = live.toJson();
        final trip = SuicaTripPresentation.fromJson(stored)!;
        expect(trip.entry.info.amountText, '余额差 $expectedAmount');
        expect(trip.journey.amountText, expectedAmount);
        expect(trip.journey.seatLabel, isNull);
        expect(trip.toJson(), stored);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: SuicaTripList(trips: [trip])),
            ),
          ),
        );
        expect(find.text(expectedAmount), findsOneWidget);
        expect(find.text('行程后余额 JP￥900'), findsOneWidget);
        expect(find.textContaining('余额差'), findsNothing);
        expect(find.textContaining('商务座'), findsNothing);
        expect(find.textContaining('普通座'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );

  test('Suica railway date does not invent a midnight time', () {
    final tx = const SuicaRecordParser()
        .parseBlock(
          blockNumber: 0,
          bytes: [0x16, 1, 0, 0, 0x33, 0x54, 1, 1, 1, 3, 0x84, 3, 0, 0, 2, 0],
        )
        .toTransaction();
    expect(felicaTime(tx), '2025-10-20');
  });

  test('Suica purchase retains a real midnight time', () {
    final tx = const SuicaRecordParser()
        .parseBlock(
          blockNumber: 0,
          bytes: [
            0xC7,
            0x46,
            0,
            0,
            0x33,
            0x54,
            0,
            0,
            1,
            3,
            0x84,
            3,
            0,
            0,
            2,
            0,
          ],
        )
        .toTransaction();
    expect(felicaTime(tx), '2025-10-20 00:00');
  });

  test('known Suica yen balance does not depend on a wallet object', () {
    expect(felicaAmountText(_rail(), const []), 'JP￥900（残高）');
    expect(felicaAmountText(_rail(balance: 12345), const []), 'JP￥12,345（残高）');
  });

  test('unknown transaction currency does not borrow a lone wallet', () {
    const transaction = FelicaTransaction(
      amountMinorUnits: 900,
      rawHex: '00',
      amountIsBalance: true,
    );
    expect(felicaAmountText(transaction, const [_yenWallet]), '900（币种未知）（残高）');
  });

  test('Suica trip does not infer yen from unconfirmed currency', () {
    final transaction = _rail(currency: null);
    final trip = presentSuicaTrips([transaction]).single;
    expect(trip.journey.balanceAfterText, '900（币种未知）');
    expect(trip.entry.info.amountText, isNull);
    expect(trip.entry.info.fields.where((field) => field.$1 == '余额差'), isEmpty);
  });

  test('Suica zero balance and zero balance change remain integer yen', () {
    final trip = presentSuicaTrips([
      _record(kind: SuicaRecordKind.special, process: 2, balance: 0, change: 0),
    ]).single;
    expect(trip.journey.balanceAfterText, 'JP￥0');
    expect(trip.entry.info.amountText, '余额差 JP￥0');
  });

  test('invalid Suica date does not claim day precision', () {
    final transaction = const SuicaRecordParser()
        .parseBlock(
          blockNumber: 0,
          bytes: [0x16, 1, 0, 0, 0, 0, 1, 1, 1, 3, 0x84, 3, 0, 0, 2, 0],
        )
        .toTransaction();
    final trip = presentSuicaTrips([transaction]).single;
    final fields = Map.fromEntries(
      trip.entry.info.fields.map((field) => MapEntry(field.$1, field.$2)),
    );
    expect(trip.entry.info.timeText, '时间未解析');
    expect(trip.entry.dateText, '日期未知');
    expect(fields['时间精度'], '未知（日期未解析）');
  });

  test(
    'special single location is an occurrence place rather than an entry',
    () async {
      final stations = await _stations();
      final transaction = const SuicaRecordParser()
          .parseBlock(
            blockNumber: 0,
            bytes: [0x12, 2, 0, 0, 0x33, 0x54, 1, 1, 0, 0, 0x84, 3, 0, 0, 2, 0],
          )
          .toTransaction();
      final trip = presentSuicaTrips([transaction], stations: stations).single;
      final fields = Map.fromEntries(
        trip.entry.info.fields.map((field) => MapEntry(field.$1, field.$2)),
      );
      expect(trip.entry.info.title, '充值');
      expect(fields['发生地点'], '東京');
      expect(fields['地点原码'], '00/01/01');
      expect(
        fields.keys.where(
          (label) => label.startsWith('进站') || label.startsWith('出站'),
        ),
        isEmpty,
      );
      expect(trip.journey.start, isNull);
      expect(trip.journey.end, isNull);
    },
  );

  test(
    'one rail record owns both endpoints and keeps balance separate',
    () async {
      final stations = await _stations();
      final trips = presentSuicaTrips([
        _rail(),
        _rail(block: 1),
      ], stations: stations);
      expect(trips, hasLength(2));
      final trip = trips.first;
      expect(trip.journey.state, JourneyState.completed);
      expect(trip.journey.events, hasLength(1));
      expect(trip.journey.start?.station, '東京');
      expect(trip.journey.end?.station, '新橋');
      expect(trip.journey.start?.line, '東海道本');
      expect(trip.journey.start?.timeText, '仅记录日期');
      expect(trip.journey.cityLabel, '日本');
      expect(trip.journey.duration, isNull);
      expect(trip.entry.info.timeText, '2025-10-20');
      expect(trip.entry.info.amountText, '余额差 -JP￥100');
      expect(trip.journey.balanceAfterText, 'JP￥900');
      final fields = Map.fromEntries(
        trip.entry.info.fields.map((f) => MapEntry(f.$1, f.$2)),
      );
      expect(fields['历史块号'], '0');
      expect(fields['交易流水号'], '2');
      expect(fields['交易后余额'], 'JP￥900');
      expect(fields['进站原码'], contains('01'));
      expect(fields['站点数据 SHA256'], stations.hash);
    },
  );

  test('unknown and suppressed station codes stay visible without invented names', () async {
    final stations = await _stations();
    final unknown = presentSuicaTrips([
      _rail(
        entry: const SuicaStationCode(
          areaCode: 2,
          lineCode: 255,
          stationCode: 254,
          status: SuicaStationStatus.available,
        ),
      ),
    ], stations: stations).single;
    expect(unknown.journey.start?.station, contains('未收录'));
    expect(unknown.journey.start?.station, contains('FF'));

    // This key exists in the database, but the record explicitly suppresses it.
    final suppressed = presentSuicaTrips([
      _rail(
        entry: const SuicaStationCode(
          areaCode: 0,
          lineCode: 1,
          stationCode: 1,
          status: SuicaStationStatus.suppressed,
        ),
      ),
    ], stations: stations).single;
    expect(suppressed.journey.start?.station, isNot('東京'));
    expect(
      suppressed.entry.info.fields.where((f) => f.$1 == '进站原码').single.$2,
      contains('01'),
    );
  });

  test('公交充值按已保存的处理码恢复，保留原处理类型', () {
    final trip = presentSuicaTrips([
      _record(kind: SuicaRecordKind.bus, process: 0x1F, change: 500),
    ]).single;
    expect(trip.entry.info.title, '充值');
    expect(trip.entry.mode, TripModeFilter.other);
    final json = trip.toJson();
    final frozen = json['info'] as Map<String, dynamic>;
    frozen['title'] = '公交 / 路面电车 · 公交充值';
    json['mode'] = 'bus';
    final restored = SuicaTripPresentation.fromJson(json)!;
    expect(restored.entry.info.title, '充值');
    expect(restored.entry.mode, TripModeFilter.other);
    expect(restored.entry.info.fields, contains(('处理类型', '公交充值')));
  });

  test(
    'money direction never promotes unknown processing to recharge or purchase',
    () {
      final trip = presentSuicaTrips([
        _record(kind: SuicaRecordKind.unknown, process: 0xFE, change: 500),
      ]).single;
      expect(trip.entry.mode, TripModeFilter.other);
      expect(trip.entry.info.title, contains('0xFE'));
      expect(trip.entry.info.title, isNot(contains('充值')));
      expect(trip.entry.info.amountText, '余额差 +JP￥500');
      expect(trip.journey.start, isNull);
      expect(trip.journey.end, isNull);
    },
  );

  test(
    'frozen display survives JSON and a closed station repository',
    () async {
      final stations = await _stations();
      final original = presentSuicaTrips([_rail()], stations: stations).single;
      final json = jsonDecode(jsonEncode(original.toJson()));
      stations.close();
      final restored = SuicaTripPresentation.fromJson(json);
      expect(restored, isNotNull);
      expect(restored!.journey.start?.station, '東京');
      expect(restored.journey.end?.station, '新橋');
      expect(restored.entry.info.rawHex, '16010000335401010103840300000200');
      expect(restored.entry.info.fields, original.entry.info.fields);
      expect(restored.entry.info.amountText, '余额差 -JP￥100');
      expect(restored.journey.cityLabel, '日本');
      expect(restored.toJson(), json);
      for (final invalid in [
        null,
        [],
        {},
        {'version': 9},
        {'version': 1, 'info': 3},
      ]) {
        expect(SuicaTripPresentation.fromJson(invalid), isNull);
      }
    },
  );

  testWidgets(
    'all twenty mixed records appear as independently openable cards',
    (tester) async {
      final transactions = List.generate(
        20,
        (index) => index < 10
            ? _rail(block: index)
            : _record(
                kind: index.isEven
                    ? SuicaRecordKind.shopping
                    : SuicaRecordKind.special,
                process: index.isEven ? 0x46 : 2,
                block: index,
              ),
      );
      final trips = presentSuicaTrips(transactions);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: SuicaTripList(trips: trips)),
          ),
        ),
      );
      expect(
        find.byType(TripEntryCard, skipOffstage: false),
        findsNWidgets(20),
      );
      expect(find.text('00:00'), findsNothing);
      expect(find.text('Suica · 20 条记录'), findsOneWidget);
      final last = find.byType(TripEntryCard).last;
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      await tester.tap(last);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      final detailScroll = find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first;
      for (final label in ['历史块号', '处理码', '交易后余额', '原始数据（HEX）']) {
        await tester.scrollUntilVisible(
          find.text(label),
          100,
          scrollable: detailScroll,
        );
        expect(find.text(label), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'rail parsing resolves hex keys through trips and the read summary',
    () async {
      final stations = await _stations();
      for (final (entryLine, entryCode, exitLine, exitCode, start, end) in [
        (0xEF, 0x04, 0xAE, 0x09, '蔵前', '成田空港'),
        (0x03, 0x0D, 0x02, 0x03, '新宿', '秋葉原'),
      ]) {
        final tx = const SuicaRecordParser()
            .parseBlock(
              blockNumber: 0,
              bytes: [
                0x16,
                1,
                0,
                0,
                0x33,
                0x54,
                entryLine,
                entryCode,
                exitLine,
                exitCode,
                0x84,
                3,
                0,
                0,
                2,
                0,
              ],
            )
            .toTransaction();
        final trip = presentSuicaTrips([tx], stations: stations).single;
        expect(trip.journey.start?.station, start);
        expect(trip.journey.end?.station, end);
        expect(trip.entry.info.timeText, '2025-10-20');
        expect(trip.journey.start?.timeText, '仅记录日期');
        expect(trip.journey.cityLabel, '日本');
        expect(
          suicaTransactionSummary(tx, stations: stations),
          contains('$start → $end'),
        );
      }
    },
  );

  testWidgets(
    'restored Japanese rail cards explain date precision at large text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 740);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final original = presentSuicaTrips([_rail()]).single;
      final restored = SuicaTripPresentation.fromJson(original.toJson())!;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: SuicaTripList(trips: [restored]),
            ),
          ),
        ),
      );
      expect(find.text('日本轨道交通'), findsOneWidget);
      expect(find.text('地区未知轨道交通'), findsNothing);
      expect(find.text('仅记录日期'), findsNWidgets(2));
      expect(find.text('本次读取的乘车履历仅含日期，不含进出站时刻。'), findsOneWidget);
      expect(find.text('00:00'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'summary resolves station names and points to the full trip page',
    (tester) async {
      final stations = (await tester.runAsync(_stations))!;
      final scan = FelicaScanResult(
        cardType: 'suica',
        displayName: 'Suica',
        cardProductType: FelicaCardType.suica,
        scannedAt: DateTime(2025, 10, 20),
        wallets: const [_yenWallet],
        transactions: List.generate(6, (index) => _rail(block: index)),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FelicaSummaryPanel(felica: scan, stations: stations),
            ),
          ),
        ),
      );
      expect(find.textContaining('東京 → 新橋'), findsNWidgets(5));
      expect(find.text('JP￥15,000'), findsOneWidget);
      expect(find.textContaining('JP￥900（残高）'), findsNWidgets(5));
      expect(find.textContaining('余额差 -JP￥100'), findsNWidgets(5));
      expect(find.textContaining('JPY ¥'), findsNothing);
      expect(find.textContaining('完整记录见行程页'), findsOneWidget);
      expect(find.textContaining('00:00'), findsNothing);
    },
  );
}

const _yenWallet = FelicaWallet(
  walletId: 'suica.sf',
  kind: FelicaWalletKind.suicaJpy,
  name: 'Suica 电子货币',
  currency: 'JPY',
  balanceMinorUnits: 15000,
  readState: FelicaWalletReadState.success,
);

FelicaTransaction _rail({
  int block = 0,
  int balance = 900,
  int? change = -100,
  String? currency = 'JPY',
  SuicaStationCode? entry,
}) => FelicaTransaction(
  time: DateTime(2025, 10, 20),
  amountMinorUnits: balance,
  decoded: true,
  sequence: block,
  currency: currency,
  walletKind: FelicaWalletKind.suicaJpy,
  amountIsBalance: true,
  rawHex: '16010000335401010103840300000200',
  suica: SuicaTransactionDetails(
    terminalCode: 0x16,
    processCode: 1,
    recordSequence: 2,
    regionCode: 0,
    hasTime: false,
    kind: SuicaRecordKind.rail,
    balanceChangeYen: change,
    entryStation:
        entry ??
        const SuicaStationCode(
          areaCode: 0,
          lineCode: 1,
          stationCode: 1,
          status: SuicaStationStatus.available,
        ),
    exitStation: const SuicaStationCode(
      areaCode: 0,
      lineCode: 1,
      stationCode: 3,
      status: SuicaStationStatus.available,
    ),
  ),
);

FelicaTransaction _record({
  required SuicaRecordKind kind,
  required int process,
  int block = 0,
  int balance = 900,
  int? change,
}) => FelicaTransaction(
  time: DateTime(2025, 10, 20),
  amountMinorUnits: balance,
  decoded: true,
  sequence: block,
  currency: 'JPY',
  walletKind: FelicaWalletKind.suicaJpy,
  amountIsBalance: true,
  rawHex: 'C7460000335400000103840300000200',
  suica: SuicaTransactionDetails(
    terminalCode: kind == SuicaRecordKind.shopping ? 0xC7 : 0x12,
    processCode: process,
    recordSequence: 2,
    regionCode: 0,
    hasTime: kind == SuicaRecordKind.shopping,
    kind: kind,
    balanceChangeYen: change,
  ),
);

Future<SuicaStationRepository> _stations() async {
  final temporary = await Directory.systemTemp.createTemp('trafarch-suica-ui-');
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (_) async => temporary.path);
  final stations = await SuicaStationRepository.load(_PublishedBundle());
  addTearDown(() async {
    stations.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await temporary.delete(recursive: true);
  });
  return stations;
}

class _PublishedBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(await File(key).readAsBytes());
}
