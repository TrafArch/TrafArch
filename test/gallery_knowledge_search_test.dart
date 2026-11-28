import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';
import 'package:transit_card_analyzer/gallery/gallery_knowledge_index.dart';
import 'package:transit_card_analyzer/gallery/gallery_theme.dart';

import 'support/gallery_scroll.dart';
import 'support/gallery_wallpaper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GalleryKnowledgeIndex index;
  setUpAll(() {
    index = GalleryKnowledgeIndex.fromPaths({
      for (final system in ['TU', 'CU'])
        system: File('assets/data/TrafArch_Database_$system.sqlite')
            .absolute
            .path,
    });
  });

  test('published search spans both systems and retains exact source keys', () {
    final cities = index.search(' 上海 ')[GalleryKnowledgeKind.city]!;
    expect(cities.map((result) => result.city.system), ['TU', 'CU']);
    expect(cities.every((result) => result.city.codeCount > 0), isTrue);
    final lines = index.search('１号线')[GalleryKnowledgeKind.line]!;
    expect(lines.first.title, '1号线');
    expect(lines.any((result) => result.city.system == 'CU'), isTrue);
    final stations = index.search('航中路')[GalleryKnowledgeKind.station]!;
    expect(
      stations.map((result) => result.city.system),
      containsAll(['TU', 'CU']),
    );
    final codes = index.search('290000100018')[GalleryKnowledgeKind.code]!;
    expect(codes.first.code, '290000100018');
    expect(codes.first.station!.name, '航中路');
    expect(codes.first.line!.name, '10号线');
    expect(codes.first.source, 'M0.i0.a');
    expect(index.search('29000010001')[GalleryKnowledgeKind.code], isNotEmpty);
    expect(index.search('00100018')[GalleryKnowledgeKind.code], isNull);
  });

  test('line codes resolve to their own line with original spelling', () {
    for (final (system, city, line, code) in [
      ('TU', '2900', '10号线', '29000010'),
      ('TU', '2900', '10号线', '0010'),
      ('TU', '3910', '1号线', '01'),
      ('TU', '3030', '6号线', '0006'),
      ('TU', '1000', '昌平线', '5E'),
      ('TU', '2900', '朱泾7', '1657'),
      ('TU', '5810', '广清城际', '0070'),
      ('TU', '5810', '广州东环城际', '0071'),
      ('TU', '5810', '广肇城际', '0072'),
      ('TU', '5810', '广惠城际', '0073'),
      ('TU', '5810', '琶莲城际', '0074'),
      ('TU', '5810', '广州东环城际', '0075'),
      ('TU', '5810', '广州东环城际', '0076'),
      ('TU', '5810', '新白广城际', '0077'),
      ('TU', '5810', '穗深城际', '0078'),
      ('TU', '6110', '1号线', '611000000001'),
      ('CU', '2000', '10号线', '1110'),
      ('CU', '2150', '1号线', '03000003'),
      ('CU', '2500', '4号线', '04'),
      ('CU', '2500', '4号线', '00000000000004'),
    ]) {
      final hits = index.search(code)[GalleryKnowledgeKind.code] ?? [];
      expect(
        hits.where(
          (hit) =>
              hit.code == code &&
              hit.city.system == system &&
              hit.city.code == city &&
              hit.line?.name == line &&
              hit.station == null &&
              hit.line!.codes.contains(code),
        ),
        hasLength(1),
        reason: '$system $city $line $code',
      );
    }
  });

  test('station and terminal keys stay separate from line codes', () {
    GalleryKnowledgeLine line(String system, String cityCode, String name) =>
        index.cities
            .singleWhere(
              (city) => city.system == system && city.code == cityCode,
            )
            .lines
            .singleWhere((line) => line.name == name);
    expect(line('TU', '2900', '10号线').codes, isNot(contains('290000100018')));
    expect(line('TU', '1610', '2').codes, isEmpty);
    expect(line('CU', '2000', '浦江线').codes, isNot(contains('1108')));
    expect(line('CU', '2000', '8号线').codes, contains('1108'));
  });

  test('default loader validates the bundled packages and builds the index off-isolate', () async {
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final support = await Directory.systemTemp.createTemp(
      'trafarch-gallery-search-',
    );
    addTearDown(() => support.delete(recursive: true));
    messenger.setMockMethodCallHandler(paths, (_) async => support.path);
    addTearDown(() => messenger.setMockMethodCallHandler(paths, null));
    final loaded = await GalleryKnowledgeIndex.load();
    expect(
      loaded
          .search('2000111018')[GalleryKnowledgeKind.code]!
          .first
          .station!
          .name,
      '航中路',
    );
  });

  Future<GalleryController> openKnowledge(
    WidgetTester tester,
    Future<GalleryKnowledgeIndex> Function() load,
  ) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = GalleryController(
      GalleryData(
        jsonDecode(File('assets/gallery/fixtures.json').readAsStringSync())
            as GalleryRecord,
      ),
    )..navigate(GalleryPage.knowledge);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      GalleryApp(controller: controller, loadKnowledgeIndex: load),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  final entry = find.byKey(const ValueKey('knowledge-search-entry'));
  final input = find.byKey(const ValueKey('knowledge-search-input'));

  testWidgets(
    'search debounces, preserves focus on theme changes and routes to the exact station',
    (tester) async {
      mockGalleryWallpaper(tester, () => const Color(0xff497253));
      var loads = 0;
      final controller = await openKnowledge(tester, () async {
        loads++;
        return index;
      });
      expect(
        tester.getTopLeft(entry).dy,
        greaterThan(tester.getTopLeft(find.text('知识库')).dy),
      );
      expect(
        tester.getTopLeft(entry).dy,
        lessThan(tester.getTopLeft(find.text('交通联合 TU')).dy),
      );
      expect(tester.getSize(entry).height, 52);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.text('查找知识库'), findsOneWidget);
      final field = tester.widget<TextField>(input);
      expect(field.focusNode!.hasFocus, isTrue);
      await tester.enterText(input, '290000100018');
      await tester.pump(const Duration(milliseconds: 279));
      expect(loads, 0);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(loads, 1);

      final initialRect = tester.getRect(input);
      for (final palette in [
        'blue',
        'teal',
        'violet',
        'rose',
        'amber',
        'mist',
      ]) {
        for (final mode in [ThemeMode.light, ThemeMode.dark]) {
          controller.update(() {
            controller.monet = false;
            controller.palette = palette;
            controller.themeMode = mode;
          });
          await tester.pumpAndSettle();
          final current = tester.widget<TextField>(input);
          final tokens = Theme.of(tester.element(input))
              .extension<GalleryTokens>()!;
          expect(current.decoration!.fillColor, tokens.inputContainer);
          expect(
            current.decoration!.focusedBorder!.borderSide.color,
            tokens.inputFocusedOutline,
          );
          expect(current.controller, same(field.controller));
          expect(current.focusNode!.hasFocus, isTrue);
          expect(tester.getRect(input), initialRect);
        }
      }
      controller.update(() => controller.monet = true);
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(input)).extension<GalleryTokens>()!.dynamic,
        isTrue,
      );
      expect(tester.widget<TextField>(input).controller, same(field.controller));
      expect(field.focusNode!.hasFocus, isTrue);
      expect(loads, 1);
      await tester.tap(find.widgetWithText(ListTile, '290000100018').first);
      await tester.pumpAndSettle();
      // US-008：编码结果并入二级城市页，不再有站点详情页（spec §2.1/§12）。
      expect(controller.page, GalleryPage.knowledgeCity);
      expect(controller.knowledgeCityLine, '10号线');
      expect(controller.knowledgeCityStation, '航中路');
      expect(controller.knowledgeCityCode, '290000100018');
      expect(find.text('匹配编码 290000100018'), findsOneWidget);
      expect(find.text('航中路'), findsOneWidget);
      final city = controller.selectedKnowledgeCity!;
      final lineIndex = city.lines.indexWhere(
        (line) => line.name == controller.knowledgeCityLine,
      );
      final stationIndex = city.lines[lineIndex].stations.indexWhere(
        (station) => station.name == '航中路',
      );
      expect(stationIndex, greaterThanOrEqualTo(0));
      final row = find.byKey(
        ValueKey('knowledge-city-station-${city.system}:$lineIndex:$stationIndex'),
      );
      expect(row, findsOneWidget);
      final tokens = Theme.of(tester.element(row)).extension<GalleryTokens>()!;
      expect(
        (tester.widget<Container>(row).decoration! as BoxDecoration).color,
        tokens.tone,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(controller.page, GalleryPage.knowledgeSearch);
      expect(tester.widget<TextField>(input).controller!.text, '290000100018');
      await tester.tap(find.byTooltip('清除搜索'));
      await tester.pumpAndSettle();
      expect(find.text('查找知识库'), findsOneWidget);
      expect(find.byTooltip('清除搜索'), findsNothing);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(controller.page, GalleryPage.knowledge);
      expect(entry, findsOneWidget);
    },
  );

  testWidgets(
    'city and line results keep the search query and scroll when popping',
    (tester) async {
      final controller = await openKnowledge(tester, () async => index);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      await tester.enterText(input, '上海');
      await tester.pump(const Duration(milliseconds: 280));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, '上海').first);
      await tester.pumpAndSettle();
      expect(controller.page, GalleryPage.knowledgeCity);
      expect(controller.selectedKnowledgeCity?.name, '上海');
      expect(controller.knowledgeCityLine, isNull);
      expect(find.text('城市编码'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(controller.page, GalleryPage.knowledgeSearch);
      await tester.enterText(input, '号线');
      await tester.pump(const Duration(milliseconds: 280));
      await tester.pumpAndSettle();
      final results = find.byKey(const ValueKey('knowledge-search-results'));
      final scroll = tester.widget<ListView>(results).controller!;
      await tester.drag(results, const Offset(0, -420));
      await tester.pumpAndSettle();
      final saved = scroll.offset;
      expect(saved, greaterThan(0));
      final visible = find
          .descendant(of: results, matching: find.byType(ListTile))
          .hitTestable();
      // 线路结果定位到城市详情页，并预先展开目标线路（US-008）。
      final lineTitle = tester
          .getSemantics(visible.first)
          .label
          .split('\n')
          .first;
      await tester.tap(visible.first);
      await tester.pumpAndSettle();
      expect(controller.page, GalleryPage.knowledgeCity);
      expect(controller.knowledgeCityLine, lineTitle);
      final city = controller.selectedKnowledgeCity!;
      expect(
        controller.knowledgeExpanded,
        contains(
          GalleryKnowledgeLineView.idFor(city.system, city.code, lineTitle),
        ),
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(controller.page, GalleryPage.knowledgeSearch);
      expect(scroll.offset, closeTo(saved, .1));
      expect(tester.widget<TextField>(input).controller!.text, '号线');
    },
  );

  testWidgets(
    'search retains the input after an error and supports immediate IME submission',
    (tester) async {
      var attempts = 0;
      await openKnowledge(tester, () async {
        if (++attempts == 1) throw const FormatException('package unavailable');
        return index;
      });
      await tester.tap(entry);
      await tester.pumpAndSettle();
      await tester.enterText(input, '不存在的站点编号码');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('知识库暂时无法搜索'), findsOneWidget);
      expect(tester.widget<TextField>(input).controller!.text, '不存在的站点编号码');
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('没有找到相关内容'), findsOneWidget);
      expect(attempts, 2);
    },
  );

  testWidgets(
    'declared line counts agree across the card, city page and both entries',
    (tester) async {
      final controller = await openKnowledge(tester, () async => index);
      final list = find.byKey(
        PageStorageKey('gallery-${controller.generation}-knowledge'),
      );
      // TU 上海的样例快照：声明 25 条线路，浏览列表有 26 条（含未标注线路）。
      final cityLabel = find.text('上海');
      await tester.scrollUntilVisible(
        cityLabel,
        300,
        scrollable: galleryVerticalScroll(within: list),
      );
      await tester.ensureVisible(cityLabel);
      await tester.pumpAndSettle();
      final card = find
          .ancestor(of: cityLabel, matching: find.byType(InkWell))
          .first;
      expect(
        find.descendant(of: card, matching: find.textContaining('收录 25 条线路')),
        findsOneWidget,
      );

      await tester.tap(cityLabel);
      await tester.pumpAndSettle();
      expect(controller.page, GalleryPage.knowledgeCity);
      final fromRegion = controller.selectedKnowledgeCity!;
      expect(fromRegion.name, '上海');
      expect(fromRegion.lineCount, 25);
      expect(fromRegion.lines, hasLength(26));
      expect(find.text('25'), findsOneWidget);
      expect(find.text('收录 25 条线路'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(entry);
      await tester.pumpAndSettle();
      await tester.enterText(input, '上海');
      await tester.pump(const Duration(milliseconds: 280));
      await tester.pumpAndSettle();
      // 搜索结果摘要也走声明值（两个体系的上海快照都是 25）。
      expect(find.textContaining('25 条线路 ·'), findsWidgets);
      await tester.tap(find.widgetWithText(ListTile, '上海').first);
      await tester.pumpAndSettle();
      expect(controller.page, GalleryPage.knowledgeCity);
      final fromCityView = controller.selectedKnowledgeCity!;
      expect(fromCityView.system, 'TU');
      expect(fromCityView.lineCount, 25);
      // 发布包另有公交线路和只有前缀、尚无站点的线路，样例概况仍取声明值。
      expect(
        fromCityView.lines.map((line) => line.name),
        containsAll(['朱泾7', '19号线']),
      );
      expect(find.text('25'), findsOneWidget);
      expect(find.text('收录 25 条线路'), findsOneWidget);

      final city = index.cities.firstWhere(
        (city) => city.system == 'TU' && city.name == '上海',
      );
      expect(fromCityView.lines.length, city.lines.length);
      expect(GalleryKnowledgeCityView.fromCity(city).lineCount, 25);
      final root = jsonDecode(
        File('assets/gallery/fixtures.json').readAsStringSync(),
      ) as GalleryRecord;
      final regions =
          (((root['knowledge'] as Map)['systems'] as Map)['tu']
                  as Map)['regions']
              as List;
      final region = regions.cast<GalleryRecord>().firstWhere(
        (region) => region['name'] == '上海',
      );
      expect(GalleryKnowledgeCityView.fromRegion('TU', region).lineCount, 25);
    },
  );
}
