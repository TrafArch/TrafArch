import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';
import 'package:transit_card_analyzer/gallery/gallery_preferences.dart';
import 'package:transit_card_analyzer/gallery/gallery_theme.dart';

Future<void> gestureEvent(
  WidgetTester tester,
  String method, [
  double progress = 0,
]) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/backgesture',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall(
        method,
        method == 'startBackGesture' || method == 'updateBackGestureProgress'
            ? {
                'touchOffset': <double>[5, 300],
                'progress': progress,
                'swipeEdge': 0,
              }
            : null,
      ),
    ),
    (_) {},
  );
  await tester.pump();
}

void main() {
  late GalleryController c;
  late GalleryPreferences preferences;
  setUp(() {
    c = GalleryController(
      GalleryData(
        jsonDecode(File('assets/gallery/fixtures.json').readAsStringSync())
            as GalleryRecord,
      ),
    );
    preferences = GalleryPreferences();
  });
  tearDown(() {
    c.dispose();
    preferences.dispose();
  });

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      GalleryApp(controller: c, preferences: preferences),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'navigation exposes stable immutable entries and snapshots popup payload',
    (tester) async {
      final mainId = c.navigationStack.single.id;
      c.navigate(GalleryPage.cards);
      expect(c.navigationStack.single.id, mainId);
      c.openCard(c.cards[1]);
      final detailId = c.navigationStack.last.id;
      c.showOverlay(GalleryOverlay.face);
      final overlay = c.navigationStack.last;
      c.update(() => c.selectedCardId = c.cards[2].id);
      expect(c.navigationStack.last.cardId, overlay.cardId);
      expect(() => c.navigationStack.clear(), throwsUnsupportedError);
      c.back();
      expect(c.navigationStack.last.id, detailId);
      c.didPopRoute(overlay.id); // A late callback from the outgoing popup.
      expect(c.page, GalleryPage.detail);
      c.back();
      c.openCard(c.cards[1]);
      expect(c.navigationStack.last.id, isNot(detailId));
      c.reset();
      expect(c.navigationStack.single.id, isNot(mainId));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'page push slides left and reverse continues right to its saved parent',
    (tester) async {
      await mount(tester);
      c.navigate(GalleryPage.settings);
      await tester.pump();
      final settings = find.byKey(const ValueKey(GalleryPage.settings));
      await tester.pump(const Duration(milliseconds: 70));
      expect(tester.getTopLeft(settings).dx, inExclusiveRange(0, 412));
      expect(find.text('设置'), findsWidgets);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(settings).dx, 0);
      c.back();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.getTopLeft(settings).dx, inExclusiveRange(0, 412));
      await tester.pump(const Duration(milliseconds: 161));
      await tester.pump();
      expect(settings, findsNothing);
      expect(c.page, GalleryPage.home);
    },
  );

  testWidgets(
    'predictive page cancel preserves history, commit resumes from the current offset',
    (tester) async {
      c.navigate(GalleryPage.settings);
      c.navigate(GalleryPage.about);
      await mount(tester);
      final about = find.byKey(const ValueKey(GalleryPage.about));
      final original = c.navigationStack.map((e) => e.id).toList();
      await gestureEvent(tester, 'startBackGesture');
      await gestureEvent(tester, 'updateBackGestureProgress', .35);
      final partial = tester.getTopLeft(about).dx;
      expect(partial, closeTo(412 * .35, .1));
      expect(c.navigationStack.map((e) => e.id), original);
      await gestureEvent(tester, 'cancelBackGesture');
      await tester.pumpAndSettle();
      expect(c.page, GalleryPage.about);
      expect(tester.getTopLeft(about).dx, 0);
      await gestureEvent(tester, 'startBackGesture');
      await gestureEvent(tester, 'updateBackGestureProgress', .35);
      await gestureEvent(tester, 'commitBackGesture');
      expect(c.page, GalleryPage.settings);
      expect(tester.getTopLeft(about).dx, closeTo(partial, .1));
      await tester.pump(const Duration(milliseconds: 30));
      expect(tester.getTopLeft(about).dx, greaterThan(partial));
      await tester.pumpAndSettle();
      expect(about, findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(c.page, GalleryPage.home);
    },
  );

  testWidgets(
    'sheets move up and down, and canceling back leaves their parent intact',
    (tester) async {
      await mount(tester);
      c.showOverlay(GalleryOverlay.face, card: c.current);
      await tester.pump();
      final title = find.text('更换卡面');
      await tester.pump(const Duration(milliseconds: 65));
      final partialY = tester.getTopLeft(title).dy;
      await tester.pumpAndSettle();
      final restingY = tester.getTopLeft(title).dy;
      expect(partialY, greaterThan(restingY));
      await gestureEvent(tester, 'startBackGesture');
      await gestureEvent(tester, 'updateBackGestureProgress', .3);
      expect(tester.getTopLeft(title).dy, greaterThan(restingY));
      await gestureEvent(tester, 'cancelBackGesture');
      await tester.pumpAndSettle();
      expect(c.overlay, GalleryOverlay.face);
      expect(tester.getTopLeft(title).dy, closeTo(restingY, .1));
      c.back();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.getTopLeft(title).dy, greaterThan(restingY));
      expect(title.hitTestable(), findsNothing);
      await tester.pumpAndSettle();
      expect(c.overlay, isNull);
      expect(c.page, GalleryPage.home);
    },
  );

  testWidgets(
    'dialogs and anchored menus animate both entrance and dismissal',
    (tester) async {
      await mount(tester);
      for (final overlay in [GalleryOverlay.rename, GalleryOverlay.source]) {
        c.showOverlay(overlay, anchor: const Rect.fromLTWH(16, 160, 140, 40));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 35));
        final route = find.byKey(
          ValueKey('route-${c.navigationStack.last.id}'),
        );
        final opacity = find
            .ancestor(of: route, matching: find.byType(Opacity))
            .first;
        expect(tester.widget<Opacity>(opacity).opacity, inExclusiveRange(0, 1));
        await tester.pumpAndSettle();
        final parentId = c.navigationStack[c.navigationStack.length - 2].id;
        await gestureEvent(tester, 'startBackGesture');
        await gestureEvent(tester, 'updateBackGestureProgress', .4);
        await gestureEvent(tester, 'commitBackGesture');
        expect(c.navigationStack.last.id, parentId);
        expect(route.hitTestable(), findsNothing);
        await tester.pumpAndSettle();
        expect(route, findsNothing);
      }
    },
  );

  testWidgets('QR cancel does not cancel acquisition until back is committed', (
    tester,
  ) async {
    c.navigate(GalleryPage.qr);
    c.qr.open('camera');
    await mount(tester);
    c.qr.acquire('valid');
    await tester.pump();
    await gestureEvent(tester, 'startBackGesture');
    await gestureEvent(tester, 'updateBackGestureProgress', .2);
    expect(c.qr.busy, isTrue);
    await gestureEvent(tester, 'cancelBackGesture');
    await tester.pump(const Duration(milliseconds: 200));
    expect(c.qr.view, 'camera');
    expect(c.qr.busy, isTrue);
    await gestureEvent(tester, 'startBackGesture');
    await gestureEvent(tester, 'updateBackGestureProgress', .2);
    await gestureEvent(tester, 'commitBackGesture');
    expect(c.qr.view, 'inspect');
    expect(c.qr.busy, isFalse);
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
    expect(c.qr.result, isNull);
    expect(c.page, GalleryPage.qr);
  });

  testWidgets('setting off and reduced motion retain ordinary system back', (
    tester,
  ) async {
    c.navigate(GalleryPage.settings);
    await preferences.setEnabled(false);
    await mount(tester);
    final page = find.byKey(const ValueKey(GalleryPage.settings));
    await gestureEvent(tester, 'startBackGesture');
    await gestureEvent(tester, 'updateBackGestureProgress', .5);
    expect(tester.getTopLeft(page).dx, 0);
    await gestureEvent(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(c.page, GalleryPage.home);
    await preferences.setEnabled(true);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    c.navigate(GalleryPage.settings);
    await tester.pump();
    await tester.pump();
    expect(tester.getTopLeft(page).dx, 0);
    await gestureEvent(tester, 'startBackGesture');
    await gestureEvent(tester, 'updateBackGestureProgress', .5);
    expect(tester.getTopLeft(page).dx, 0);
    await gestureEvent(tester, 'cancelBackGesture');
    final reducedPop = tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await reducedPop;
    expect(c.page, GalleryPage.home);
  });

  testWidgets(
    'reset during a gesture releases routes and observers without late mutations',
    (tester) async {
      c.navigate(GalleryPage.settings);
      await mount(tester);
      await gestureEvent(tester, 'startBackGesture');
      await gestureEvent(tester, 'updateBackGestureProgress', .4);
      c.reset();
      await tester.pumpAndSettle();
      await gestureEvent(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(c.page, GalleryPage.home);
      expect(c.navigationStack, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'folds retain their contents while shrinking and disable closing controls',
    (tester) async {
      c.navigate(GalleryPage.settings);
      c.navigate(GalleryPage.knowledge);
      await mount(tester);
      expect(find.text('源文件'), findsNothing);
      await tester.tap(find.text('数据概况'));
      await tester.pump();
      final clipped = find
          .ancestor(of: find.text('源文件'), matching: find.byType(ClipRect))
          .first;
      await tester.pump(const Duration(milliseconds: 45));
      final growing = tester.getSize(clipped).height;
      await tester.pumpAndSettle();
      final full = tester.getSize(clipped).height;
      expect(growing, inExclusiveRange(0, full));
      await tester.tap(find.text('数据概况'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 45));
      expect(tester.getSize(clipped).height, inExclusiveRange(0, full));
      expect(find.text('源文件').hitTestable(), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('源文件'), findsNothing);
    },
  );

  testWidgets(
    'QR completion in a gesture retires the acquisition route and ignores its late commit',
    (tester) async {
      c.navigate(GalleryPage.qr);
      c.qr.open('gallery');
      await mount(tester);
      c.qr.acquire('valid');
      await tester.pump();
      await gestureEvent(tester, 'startBackGesture');
      await gestureEvent(tester, 'updateBackGestureProgress', .4);
      await tester.pump(const Duration(milliseconds: 750));
      await tester.pumpAndSettle();
      expect(c.qr.result, isNotNull);
      expect(c.qr.view, 'inspect');
      await gestureEvent(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(c.page, GalleryPage.qr);
      expect(c.qr.result, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('keyboard focus is visible and activation switches tabs once', (
    tester,
  ) async {
    await mount(tester);
    final nav = find.byKey(const ValueKey('nav-cards'));
    final focusable = find.descendant(
      of: nav,
      matching: find.byType(FocusableActionDetector),
    );
    final focus = Focus.of(
      tester.element(
        find.descendant(of: focusable, matching: find.byType(GestureDetector)),
      ),
    );
    focus.requestFocus();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    // Move focus back after entering keyboard traversal mode.
    focus.requestFocus();
    await tester.pumpAndSettle();
    final containers = tester.widgetList<Container>(
      find.descendant(of: nav, matching: find.byType(Container)),
    );
    expect(
      containers.any(
        (w) =>
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).border != null,
      ),
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(c.page, GalleryPage.cards);
    expect(c.navigationStack, hasLength(1));
  });

  testWidgets(
    'rapid nonadjacent reversals keep the viewport covered and settle on the last tab',
    (tester) async {
      await mount(tester);
      void expectCovered() {
        final rectangles = <Rect>[];
        for (final page in GalleryPage.values.take(5)) {
          final lists = find.descendant(
            of: find.byKey(ValueKey(page)),
            matching: find.byType(ListView),
          );
          if (lists.evaluate().isNotEmpty) {
            rectangles.add(tester.getRect(lists.first));
          }
        }
        rectangles.sort((a, b) => a.left.compareTo(b.left));
        var covered = 0.0;
        for (final rect in rectangles) {
          if (rect.right < 0 || rect.left > 412) continue;
          expect(
            rect.left,
            lessThanOrEqualTo(covered + .1),
            reason: 'No uncovered stripe during a rapid change',
          );
          if (rect.right > covered) covered = rect.right;
        }
        expect(covered, greaterThanOrEqualTo(411.9));
      }

      c.navigate(GalleryPage.cards);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      for (final page in [
        GalleryPage.trips,
        GalleryPage.footprints,
        GalleryPage.home,
        GalleryPage.expert,
      ]) {
        c.navigate(page);
        await tester.pump();
        for (var frame = 0; frame < 4; frame++) {
          await tester.pump(const Duration(milliseconds: 12));
          expectCovered();
        }
      }
      await tester.pumpAndSettle();
      expect(c.page, GalleryPage.expert);
      expect(find.byKey(const ValueKey(GalleryPage.expert)), findsOneWidget);
      expect(find.byKey(const ValueKey(GalleryPage.home)), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'knowledge tabs crossfade and restore each protocol scroll position',
    (tester) async {
      c.navigate(GalleryPage.settings);
      c.navigate(GalleryPage.knowledge);
      await mount(tester);
      final tu = find.byKey(
        PageStorageKey('gallery-${c.generation}-knowledge-tu'),
      );
      final cu = find.byKey(
        PageStorageKey('gallery-${c.generation}-knowledge-cu'),
      );
      await tester.drag(tu, const Offset(0, -240));
      await tester.pumpAndSettle();
      double offset(Finder list) => tester
          .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)),
          )
          .position
          .pixels;
      final savedOffset = offset(tu);
      expect(savedOffset, greaterThan(0));
      c.update(() => c.knowledgeTab = 'cu');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(tu, findsOneWidget);
      expect(cu, findsOneWidget);
      final transition = find
          .ancestor(of: cu, matching: find.byType(FadeTransition))
          .first;
      expect(
        tester.widget<FadeTransition>(transition).opacity.value,
        inExclusiveRange(0, 1),
      );
      expect(tu.hitTestable(), findsNothing);
      await tester.pumpAndSettle();
      expect(tu, findsNothing);
      c.update(() => c.knowledgeTab = 'tu');
      await tester.pumpAndSettle();
      expect(offset(tu), closeTo(savedOffset, .1));
    },
  );

  testWidgets(
    'theme segment slides continuously and reverses from its current position',
    (tester) async {
      c.navigate(GalleryPage.settings);
      await mount(tester);
      final indicator = find.byKey(const ValueKey('segments-跟随系统-indicator'));
      await tester.ensureVisible(indicator);
      await tester.pumpAndSettle();
      final start = tester.getCenter(indicator).dx;
      await tester.tap(find.text('深色'));
      await tester.pump();
      expect(tester.getCenter(indicator).dx, closeTo(start, .1));
      await tester.pump(const Duration(milliseconds: 60));
      final partial = tester.getCenter(indicator).dx;
      final destination = tester.getCenter(find.text('深色')).dx;
      expect(partial, inExclusiveRange(start, destination));
      await tester.tap(find.text('跟随系统'));
      await tester.pump();
      expect(tester.getCenter(indicator).dx, closeTo(partial, .1));
      await tester.pump(const Duration(milliseconds: 45));
      expect(tester.getCenter(indicator).dx, inExclusiveRange(start, partial));
      await tester.pumpAndSettle();
      expect(tester.getCenter(indicator).dx, closeTo(start, .1));
    },
  );

  testWidgets(
    'conditional settings animate height and disable outgoing actions immediately',
    (tester) async {
      c.navigate(GalleryPage.settings);
      await mount(tester);
      final logs = find.widgetWithText(SwitchListTile, '启用运行日志');
      await tester.ensureVisible(logs);
      await tester.pumpAndSettle();
      final tile = tester.getRect(logs);
      final panel = find
          .ancestor(of: logs, matching: find.byType(Material))
          .first;
      final collapsedHeight = tester.getSize(panel).height;
      await tester.tap(logs);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final partialHeight = tester.getSize(panel).height;
      expect(partialHeight, greaterThan(collapsedHeight));
      await tester.pumpAndSettle();
      expect(tester.getSize(panel).height, greaterThan(partialHeight));
      expect(find.text('导出日志').hitTestable(), findsOneWidget);
      await tester.tapAt(tile.center);
      await tester.pump();
      expect(find.text('导出日志'), findsOneWidget);
      expect(find.text('导出日志').hitTestable(), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('导出日志'), findsNothing);
      expect(tester.getSize(panel).height, closeTo(collapsedHeight, .1));
    },
  );

  testWidgets(
    'navigation pixels stay inside palette bounds during every selected-color transition',
    (tester) async {
      await mount(tester);
      for (final theme in [ThemeMode.light, ThemeMode.dark]) {
        for (final docked in [false, true]) {
          c.update(() {
            c.themeMode = theme;
            c.docked = docked;
          });
          await tester.pumpAndSettle();
          final boundaryFinder = find.byKey(
            const ValueKey('gallery-navigation'),
          );
          final tokens = Theme.of(tester.element(boundaryFinder))
              .extension<GalleryTokens>()!;
          final colors = [
            tokens.bg,
            tokens.surface,
            tokens.surface2,
            tokens.tone,
            tokens.muted,
            tokens.onTone,
          ];
          final minR = colors
              .map((v) => (v.r * 255).round())
              .reduce((a, b) => a < b ? a : b);
          final minG = colors
              .map((v) => (v.g * 255).round())
              .reduce((a, b) => a < b ? a : b);
          final minB = colors
              .map((v) => (v.b * 255).round())
              .reduce((a, b) => a < b ? a : b);
          await tester.tap(find.byKey(const ValueKey('nav-footprints')));
          await tester.pump();
          for (final elapsed in [0, 45, 45, 90]) {
            await tester.pump(Duration(milliseconds: elapsed));
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              boundaryFinder,
            );
            final pixels = await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 1);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
              image.dispose();
              return bytes!.buffer.asUint8List();
            });
            var darkPixels = 0;
            for (var i = 0; i < pixels!.length; i += 4) {
              if (pixels[i + 3] > 250 &&
                  (pixels[i] < minR - 2 ||
                      pixels[i + 1] < minG - 2 ||
                      pixels[i + 2] < minB - 2)) {
                darkPixels++;
              }
            }
            expect(
              darkPixels,
              0,
              reason: '$theme docked=$docked: no black glyph shadows',
            );
          }
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('nav-home')));
          await tester.pumpAndSettle();
        }
      }
    },
  );
}
