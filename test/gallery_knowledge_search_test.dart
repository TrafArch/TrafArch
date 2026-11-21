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
      expect(loads, 1);
      await tester.tap(find.widgetWithText(ListTile, '290000100018').first);
      await tester.pumpAndSettle();
      expect(controller.page, GalleryPage.knowledgeStation);
      expect(find.text('航中路'), findsOneWidget);
      expect(find.text('匹配编码'), findsOneWidget);
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
    'city and line detail routes preserve the search scroll when popping',
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
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      expect(controller.page, GalleryPage.knowledgeLine);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(controller.page, GalleryPage.knowledgeCity);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.enterText(input, '号线');
      await tester.pump(const Duration(milliseconds: 280));
      await tester.pumpAndSettle();
      final results = find.byKey(const ValueKey('knowledge-search-results'));
      final scroll = tester.widget<ListView>(results).controller!;
      await tester.drag(results, const Offset(0, -420));
      await tester.pumpAndSettle();
      final saved = scroll.offset;
      final visible = find
          .descendant(of: results, matching: find.byType(ListTile))
          .hitTestable();
      await tester.tap(visible.first);
      await tester.pumpAndSettle();
      expect(controller.page, GalleryPage.knowledgeLine);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
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
}
