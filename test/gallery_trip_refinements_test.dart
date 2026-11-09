import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';

void main() {
  late GalleryController controller;
  setUp(() {
    controller = GalleryController(
      GalleryData(
        jsonDecode(File('assets/gallery/fixtures.json').readAsStringSync())
            as GalleryRecord,
      ),
    );
    controller.hasRead = true;
    controller.monet = false;
    controller.navigate(GalleryPage.trips);
  });
  tearDown(() => controller.dispose());

  Future<void> mount(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 892);
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(GalleryApp(controller: controller));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'trip layout keeps dates, endpoint evidence and working details',
    (tester) async {
      final original = jsonEncode(controller.trips);
      await mount(tester);
      expect(find.text('本次开销'), findsNothing);
      expect(find.text('未记录换乘站'), findsNothing);
      expect(find.text('今天'), findsOneWidget);
      expect(find.text('昨天'), findsOneWidget);
      expect(find.text('未记录'), findsWidgets);
      final summary = tester.getRect(
        find.byKey(const ValueKey('trips-summary')),
      );
      expect(summary.height, lessThanOrEqualTo(80));
      final time = tester.getRect(find.text('08:07'));
      final station = tester.getRect(find.text('徐家汇').first);
      expect(time.bottom, lessThan(station.top));
      await tester.tap(find.text('陆家嘴'));
      await tester.pumpAndSettle();
      expect(controller.overlay, GalleryOverlay.trip);
      expect(find.text('未记录换乘站'), findsOneWidget);
      expect(find.text('0x18 交易 / 0x1E 过程'), findsOneWidget);
      expect(jsonEncode(controller.trips), original);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('trip summary and endpoints fit narrow windows and large fonts', (
    tester,
  ) async {
    await mount(tester);
    final original = jsonEncode(controller.trips);
    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      for (final width in [240.0, 320.0, 360.0, 412.0]) {
        for (final scale in [1.0, 1.5, 2.0]) {
          tester.view.physicalSize = Size(width, 1000);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          controller.update(() => controller.themeMode = theme);
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$theme $width $scale',
          );
          final summary = tester.getRect(
            find.byKey(const ValueKey('trips-summary')),
          );
          final title = tester.getRect(find.text(controller.current.name));
          expect(summary.contains(title.topLeft), isTrue);
          expect(
            summary.contains(title.bottomRight - const Offset(.1, .1)),
            isTrue,
          );
        }
      }
    }
    expect(jsonEncode(controller.trips), original);
  });
}
