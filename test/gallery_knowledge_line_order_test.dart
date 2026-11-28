import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_knowledge_index.dart';
import 'package:transit_card_analyzer/gallery/gallery_theme.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_service.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';

import 'support/gallery_scroll.dart';
import 'support/test_database.dart';

void main() {
  test('city projection only sorts single numbered metro lines, stably', () {
    const source = [
      '11号线',
      '机场联络线',
      '地鐵 ０２ 號線（支線）',
      '2', // TU 太原公交原名，不参与排序。
      '1号线',
      '1/2号线', // 复合标注无法归到单个号码。
      '10号线',
      '2号线',
      '亦庄T1线',
      '9号线',
      '快速公交1线',
      '2号线东支线',
      '松江有轨电车1号线',
      'S1线',
    ];
    final rawLines = [
      for (final name in source)
        {
          'name': name,
          'stations': ['$name 西站', '$name 东站'],
        },
    ];
    for (final system in ['TU', 'CU']) {
      final view = GalleryKnowledgeCityView.fromRegion(system, {
        'code': '0009',
        'lines': rawLines,
      });
      expect(view.lines.map((line) => line.name), [
        '1号线',
        '机场联络线',
        '地鐵 ０２ 號線（支線）',
        '2',
        '2号线',
        '1/2号线',
        '2号线东支线',
        '9号线',
        '亦庄T1线',
        '10号线',
        '快速公交1线',
        '11号线',
        '松江有轨电车1号线',
        'S1线',
      ], reason: system);
      expect(view.code, '0009');
      expect(view.lineCount, source.length);
      for (final line in view.lines) {
        expect(line.stations.map((station) => station.name), [
          '${line.name} 西站',
          '${line.name} 东站',
        ]);
      }
    }
    expect(rawLines.map((line) => line['name']), source);
  });

  for (final (system, code, source, lineKey, lineCode) in [
    ('TU', '290000100018', 'M0.i0.a', '29000010', '0010'),
    ('CU', '2000111018', 'M0.B.b', '20001110', '1110'),
  ]) {
    testWidgets(
      '$system published city shows one order when browsing and searching',
      (tester) async {
        final empty = KnowledgeBase.empty();
        final app = _KnowledgeApp(
          KnowledgeBase(
            cities: empty.cities,
            issuers: empty.issuers,
            terminalRules: empty.terminalRules,
            packagePaths: {
              system: File('assets/data/TrafArch_Database_$system.sqlite')
                  .absolute
                  .path,
            },
          ),
        );
        addTearDown(app.dispose);
        tester.view.physicalSize = const Size(412, 892);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.runAsync(app.init);
        await tester.pumpWidget(GalleryApp(liveApp: app));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('设置'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('知识库'));
        final overview = find.text('数据概况');
        for (var i = 0; i < 100 && overview.evaluate().isEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(overview, findsOneWidget);
        await tester.pumpAndSettle();
        if (system == 'CU') {
          await tester.tap(find.text('城市一卡通 CU'));
          await tester.pumpAndSettle();
        }

        final city = find.text('上海');
        await tester.scrollUntilVisible(
          city,
          260,
          scrollable: galleryVerticalScroll(),
        );
        await Scrollable.ensureVisible(tester.element(city), alignment: .3);
        await tester.pumpAndSettle();
        await tester.tap(city);
        await tester.pumpAndSettle();

        Finder card(int index) =>
            find.byKey(ValueKey('knowledge-city-line-$system:$index'));
        Finder toggle(int index) =>
            find.byKey(ValueKey('knowledge-line-toggle-$system:$index'));
        Finder labelIn(int index, String label) =>
            find.descendant(of: card(index), matching: find.text(label));
        void expectLineCodes() {
          final label = find.descendant(
            of: card(9),
            matching: find.textContaining('线路编码 '),
          );
          final text = tester.widget<Text>(label).data!;
          expect(
            text.substring('线路编码 '.length).split('、'),
            containsAll([lineKey, lineCode]),
          );
        }

        for (final (index, label) in [
          (0, '1号线'),
          (1, '2号线'),
          (8, '9号线'),
          (9, '10号线'),
          (10, '11号线'),
        ]) {
          await tester.scrollUntilVisible(
            card(index),
            240,
            scrollable: galleryVerticalScroll(),
          );
          expect(labelIn(index, label), findsOneWidget);
        }
        final firstStation = find.byKey(
          ValueKey('knowledge-city-station-$system:9:0'),
        );
        final lineToggle = toggle(9);
        await Scrollable.ensureVisible(
          tester.element(lineToggle),
          alignment: .3,
        );
        await tester.pumpAndSettle();
        await tester.tap(lineToggle);
        await tester.pumpAndSettle();
        expectLineCodes();
        expect(
          find.descendant(
            of: firstStation,
            matching: find.textContaining(code),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: firstStation, matching: find.text('航中路')),
          findsOneWidget,
        );
        await tester.tap(lineToggle);
        await tester.pumpAndSettle();
        expect(firstStation, findsNothing);

        // 清到页面顶部，避免第二次进入时复用已滚到 10 号线的视口位置。
        tester
            .state<ScrollableState>(galleryVerticalScroll())
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('返回'));
        await tester.pumpAndSettle();
        // 首页也会恢复浏览时的滚动位置，先回顶部再点击搜索入口。
        tester
            .state<ScrollableState>(galleryVerticalScroll())
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
        final entry = find
            .byKey(const ValueKey('knowledge-search-entry'))
            .hitTestable();
        expect(entry, findsOneWidget);
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(find.text('查找知识库'), findsOneWidget);
        final input = find.byKey(const ValueKey('knowledge-search-input'));
        await tester.enterText(input, code);
        expect(tester.widget<TextField>(input).controller!.text, code);
        await tester.pump(const Duration(milliseconds: 280));

        // CU 原码跨城市复用，必须同时命中上海 10 号线的航中路。
        final result = find.ancestor(
          of: find.text('编码 · $system\n上海 · 10号线 · 航中路 · $source'),
          matching: find.widgetWithText(ListTile, code),
        );
        final loading = find.text('正在检索本地知识库…');
        // 虚拟帧只触发防抖；发布包的 SQLite 索引在真实 isolate 中构建。
        for (
          var i = 0;
          i < 200 && result.evaluate().isEmpty && loading.evaluate().isNotEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump();
        }
        expect(find.text('知识库暂时无法搜索'), findsNothing);
        expect(result, findsOneWidget);
        await tester.ensureVisible(result);
        await tester.pumpAndSettle();
        final visibleResult = result.hitTestable();
        expect(visibleResult, findsOneWidget);
        await tester.tap(visibleResult);
        await tester.pumpAndSettle();

        expect(labelIn(9, '10号线'), findsOneWidget);
        expectLineCodes();
        expect(firstStation.hitTestable(), findsOneWidget);
        expect(
          find.descendant(of: firstStation, matching: find.text('航中路')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: firstStation, matching: find.text('匹配编码 $code')),
          findsOneWidget,
        );
        final tokens = Theme.of(tester.element(firstStation))
            .extension<GalleryTokens>()!;
        expect(
          (tester.widget<Container>(firstStation).decoration! as BoxDecoration)
              .color,
          tokens.tone,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
}

class _KnowledgeApp extends AppDependencies {
  _KnowledgeApp(this.active)
    : super(
        channel: _IdleNfc(),
        bundle: MissingTestAssets(),
        database: testDatabase(),
        settingsStore: MemorySettingsStore(),
      );

  final KnowledgeBase active;

  @override
  KnowledgeBase get knowledgeBase => active;
}

class _IdleNfc implements NfcChannel {
  @override
  Future<NfcScanResult?> scanOnce() async => null;

  @override
  Future<void> stopScan() async {}

  @override
  Future<List<int>> transceive(List<int> apdu) async => const [];
}
