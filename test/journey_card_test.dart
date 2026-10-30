import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_card.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_presenter.dart';
import 'package:transit_card_analyzer/features/trips/trip_filters.dart';

const _detail = TripEntryInfo(
  sourceLabel: '0x18 交易明细',
  title: '出站 · 序号 41',
  isConsume: true,
  amountText: '-¥7.00',
  subText: '交易后余额 ¥118.50',
);

JourneyPresentation<TripEntryInfo> _journey({
  JourneyState state = JourneyState.completed,
  TripModeFilter mode = TripModeFilter.rail,
  String city = '北京',
  String cityCode = '1100',
  String? endCityCode,
  String line = '大兴机场线',
  String? startStation = '草桥',
  String? seatLabel,
  bool fareAdjustment = false,
}) {
  final start = JourneyEndpoint(
    line: line,
    station: startStation,
    time: DateTime(2026, 10, 26, 23, 55),
    timeText: '23:55',
  );
  final end = JourneyEndpoint(
    line: '昌平线',
    station: '沙河',
    time: DateTime(2026, 10, 27, 0, 25),
    timeText: '00:25',
  );
  return JourneyPresentation(
    events: [
      JourneyEvent(
        payload: _detail,
        mode: mode,
        role: fareAdjustment
            ? JourneyEventRole.fareAdjustment
            : state != JourneyState.single
            ? JourneyEventRole.entry
            : JourneyEventRole.single,
        endpoint: start,
        cityCode: cityCode,
      ),
      if (state == JourneyState.completed)
        JourneyEvent(
          payload: _detail,
          mode: mode,
          role: JourneyEventRole.exit,
          endpoint: end,
          cityCode: endCityCode ?? cityCode,
        ),
    ],
    mode: mode,
    cityLabel: city,
    state: state,
    start: state == JourneyState.single ? null : start,
    end: state == JourneyState.completed ? end : null,
    duration: state == JourneyState.completed && !fareAdjustment
        ? const Duration(minutes: 30)
        : null,
    amountText: state == JourneyState.inProgress ? null : '-¥7.00',
    fareAdjustmentAmountText: fareAdjustment ? '-¥3.00' : null,
    balanceAfterText: '¥118.50',
    seatLabel: seatLabel,
  );
}

Future<void> _show(
  WidgetTester tester,
  JourneyPresentation<TripEntryInfo> journey, {
  Size size = const Size(400, 800),
  double scale = 1,
  Brightness brightness = Brightness.light,
  bool remote = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: brightness,
        ),
      ),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: TripEntryCard(
              info: _detail,
              remote: remote,
              onTap: () {},
              journey: journey,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('补票行程在窄屏字体$scale下分别显示两笔金额及补票标签', (tester) async {
      await _show(
        tester,
        _journey(fareAdjustment: true, line: '首都机场至城市副中心特别长的线路名称'),
        size: const Size(320, 1100),
        scale: scale,
        remote: true,
      );
      expect(find.text('补票'), findsOneWidget);
      _expectFareLabelAtStation(tester, '草桥');
      expect(find.text('补票 -¥3.00'), findsOneWidget);
      expect(find.text('出站 -¥7.00'), findsOneWidget);
      expect(find.text('行程后余额 ¥118.50'), findsOneWidget);
      expect(find.text('30分钟'), findsNothing);
      final arrow = tester.getCenter(
        find.byKey(const ValueKey('journey-arrow')),
      );
      expect(arrow.dy, closeTo(tester.getCenter(find.text('草桥')).dy, 0.5));
      expect(arrow.dy, closeTo(tester.getCenter(find.text('沙河')).dy, 0.5));
      expect(tester.takeException(), isNull);
    });
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('孤立补票卡片在窄屏字体$scale下于长站名右上角显示补票', (tester) async {
      final event = _journey(
        fareAdjustment: true,
        startStation: '中国轻纺城',
      ).events.first;
      await _show(
        tester,
        projectJourneys([event]).single,
        size: const Size(320, 1100),
        scale: scale,
      );
      expect(find.text('补票'), findsOneWidget);
      _expectFareLabelAtStation(tester, '中国轻纺城');
      expect(find.byKey(const ValueKey('journey-arrow')), findsNothing);
      expect(find.text('沙河'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('补票站点缺失时仍在占位站名右上角显示补票', (tester) async {
    final event = _journey(
      fareAdjustment: true,
      startStation: null,
    ).events.first;
    await _show(tester, projectJourneys([event]).single);
    _expectFareLabelAtStation(tester, '站点未记录');
    expect(tester.takeException(), isNull);
  });

  testWidgets('地铁名称不追加站且箭头与两端站名垂直居中对齐', (tester) async {
    await _show(tester, _journey());
    expect(find.text('草桥站'), findsNothing);
    expect(find.text('沙河站'), findsNothing);
    final arrow = tester.getCenter(find.byKey(const ValueKey('journey-arrow')));
    final start = tester.getCenter(find.text('草桥'));
    final end = tester.getCenter(find.text('沙河'));
    expect(arrow.dy, closeTo(start.dy, 0.5));
    expect(arrow.dy, closeTo(end.dy, 0.5));
    expect(arrow.dx, greaterThan(start.dx));
    expect(arrow.dx, lessThan(end.dx));
  });

  testWidgets('完成卡显示两端线路站点跨日时长及扣款右侧的行程后余额', (tester) async {
    await _show(tester, _journey());
    expect(find.text('北京轨道交通'), findsOneWidget);
    expect(find.text('大兴机场线'), findsOneWidget);
    expect(find.text('草桥'), findsOneWidget);
    expect(find.text('昌平线'), findsOneWidget);
    expect(find.text('沙河'), findsOneWidget);
    expect(find.textContaining('23:55'), findsOneWidget);
    expect(find.textContaining('00:25'), findsOneWidget);
    expect(find.text('30分钟'), findsOneWidget);
    expect(find.text('2026年10月26日'), findsOneWidget);
    expect(find.text('-¥7.00'), findsOneWidget);
    expect(find.text('行程后余额 ¥118.50'), findsOneWidget);
    expect(
      tester.getCenter(find.text('行程后余额 ¥118.50')).dx,
      greaterThan(tester.getCenter(find.text('-¥7.00')).dx),
    );
    expect(find.textContaining('普通座'), findsNothing);
  });
  testWidgets('行程提示隐藏终点时长扣款，详情中的金额不得泄漏到卡片', (tester) async {
    await _show(tester, _journey(state: JourneyState.inProgress));
    expect(find.text('草桥'), findsOneWidget);
    expect(find.text('沙河'), findsNothing);
    expect(find.textContaining('分钟'), findsNothing);
    expect(find.textContaining('¥'), findsNothing);
    expect(find.textContaining('行程后余额'), findsNothing);
    expect(find.byKey(const ValueKey('journey-arrow')), findsNothing);
  });
  for (final (mode, title) in [
    (TripModeFilter.rail, '轨道交通'),
    (TripModeFilter.bus, '公共汽电车'),
  ]) {
    testWidgets('跨城$title行程标题不采用单一受理城市', (tester) async {
      await _show(
        tester,
        _journey(mode: mode, city: '绍兴', cityCode: '3370', endCityCode: '3310'),
      );
      expect(find.text(title), findsOneWidget);
      expect(find.text('绍兴$title'), findsNothing);
      expect(find.text('杭州$title'), findsNothing);
    });

    testWidgets('异地卡同城$title行程标题保留实际受理城市', (tester) async {
      await _show(
        tester,
        _journey(mode: mode, city: '杭州', cityCode: '3310'),
        remote: true,
      );
      expect(find.text('杭州$title'), findsOneWidget);
      expect(find.text(title), findsNothing);
      final badge = find.text('异地用卡');
      final menu = find.byTooltip('查看行程记录');
      expect(badge, findsOneWidget);
      expect(
        tester.getRect(badge).left,
        greaterThan(tester.getRect(find.text('杭州$title')).right),
      );
      expect(tester.getRect(badge).right, lessThan(tester.getRect(menu).left));
      expect(
        tester.getCenter(badge).dy,
        closeTo(tester.getCenter(menu).dy, 0.5),
      );
    });

    testWidgets('本地$title行程不显示异地标识', (tester) async {
      await _show(tester, _journey(mode: mode));
      expect(find.text('异地用卡'), findsNothing);
    });

    for (final state in [JourneyState.inProgress, JourneyState.single]) {
      testWidgets('异地$title的$state行程也显示标识', (tester) async {
        await _show(tester, _journey(mode: mode, state: state), remote: true);
        expect(find.text('异地用卡'), findsOneWidget);
      });
    }
  }
  for (final unknown in ['', '0000', 'ffff', '0F0F']) {
    testWidgets('未知城市$unknown不构成跨城标题证据', (tester) async {
      await _show(tester, _journey(endCityCode: unknown));
      expect(find.text('北京轨道交通'), findsOneWidget);
      expect(find.text('轨道交通'), findsNothing);
    });
  }
  testWidgets('单次公交仅展示线路及日期金额，不虚构上下车站', (tester) async {
    await _show(
      tester,
      _journey(
        state: JourneyState.single,
        mode: TripModeFilter.bus,
        city: '太原',
        line: '100路',
      ),
    );
    expect(find.text('太原公共汽电车'), findsOneWidget);
    expect(find.text('100路'), findsOneWidget);
    expect(find.text('草桥'), findsNothing);
    expect(find.textContaining('23:55'), findsNothing);
    expect(find.byKey(const ValueKey('journey-arrow')), findsNothing);
    expect(find.text('-¥7.00'), findsOneWidget);
  });
  testWidgets('只有明确提供的席别才显示', (tester) async {
    await _show(tester, _journey(seatLabel: '商务座'));
    expect(find.text('商务座'), findsOneWidget);
    await _show(tester, _journey());
    expect(find.text('商务座'), findsNothing);
    expect(find.text('普通座'), findsNothing);
  });
  testWidgets('窄屏长线路大字体及深色模式无溢出', (tester) async {
    await _show(
      tester,
      _journey(line: '首都机场至城市副中心特别长的线路名称'),
      size: const Size(320, 1000),
      scale: 2,
      brightness: Brightness.dark,
      remote: true,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('沙河'), findsOneWidget);
    expect(find.text('异地用卡'), findsOneWidget);
  });
}

void _expectFareLabelAtStation(WidgetTester tester, String station) {
  final stationFinder = find.text(station);
  final labelFinder = find.text('补票');
  final stationRect = tester.getRect(stationFinder);
  final labelRect = tester.getRect(labelFinder);
  expect(labelRect.left, greaterThan(stationRect.right));
  expect(labelRect.center.dy, lessThan(stationRect.center.dy));
  expect(
    tester.widget<Text>(labelFinder).style!.fontSize,
    lessThan(tester.widget<Text>(stationFinder).style!.fontSize!),
  );
}
