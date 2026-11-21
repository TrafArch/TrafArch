import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_color_engine.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';
import 'package:transit_card_analyzer/gallery/gallery_design.dart';
import 'package:transit_card_analyzer/gallery/gallery_layout.dart';
import 'package:transit_card_analyzer/gallery/gallery_theme.dart';

void main() {
  test('floating navigation blends dual light shadows into a dark border', () {
    for (final palette in GalleryPalette.values) {
      final light = GalleryTokens(scheme: palette.scheme(false));
      final dark = GalleryTokens(scheme: palette.scheme(true));
      expect(light.floatingNavigationBorder, isNull);
      expect(dark.floatingNavigationShadows, isEmpty);
      expect(dark.floatingNavigationBorder!.top.width, 1);
      expect(dark.floatingNavigationBorder!.top.color, dark.line);
      for (final progress in [0.0, .25, .49, .5, .51, .75, .99]) {
        final tokens = light.lerp(dark, progress);
        final shadows = tokens.floatingNavigationShadows;
        expect(shadows, hasLength(2));
        final tint = Color.lerp(
          const Color(0xff14202e),
          const Color(0xff000000),
          progress,
        )!;
        for (var index = 0; index < shadows.length; index++) {
          final shadow = shadows[index];
          expect(shadow.blurRadius, index == 0 ? 10 : 24);
          expect(shadow.offset, Offset(0, index == 0 ? 2 : 8));
          expect(shadow.spreadRadius, 0);
          expect(
            shadow.color,
            tint.withValues(alpha: (index == 0 ? .16 : .14) * (1 - progress)),
          );
          expect(
            dark
                .lerp(light, 1 - progress)
                .floatingNavigationShadows[index]
                .color
                .a,
            closeTo(shadow.color.a, 1e-9),
          );
        }
        if (progress > 0) {
          expect(
            tokens.floatingNavigationBorder!.top.color.a,
            closeTo(tokens.line.a * progress, 1e-9),
          );
        }
      }
    }
  });
  late GalleryController c;
  setUp(() {
    c = GalleryController(
      GalleryData(
        jsonDecode(File('assets/gallery/fixtures.json').readAsStringSync())
            as GalleryRecord,
      ),
    );
  });
  tearDown(() => c.dispose());
  Future<void> mount(WidgetTester tester, {double width = 412}) async {
    tester.view.physicalSize = Size(width, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(GalleryApp(controller: c));
    await tester.pumpAndSettle();
  }

  Future<void> swipe(WidgetTester tester, double dx) async {
    await tester.timedDragFrom(
      const Offset(206, 400),
      Offset(dx, 0),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'horizontal drags leave every main destination and its capsule in place',
    (tester) async {
      await mount(tester);
      for (final page in GalleryController.visibleMainPages) {
        c.navigate(page);
        await tester.pumpAndSettle();
        final capsule = find.byKey(const ValueKey('nav-capsule'));
        final origin = tester.getTopLeft(capsule).dx;
        for (final dx in [-170.0, 170.0]) {
          await swipe(tester, dx);
          expect(c.page, page);
          expect(tester.getTopLeft(find.byKey(ValueKey(page))).dx, 0);
          expect(tester.getTopLeft(capsule).dx, closeTo(origin, .1));
        }
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'navigation clicks crossfade in place and can reverse mid transition',
    (tester) async {
      await mount(tester);
      Finder surface(GalleryPage page) => find
          .descendant(
            of: find.byKey(ValueKey(page)),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is ListView ||
                  widget is ReorderableListView ||
                  widget is CustomScrollView,
            ),
          )
          .first;
      final home = surface(GalleryPage.home);
      final cards = surface(GalleryPage.cards);
      double opacity(GalleryPage page) => tester
          .widget<Opacity>(
            find.byWidgetPredicate(
              (widget) => widget is Opacity && widget.key == ValueKey(page),
            ),
          )
          .opacity;
      await tester.tap(find.byKey(const ValueKey('nav-cards')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.getTopLeft(home).dx, 0);
      expect(tester.getTopLeft(cards).dx, 0);
      final beforeReverse = opacity(GalleryPage.home);
      expect(beforeReverse, inExclusiveRange(0, 1));
      expect(opacity(GalleryPage.cards), inExclusiveRange(0, 1));
      await tester.tap(find.byKey(const ValueKey('nav-home')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(opacity(GalleryPage.home), greaterThan(beforeReverse));
      await tester.pumpAndSettle();
      expect(c.page, GalleryPage.home);
      expect(tester.getTopLeft(home).dx, 0);
      expect(find.byKey(const ValueKey(GalleryPage.cards)), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'expert tab strip scrolls but does not swipe its internal selection',
    (tester) async {
      c.hasRead = true;
      c.navigate(GalleryPage.expert);
      await mount(tester, width: 360);
      final strip = find.byKey(
        PageStorageKey('gallery-${c.generation}-expert-tabs'),
      );
      await tester.drag(strip, const Offset(-220, 0));
      await tester.pumpAndSettle();
      expect(c.page, GalleryPage.expert);
      expect(c.expertTab, 0);
      await tester.tap(find.text('APDU / Raw Data'));
      await tester.pumpAndSettle();
      expect(c.expertTab, 3);
      await swipe(tester, -160);
      expect(c.page, GalleryPage.expert);
      expect(c.expertTab, 3);
      await tester.tap(find.byKey(const ValueKey('nav-cards')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-expert')));
      await tester.pumpAndSettle();
      await swipe(tester, 160);
      expect(c.page, GalleryPage.expert);
      expect(c.expertTab, 3);
    },
  );
  testWidgets('subpages and open menus keep main swipe inactive', (
    tester,
  ) async {
    c.navigate(GalleryPage.settings);
    await mount(tester);
    await swipe(tester, -170);
    expect(c.page, GalleryPage.settings);
    c.back();
    c.navigate(GalleryPage.cards);
    c.showOverlay(
      GalleryOverlay.cardMenu,
      card: c.savedCards.first,
      anchor: const Rect.fromLTWH(330, 180, 36, 36),
    );
    await tester.pumpAndSettle();
    await swipe(tester, -170);
    expect(c.page, GalleryPage.cards);
    expect(c.overlay, GalleryOverlay.cardMenu);
  });
  testWidgets(
    'both bars place all controls above gesture or button system areas',
    (tester) async {
      await mount(tester);
      for (final docked in [false, true]) {
        for (final safe in [0.0, 24.0, 48.0]) {
          tester.view.viewPadding = FakeViewPadding(bottom: safe);
          tester.view.padding = FakeViewPadding(bottom: safe);
          c.update(() => c.docked = docked);
          await tester.pumpAndSettle();
          final layout = GalleryNavigationLayout(
            MediaQueryData(viewPadding: EdgeInsets.only(bottom: safe)),
            docked: docked,
          );
          final nav = find.byKey(const ValueKey('nav-home'));
          final navBottom = tester.getBottomLeft(nav).dy;
          expect(navBottom, lessThanOrEqualTo(892 - layout.bottomSpace + .1));
          final list = tester.widget<ListView>(
            find.byKey(PageStorageKey('gallery-${c.generation}-home-inspect')),
          );
          expect((list.padding! as EdgeInsets).bottom, layout.listBottom);
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          tester.view.padding = const FakeViewPadding();
          await tester.pumpAndSettle();
          expect(
            tester.getBottomLeft(nav).dy,
            closeTo(
              navBottom - 300 + layout.bottomSpace - (docked ? 0 : 18),
              .1,
            ),
          );
          expect(
            tester.getBottomLeft(nav).dy,
            lessThanOrEqualTo(892 - 300 - (docked ? 0 : 18)),
          );
          tester.view.viewInsets = const FakeViewPadding();
          tester.view.padding = FakeViewPadding(bottom: safe);
          await tester.pumpAndSettle();
          expect(tester.getBottomLeft(nav).dy, closeTo(navBottom, .1));
        }
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('wallet aligns currency groups with a tight leading number gap', (
    tester,
  ) async {
    c.navigate(GalleryPage.cards);
    await mount(tester);
    for (final width in [412.0, 360.0, 320.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        tester.view.physicalSize = Size(width, 2400);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        c.update(() {});
        await tester.pumpAndSettle();
        final currencyLeftEdges = <double>[];
        for (final card in c.savedCards) {
          final currencyFinder = find.byKey(
            ValueKey('wallet-currency-${card.id}'),
          );
          final numberFinder = find.byKey(ValueKey('wallet-number-${card.id}'));
          final currency = tester.getRect(currencyFinder);
          final number = tester.getRect(numberFinder);
          final panel = tester.getRect(
            find.byKey(ValueKey('wallet-card-${card.id}')),
          );
          final appliedScale =
              currency.width / tester.getSize(currencyFinder).width;
          currencyLeftEdges.add(currency.left);
          expect(
            number.left - currency.right,
            closeTo(4 * appliedScale, .1),
            reason: '${card.id}, width=$width, scale=$scale',
          );
          expect(tester.widget<Text>(numberFinder).textAlign, TextAlign.left);
          expect(currency.left, greaterThanOrEqualTo(panel.left));
          expect(number.right, lessThanOrEqualTo(panel.right));
        }
        for (final (id, label) in [
          ('shenzhen', 'CNY ¥'),
          ('suica', 'JP￥'),
          ('octopus', r'HK$'),
        ]) {
          expect(
            tester
                .widget<Text>(find.byKey(ValueKey('wallet-currency-$id')))
                .data,
            label,
          );
        }
        expect(
          currencyLeftEdges.reduce((a, b) => a > b ? a : b) -
              currencyLeftEdges.reduce((a, b) => a < b ? a : b),
          lessThan(.1),
        );
        expect(tester.takeException(), isNull);
      }
    }
  });
  testWidgets(
    'landscape bars also respect bottom and side system navigation areas',
    (tester) async {
      await mount(tester);
      tester.view.physicalSize = const Size(892, 412);
      for (final docked in [false, true]) {
        for (final bottom in [0.0, 24.0]) {
          final right = bottom == 0 ? 48.0 : 0.0;
          tester.view.viewPadding = FakeViewPadding(
            bottom: bottom,
            right: right,
          );
          tester.view.padding = FakeViewPadding(bottom: bottom, right: right);
          c.update(() => c.docked = docked);
          await tester.pumpAndSettle();
          final navigation = tester.getRect(
            find.byKey(const ValueKey('gallery-navigation')),
          );
          final home = tester.getRect(find.byKey(const ValueKey('nav-home')));
          expect(navigation.right, lessThanOrEqualTo(892 - right));
          expect(home.bottom, lessThanOrEqualTo(412 - bottom));
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
  testWidgets(
    'upward card menu scales from its trigger edge and cannot be activated while closing',
    (tester) async {
      c.navigate(GalleryPage.cards);
      await mount(tester);
      tester.view.physicalSize = const Size(412, 412);
      const anchor = Rect.fromLTWH(330, 330, 36, 36);
      c.showOverlay(
        GalleryOverlay.cardMenu,
        card: c.savedCards.first,
        anchor: anchor,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 35));
      final menu = find.byKey(const ValueKey('gallery-dropdown'));
      expect(tester.getRect(menu).right, closeTo(anchor.right, .1));
      await tester.pumpAndSettle();
      expect(tester.getRect(menu).bottom, closeTo(anchor.top - 6, .1));
      c.back();
      await tester.pump(const Duration(milliseconds: 30));
      expect(find.text('删除本卡').hitTestable(), findsNothing);
      await tester.pumpAndSettle();
      expect(menu, findsNothing);
    },
  );
  testWidgets(
    'card Monet source, brand artwork and manual overrides share the scheme',
    (tester) async {
      await mount(tester);
      GalleryTokens tokens() => Theme.of(
        tester.element(find.byKey(const ValueKey('gallery-brand-mark'))),
      ).extension<GalleryTokens>()!;
      final initial = tokens().action;
      expect(tokens().dynamic, isTrue);
      expect(
        initial,
        GalleryColorEngine.tokens(c.themeSeed, dark: false).primary,
      );
      final mark = tester.widget<SvgPicture>(
        find.byKey(const ValueKey('gallery-brand-mark')),
      );
      final mapper = (mark.bytesLoader as SvgAssetLoader).colorMapper!;
      expect(
        mapper.substitute(null, 'path', 'stroke', const Color(0xff4e7098)),
        initial,
      );
      c.update(() {
        c.monet = false;
        c.palette = 'teal';
      });
      await tester.pumpAndSettle();
      expect(tokens().dynamic, isFalse);
      expect(tokens().action, isNot(initial));
      c.update(() => c.monet = true);
      await tester.pumpAndSettle();
      expect(tokens().action, initial);
    },
  );

  testWidgets(
    'home card centers the full number and keeps the corner fields separate',
    (tester) async {
      c.hasRead = true;
      c.current.saved = true;
      await mount(tester, width: 320);
      for (final scale in [1.0, 1.5, 2.0]) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        c.update(() {});
        await tester.pumpAndSettle();
        final face = tester.getRect(
          find.byKey(const ValueKey('card-face-shanghai')),
        );
        final title = tester.getRect(
          find.byKey(const ValueKey('face-title-shanghai')),
        );
        final number = tester.getRect(
          find.byKey(const ValueKey('face-card-number-shanghai')),
        );
        final label = tester.getRect(
          find.byKey(const ValueKey('face-balance-label-shanghai')),
        );
        final balance = tester.getRect(
          find.byKey(const ValueKey('face-number-shanghai')),
        );
        final brand = tester.getRect(
          find.byKey(const ValueKey('face-brand-shanghai')),
        );
        expect(number.center.dx, closeTo(face.center.dx, .5));
        expect(number.center.dy, closeTo(face.center.dy, .5));
        expect(number.top, greaterThan(title.bottom));
        expect(label.top, greaterThan(number.bottom));
        expect(balance.top, greaterThan(label.bottom));
        expect(label.left, closeTo(title.left, .5));
        expect(brand.left, greaterThan(balance.right));
        expect(brand.top, greaterThan(number.bottom));
        expect(brand.right, closeTo(face.right - (title.left - face.left), .5));
        expect(brand.bottom, closeTo(balance.bottom, .5));
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets('home card seed drives independent light and dark schemes', (
    tester,
  ) async {
    c.themeMode = ThemeMode.light;
    await mount(tester);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeAnimationDuration, const Duration(milliseconds: 200));
    expect(app.themeAnimationCurve, Curves.easeInOutCubic);
    GalleryTokens tokens() => Theme.of(
      tester.element(find.byKey(const ValueKey('gallery-brand-mark'))),
    ).extension<GalleryTokens>()!;
    expect(tokens().dynamic, isTrue);
    expect(
      tokens().action,
      GalleryColorEngine.tokens(c.themeSeed, dark: false).primary,
    );
    final lightCanvas = tokens().canvas;
    c.update(() => c.themeMode = ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(
      tokens().action,
      GalleryColorEngine.tokens(c.themeSeed, dark: true).primary,
    );
    expect(tokens().canvas, isNot(lightCanvas));
    final blueAction = tokens().action;
    c.update(() => c.current.face = 'teal');
    await tester.pumpAndSettle();
    expect(tokens().action, isNot(blueAction));
    expect(
      tokens().action,
      GalleryColorEngine.tokens(c.themeSeed, dark: true).primary,
    );
  });
  testWidgets(
    'all content pages and long balances fit 320dp at twice the font size',
    (tester) async {
      c.hasRead = true;
      c.cards[1].rawBalance = '-123,456.78';
      c.cards[2].rawBalance = '暂不可用';
      c.cards[3].rawBalance = 'HK\$123456.78';
      await mount(tester, width: 320);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      Future<void> auditEntireList(String state) async {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: state);
        final list = find
            .byWidgetPredicate(
              (widget) => widget is ListView || widget is CustomScrollView,
            )
            .first;
        final scroll = tester.state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        );
        scroll.position.jumpTo(0);
        await tester.pumpAndSettle();
        for (
          var step = 0;
          step < 50 && scroll.position.extentAfter > 1;
          step++
        ) {
          scroll.position.jumpTo(
            (scroll.position.pixels + 400).clamp(
              0.0,
              scroll.position.maxScrollExtent,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$state, scroll step $step',
          );
        }
        expect(
          scroll.position.extentAfter,
          lessThanOrEqualTo(1),
          reason: state,
        );
      }

      for (final page in [
        GalleryPage.home,
        GalleryPage.trips,
        GalleryPage.expert,
        GalleryPage.cards,
        GalleryPage.footprints,
        GalleryPage.settings,
        GalleryPage.knowledge,
        GalleryPage.qr,
        GalleryPage.detail,
        GalleryPage.feedback,
        GalleryPage.acknowledgements,
      ]) {
        c.navigate(page);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$page at 320dp / 2x');
        await auditEntireList('$page at 320dp / 2x');
      }
      c.navigate(GalleryPage.detail);
      for (final tab in [1, 2]) {
        c.update(() => c.detailTab = tab);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'detail tab $tab at 2x');
        await auditEntireList('detail tab $tab at 2x');
      }
      c.navigate(GalleryPage.expert);
      for (final tab in [1, 2, 3]) {
        c.update(() => c.expertTab = tab);
        await auditEntireList('expert tab $tab at 2x');
      }
    },
  );
}
