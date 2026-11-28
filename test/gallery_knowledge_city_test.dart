import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';
import 'package:transit_card_analyzer/gallery/gallery_knowledge_index.dart';
import 'package:transit_card_analyzer/gallery/gallery_theme.dart';

import 'support/gallery_scroll.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  GalleryRecord fixture() =>
      jsonDecode(File('assets/gallery/fixtures.json').readAsStringSync())
          as GalleryRecord;

  GalleryKnowledgeLineView line(
    String name, {
    int stations = 3,
    List<String> lineCodes = const [],
    List<List<String>> stationCodes = const [],
  }) => GalleryKnowledgeLineView(
    name: name,
    stations: [
      for (var i = 0; i < stations; i++)
        GalleryKnowledgeStationView(
          name: '本站$name-$i',
          codes: i < stationCodes.length ? stationCodes[i] : const [],
        ),
    ],
    codes: lineCodes,
  );

  GalleryKnowledgeCityView city({
    String name = '测试市',
    String code = '9999',
    int? lineCount,
    int? codeCount = 0,
    bool hasStationData = true,
    required List<GalleryKnowledgeLineView> lines,
  }) => GalleryKnowledgeCityView(
    system: 'TU',
    name: name,
    code: code,
    province: '测试省',
    lineCount: lineCount ?? lines.length,
    codeCount: codeCount,
    lines: lines,
    hasStationData: hasStationData,
  );

  Future<GalleryController> openCity(
    WidgetTester tester,
    GalleryKnowledgeCityView view,
  ) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = GalleryController(GalleryData(fixture()))
      ..openKnowledgeCity(view);
    addTearDown(controller.dispose);
    await tester.pumpWidget(GalleryApp(controller: controller));
    await tester.pumpAndSettle();
    return controller;
  }

  Finder card(int index) =>
      find.byKey(ValueKey('knowledge-city-line-TU:$index'));
  Finder toggle(int index) =>
      find.byKey(ValueKey('knowledge-line-toggle-TU:$index'));
  Finder stationRow(int lineIndex, int stationIndex) => find.byKey(
    ValueKey('knowledge-city-station-TU:$lineIndex:$stationIndex'),
  );
  Finder stationRowOf(String system, int lineIndex, int stationIndex) =>
      find.byKey(
        ValueKey('knowledge-city-station-$system:$lineIndex:$stationIndex'),
      );

  double height(WidgetTester tester, int index) =>
      tester.getSize(card(index)).height;

  testWidgets(
    'a line card expands into stations with raw codes and collapses',
    (tester) async {
      await openCity(
        tester,
        city(
          lines: [
            line('1号线', lineCodes: ['L1'], stations: 3),
            line('2号线', stations: 2),
          ],
        ),
      );
      final collapsed = height(tester, 0);
      expect(collapsed, greaterThan(0));
      expect(stationRow(0, 0), findsNothing);
      expect(find.text('线路编号未知'), findsWidgets);

      await tester.tap(toggle(0));
      await tester.pumpAndSettle();
      expect(stationRow(0, 0), findsOneWidget);
      expect(find.text('本站1号线-0'), findsOneWidget);
      expect(height(tester, 0), greaterThan(collapsed));
      expect(
        tester
            .widget<AnimatedRotation>(
              find.descendant(
                of: card(0),
                matching: find.byType(AnimatedRotation),
              ),
            )
            .turns,
        .5,
      );
      // 站点没有编码时显示「编码未知」，不猜测、不留空白。
      expect(
        find.descendant(of: stationRow(0, 0), matching: find.text('编码未知')),
        findsOneWidget,
      );

      await tester.tap(toggle(0));
      await tester.pumpAndSettle();
      expect(stationRow(0, 0), findsNothing);
      expect(height(tester, 0), closeTo(collapsed, .1));
      expect(
        tester
            .widget<AnimatedRotation>(
              find.descendant(
                of: card(0),
                matching: find.byType(AnimatedRotation),
              ),
            )
            .turns,
        0,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('station codes keep their original spelling', (tester) async {
    await openCity(
      tester,
      city(
        lines: [
          line(
            '1号线',
            stations: 1,
            stationCodes: const [
              ['??-0001', '0900/未登记'],
            ],
          ),
        ],
      ),
    );
    await tester.tap(toggle(0));
    await tester.pumpAndSettle();
    expect(find.text('??-0001、0900/未登记'), findsOneWidget);
    expect(find.text('编码未知'), findsNothing);
  });

  testWidgets('each line card keeps its own expansion state', (tester) async {
    await openCity(
      tester,
      city(lines: [line('1号线', stations: 2), line('2号线', stations: 4)]),
    );
    await tester.tap(toggle(0));
    await tester.pumpAndSettle();
    await tester.tap(toggle(1));
    await tester.pumpAndSettle();
    expect(stationRow(0, 0), findsOneWidget);
    expect(stationRow(1, 3), findsOneWidget);
    final second = height(tester, 1);

    await tester.tap(toggle(0));
    await tester.pumpAndSettle();
    expect(stationRow(0, 0), findsNothing);
    // 收起一张卡不会改动另一张卡的展开状态与高度。
    expect(stationRow(1, 3), findsOneWidget);
    expect(height(tester, 1), closeTo(second, .1));
  });

  testWidgets('a rapid second tap retracts from the current height', (
    tester,
  ) async {
    await openCity(tester, city(lines: [line('1号线', stations: 6)]));
    final collapsed = height(tester, 0);
    await tester.tap(toggle(0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final growing = height(tester, 0);
    expect(growing, greaterThan(collapsed));

    await tester.tap(toggle(0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final retracting = height(tester, 0);
    expect(retracting, lessThan(growing));

    await tester.pumpAndSettle();
    expect(height(tester, 0), closeTo(collapsed, .1));
    expect(stationRow(0, 0), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion jumps straight to the target state', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await openCity(tester, city(lines: [line('1号线', stations: 6)]));
    final collapsed = height(tester, 0);

    await tester.tap(toggle(0));
    await tester.pump();
    expect(stationRow(0, 0), findsOneWidget);
    final expanded = height(tester, 0);
    expect(expanded, greaterThan(collapsed));
    await tester.pump(const Duration(milliseconds: 400));
    expect(height(tester, 0), closeTo(expanded, .1));

    await tester.tap(toggle(0));
    await tester.pump();
    expect(stationRow(0, 0), findsNothing);
    expect(height(tester, 0), closeTo(collapsed, .1));
  });

  testWidgets('content of a closing card is no longer operable', (
    tester,
  ) async {
    await openCity(tester, city(lines: [line('1号线', stations: 5)]));
    await tester.tap(toggle(0));
    await tester.pumpAndSettle();
    final station = find.text('本站1号线-0');
    expect(station.hitTestable(), findsOneWidget);

    await tester.tap(toggle(0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // 收起动画进行中内容仍在树里，但已退出触控与焦点。
    expect(station, findsOneWidget);
    expect(station.hitTestable(), findsNothing);
    final ignoring = tester.widget<IgnorePointer>(
      find.ancestor(of: station, matching: find.byType(IgnorePointer)).first,
    );
    expect(ignoring.ignoring, isTrue);
    await tester.pumpAndSettle();
    expect(station, findsNothing);
  });

  Future<GalleryKnowledgeIndex> index() async =>
      GalleryKnowledgeIndex.fromPaths({
        for (final system in ['TU', 'CU'])
          system: File('assets/data/TrafArch_Database_$system.sqlite')
              .absolute
              .path,
      });

  Future<GalleryController> openSearch(
    WidgetTester tester,
    GalleryKnowledgeIndex loaded,
  ) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = GalleryController(GalleryData(fixture()))
      ..navigate(GalleryPage.knowledge);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      GalleryApp(
        controller: controller,
        loadKnowledgeIndex: () async => loaded,
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('a line search result opens the city page with that line open', (
    tester,
  ) async {
    final loaded = await index();
    final controller = await openSearch(tester, loaded);
    await tester.tap(find.byKey(const ValueKey('knowledge-search-entry')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('knowledge-search-input')),
      '1号线',
    );
    await tester.pump(const Duration(milliseconds: 280));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '1号线').first);
    await tester.pumpAndSettle();

    expect(controller.page, GalleryPage.knowledgeCity);
    expect(controller.knowledgeCityLine, '1号线');
    final city = controller.selectedKnowledgeCity!;
    final lineIndex = city.lines.indexWhere((line) => line.name == '1号线');
    expect(lineIndex, greaterThanOrEqualTo(0));
    // 定位滚动后吸顶头已收合（与首页一致）：城市名淡出，搜索条顶进标题栏
    // 且仍可点。
    expect(
      find.byKey(const ValueKey('knowledge-city-search-position')),
      findsOneWidget,
    );
    expect(find.text(city.name), findsNothing);
    expect(
      find.byKey(const ValueKey('knowledge-search-entry')).hitTestable(),
      findsOneWidget,
    );
    expect(stationRowOf(city.system, lineIndex, 0), findsOneWidget);
    expect(
      stationRowOf(city.system, lineIndex, 0).hitTestable(),
      findsOneWidget,
    );
    // 定位让出了吸顶头的收合高度：目标线路卡不被标题栏压住。
    expect(
      tester
          .getTopLeft(
            find.byKey(
              ValueKey('knowledge-city-line-${city.system}:$lineIndex'),
            ),
          )
          .dy,
      greaterThan(
        tester
            .getRect(
              find.byKey(const ValueKey('knowledge-city-search-position')),
            )
            .bottom,
      ),
    );
    // 其它线路保持收起：搜索定位不应把所有卡片一起展开。
    final other = lineIndex == 0 ? 1 : 0;
    expect(stationRowOf(city.system, other, 0), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(controller.page, GalleryPage.knowledgeSearch);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('knowledge-search-input')),
          )
          .controller!
          .text,
      '1号线',
    );
  });

  testWidgets('a station search result opens and highlights that station', (
    tester,
  ) async {
    final loaded = await index();
    final controller = await openSearch(tester, loaded);
    await tester.tap(find.byKey(const ValueKey('knowledge-search-entry')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('knowledge-search-input')),
      '航中路',
    );
    await tester.pump(const Duration(milliseconds: 280));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '航中路').first);
    await tester.pumpAndSettle();

    expect(controller.page, GalleryPage.knowledgeCity);
    expect(controller.knowledgeCityStation, '航中路');
    final city = controller.selectedKnowledgeCity!;
    final lineIndex = city.lines.indexWhere(
      (line) => line.name == controller.knowledgeCityLine,
    );
    final stationIndex = city.lines[lineIndex].stations.indexWhere(
      (station) => station.name == '航中路',
    );
    expect(stationIndex, greaterThanOrEqualTo(0));
    final row = stationRowOf(city.system, lineIndex, stationIndex);
    expect(row, findsOneWidget);
    expect(row.hitTestable(), findsOneWidget);
    final tokens = Theme.of(tester.element(row)).extension<GalleryTokens>()!;
    expect(
      (tester.widget<Container>(row).decoration! as BoxDecoration).color,
      tokens.tone,
    );
  });

  testWidgets('a line code opens the matching card deep in the city list', (
    tester,
  ) async {
    await openSearch(tester, await index());
    await tester.tap(find.byKey(const ValueKey('knowledge-search-entry')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('knowledge-search-input')),
      '4275',
    );
    await tester.pump(const Duration(milliseconds: 280));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '4275'));
    await tester.pumpAndSettle();
    expect(find.text('宝山35').hitTestable(), findsOneWidget);
    expect(find.text('匹配编码 4275').hitTestable(), findsOneWidget);
  });

  testWidgets('the city page restores its scroll position after search', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = GalleryController(GalleryData(fixture()))
      ..navigate(GalleryPage.knowledge);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      GalleryApp(controller: controller, loadKnowledgeIndex: index),
    );
    await tester.pumpAndSettle();
    final firstCard = find.byKey(const ValueKey('knowledge-city-tu:0'));
    await tester.tap(firstCard);
    await tester.pumpAndSettle();
    final city = controller.selectedKnowledgeCity!;
    final list = find.byKey(
      PageStorageKey(
        'gallery-${controller.generation}-knowledge-city-${city.system}-${city.code}',
      ),
    );
    double offset() => tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        )
        .position
        .pixels;

    await tester.drag(list, const Offset(0, -260));
    await tester.pumpAndSettle();
    final saved = offset();
    expect(saved, greaterThan(0));

    await tester.tap(find.byKey(const ValueKey('knowledge-search-entry')));
    await tester.pumpAndSettle();
    expect(controller.page, GalleryPage.knowledgeSearch);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(controller.page, GalleryPage.knowledgeCity);
    expect(offset(), closeTo(saved, .1));
  });

  testWidgets('long line lists build cards on demand and release stations', (
    tester,
  ) async {
    final controller = await openCity(
      tester,
      city(
        lines: [for (var i = 0; i < 240; i++) line('线路$i', stations: 2)],
        lineCount: 240,
      ),
    );
    final built = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('knowledge-city-line-TU:');
    });
    expect(built.evaluate().length, lessThan(240));
    expect(
      find.byKey(const ValueKey('knowledge-city-line-TU:239')),
      findsNothing,
    );
    final list = find.byKey(
      PageStorageKey('gallery-${controller.generation}-knowledge-city-TU-9999'),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('knowledge-city-line-TU:239')),
      400,
      scrollable: galleryVerticalScroll(within: list),
    );
    expect(
      find.byKey(const ValueKey('knowledge-city-line-TU:239')),
      findsOneWidget,
    );
  });

  testWidgets('a station heavy line only builds rows while expanded', (
    tester,
  ) async {
    await openCity(tester, city(lines: [line('长线', stations: 150)]));
    expect(stationRow(0, 149), findsNothing);
    await tester.tap(toggle(0));
    await tester.pumpAndSettle();
    expect(stationRow(0, 149), findsOneWidget);
    await tester.tap(toggle(0));
    await tester.pumpAndSettle();
    expect(stationRow(0, 149), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('a city with route rows but no station rows reports unknown', () {
    final support = Directory.systemTemp.createTempSync(
      'trafarch-knowledge-city-',
    );
    addTearDown(() => support.delete(recursive: true));
    final path = '${support.path}/tu-routes.sqlite';
    final database = sqlite3.open(path);
    try {
      database.execute(
        'CREATE TABLE regions (region_id INTEGER, region_code TEXT, '
        'region_name TEXT, province TEXT)',
      );
      database.execute(
        "INSERT INTO regions VALUES (1, '0999', '只有线路市', '测试省')",
      );
      database.execute(
        'CREATE TABLE region_aliases (region_id INTEGER, '
        'source_region_name TEXT)',
      );
      database.execute(
        'CREATE TABLE all_records (region_id INTEGER, station_id INTEGER, '
        'line_name TEXT, station_name TEXT, source_key TEXT, source_field TEXT)',
      );
      database.execute(
        "INSERT INTO all_records VALUES "
        "(1, 1, '1号线', '', 'line-key', 'routes')",
      );
    } finally {
      database.close();
    }
    final loaded = GalleryKnowledgeIndex.fromPaths({'TU': path});
    final view = GalleryKnowledgeCityView.fromCity(loaded.cities.single);
    expect(view.lines, hasLength(1));
    expect(view.lines.single.codes, ['line-key']);
    expect(view.hasStationData, isFalse);
    expect(view.stationCount, isNull);
  });
}
