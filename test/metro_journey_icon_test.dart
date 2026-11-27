import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/trips/journey_transport_icon.dart';
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

void main() {
  testWidgets('custom badge size and fallback survive a missing city asset', (
    tester,
  ) async {
    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: _MissingBundle(),
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              child: JourneyTransportIcon(
                mode: TripModeFilter.rail,
                cityLabel: '上海',
                isCrossCity: false,
                size: 23,
                fallbackIcon: Icons.train_outlined,
                fallbackColor: Colors.teal,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final fallback = find.byIcon(Icons.train_outlined);
    expect(fallback, findsOneWidget);
    expect(tester.widget<Icon>(fallback).color, Colors.teal);
    expect(tester.widget<Icon>(fallback).size, 23);
    expect(tester.takeException(), isNull);
  });

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

class _MissingBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) =>
      Future.error(StateError('synthetic missing SVG'));
}
