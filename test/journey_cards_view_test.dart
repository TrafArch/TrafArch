import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/features/trips/trip_cards_view.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_card.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_presenter.dart';
import 'package:transit_card_analyzer/features/trips/trip_filters.dart';

TripCardPresentation<TripSourceFilter> event({
  required int sequence,
  required DateTime time,
  required String line,
  required String station,
  required JourneyEventRole role,
  String city = '北京',
  String code = '1000',
  bool remote = false,
  TripModeFilter mode = TripModeFilter.rail,
  String? amount,
  String? balance,
  String? recordedBalance,
  TripSourceFilter source = TripSourceFilter.transaction,
}) {
  final status = role == JourneyEventRole.entry ? '进站' : '出站';
  final info = TripEntryInfo(
    sourceLabel: '0x18 交易明细',
    title: '$status · $station · 序号 $sequence',
    isConsume: true,
    amountText: amount,
    subText: recordedBalance == null ? null : '记录余额 $recordedBalance',
    fields: [('交易序号', '$sequence'), ('站点', station)],
  );
  return TripCardPresentation(
    info: info,
    source: source,
    mode: mode,
    dateText: '2026-10-27',
    remote: remote,
    journeyEvent: JourneyEvent(
      payload: info,
      mode: mode,
      role: role,
      scopeKey: 'one-wallet',
      sourceIds: const {'one-scan'},
      cityCode: code,
      cityLabel: city,
      sequence: sequence,
      amountText: amount,
      balanceAfterText: balance,
      endpoint: JourneyEndpoint(
        line: line,
        station: station,
        time: time,
        timeText:
            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
      ),
    ),
  );
}

List<TripCardPresentation<TripSourceFilter>> sample() => [
  event(
    sequence: 44,
    time: DateTime(2026, 10, 27, 18, 9),
    line: '昌平线',
    station: '沙河',
    role: JourneyEventRole.entry,
    amount: '-¥0.00',
  ),
  event(
    sequence: 43,
    time: DateTime(2026, 10, 27, 12, 44),
    line: '2号线',
    station: '东直门',
    role: JourneyEventRole.exit,
    amount: '-¥25.00',
    balance: '¥118.50',
    remote: true,
  ),
  event(
    sequence: 42,
    time: DateTime(2026, 10, 27, 12, 7),
    line: '首都机场线',
    station: '3号航站楼',
    role: JourneyEventRole.entry,
    amount: '-¥0.00',
    remote: true,
  ),
  event(
    sequence: 40,
    time: DateTime(2026, 10, 26, 9, 25),
    line: '100路',
    station: '不应展示的单次扣款站点',
    role: JourneyEventRole.single,
    city: '太原',
    code: '1610',
    mode: TripModeFilter.bus,
    amount: '-¥1.00',
    balance: '¥143.50',
    remote: true,
  ),
  event(
    sequence: 38,
    time: DateTime(2026, 10, 25, 9, 9),
    line: '345路',
    station: '站点29',
    role: JourneyEventRole.exit,
    mode: TripModeFilter.bus,
    amount: '-¥3.00',
    balance: '¥144.50',
  ),
  event(
    sequence: 37,
    time: DateTime(2026, 10, 25, 8, 42),
    line: '345路',
    station: '站点17',
    role: JourneyEventRole.entry,
    mode: TripModeFilter.bus,
    amount: '-¥0.00',
  ),
];

Future<void> pumpCards(
  WidgetTester tester,
  List<TripCardPresentation<TripSourceFilter>> entries, {
  GlobalKey? previewKey,
  String? font,
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        fontFamily: font,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: brightness,
        ),
      ),
      home: RepaintBoundary(
        key: previewKey,
        child: Scaffold(
          appBar: AppBar(title: const Text('行程')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: TripCardsView(
              entries: entries,
              sourceLabels: tripSourceLabels,
              summaryText: '交易 ${entries.length} 笔',
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('跨城行程任一端异地只显示一个标识且更多菜单仍打开两端详情', (tester) async {
    await pumpCards(tester, [
      event(
        sequence: 43,
        time: DateTime(2026, 10, 27, 12, 44),
        line: '2号线',
        station: '东直门',
        role: JourneyEventRole.exit,
        remote: false,
      ),
      event(
        sequence: 42,
        time: DateTime(2026, 10, 27, 12, 7),
        line: '1号线',
        station: '起点',
        city: '异地',
        code: '2900',
        role: JourneyEventRole.entry,
        remote: true,
      ),
    ]);
    expect(find.byType(TripEntryCard), findsOneWidget);
    expect(find.text('轨道交通'), findsOneWidget);
    expect(find.text('异地用卡'), findsOneWidget);
    await tester.tap(find.byTooltip('查看行程记录'));
    await tester.pumpAndSettle();
    expect(find.textContaining('序号 42'), findsOneWidget);
    expect(find.textContaining('序号 43'), findsOneWidget);
  });

  testWidgets('进出站原始余额一致时仍区分出站后的投影余额', (tester) async {
    await pumpCards(tester, [
      event(
        sequence: 29,
        time: DateTime(2026, 9, 20, 13, 19, 30),
        line: '8号线',
        station: '奥林匹克公园',
        role: JourneyEventRole.exit,
        amount: '-¥6.00',
        balance: '¥165.50',
        recordedBalance: '¥171.50',
      ),
      event(
        sequence: 28,
        time: DateTime(2026, 9, 20, 12, 34),
        line: '昌平线',
        station: '沙河',
        role: JourneyEventRole.entry,
        amount: '-¥0.00',
        recordedBalance: '¥171.50',
      ),
    ]);
    await tester.tap(find.byType(TripEntryCard));
    await tester.pumpAndSettle();
    expect(find.textContaining('出站后余额 ¥165.50'), findsOneWidget);
    expect(find.textContaining('记录余额 ¥171.50'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('两条交易呈现完整行程且两侧详情均可打开', (tester) async {
    final entries = sample().sublist(1, 3);
    await pumpCards(tester, entries);
    expect(find.byType(TripEntryCard), findsOneWidget);
    expect(find.text('行程信息提示 0'), findsOneWidget);
    expect(find.text('历史行程 1'), findsOneWidget);
    expect(find.text('37分钟'), findsOneWidget);
    await tester.tap(find.byType(TripEntryCard));
    await tester.pumpAndSettle();
    expect(find.textContaining('序号 42'), findsOneWidget);
    expect(find.textContaining('序号 43'), findsOneWidget);
    await tester.tap(find.textContaining('序号 43'));
    await tester.pumpAndSettle();
    expect(find.text('交易序号'), findsOneWidget);
    expect(find.text('43'), findsOneWidget);
  });

  testWidgets('进行中、单次公交、分段公交使用不同布局且截图可复查', (tester) async {
    tester.view.physicalSize = const Size(430, 1450);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final output = Platform.environment['TRAFARCH_VISUAL_REVIEW_DIR'];
    String? font;
    if (output != null) {
      final iconFont = Platform.environment['TRAFARCH_VISUAL_ICON_FONT'];
      if (iconFont != null) {
        final icons = FontLoader('MaterialIcons')
          ..addFont(
            Future.value(
              ByteData.sublistView(File(iconFont).readAsBytesSync()),
            ),
          );
        await icons.load();
      }
      final fontFile = Platform.environment['TRAFARCH_VISUAL_FONT'];
      if (fontFile != null) {
        font = 'JourneyPreview';
        final loader = FontLoader(font)
          ..addFont(
            Future.value(
              ByteData.sublistView(File(fontFile).readAsBytesSync()),
            ),
          );
        await loader.load();
      }
    }
    final key = GlobalKey();
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await pumpCards(
        tester,
        sample(),
        previewKey: key,
        font: font,
        brightness: brightness,
      );
      expect(find.byType(TripEntryCard), findsNWidgets(4));
      expect(find.text('行程信息提示 1'), findsOneWidget);
      expect(find.text('历史行程 3'), findsOneWidget);
      expect(find.text('-¥0.00'), findsNothing);
      expect(find.textContaining('不应展示'), findsNothing);
      expect(find.text('站点17'), findsOneWidget);
      expect(find.text('站点29'), findsOneWidget);
      expect(find.text('27分钟'), findsOneWidget);
      expect(find.text('异地用卡'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      if (output != null) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final rendered = await boundary.toImage(pixelRatio: 2);
          final bytes = await rendered.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final target = File('$output/journeys-${brightness.name}.png');
          await target.parent.create(recursive: true);
          await target.writeAsBytes(bytes!.buffer.asUint8List());
          rendered.dispose();
        });
      }
    }
  });
}
