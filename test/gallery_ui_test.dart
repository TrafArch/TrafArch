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
    expect(find.text('卡片名称'), findsNothing);
    expect(find.textContaining('卡号尾号'), findsNothing);
    final form = find
        .ancestor(of: find.byType(TextField), matching: find.byType(Material))
        .first;
    expect(tester.getSize(form).height, lessThan(250));
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
    await tester.tap(find.text('消费统计'));
    await tester.pumpAndSettle();
    expect(find.text('消费趋势'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    c.navigate(GalleryPage.settings);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('启用新界面（beta）'),
      400,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .last,
    );
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
    expect(
      (tester.widget<Material>(menu).shape! as RoundedRectangleBorder).side,
      BorderSide.none,
    );
    expect(
      find.descendant(of: menu, matching: find.byType(Divider)),
      findsNWidgets(3),
    );
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
    'capsule accelerates while pages slide directly to the selected destination',
    (tester) async {
      tester.view.physicalSize = const Size(360, 892);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = GalleryController(data);
      addTearDown(c.dispose);
      await tester.pumpWidget(GalleryApp(controller: c));
      await tester.pumpAndSettle();
      final capsule = find.byKey(const ValueKey('nav-capsule'));
      final initialRect = tester.getRect(capsule);
      final originalElement = tester.element(capsule);
      final home = find.byKey(const ValueKey('nav-home'));
      expect(initialRect.height, closeTo(52, .1));
      expect(
        initialRect.contains(
          tester.getCenter(
            find.descendant(
              of: home,
              matching: find.byIcon(Icons.home_outlined),
            ),
          ),
        ),
        isTrue,
      );
      expect(
        initialRect.contains(
          tester.getCenter(
            find.descendant(of: home, matching: find.text('首页')),
          ),
        ),
        isTrue,
      );

      await tester.tap(find.byKey(const ValueKey('nav-cards')));
      await tester.pump();
      final headerY = tester.getTopLeft(find.text('卡包').first).dy;
      expect(find.byKey(const ValueKey(GalleryPage.home)), findsOneWidget);
      final incoming = find.descendant(
        of: find.byKey(const ValueKey(GalleryPage.cards)),
        matching: find.byType(ReorderableListView),
      );
      expect(tester.getTopLeft(incoming).dx, closeTo(360, .1));
      expect(find.byKey(const ValueKey(GalleryPage.trips)), findsNothing);
      await tester.pump(const Duration(milliseconds: 100));
      final midway = tester.getRect(capsule);
      final target = tester
          .getCenter(find.byKey(const ValueKey('nav-cards')))
          .dx;
      expect(midway.center.dx, greaterThan(initialRect.center.dx));
      expect(midway.center.dx, lessThan(target));
      expect(tester.element(capsule), same(originalElement));
      expect(tester.getTopLeft(find.text('卡包').first).dy, headerY);
      expect(tester.getTopLeft(incoming).dx, inExclusiveRange(0, 360));

      // A new tap redirects the existing moving capsule without replacing it.
      await tester.tap(find.byKey(const ValueKey('nav-trips')));
      await tester.pump();
      expect(tester.getRect(capsule).left, closeTo(midway.left, .1));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(capsule).center.dx,
        closeTo(
          tester.getCenter(find.byKey(const ValueKey('nav-trips'))).dx,
          .1,
        ),
      );
      expect(find.byKey(const ValueKey(GalleryPage.trips)), findsOneWidget);
      c.update(() => c.docked = true);
      await tester.pumpAndSettle();
      expect(capsule, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'bottom bar paints one shadow-free glyph layer through touch transitions',
    (tester) async {
      final c = GalleryController(data);
      addTearDown(c.dispose);
      await tester.pumpWidget(GalleryApp(controller: c));
      await tester.pumpAndSettle();
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        for (final docked in [false, true]) {
          c.update(() {
            c.themeMode = mode;
            c.docked = docked;
          });
          await tester.pumpAndSettle();
          final nav = find.byKey(const ValueKey('nav-expert'));
          final gesture = await tester.startGesture(tester.getCenter(nav));
          await tester.pump(const Duration(milliseconds: 45));
          await gesture.up();
          for (var frame = 0; frame < 5; frame++) {
            await tester.pump(const Duration(milliseconds: 45));
            final text = tester.widget<Text>(
              find.descendant(of: nav, matching: find.text('专家')),
            );
            final icon = tester.widget<Icon>(
              find.descendant(
                of: nav,
                matching: find.byIcon(Icons.science_outlined),
              ),
            );
            expect(text.style!.inherit, isFalse);
            expect(text.style!.shadows, isEmpty);
            expect(text.style!.fontWeight, FontWeight.w600);
            expect(icon.shadows, isEmpty);
            expect(icon.color, text.style!.color);
            expect(
              find.descendant(of: nav, matching: find.byType(Material)),
              findsNothing,
            );
          }
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('nav-home')));
          await tester.pumpAndSettle();
        }
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('expert raw tab keeps horizontal offset and list identity', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = GalleryController(data);
    c.update(() => c.hasRead = true);
    c.navigate(GalleryPage.expert);
    addTearDown(c.dispose);
    await tester.pumpWidget(GalleryApp(controller: c));
    await tester.pumpAndSettle();
    final vertical = find.byKey(
      PageStorageKey('gallery-${c.generation}-expert'),
    );
    final listElement = tester.element(vertical);
    final horizontal = find.byKey(
      PageStorageKey('gallery-${c.generation}-expert-tabs'),
    );
    await tester.drag(horizontal, const Offset(-300, 0));
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(
      find.descendant(of: horizontal, matching: find.byType(Scrollable)),
    );
    final offset = scroll.position.pixels;
    expect(offset, greaterThan(0));
    final raw = find.text('APDU / Raw Data');
    final before = tester.getRect(raw);
    await tester.tap(raw);
    await tester.pump();
    expect(c.expertTab, 3);
    expect(tester.element(vertical), same(listElement));
    expect(scroll.position.pixels, closeTo(offset, .1));
    expect(tester.getRect(raw), before);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getRect(raw), before);
    expect(find.textContaining('C-APDU'), findsWidgets);
    // Other updates and leaving the page must preserve the tab strip offset.
    c.update(() => c.includeOverdraft = true);
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, closeTo(offset, .1));
    c.navigate(GalleryPage.cards);
    await tester.pumpAndSettle();
    c.navigate(GalleryPage.expert);
    await tester.pumpAndSettle();
    final restored = tester.state<ScrollableState>(
      find.descendant(of: horizontal, matching: find.byType(Scrollable)),
    );
    expect(restored.position.pixels, closeTo(offset, .1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

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
    await tester.tap(find.byKey(const ValueKey('wallet-card-shenzhen')));
    await tester.pumpAndSettle();
    final trigger = find.byTooltip('深圳通 管理');
    final anchor = tester.getRect(trigger);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    final menu = find.byKey(const ValueKey('gallery-dropdown'));
    final rect = tester.getRect(menu);
    expect(rect.top, closeTo(anchor.bottom + 6, 1));
    expect(rect.right, closeTo(anchor.right, 1));
    expect(c.page, GalleryPage.detail);
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
    // The accepted top-right feedback temporarily covers the fixed actions.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('通勤深圳通 管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('更改卡面'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('海蓝'));
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
    ('shanghai', '¥12.00', '周一，¥8.00'),
    ('suica', '337 JPY', '周一，337 JPY'),
    ('octopus', 'HK\$10.60', '周一，HK\$10.60'),
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
      await tester.tap(find.byKey(const ValueKey('spending-period-week')));
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
      await tester.scrollUntilVisible(
        find.text('分类开销'),
        250,
        scrollable: find
            .byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            )
            .last,
      );
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
        GalleryPage.expert,
        GalleryPage.about,
        GalleryPage.feedback,
        GalleryPage.acknowledgements,
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
