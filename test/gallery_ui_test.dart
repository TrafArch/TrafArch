import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';

void main() {
  late GalleryData data;
  setUpAll(() {
    data = GalleryData(
      jsonDecode(File('assets/gallery/fixtures.json').readAsStringSync())
          as GalleryRecord,
    );
  });

  testWidgets('navigation, saving and the beta return control work by touch', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = GalleryController(data);
    addTearDown(c.dispose);
    var disabled = false;
    await tester.pumpWidget(
      GalleryApp(controller: c, onDisableBeta: () => disabled = true),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始读取'));
    await tester.pump(const Duration(milliseconds: 1700));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存卡片'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '我的通勤卡');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(c.current.saved, isTrue);
    expect(c.current.name, '我的通勤卡');
    await tester.tap(find.byKey(const ValueKey('nav-cards')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的通勤卡'));
    await tester.pumpAndSettle();
    expect(find.text('卡片详情'), findsOneWidget);
    await tester.tap(find.text('本周消费'));
    await tester.pumpAndSettle();
    expect(find.text('每日消费'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    c.navigate(GalleryPage.settings);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('启用新界面（beta）'), 400);
    await tester.tap(find.text('启用新界面（beta）'));
    await tester.pump();
    expect(disabled, isTrue);
  });

  testWidgets('source and mode use working dropdown menus', (tester) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = GalleryController(data);
    addTearDown(c.dispose);
    c.applyScene(data.scenes.firstWhere((s) => s.id == 'main-trips'));
    await tester.pumpWidget(GalleryApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部来源'));
    await tester.pumpAndSettle();
    final menu = find.byKey(const ValueKey('gallery-dropdown'));
    expect(find.byType(CheckedPopupMenuItem<String>), findsNothing);
    expect(
      find.descendant(of: menu, matching: find.byType(TextButton)),
      findsNWidgets(4),
    );
    final selectedText = find.descendant(of: menu, matching: find.text('全部来源'));
    final check = find.descendant(
      of: menu,
      matching: find.byIcon(Icons.check_rounded),
    );
    expect(
      tester.getRect(selectedText).left - tester.getRect(menu).left,
      lessThan(24),
    );
    expect(
      tester.getRect(check).left,
      greaterThan(tester.getRect(selectedText).right),
    );
    await tester.tap(find.byKey(const ValueKey('menu-option-0x1E 过程')));
    await tester.pumpAndSettle();
    expect(c.source, '0x1E 过程');
    await tester.tap(find.text('全部方式'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-option-公共汽电车')));
    await tester.pumpAndSettle();
    expect(c.mode, '公共汽电车');
    expect(find.text('当前筛选下没有记录'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'floating selection encloses icon and label while pages animate',
    (tester) async {
      tester.view.physicalSize = const Size(360, 892);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = GalleryController(data);
      addTearDown(c.dispose);
      await tester.pumpWidget(GalleryApp(controller: c));
      await tester.pumpAndSettle();
      final highlight = find.byKey(const ValueKey('nav-highlight-home'));
      final button = find.byKey(const ValueKey('nav-home'));
      final label = find.descendant(of: button, matching: find.text('首页'));
      final icon = find.descendant(
        of: button,
        matching: find.byIcon(Icons.home_outlined),
      );
      expect(tester.getSize(highlight).height, closeTo(50, .1));
      expect(
        tester.getRect(highlight).contains(tester.getCenter(icon)),
        isTrue,
      );
      expect(
        tester.getRect(highlight).contains(tester.getCenter(label)),
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('nav-trips')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      final fades = tester.widgetList<FadeTransition>(
        find.ancestor(
          of: find.byKey(const ValueKey(GalleryPage.trips)),
          matching: find.byType(FadeTransition),
        ),
      );
      expect(
        fades.any((fade) => fade.opacity.value > 0 && fade.opacity.value < 1),
        isTrue,
      );
      // Repeated taps during a transition must leave one usable current page.
      await tester.tap(find.byKey(const ValueKey('nav-cards')));
      await tester.pump(const Duration(milliseconds: 30));
      await tester.tap(find.byKey(const ValueKey('nav-home')));
      await tester.pumpAndSettle();
      expect(c.page, GalleryPage.home);
      expect(find.text('开始读取'), findsOneWidget);
      expect(tester.takeException(), isNull);
      c.update(() => c.docked = true);
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('nav-highlight-home'))).height,
        closeTo(60, .1),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('card actions stay anchored and edit only the chosen card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = GalleryController(data)..navigate(GalleryPage.cards);
    addTearDown(c.dispose);
    await tester.pumpWidget(GalleryApp(controller: c));
    await tester.pumpAndSettle();
    final trigger = find.byTooltip('深圳通 管理');
    final anchor = tester.getRect(trigger);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    final menu = find.byKey(const ValueKey('gallery-dropdown'));
    final rect = tester.getRect(menu);
    expect(rect.top, closeTo(anchor.bottom + 6, 1));
    expect(rect.right, closeTo(anchor.right, 1));
    expect(c.page, GalleryPage.cards);
    expect(find.text('卡片管理'), findsNothing);
    expect(
      find.descendant(of: menu, matching: find.byType(TextButton)),
      findsNWidgets(3),
    );
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '通勤深圳通');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(c.cards.firstWhere((card) => card.id == 'shenzhen').name, '通勤深圳通');
    expect(c.current.name, '上海公共交通卡');
    await tester.tap(find.byTooltip('通勤深圳通 管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('更改卡面'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('蔚蓝'));
    await tester.pumpAndSettle();
    expect(c.selectedCard.face, 'blue');
    c.back();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('通勤深圳通 管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除本卡'));
    await tester.pumpAndSettle();
    expect(c.selectedCard.saved, isTrue);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(c.selectedCard.saved, isTrue);
    await tester.tap(find.byTooltip('通勤深圳通 管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除本卡'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(c.savedCards.map((card) => card.id), isNot(contains('shenzhen')));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'scene dropdowns fit short screens and dismiss without activating the page',
    (tester) async {
      tester.view.physicalSize = const Size(320, 420);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final c = GalleryController(data);
      addTearDown(c.dispose);
      await tester.pumpWidget(GalleryApp(controller: c));
      await tester.pumpAndSettle();
      for (final scene in ['card-menu', 'trips-filter']) {
        c.applyScene(data.scenes.firstWhere((s) => s.id == scene));
        await tester.pumpAndSettle();
        final rect = tester.getRect(
          find.byKey(const ValueKey('gallery-dropdown')),
        );
        expect(rect.left, greaterThanOrEqualTo(12));
        expect(rect.right, lessThanOrEqualTo(308));
        expect(rect.top, greaterThanOrEqualTo(8));
        expect(rect.bottom, lessThanOrEqualTo(412));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(c.overlay, isNull);
        expect(c.isMainPage, isTrue);
        expect(tester.takeException(), isNull);
      }
      c.showOverlay(GalleryOverlay.source);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(310, 410));
      await tester.pumpAndSettle();
      expect(c.overlay, isNull);
      expect(c.page, GalleryPage.trips);
      c.showOverlay(GalleryOverlay.mode);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(c.overlay, isNull);
      expect(c.page, GalleryPage.trips);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'pressed controls stay flat and reduced motion switches immediately',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final c = GalleryController(data);
      addTearDown(c.dispose);
      await tester.pumpWidget(GalleryApp(controller: c));
      await tester.pumpAndSettle();
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        c.update(() => c.themeMode = mode);
        await tester.pumpAndSettle();
        final control = find.widgetWithText(TextButton, '开始读取');
        final theme = Theme.of(tester.element(control));
        for (final style in [
          theme.textButtonTheme.style,
          theme.filledButtonTheme.style,
          theme.iconButtonTheme.style,
        ]) {
          expect(
            style!.overlayColor!.resolve({WidgetState.pressed}),
            Colors.transparent,
          );
          expect(style.elevation!.resolve({WidgetState.pressed}), 0);
        }
        final gesture = await tester.startGesture(tester.getCenter(control));
        await tester.pump(const Duration(milliseconds: 100));
        final surfaces = tester.widgetList<Material>(
          find.descendant(of: control, matching: find.byType(Material)),
        );
        expect(surfaces.every((surface) => surface.elevation == 0), isTrue);
        await gesture.cancel();
      }
      await tester.tap(find.byKey(const ValueKey('nav-trips')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey(GalleryPage.home)), findsNothing);
      expect(find.byKey(const ValueKey(GalleryPage.trips)), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final sample in [
    ('shanghai', '¥10.00', '周一 ¥6.00'),
    ('suica', '337 JPY', '周一 337 JPY'),
    ('octopus', 'HK\$10.60', '周一 HK\$10.60'),
  ]) {
    testWidgets('weekly totals and chart semantics use ${sample.$1} currency', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 892);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = GalleryData(
        jsonDecode(jsonEncode(data.json)) as GalleryRecord,
      );
      // Dates exist only in this test; the frozen undated fixtures stay intact.
      for (final id in ['suica', 'octopus']) {
        for (final row in fixture.ledger(id)) {
          row['isoDate'] = '2026-10-26';
        }
      }
      final c = GalleryController(fixture);
      addTearDown(c.dispose);
      c.openCard(c.cards.firstWhere((card) => card.id == sample.$1));
      c.update(() => c.detailTab = 1);
      await tester.pumpWidget(GalleryApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.text(sample.$2), findsWidgets);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              (widget.properties.label?.contains(sample.$3) ?? false),
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(find.text('分类开销'), 250);
      await tester.pumpAndSettle();
      expect(find.text(sample.$2), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'large text, long fields and both bottom bars fit narrow screens',
    (tester) async {
      tester.view.physicalSize = const Size(360, 892);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = GalleryController(data);
      addTearDown(c.dispose);
      await tester.pumpWidget(GalleryApp(controller: c));
      await tester.pump();
      for (final page in [
        GalleryPage.home,
        GalleryPage.trips,
        GalleryPage.cards,
        GalleryPage.detail,
        GalleryPage.settings,
        GalleryPage.qr,
      ]) {
        for (final dock in [false, true]) {
          c.applyScene(data.scenes.firstWhere((s) => s.id == 'home-long'));
          c.navigate(page);
          c.update(() => c.docked = dock);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(
            tester.takeException(),
            isNull,
            reason: '$page dock=$dock large text',
          );
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
