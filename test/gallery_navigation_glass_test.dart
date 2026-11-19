import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';
import 'package:transit_card_analyzer/gallery/gallery_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GalleryController controller;

  setUp(() {
    controller = GalleryController(
      GalleryData(
        jsonDecode(File('assets/gallery/fixtures.json').readAsStringSync())
            as GalleryRecord,
      ),
    );
  });

  tearDown(() => controller.dispose());

  Future<void> pumpGallery(
    WidgetTester tester, {
    required bool docked,
  }) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    controller.update(() {
      controller.monet = false;
      controller.docked = docked;
    });
    await tester.pumpWidget(GalleryApp(controller: controller));
    await tester.pumpAndSettle();
  }

  for (final docked in [false, true]) {
    testWidgets('${docked ? '下沉' : '悬浮'}底栏切换页面振动一次，重复点按不振动', (tester) async {
      final haptics = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpGallery(tester, docked: docked);
      expect(controller.mainPage, GalleryPage.home);

      await tester.tap(find.byKey(const ValueKey('nav-trips')));
      await tester.pumpAndSettle();
      expect(controller.mainPage, GalleryPage.trips);
      expect(haptics, ['HapticFeedbackType.selectionClick']);

      // The current page is inert: no haptic, no navigation event.
      await tester.tap(find.byKey(const ValueKey('nav-trips')));
      await tester.pumpAndSettle();
      expect(controller.mainPage, GalleryPage.trips);
      expect(haptics, hasLength(1));

      await tester.tap(find.byKey(const ValueKey('nav-cards')));
      await tester.pumpAndSettle();
      expect(controller.mainPage, GalleryPage.cards);
      expect(haptics, hasLength(2));
    });
  }

  testWidgets('底栏保持 design.md 的材质', (tester) async {
    await pumpGallery(tester, docked: false);
    final tokens = Theme.of(
      tester.element(find.byKey(const ValueKey('gallery-navigation'))),
    ).extension<GalleryTokens>()!;
    final floating = tester.widget<Container>(
      find.byKey(const ValueKey('nav-bar')),
    );
    expect(
      (floating.decoration! as BoxDecoration).color,
      tokens.surface.withValues(alpha: .78),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('gallery-navigation')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is BackdropFilter &&
              widget.filter == ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        ),
      ),
      findsOneWidget,
    );

    await pumpGallery(tester, docked: true);
    final docked = tester.widget<Container>(
      find.byKey(const ValueKey('nav-bar')),
    );
    expect(
      (docked.decoration! as BoxDecoration).color,
      tokens.dockedNavigationSurface,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('gallery-navigation')),
        matching: find.byType(BackdropFilter),
      ),
      findsNothing,
    );
  });
}