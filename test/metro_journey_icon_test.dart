import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/features/trips/journey_transport_icon.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_card.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_presenter.dart';
import 'package:transit_card_analyzer/features/trips/trip_filters.dart';

const _cities = <String, String>{
  '北京': 'beijing',
  '长春': 'changchun',
  '长沙': 'changsha',
  '常州': 'changzhou',
  '成都': 'chengdu',
  '重庆': 'chongqing',
  '大连': 'dalian',
  '东莞': 'dongguan',
  '佛山': 'foshan',
  '福州': 'fuzhou',
  '广州': 'guangzhou',
  '贵阳': 'guiyang',
  '海宁': 'haining',
  '杭州': 'hangzhou',
  '哈尔滨': 'harbin',
  '合肥': 'hefei',
  '香港': 'hongkong',
  '呼和浩特': 'huhhot',
  '济南': 'jinan',
  '金华': 'jinhua',
  '高雄': 'kaohsiung',
  '昆明': 'kunming',
  '兰州': 'lanzhou',
  '柳州': 'liuzhou',
  '洛阳': 'luoyang',
  '澳门': 'macau',
  '南昌': 'nanchang',
  '南京': 'nanjing',
  '南宁': 'nanning',
  '南通': 'nantong',
  '新北': 'newtaipei',
  '宁波': 'ningbo',
  '青岛': 'qingdao',
  '上海': 'shanghai',
  '绍兴': 'shaoxing',
  '沈阳': 'shenyang',
  '深圳': 'shenzhen',
  '石家庄': 'shijiazhuang',
  '苏州': 'suzhou',
  '台中': 'taichung',
  '台北': 'taipei',
  '太原': 'taiyuan',
  '台州': 'taizhou',
  '桃园': 'taoyuan',
  '天津': 'tianjin',
  '乌鲁木齐': 'urumqi',
  '温州': 'wenzhou',
  '芜湖': 'wuhu',
  '无锡': 'wuxi',
  '厦门': 'xiamen',
  '西安': 'xian',
  '徐州': 'xuzhou',
  '郑州': 'zhengzhou',
  '武汉': 'wuhan',
};
const _info = TripEntryInfo(
  sourceLabel: 'test',
  title: 'test',
  isConsume: true,
);

void main() {
  for (final city in _cities.entries) {
    testWidgets('${city.key} rail ticket displays its supplied SVG', (
      tester,
    ) async {
      await _show(tester, _journey(city: city.key));
      expect(find.byType(SvgPicture), findsOneWidget);
      final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(
        (picture.bytesLoader as SvgAssetLoader).assetName,
        'assets/metro/metro_logo_${city.value}.svg',
      );
      expect(picture.colorFilter, isNull);
      expect(tester.getSize(find.byType(SvgPicture)), const Size(21, 21));
      expect(find.byIcon(Icons.subway_outlined), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final alias in <String, String>{
    ' 北京市 ': 'beijing',
    '太原市': 'taiyuan',
    '臺北市': 'taipei',
    '臺中': 'taichung',
    '桃園市': 'taoyuan',
    '新北市': 'newtaipei',
    '香港特别行政区': 'hongkong',
    '澳門特別行政區': 'macau',
  }.entries) {
    testWidgets('${alias.key} resolves only an explicit city alias', (
      tester,
    ) async {
      await _show(tester, _journey(city: alias.key));
      expect(
        (tester.widget<SvgPicture>(find.byType(SvgPicture)).bytesLoader
                as SvgAssetLoader)
            .assetName,
        'assets/metro/metro_logo_${alias.value}.svg',
      );
    });
  }

  for (final city in [
    null,
    '',
    '地区未知',
    '未知城市',
    '地区 1000',
    '泰州',
    '北京市郊',
    '北京 / 太原',
  ]) {
    testWidgets('unknown or unprovided city $city uses the generic rail icon', (
      tester,
    ) async {
      await _show(tester, _journey(city: city));
      expect(find.byType(SvgPicture), findsNothing);
      expect(find.byIcon(Icons.subway_outlined), findsOneWidget);
    });
  }

  testWidgets(
    'cross-city ticket keeps generic rail icon despite a city label',
    (tester) async {
      final start = _event('1000', '北京', JourneyEventRole.entry);
      final end = _event('3510', '太原', JourneyEventRole.exit);
      await _show(
        tester,
        JourneyPresentation(
          events: [start, end],
          mode: TripModeFilter.rail,
          state: JourneyState.completed,
          cityLabel: '北京',
          start: start.endpoint,
          end: end.endpoint,
        ),
      );
      expect(find.byType(SvgPicture), findsNothing);
      expect(find.byIcon(Icons.subway_outlined), findsOneWidget);
    },
  );

  testWidgets('known city does not replace the bus icon', (tester) async {
    await _show(tester, _journey(city: '北京', mode: TripModeFilter.bus));
    expect(find.byType(SvgPicture), findsNothing);
    expect(find.byIcon(Icons.directions_bus_outlined), findsOneWidget);
  });

  for (final state in [
    JourneyState.completed,
    JourneyState.inProgress,
    JourneyState.incomplete,
  ]) {
    testWidgets('known-city $state ticket has a logo', (tester) async {
      await _show(tester, _journey(city: '北京', state: state), remote: true);
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.text('异地用卡'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('asset load error falls back to the rail icon', (tester) async {
    await _show(tester, _journey(city: '北京'), bundle: _MissingBundle());
    expect(find.byIcon(Icons.subway_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark-theme load error uses the original rail icon color', (
    tester,
  ) async {
    await _show(
      tester,
      _journey(city: '北京'),
      bundle: _MissingBundle(),
      brightness: Brightness.dark,
    );
    final iconFinder = find.byIcon(Icons.subway_outlined);
    expect(iconFinder, findsOneWidget);
    expect(
      tester.widget<Icon>(iconFinder).color,
      Theme.of(tester.element(iconFinder)).colorScheme.primary,
    );
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('$brightness theme preserves logo colors and ticket layout', (
      tester,
    ) async {
      await _show(
        tester,
        _journey(city: '北京'),
        brightness: brightness,
        textScaler: const TextScaler.linear(2),
      );
      expect(
        tester.widget<SvgPicture>(find.byType(SvgPicture)).colorFilter,
        isNull,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('$brightness theme leaves SVG surroundings transparent', (
      tester,
    ) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: key,
                child: const JourneyTransportIcon(
                  mode: TripModeFilter.rail,
                  cityLabel: '北京',
                  isCrossCity: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final pixels = await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        try {
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
          var transparent = 0;
          var painted = 0;
          var white = 0;
          for (var index = 0; index < data.length; index += 4) {
            if (data[index + 3] == 0) transparent++;
            if (data[index + 3] > 128) painted++;
            if (data[index] > 200 &&
                data[index + 1] > 200 &&
                data[index + 2] > 200 &&
                data[index + 3] > 200) {
              white++;
            }
          }
          return (transparent: transparent, painted: painted, white: white);
        } finally {
          image.dispose();
        }
      });
      expect(pixels!.transparent, greaterThan(100));
      expect(pixels.painted, greaterThan(20));
      expect(pixels.white, 0);
      expect(
        tester.widget<SvgPicture>(find.byType(SvgPicture)).colorFilter,
        isNull,
      );
    });
  }

  test('all supplied SVGs decode and render nonempty colored pixels', () async {
    for (final city in _cities.entries) {
      final picture = await vg.loadPicture(
        SvgAssetLoader('assets/metro/metro_logo_${city.value}.svg'),
        null,
      );
      final image = await picture.picture.toImage(100, 100);
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      var colored = 0;
      for (var index = 0; index < pixels.length; index += 4) {
        if (pixels[index + 3] > 128 &&
            (pixels[index] != pixels[index + 1] ||
                pixels[index + 1] != pixels[index + 2])) {
          colored++;
        }
      }
      expect(colored, greaterThan(10), reason: city.key);
      image.dispose();
      picture.picture.dispose();
    }
  });

  testWidgets('logo contact sheet renders in both themes', (tester) async {
    final output = Platform.environment['TRAFARCH_METRO_PREVIEW_DIR'];
    final fontPath = Platform.environment['TRAFARCH_METRO_PREVIEW_FONT'];
    String? font;
    if (output != null && fontPath != null) {
      font = 'MetroPreview';
      await (FontLoader(font)..addFont(
            Future.value(
              ByteData.sublistView(File(fontPath).readAsBytesSync()),
            ),
          ))
          .load();
    }
    tester.view.physicalSize = const Size(900, 1320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: boundary,
          child: Column(
            children: [
              for (final brightness in Brightness.values)
                Theme(
                  data: ThemeData(brightness: brightness, fontFamily: font),
                  child: Builder(
                    builder: (context) => ColoredBox(
                      color: Theme.of(context).colorScheme.surface,
                      child: SizedBox(
                        height: 660,
                        child: GridView.count(
                          crossAxisCount: 9,
                          childAspectRatio: 1.1,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(12),
                          children: [
                            for (final city in _cities.entries)
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SvgPicture.asset(
                                    'assets/metro/metro_logo_${city.value}.svg',
                                    width: 36,
                                    height: 36,
                                  ),
                                  Text(
                                    city.key,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (output != null) {
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        try {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$output/metro-logo-preview.png')
              .writeAsBytes(png!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }
  });
}

JourneyEvent<TripEntryInfo> _event(
  String code,
  String city,
  JourneyEventRole role,
) => JourneyEvent(
  payload: _info,
  mode: TripModeFilter.rail,
  role: role,
  cityCode: code,
  cityLabel: city,
  endpoint: JourneyEndpoint(station: '示例', time: DateTime(2026, 11, 12)),
);

JourneyPresentation<TripEntryInfo> _journey({
  String? city,
  TripModeFilter mode = TripModeFilter.rail,
  JourneyState state = JourneyState.single,
}) {
  final start = _event('1000', city ?? '', JourneyEventRole.entry);
  final end = _event('1000', city ?? '', JourneyEventRole.exit);
  return JourneyPresentation(
    events: [start, end],
    mode: mode,
    state: state,
    cityLabel: city,
    start: state == JourneyState.single || state == JourneyState.incomplete
        ? null
        : start.endpoint,
    end: state == JourneyState.completed || state == JourneyState.incomplete
        ? end.endpoint
        : null,
  );
}

Future<void> _show(
  WidgetTester tester,
  JourneyPresentation<TripEntryInfo> journey, {
  bool remote = false,
  AssetBundle? bundle,
  Brightness brightness = Brightness.light,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  Widget child = MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: MediaQuery(
      data: MediaQueryData(textScaler: textScaler),
      child: Scaffold(
        body: SingleChildScrollView(
          child: TripEntryCard(
            info: _info,
            remote: remote,
            onTap: () {},
            journey: journey,
          ),
        ),
      ),
    ),
  );
  if (bundle != null) child = DefaultAssetBundle(bundle: bundle, child: child);
  await tester.pumpWidget(child);
  await tester.pumpAndSettle();
}

class _MissingBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) =>
      Future.error(StateError('synthetic missing SVG'));
}
