import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  GalleryRecord fixture() =>
      jsonDecode(File('assets/gallery/fixtures.json').readAsStringSync())
          as GalleryRecord;

  Future<GalleryController> open(
    WidgetTester tester, {
    GalleryRecord? data,
  }) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = GalleryController(GalleryData(data ?? fixture()))
      ..navigate(GalleryPage.knowledge);
    addTearDown(controller.dispose);
    await tester.pumpWidget(GalleryApp(controller: controller));
    await tester.pumpAndSettle();
    return controller;
  }

  List<GalleryRecord> regionData(GalleryRecord root, String system) {
    final systems = (root['knowledge'] as Map)['systems'] as Map;
    return ((systems[system] as Map)['regions'] as List).cast<GalleryRecord>();
  }

  String group(int value) => value.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (match) => '${match[1]},',
  );

  String metric(WidgetTester tester, String id) => tester
      .widget<Text>(
        find
            .descendant(
              of: find.byKey(ValueKey('knowledge-metric-$id')),
              matching: find.byType(Text),
            )
            .first,
      )
      .data!;

  testWidgets(
    'full-width search takes over the title row when scrolling and restores at top',
    (tester) async {
      final controller = await open(tester);
      final data = controller.data.json;
      final regions = regionData(data, 'tu');
      final lines = regions.fold<int>(
        0,
        (total, region) => total + (region['lineCount'] as int),
      );
      final stations = regions.fold<int>(0, (total, region) {
        final names = <String>{};
        for (final line in (region['lines'] as List)) {
          names.addAll(((line as Map)['stations'] as List).cast<String>());
        }
        return total + names.length;
      });

      final search = find.byKey(const ValueKey('knowledge-search-entry'));
      final title = find.text('知识库');
      final back = find.byTooltip('返回');
      final tabs = find.text('交通联合 TU');
      final overview = find.text('数据概况');
      final cities = find.text('城市列表');
      expect(search, findsOneWidget);
      final expanded = tester.getRect(search);
      final entry = tester.element(search);
      final titleLeft = tester.getTopLeft(title).dx;
      final backCenter = tester.getCenter(back);
      expect(expanded.left, 16);
      expect(expanded.right, 412 - 16);
      expect(expanded.top, greaterThan(tester.getBottomLeft(title).dy));
      expect(
        tester.getTopLeft(search).dy,
        lessThan(tester.getTopLeft(tabs).dy),
      );
      expect(
        tester.getTopLeft(tabs).dy,
        lessThan(tester.getTopLeft(overview).dy),
      );
      expect(
        tester.getTopLeft(overview).dy,
        lessThan(tester.getTopLeft(cities).dy),
      );

      expect(metric(tester, 'cities'), '${regions.length}');
      expect(metric(tester, 'lines'), group(lines));
      expect(metric(tester, 'stations'), group(stations));

      final first = regions.first;
      final card = find.byKey(const ValueKey('knowledge-city-tu:0'));
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text(first['name'] as String)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.textContaining('${first['lineCount']} 条线路'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.textContaining(
            '${group(first['entries'] as int)} 条编码',
          ),
        ),
        findsOneWidget,
      );

      expect(find.text('源文件'), findsNothing);
      await tester.tap(find.text('数据来源与版本'));
      await tester.pumpAndSettle();
      expect(find.text('源文件'), findsOneWidget);
      expect(find.text('TrafArch_Database_TU.sqlite'), findsOneWidget);

      final list = find.byKey(
        PageStorageKey('gallery-${controller.generation}-knowledge'),
      );
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)).first,
      );
      scroll.position.jumpTo(10);
      await tester.pump();
      expect(tester.getTopLeft(search).dy, lessThan(expanded.top));
      expect(tester.element(search), same(entry));

      await tester.drag(list, const Offset(0, -420));
      await tester.pumpAndSettle();
      final pinned = tester.getRect(search);
      expect(tester.getCenter(back), backCenter);
      expect(pinned.left, closeTo(titleLeft, .1));
      expect(pinned.center.dy, closeTo(backCenter.dy, .1));
      expect(pinned.right, expanded.right);
      expect(title, findsNothing);
      expect(tester.element(search), same(entry));
      expect(search.hitTestable(), findsOneWidget);
      final browseOffset = scroll.position.pixels;

      await tester.tap(search);
      await tester.pumpAndSettle();
      expect(controller.page, GalleryPage.knowledgeSearch);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(controller.page, GalleryPage.knowledge);
      expect(scroll.position.pixels, browseOffset);
      expect(tester.getRect(search), pinned);

      await tester.drag(list, const Offset(0, 650));
      await tester.pumpAndSettle();
      expect(title, findsOneWidget);
      expect(tester.getRect(search), expanded);
    },
  );

  testWidgets('TU and CU keep separate scroll positions', (tester) async {
    final controller = await open(tester);
    final list = find.byKey(
      PageStorageKey('gallery-${controller.generation}-knowledge'),
    );
    double offset() => tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        )
        .position
        .pixels;

    await tester.drag(list, const Offset(0, -260));
    await tester.pumpAndSettle();
    final tu = offset();
    expect(tu, greaterThan(0));
    controller.update(() => controller.knowledgeTab = 'cu');
    await tester.pumpAndSettle();
    expect(find.text('城市一卡通参考数据'), findsOneWidget);
    expect(offset(), closeTo(0, .1));

    await tester.drag(list, const Offset(0, -140));
    await tester.pumpAndSettle();
    final cu = offset();
    expect(cu, greaterThan(0));

    controller.update(() => controller.knowledgeTab = 'tu');
    await tester.pumpAndSettle();
    expect(find.text('交通联合参考数据'), findsOneWidget);
    expect(offset(), closeTo(tu, .1));

    controller.update(() => controller.knowledgeTab = 'cu');
    await tester.pumpAndSettle();
    expect(offset(), closeTo(cu, .1));
  });

  testWidgets('city card opens the city page skeleton and back returns home', (
    tester,
  ) async {
    final controller = await open(tester);
    await tester.tap(find.byKey(const ValueKey('knowledge-city-tu:0')));
    await tester.pumpAndSettle();
    expect(controller.page, GalleryPage.knowledgeCity);
    final city = controller.selectedKnowledgeCity!;
    expect(city.system, 'TU');
    expect(find.text(city.name), findsOneWidget);
    expect(find.textContaining('交通联合 TU'), findsOneWidget);
    expect(find.text('城市编码'), findsOneWidget);
    expect(find.text(city.lines.first.name), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(controller.page, GalleryPage.knowledge);
    expect(find.text('城市列表'), findsOneWidget);
  });

  testWidgets('missing structure shows unknown instead of zero', (
    tester,
  ) async {
    final data = fixture();
    final systems = (data['knowledge'] as Map)['systems'] as Map;
    final tu = systems['tu'] as Map;
    tu['regions'] = [
      {'code': '9999', 'name': '数据缺失市', 'province': ''},
    ];
    await open(tester, data: data);

    expect(metric(tester, 'cities'), '1');
    expect(metric(tester, 'lines'), '未知');
    expect(metric(tester, 'stations'), '未知');
    expect(find.text('线路数量未知'), findsOneWidget);
    expect(find.text('线路与编码简介未知'), findsOneWidget);
  });

  testWidgets('sample overview numbers are pinned to the published snapshot', (
    tester,
  ) async {
    // 独立常量，不复用页面里的推导公式：fixtures 的 TU 快照为
    // 41 个城市 / 307 条线路（声明值合计）/ 5,971 个去重站点。
    await open(tester);
    expect(metric(tester, 'cities'), '41');
    expect(metric(tester, 'lines'), '307');
    expect(metric(tester, 'stations'), '5,971');
  });

  testWidgets('city page keeps the search entry and returns to the city', (
    tester,
  ) async {
    final controller = await open(tester);
    final card = find.byKey(const ValueKey('knowledge-city-tu:0'));
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(controller.page, GalleryPage.knowledgeCity);
    final city = controller.selectedKnowledgeCity!;

    final entry = find.byKey(const ValueKey('knowledge-search-entry'));
    expect(entry, findsOneWidget);
    expect(entry.hitTestable(), findsOneWidget);
    expect(tester.getSize(entry).height, 52);
    expect(
      tester.getTopLeft(entry).dy,
      greaterThan(tester.getTopLeft(find.text(city.name)).dy),
    );

    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(controller.page, GalleryPage.knowledgeSearch);
    expect(find.text('查找知识库'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(controller.page, GalleryPage.knowledgeCity);
    expect(find.text(city.name), findsOneWidget);
    expect(find.text('城市编码'), findsOneWidget);
  });

  testWidgets('city page header matches the home search geometry', (
    tester,
  ) async {
    final controller = await open(tester);
    final entry = find.byKey(const ValueKey('knowledge-search-entry'));
    final homeRect = tester.getRect(entry);
    final homeTitleLeft = tester.getTopLeft(find.text('知识库')).dx;
    expect(homeRect.left, 16);
    expect(homeRect.right, 412 - 16);

    final card = find.byKey(const ValueKey('knowledge-city-tu:0'));
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(controller.page, GalleryPage.knowledgeCity);
    final city = controller.selectedKnowledgeCity!;

    // 静止态：同一搜索条、同一 inset、同一标题缩进（16 + 44 + 8）。
    final rest = tester.getRect(entry);
    expect(tester.getSize(entry), homeRect.size);
    expect(rest.left, homeRect.left);
    expect(rest.right, homeRect.right);
    expect(tester.getTopLeft(find.text(city.name)).dx, homeTitleLeft);
    expect(rest.top, greaterThan(tester.getTopLeft(find.text(city.name)).dy));
    expect(tester.getCenter(find.byTooltip('返回')).dx, 16 + 22);

    // 向下滚动：搜索条收进标题栏，城市名淡出，返回按钮留在可视区。
    final list = find.byKey(
      PageStorageKey(
        'gallery-${controller.generation}-knowledge-city-'
        '${city.system}-${city.code}',
      ),
    );
    await tester.drag(list, const Offset(0, -420));
    await tester.pumpAndSettle();
    final pinned = tester.getRect(entry);
    expect(pinned.left, homeTitleLeft);
    expect(pinned.top, lessThan(rest.top));
    expect(
      tester.getCenter(entry).dy,
      closeTo(tester.getCenter(find.byTooltip('返回')).dy, .1),
    );
    expect(tester.getSize(entry).height, homeRect.height);
    expect(pinned.right, rest.right);
    expect(pinned.width, 412 - homeTitleLeft - 16);
    expect(find.text(city.name), findsNothing);
    expect(find.byTooltip('返回').hitTestable(), findsOneWidget);

    // 收合态下搜索条仍可点，返回后保持收合位置。
    final offset = tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        )
        .position
        .pixels;
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(controller.page, GalleryPage.knowledgeSearch);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(controller.page, GalleryPage.knowledgeCity);
    expect(tester.getRect(entry), pinned);
    expect(
      tester
          .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)).first,
          )
          .position
          .pixels,
      closeTo(offset, .1),
    );

    // 滚回顶部恢复完整展开态。
    await tester.drag(list, const Offset(0, 650));
    await tester.pumpAndSettle();
    expect(tester.getRect(entry), rest);
    expect(find.text(city.name), findsOneWidget);
  });

  testWidgets('city page without a selected city keeps header and search', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = GalleryController(GalleryData(fixture()))
      ..navigate(GalleryPage.knowledgeCity);
    addTearDown(controller.dispose);
    await tester.pumpWidget(GalleryApp(controller: controller));
    await tester.pumpAndSettle();
    expect(controller.page, GalleryPage.knowledgeCity);

    expect(find.text('未选择城市'), findsOneWidget);
    expect(find.text('城市详情'), findsOneWidget);
    expect(find.byTooltip('返回').hitTestable(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('knowledge-city-search-position')),
      findsOneWidget,
    );
    final entry = find.byKey(const ValueKey('knowledge-search-entry'));
    expect(tester.getRect(entry).left, 16);
    expect(tester.getRect(entry).right, 412 - 16);
    expect(tester.getSize(entry).height, 52);

    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(controller.page, GalleryPage.knowledgeSearch);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(controller.page, GalleryPage.knowledgeCity);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(controller.page, GalleryPage.home);
  });

  testWidgets('each city keeps its own scroll offset', (tester) async {
    final controller = await open(tester);
    final first = find.byKey(const ValueKey('knowledge-city-tu:0'));
    await tester.ensureVisible(first);
    await tester.pumpAndSettle();
    await tester.tap(first);
    await tester.pumpAndSettle();
    final city = controller.selectedKnowledgeCity!;
    final list = find.byKey(
      PageStorageKey(
        'gallery-${controller.generation}-knowledge-city-'
        '${city.system}-${city.code}',
      ),
    );
    double offset() => tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        )
        .position
        .pixels;
    await tester.drag(list, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(offset(), greaterThan(0));

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(controller.page, GalleryPage.knowledge);
    final second = find.byKey(const ValueKey('knowledge-city-tu:1'));
    await tester.ensureVisible(second);
    await tester.pumpAndSettle();
    await tester.tap(second);
    await tester.pumpAndSettle();
    final other = controller.selectedKnowledgeCity!;
    expect(other.code, isNot(city.code));
    final otherList = find.byKey(
      PageStorageKey(
        'gallery-${controller.generation}-knowledge-city-'
        '${other.system}-${other.code}',
      ),
    );
    expect(
      tester
          .state<ScrollableState>(
            find
                .descendant(of: otherList, matching: find.byType(Scrollable))
                .first,
          )
          .position
          .pixels,
      closeTo(0, .1),
    );
  });

  testWidgets('a city with lines but no stations shows unknown', (
    tester,
  ) async {
    final data = fixture();
    final systems = (data['knowledge'] as Map)['systems'] as Map;
    (systems['tu'] as Map)['regions'] = [
      {
        'code': '9998',
        'name': '缺站点市',
        'province': '测试省',
        'lineCount': 2,
        'entries': 3,
        'lines': [
          {'name': '1号线'},
          {'name': '2号线'},
        ],
      },
    ];
    final controller = await open(tester, data: data);

    expect(metric(tester, 'cities'), '1');
    expect(metric(tester, 'lines'), '2');
    expect(metric(tester, 'stations'), '未知');
    final card = find.byKey(const ValueKey('knowledge-city-tu:0'));
    expect(
      find.descendant(of: card, matching: find.textContaining('收录 2 条线路')),
      findsOneWidget,
    );

    await tester.tap(card);
    await tester.pumpAndSettle();
    final city = controller.selectedKnowledgeCity!;
    expect(city.lineCount, 2);
    expect(city.lines, hasLength(2));
    expect(city.hasStationData, isFalse);
    expect(city.stationCount, isNull);
    final stationRow = find
        .ancestor(of: find.text('站点'), matching: find.byType(Row))
        .first;
    expect(
      find.descendant(of: stationRow, matching: find.text('未知')),
      findsOneWidget,
    );
    expect(find.textContaining('0 站'), findsNothing);
  });
}
