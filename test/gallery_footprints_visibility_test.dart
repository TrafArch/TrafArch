import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';

import 'support/gallery_scroll.dart';

void main() {
  late GalleryController c;
  setUp(() {
    c = GalleryController(
      GalleryData(
        jsonDecode(File('assets/gallery/fixtures.json').readAsStringSync())
            as GalleryRecord,
      ),
    );
    c.themeMode = ThemeMode.light;
    c.monet = false;
  });
  tearDown(() => c.dispose());

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 1000);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(GalleryApp(controller: c));
    await tester.pumpAndSettle();
  }

  test('visible scenes omit footprints and preserve all frozen samples', () {
    final original = jsonEncode(c.data.json);
    expect(c.data.scenes, hasLength(52));
    expect(c.visibleScenes, hasLength(51));
    expect(
      c.visibleScenes.map((scene) => scene.id),
      isNot(contains('main-footprints')),
    );
    expect(c.data.scenes.map((scene) => scene.id), contains('main-footprints'));
    expect(jsonEncode(c.data.json), original);
  });

  for (final docked in [false, true]) {
    testWidgets('home exposes four destinations with docked=$docked', (
      tester,
    ) async {
      c.docked = docked;
      await mount(tester);
      final navigation = find.byKey(const ValueKey('gallery-navigation'));
      double? itemWidth;
      Rect? previousItem;
      for (final name in ['home', 'trips', 'expert', 'cards']) {
        final item = find.descendant(
          of: navigation,
          matching: find.byKey(ValueKey('nav-$name')),
        );
        expect(item, findsOneWidget);
        final bounds = tester.getRect(item);
        itemWidth ??= bounds.width;
        expect(bounds.width, closeTo(itemWidth, .1));
        if (previousItem != null) {
          expect(bounds.left, greaterThanOrEqualTo(previousItem.right - .1));
          expect(bounds.center.dy, closeTo(previousItem.center.dy, .1));
        }
        previousItem = bounds;
      }
      expect(find.byKey(const ValueKey('nav-footprints')), findsNothing);
      expect(find.textContaining('足迹'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('nav-cards')));
      await tester.pumpAndSettle();
      expect(c.page, GalleryPage.cards);
      await tester.tap(find.byKey(const ValueKey('nav-home')));
      await tester.pumpAndSettle();
      expect(c.page, GalleryPage.home);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('settings and its scene picker provide no footprints entry', (
    tester,
  ) async {
    c.navigate(GalleryPage.settings);
    await mount(tester);
    final settingsList = find.byType(ListView).last;
    await tester.scrollUntilVisible(
      find.text('内置场景'),
      350,
      scrollable: galleryVerticalScroll(within: settingsList),
    );
    expect(find.textContaining('足迹'), findsNothing);
    expect(find.text('51 个预置场景 · 切换后载入固定样例'), findsOneWidget);
    await tester.tap(find.text('内置场景'));
    await tester.pumpAndSettle();
    expect(c.page, GalleryPage.scenes);
    expect(find.text('01 主页面'), findsOneWidget);
    expect(find.text('卡包'), findsOneWidget);
    expect(find.textContaining('足迹'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'retained footprints frontend can still render an internal scene',
    (tester) async {
      c.applyScene(
        c.data.scenes.firstWhere((scene) => scene.id == 'main-footprints'),
      );
      c.docked = false;
      await mount(tester);
      expect(c.page, GalleryPage.footprints);
      expect(c.isMainPage, isTrue);
      expect(find.byKey(const ValueKey('footprint-summary')), findsOneWidget);
      expect(find.text('足迹'), findsOneWidget);
      expect(find.byKey(const ValueKey('nav-footprints')), findsNothing);
      expect(find.byKey(const ValueKey('nav-capsule')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('nav-home')));
      await tester.pumpAndSettle();
      expect(c.page, GalleryPage.home);
      expect(c.navigationStack, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}
