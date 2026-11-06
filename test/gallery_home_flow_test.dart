import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';

void main() {
  late GalleryController c;
  setUp(() {
    c = GalleryController(
      GalleryData(
        jsonDecode(File('assets/gallery/fixtures.json').readAsStringSync())
            as GalleryRecord,
      ),
    );
    c.monet = false;
    c.themeMode = ThemeMode.light;
  });
  tearDown(() => c.dispose());

  Future<void> mount(WidgetTester tester, {bool reduced = false}) async {
    tester.view.physicalSize = const Size(360, 892);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: reduced);
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(GalleryApp(controller: c));
    await tester.pumpAndSettle();
  }

  double cardOffset(WidgetTester tester) => tester
      .widget<Transform>(find.byKey(const ValueKey('home-read-card-position')))
      .transform
      .getTranslation()
      .x;

  testWidgets('home reveals the reading step only after starting', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('贴卡，了解你的每一次出行'), findsOneWidget);
    expect(find.textContaining('支持交通联合'), findsOneWidget);
    expect(find.text('开始读取'), findsOneWidget);
    expect(find.text('把交通卡贴近手机背面'), findsNothing);
    expect(find.textContaining('读取中'), findsNothing);
    expect(find.text('内置卡片已就绪'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    final group = find.byKey(const ValueKey('main-action-group'));
    expect(
      find.descendant(of: group, matching: find.byType(IconButton)),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: group, matching: find.byType(VerticalDivider)),
      findsOneWidget,
    );
    for (final button in tester.widgetList<IconButton>(
      find.descendant(of: group, matching: find.byType(IconButton)),
    )) {
      for (final state in [
        WidgetState.hovered,
        WidgetState.pressed,
        WidgetState.focused,
      ]) {
        final shape =
            button.style!.shape!.resolve({state})! as RoundedRectangleBorder;
        expect(shape.borderRadius, BorderRadius.circular(14));
      }
    }

    final prompt = tester.element(
      find.byKey(const ValueKey('home-read-prompt')),
    );
    await tester.tap(find.text('开始读取'));
    await tester.pump();
    expect(c.readState, GalleryReadState.reading);
    final start = cardOffset(tester);
    await tester.pump(const Duration(milliseconds: 200));
    final early = cardOffset(tester);
    final captions = tester.widgetList<FadeTransition>(
      find.descendant(
        of: find.byKey(const ValueKey('home-read-prompt')),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(captions.where((caption) => caption.opacity.value > .01).length, 1);
    await tester.pump(const Duration(milliseconds: 400));
    final middle = cardOffset(tester);
    expect(start, greaterThan(early));
    expect(early, greaterThan(middle));
    // The contact motion advances faster than a constant-speed translation.
    expect(early, lessThan(start + (middle - start) / 3 - 1));
    expect(
      tester.element(find.byKey(const ValueKey('home-read-prompt'))),
      same(prompt),
    );
    expect(find.byKey(const ValueKey('home-read-ripples')), findsNothing);
    final progress = find.byKey(const ValueKey('home-read-progress'));
    expect(progress, findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(progress).value, isNull);
    expect(
      tester.getTopLeft(progress).dy,
      greaterThan(
        tester
            .getBottomLeft(find.byKey(const ValueKey('home-read-illustration')))
            .dy,
      ),
    );
    expect(find.text('贴卡，了解你的每一次出行'), findsNothing);
    expect(find.text('把交通卡贴近手机背面'), findsOneWidget);
    expect(find.textContaining('正在读取余额与行程'), findsOneWidget);
    expect(find.text('开始读取'), findsNothing);
    expect(find.text('正在读取…'), findsNothing);
    expect(find.text('模拟数据'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    expect(c.hasRead, isTrue);
    expect(find.byKey(const ValueKey('home-read-prompt')), findsNothing);
    expect(find.text('保存卡片'), findsOneWidget);
    tester.view.physicalSize = const Size(412, 892);
    await tester.pumpAndSettle();
    final face = tester.getRect(
      find.byKey(const ValueKey('card-face-shanghai')),
    );
    final tripPanel = tester.getRect(
      find
          .ancestor(of: find.text('最近一次行程'), matching: find.byType(Material))
          .first,
    );
    expect(face.left, tripPanel.left);
    expect(face.right, tripPanel.right);
    expect(face.width, 380);
    expect(face.height, lessThan(240));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion keeps a static contact pose and supports retry', (
    tester,
  ) async {
    await mount(tester, reduced: true);
    c.read(fail: true);
    await tester.pump();
    expect(find.text('贴卡，了解你的每一次出行'), findsNothing);
    expect(find.text('把交通卡贴近手机背面'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-read-ripples')), findsNothing);
    final offset = cardOffset(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(cardOffset(tester), offset);
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();
    expect(find.text('未能读到卡片'), findsOneWidget);
    expect(find.text('重新读取'), findsOneWidget);
    await tester.tap(find.text('重新读取'));
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    expect(c.hasRead, isTrue);
    c.read(fail: true);
    await tester.pump();
    expect(find.text('保存卡片'), findsNothing);
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    expect(c.hasRead, isTrue);
    expect(find.text('读取失败，保留上次结果'), findsOneWidget);
    expect(find.text('重新读取'), findsOneWidget);
  });

  testWidgets(
    'main headers keep settings mounted and animate only extra actions',
    (tester) async {
      await mount(tester);
      final settings = find.byTooltip('设置');
      final settingsElement = tester.element(settings);
      final settingsRect = tester.getRect(settings);
      final header = find.byKey(const ValueKey('main-page-header'));
      final headerHeight = tester.getSize(header).height;
      final groupElement = tester.element(
        find.byKey(const ValueKey('main-action-group')),
      );
      for (final page in [
        GalleryPage.trips,
        GalleryPage.expert,
        GalleryPage.cards,
        GalleryPage.home,
      ]) {
        c.navigate(page);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 70));
        expect(tester.element(settings), same(settingsElement));
        expect(tester.getRect(settings), settingsRect);
        expect(tester.getSize(header).height, headerHeight);
        expect(
          tester.element(find.byKey(const ValueKey('main-action-group'))),
          same(groupElement),
        );
        if (page == GalleryPage.cards || page == GalleryPage.home) {
          final fade = tester.widget<FadeTransition>(
            find
                .ancestor(
                  of: find.byKey(ValueKey('header-extra-${page.name}')),
                  matching: find.byType(FadeTransition),
                )
                .first,
          );
          expect(fade.opacity.value, inExclusiveRange(0, 1));
        }
        await tester.pumpAndSettle();
        expect(find.textContaining('已保存 3 张'), findsNothing);
        expect(find.text('读取卡片后查看最近行程'), findsNothing);
        expect(tester.takeException(), isNull);
      }
      for (final scale in [1.0, 1.5, 2.0]) {
        tester.view.physicalSize = const Size(320, 1000);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        double? height;
        for (final page in GalleryController.visibleMainPages) {
          c.navigate(page);
          await tester.pumpAndSettle();
          height ??= tester.getSize(header).height;
          expect(tester.getSize(header).height, height);
          expect(tester.takeException(), isNull);
        }
      }
      c.navigate(GalleryPage.home);
      await tester.pumpAndSettle();
      c.navigate(GalleryPage.cards);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      c.navigate(GalleryPage.trips);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      c.navigate(GalleryPage.home);
      await tester.pumpAndSettle();
      expect(find.byTooltip('扫码'), findsOneWidget);
      expect(find.byTooltip('导出卡片记录'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'trip overview shows the current card name including renamed cards',
    (tester) async {
      c.hasRead = true;
      c.current.name = '通勤交通卡';
      c.navigate(GalleryPage.trips);
      await mount(tester);
      expect(find.text('通勤交通卡'), findsOneWidget);
      expect(find.textContaining('交易 '), findsNothing);
      final header = tester.getRect(
        find.byKey(const ValueKey('main-page-header')),
      );
      expect(
        tester.getTopLeft(find.text('通勤交通卡')).dy,
        greaterThan(header.bottom),
      );
      c.update(() => c.current.name = '重新命名的交通卡');
      await tester.pumpAndSettle();
      expect(find.text('重新命名的交通卡'), findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, -240));
      await tester.pumpAndSettle();
      final capsule = find.byKey(const ValueKey('trips-summary-capsule'));
      expect(
        find.descendant(of: capsule, matching: find.text('重新命名的交通卡')),
        findsOneWidget,
      );
      expect(tester.getTopLeft(capsule).dy, closeTo(header.bottom, .1));
      expect(find.textContaining('交易 '), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('home steps fit narrow screens and large text in both themes', (
    tester,
  ) async {
    await mount(tester, reduced: true);
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final width in [320.0, 360.0, 412.0]) {
        for (final scale in [1.0, 1.5, 2.0]) {
          tester.view.physicalSize = Size(width, 1000);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          c.update(() {
            c.themeMode = mode;
            c.hasRead = false;
            c.readState = GalleryReadState.unread;
          });
          await tester.pumpAndSettle();
          expect(find.text('开始读取'), findsOneWidget);
          c.update(() => c.readState = GalleryReadState.reading);
          await tester.pumpAndSettle();
          expect(find.text('把交通卡贴近手机背面'), findsOneWidget);
          expect(
            tester.takeException(),
            isNull,
            reason: '$mode / $width / $scale',
          );
        }
      }
    }
  });
}
