import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';
import 'package:transit_card_analyzer/gallery/gallery_design.dart';
import 'package:transit_card_analyzer/gallery/gallery_feedback.dart';
import 'package:transit_card_analyzer/gallery/gallery_layout.dart';
import 'package:transit_card_analyzer/gallery/gallery_theme.dart';

void main() {
  final surface = find.byKey(const ValueKey('gallery-feedback'));
  late BuildContext pageContext;

  Future<void> mount(
    WidgetTester tester, {
    GalleryTokens? tokens,
    Size size = const Size(412, 892),
    bool reduced = false,
    bool accessible = false,
    bool mainPage = true,
    bool docked = false,
    double scale = 1,
    double keyboard = 0,
    bool cleanup = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    if (cleanup) addTearDown(tester.view.reset);
    final theme =
        tokens ??
        GalleryTokens(scheme: GalleryPalette.values.first.scheme(false));
    await tester.pumpWidget(
      MaterialApp(
        theme: theme.theme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 24),
            viewPadding: const EdgeInsets.only(top: 24, bottom: 24),
            viewInsets: EdgeInsets.only(bottom: keyboard),
            textScaler: TextScaler.linear(scale),
            accessibleNavigation: accessible,
            disableAnimations: reduced,
          ),
          child: GalleryFeedbackHost(
            mainPage: mainPage,
            docked: docked,
            child: child!,
          ),
        ),
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> show(
    WidgetTester tester,
    String message, {
    GalleryFeedbackType type = GalleryFeedbackType.success,
    String? title,
  }) async {
    GalleryFeedbackHost.show(pageContext, message, type: type, title: title);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'save feedback survives dialogs and navigation, clears on reset',
    (tester) async {
      final controller = GalleryController(
        GalleryData(
          jsonDecode(File('assets/gallery/fixtures.json').readAsStringSync())
              as GalleryRecord,
        ),
      );
      addTearDown(controller.dispose);
      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      controller.hasRead = true;
      await tester.pumpWidget(GalleryApp(controller: controller));
      await tester.pumpAndSettle();
      controller.showOverlay(GalleryOverlay.save);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '通勤卡');
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(surface, findsOneWidget);
      expect(find.text('已保存到卡包'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(tester.getSize(surface).width, lessThan(380));
      await tester.tap(find.byKey(const ValueKey('nav-trips')));
      await tester.pumpAndSettle();
      expect(controller.page, GalleryPage.trips);
      expect(surface, findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nav-cards')));
      await tester.pumpAndSettle();
      expect(controller.page, GalleryPage.cards);
      expect(surface, findsOneWidget);
      controller.reset();
      await tester.pumpAndSettle();
      expect(surface, findsNothing);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(surface, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'queue preserves current feedback, deduplicates, and prioritizes errors',
    (tester) async {
      await mount(tester, reduced: true);
      await show(tester, '已保存到卡包');
      for (var i = 0; i < 3; i++) {
        GalleryFeedbackHost.show(
          pageContext,
          '已保存到卡包',
          type: GalleryFeedbackType.success,
        );
        GalleryFeedbackHost.show(pageContext, '没有更多记录');
      }
      GalleryFeedbackHost.show(
        pageContext,
        '复制失败，请重试',
        type: GalleryFeedbackType.error,
        title: '操作失败',
      );
      await tester.pump();
      expect(find.text('已保存到卡包'), findsOneWidget);
      expect(surface, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2501));
      await tester.pump();
      expect(find.text('操作失败'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.text('没有更多记录'), findsNothing);
      await tester.pump(const Duration(milliseconds: 3001));
      await tester.pump();
      expect(find.text('没有更多记录'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2501));
      await tester.pump();
      expect(surface, findsNothing);
    },
  );

  testWidgets('visible feedback follows every palette and light/dark theme', (
    tester,
  ) async {
    var first = true;
    for (final palette in GalleryPalette.values) {
      for (final dark in [false, true]) {
        final tokens = GalleryTokens(scheme: palette.scheme(dark));
        await mount(
          tester,
          tokens: tokens,
          reduced: true,
          accessible: true,
          cleanup: first,
        );
        if (first) await show(tester, '卡片已保存');
        first = false;
        final decoration =
            tester.widget<DecoratedBox>(surface).decoration as BoxDecoration;
        expect(decoration.color, tokens.feedbackSurface);
        final text = tester.widget<Text>(find.text('卡片已保存'));
        expect(text.style!.color, tokens.text);
        expect(text.style!.fontWeight, FontWeight.w500);
        expect(
          _contrast(tokens.text, tokens.feedbackSurface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(tokens.muted, tokens.feedbackSurface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(tokens.onSuccessContainer, tokens.successContainer),
          greaterThanOrEqualTo(4.5),
        );
      }
    }
    final dynamic = GalleryTokens(
      scheme: ColorScheme.fromSeed(
        seedColor: Colors.lime,
        brightness: Brightness.dark,
      ),
      dynamic: true,
    );
    await mount(
      tester,
      tokens: dynamic,
      reduced: true,
      accessible: true,
      cleanup: false,
    );
    expect(
      (tester.widget<DecoratedBox>(surface).decoration as BoxDecoration).color,
      dynamic.feedbackSurface,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'long feedback adapts to small windows, large text, navigation and keyboard',
    (tester) async {
      const message = '卡片名称已更新，返回卡包后可查看完整的卡片名称与最近读取日期。';
      for (final docked in [false, true]) {
        await mount(
          tester,
          size: const Size(240, 540),
          scale: 2,
          docked: docked,
          reduced: true,
          cleanup: !docked,
        );
        if (!docked) await show(tester, message, title: '操作成功');
        final media = MediaQuery.of(pageContext);
        final navigation = GalleryNavigationLayout(media, docked: docked);
        expect(
          tester.getBottomRight(surface).dy,
          closeTo(540 - navigation.toastBottom, .01),
        );
        expect(tester.getSize(surface).width, lessThanOrEqualTo(208));
        expect(find.text(message), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await mount(
        tester,
        mainPage: false,
        size: const Size(600, 800),
        keyboard: 300,
        reduced: true,
        cleanup: false,
      );
      expect(tester.getBottomRight(surface).dy, closeTo(800 - 300 - 16, .01));
      expect(tester.getSize(surface).width, lessThanOrEqualTo(560));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'feedback announces status and extends its duration for accessibility',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await mount(tester, accessible: true, reduced: true);
      await show(
        tester,
        '复制失败，请重试',
        type: GalleryFeedbackType.error,
        title: '操作失败',
      );
      expect(find.bySemanticsLabel('操作失败，复制失败，请重试'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(surface, findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
      await tester.pump();
      expect(surface, findsNothing);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
}

double _contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
}
