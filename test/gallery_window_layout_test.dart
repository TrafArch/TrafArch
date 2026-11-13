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

Finder verticalScroll() => find
    .byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    )
    .last;

void main() {
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

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(GalleryApp(controller: c));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Gallery continuously resizes without resetting navigation, filters or scroll',
    (tester) async {
      await mount(tester);
      c.update(() {
        c.hasRead = true;
        c.expertTab = 3;
        c.source = '当前卡片';
      });
      c.navigate(GalleryPage.expert);
      await tester.pumpAndSettle();
      await tester.drag(verticalScroll(), const Offset(0, -100));
      await tester.pumpAndSettle();
      final appState = tester.state(find.byType(GalleryApp));
      final route = c.navigationStack.first;
      for (final size in const [
        Size(240, 320),
        Size(280, 400),
        Size(600, 320),
        Size(600, 800),
        Size(840, 800),
        Size(1200, 900),
        Size(390, 844),
      ]) {
        final scrollState = tester.state<ScrollableState>(verticalScroll());
        final offset = scrollState.position.pixels;
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(
          tester.state<ScrollableState>(verticalScroll()),
          same(scrollState),
        );
        expect(
          scrollState.position.pixels,
          closeTo(offset.clamp(0.0, scrollState.position.maxScrollExtent), .1),
        );
        expect(tester.state(find.byType(GalleryApp)), same(appState));
        expect(c.navigationStack.first, same(route));
        expect(c.expertTab, 3);
        expect(c.source, '当前卡片');
        for (final page in GalleryController.visibleMainPages) {
          final nav = find.byKey(ValueKey('nav-${page.name}'));
          expect(tester.getSize(nav).width, greaterThanOrEqualTo(47.99));
          expect(nav.hitTestable(), findsOneWidget);
          await tester.tap(nav);
          await tester.pumpAndSettle();
          expect(c.page, page);
          expect(tester.takeException(), isNull, reason: '$size ${page.name}');
        }
        c.navigate(GalleryPage.expert);
        await tester.pumpAndSettle();
      }
      expect(c.expertTab, 3);
    },
  );

  testWidgets(
    '240–320dp and large text retain usable navigation, wallet and details',
    (tester) async {
      await mount(tester);
      for (final width in [240.0, 280.0, 320.0]) {
        for (final scale in [1.0, 1.5, 2.0]) {
          tester.view.physicalSize = Size(width, 700);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          for (final docked in [false, true]) {
            c.update(() {
              c.docked = docked;
              c.hasRead = true;
            });
            for (final page in GalleryController.visibleMainPages) {
              c.navigate(page);
              await tester.pumpAndSettle();
              final nav = find.byKey(const ValueKey('nav-home'));
              expect(tester.getSize(nav).width, greaterThanOrEqualTo(47.99));
              expect(tester.getBottomLeft(nav).dy, lessThanOrEqualTo(700));
              expect(find.byTooltip('设置').hitTestable(), findsOneWidget);
              expect(
                tester.takeException(),
                isNull,
                reason: '$width $scale $docked $page',
              );
            }
          }
          c.openCard(c.current);
          c.update(() => c.detailTab = 1);
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byKey(PageStorageKey('gallery-${c.generation}-detail-tabs')),
            120,
            scrollable: verticalScroll(),
          );
          await tester.pumpAndSettle();
          expect(find.text('消费统计').hitTestable(), findsWidgets);
          await tester.scrollUntilVisible(
            find.text('消费趋势'),
            180,
            scrollable: verticalScroll(),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$width $scale weekly',
          );
          c.back();
          await tester.pumpAndSettle();
        }
      }
    },
  );

  testWidgets(
    'physical hinges constrain pages, navigation and all popup types to the largest pane',
    (tester) async {
      await mount(tester, size: const Size(1000, 800));
      tester.view.padding = const FakeViewPadding(top: 48, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 48, bottom: 24);
      for (final hinge in [
        const Rect.fromLTWH(300, 0, 20, 800),
        const Rect.fromLTWH(0, 250, 1000, 20),
        const Rect.fromLTWH(490, 0, 20, 800),
        const Rect.fromLTWH(0, 390, 1000, 20),
      ]) {
        tester.view.displayFeatures = [
          ui.DisplayFeature(
            bounds: hinge,
            type: ui.DisplayFeatureType.hinge,
            state: ui.DisplayFeatureState.postureFlat,
          ),
        ];
        await tester.pumpAndSettle();
        final pane = tester.getRect(
          find.byKey(const ValueKey('gallery-safe-window')),
        );
        expect(pane.overlaps(hinge), isFalse);
        if (hinge.left == 300) expect(pane.left, 320);
        if (hinge.top == 250) expect(pane.top, 270);
        if (hinge.left == 490) expect(pane.left, 0);
        if (hinge.top == 390) expect(pane.top, 0);
        final nav = tester.getRect(
          find.byKey(const ValueKey('gallery-navigation')),
        );
        expect(pane.contains(nav.center), isTrue);
        expect(nav.overlaps(hinge), isFalse);
        for (final type in [
          GalleryOverlay.rename,
          GalleryOverlay.face,
          GalleryOverlay.source,
        ]) {
          c.showOverlay(type);
          await tester.pumpAndSettle();
          final surface = find
              .byWidgetPredicate(
                (widget) =>
                    widget is Material && widget.clipBehavior == Clip.antiAlias,
              )
              .last;
          final rect = tester.getRect(surface);
          expect(rect.overlaps(hinge), isFalse);
          expect(pane.contains(rect.center), isTrue);
          expect(tester.takeException(), isNull);
          c.back();
          await tester.pumpAndSettle();
        }
      }
    },
  );

  testWidgets(
    'fold posture is ignored and caption Insets are consumed exactly once',
    (tester) async {
      await mount(tester, size: const Size(1000, 800));
      Rect? original;
      for (final top in [24.0, 48.0, 24.0]) {
        tester.view.padding = FakeViewPadding(top: top, bottom: 24);
        tester.view.viewPadding = FakeViewPadding(top: top, bottom: 24);
        for (final state in [
          ui.DisplayFeatureState.postureFlat,
          ui.DisplayFeatureState.postureHalfOpened,
        ]) {
          tester.view.displayFeatures = [
            ui.DisplayFeature(
              bounds: const Rect.fromLTWH(0, 390, 1000, 20),
              type: ui.DisplayFeatureType.fold,
              state: state,
            ),
          ];
          await tester.pumpAndSettle();
          final rect = tester.getRect(
            find.byKey(const ValueKey('main-page-header')),
          );
          expect(rect.top, top);
          if (top == 24) {
            original ??= rect;
            expect(rect, original);
          }
          expect(
            tester.getRect(find.byKey(const ValueKey('gallery-safe-window'))),
            const Rect.fromLTWH(0, 0, 1000, 800),
          );
          expect(tester.takeException(), isNull);
        }
      }
      c.showOverlay(GalleryOverlay.rename);
      await tester.pumpAndSettle();
      final inputRect = tester.getRect(find.byType(TextField));
      tester.view.displayFeatures = [
        ui.DisplayFeature(
          bounds: const Rect.fromLTWH(490, 0, 20, 800),
          type: ui.DisplayFeatureType.fold,
          state: ui.DisplayFeatureState.postureHalfOpened,
        ),
      ];
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(TextField)), inputRect);
    },
  );

  testWidgets(
    'live menus follow fixed detail buttons across resizing and scrolling',
    (tester) async {
      await mount(tester);
      c.navigate(GalleryPage.cards);
      await tester.pumpAndSettle();
      final card = c.savedCards.first;
      c.openCard(card);
      await tester.pumpAndSettle();
      final button = find.byTooltip('${card.name} 管理');
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(c.navigationStack.last.anchorId, 'detail-card-${card.id}');
      for (final size in const [
        Size(1000, 800),
        Size(280, 600),
        Size(600, 800),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        final menu = tester.getRect(
          find.byKey(const ValueKey('gallery-dropdown')),
        );
        final anchor = tester.getRect(button);
        expect(menu.right, closeTo(anchor.right, .1));
        expect(menu.top, closeTo(anchor.bottom + 6, .1));
        expect(tester.takeException(), isNull);
      }
      tester.view.physicalSize = const Size(280, 320);
      await tester.pumpAndSettle();
      final list = find.byType(CustomScrollView).first;
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)).first,
      );
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(c.overlay, GalleryOverlay.cardMenu);
      expect(find.byTooltip('${card.name} 管理').hitTestable(), findsNothing);
      final pinnedAnchor = tester.getRect(button);
      final pinnedMenu = tester.getRect(
        find.byKey(const ValueKey('gallery-dropdown')),
      );
      expect(pinnedMenu.top, closeTo(pinnedAnchor.bottom + 6, .1));
    },
  );

  testWidgets(
    'caption, keyboard and resizes preserve name drafts and reachable final actions',
    (tester) async {
      await mount(tester);
      c.showOverlay(GalleryOverlay.rename);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '窗口切换中的草稿');
      final input = tester.widget<TextField>(find.byType(TextField)).controller;
      for (final size in const [
        Size(280, 400),
        Size(600, 320),
        Size(840, 800),
        Size(390, 844),
      ]) {
        tester.view.physicalSize = size;
        for (final bottom in [0.0, 24.0, 48.0]) {
          for (final keyboard in [0.0, 180.0]) {
            tester.view.viewPadding = FakeViewPadding(top: 48, bottom: bottom);
            tester.view.padding = FakeViewPadding(
              top: 48,
              bottom: keyboard == 0 ? bottom : 0,
            );
            tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
            await tester.pumpAndSettle();
            expect(
              tester.widget<TextField>(find.byType(TextField)).controller,
              same(input),
            );
            expect(input!.text, '窗口切换中的草稿');
            await tester.ensureVisible(find.widgetWithText(FilledButton, '确认'));
            await tester.pumpAndSettle();
            final confirm = tester.getRect(
              find.widgetWithText(FilledButton, '确认'),
            );
            expect(
              confirm.bottom,
              lessThanOrEqualTo(
                size.height - (keyboard == 0 ? bottom : keyboard) + .1,
              ),
            );
            expect(confirm.top, greaterThanOrEqualTo(48));
            expect(tester.takeException(), isNull);
          }
        }
      }
    },
  );

  testWidgets(
    'short caption window with large text keeps primary actions and header controls reachable',
    (tester) async {
      await mount(tester, size: const Size(240, 320));
      tester.view.padding = const FakeViewPadding(top: 48, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 48, bottom: 24);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await tester.pumpAndSettle();
      final start = find.widgetWithText(TextButton, '开始读取');
      final navTop = tester
          .getTopLeft(find.byKey(const ValueKey('gallery-navigation')))
          .dy;
      // The floating bar covers the center of this unusually short viewport;
      // drag the visible content above it, as a user would.
      for (var step = 0; start.evaluate().isEmpty && step < 30; step++) {
        await tester.dragFrom(Offset(120, navTop - 12), const Offset(0, -100));
        await tester.pumpAndSettle();
      }
      await Scrollable.ensureVisible(tester.element(start), alignment: 0);
      await tester.pumpAndSettle();
      expect(tester.getBottomLeft(start).dy, lessThanOrEqualTo(navTop));
      expect(start.hitTestable(), findsOneWidget);
      final settings = find.byTooltip('设置');
      await Scrollable.ensureVisible(tester.element(settings), alignment: 1);
      await tester.pumpAndSettle();
      expect(settings.hitTestable(), findsOneWidget);
      await tester.tap(settings);
      await tester.pumpAndSettle();
      expect(c.page, GalleryPage.settings);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'wide single-column surfaces stay centered and reading stays alive on resize',
    (tester) async {
      await mount(tester, size: const Size(1200, 900));
      final header = tester.getRect(
        find.byKey(const ValueKey('main-page-header')),
      );
      expect(header.width, 720);
      expect(header.center.dx, 600);
      c.read();
      await tester.pump();
      tester.view.physicalSize = const Size(280, 400);
      await tester.pump(const Duration(milliseconds: 150));
      expect(c.readState, GalleryReadState.reading);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('home-read-illustration')))
            .height,
        96,
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(c.readState, GalleryReadState.success);
    },
  );

  final captureDir = Platform.environment['GALLERY_WINDOW_CAPTURE_DIR'];
  testWidgets('capture narrow, wide and hinge Gallery windows', (tester) async {
    final oldShadows = debugDisableShadows;
    debugDisableShadows = false;
    try {
      await tester.runAsync(() async {
        final sans = FontLoader('sans-serif')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                await File('C:/Windows/Fonts/msyh.ttc').readAsBytes(),
              ),
            ),
          );
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await Future.wait([sans.load(), icons.load()]);
        await Directory(captureDir!).create(recursive: true);
      });
      final boundary = GlobalKey();
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: GalleryApp(controller: c),
        ),
      );
      for (final dark in [false, true]) {
        c.update(() {
          c.themeMode = dark ? ThemeMode.dark : ThemeMode.light;
          c.monet = false;
        });
        for (final scenario in [
          'small-home',
          'small-home-action',
          'small-wallet',
          'large-text',
          'wide',
          'hinge',
          'horizontal-hinge',
          'menu',
          'sheet',
        ]) {
          tester.view.physicalSize = scenario == 'wide'
              ? const Size(1200, 900)
              : scenario.contains('hinge')
              ? const Size(1000, 800)
              : const Size(280, 400);
          tester.view.displayFeatures = scenario.contains('hinge')
              ? [
                  ui.DisplayFeature(
                    bounds: scenario == 'hinge'
                        ? const Rect.fromLTWH(300, 0, 20, 800)
                        : const Rect.fromLTWH(0, 250, 1000, 20),
                    type: ui.DisplayFeatureType.hinge,
                    state: ui.DisplayFeatureState.postureFlat,
                  ),
                ]
              : [];
          tester.view.padding = const FakeViewPadding(top: 48, bottom: 24);
          tester.view.viewPadding = const FakeViewPadding(top: 48, bottom: 24);
          tester.platformDispatcher.textScaleFactorTestValue =
              scenario == 'large-text' ? 2 : 1;
          c.navigate(
            scenario.startsWith('small-home')
                ? GalleryPage.home
                : GalleryPage.cards,
          );
          await tester.pumpAndSettle();
          if (scenario == 'small-home-action') {
            await Scrollable.ensureVisible(
              tester.element(find.widgetWithText(TextButton, '开始读取')),
              alignment: .15,
            );
            await tester.pumpAndSettle();
          }
          if (scenario == 'menu') {
            c.openCard(c.savedCards.first);
            await tester.pumpAndSettle();
            await tester.tap(find.byTooltip('${c.savedCards.first.name} 管理'));
          } else if (scenario == 'sheet') {
            c.showOverlay(GalleryOverlay.face);
          }
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: scenario);
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('$captureDir/${dark ? 'dark' : 'light'}-$scenario.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
          if (c.overlay != null) {
            c.back();
            await tester.pumpAndSettle();
          }
        }
      }
    } finally {
      debugDisableShadows = oldShadows;
    }
  }, skip: captureDir == null);
}
