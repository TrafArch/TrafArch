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
  });

  tearDown(() => controller.dispose());

  Future<void> pumpSheet(WidgetTester tester, Map<String, dynamic> trip) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    controller.hasRead = true;
    controller.navigate(GalleryPage.trips);
    await tester.pumpWidget(GalleryApp(controller: controller));
    await tester.pumpAndSettle();
    if (trip['kind'] == 'event') {
      controller.showOverlay(GalleryOverlay.trip, trip: trip);
      await tester.pumpAndSettle();
    } else {
      await tester.tap(find.text('陆家嘴'));
      await tester.pumpAndSettle();
    }
    expect(controller.overlay, GalleryOverlay.trip);
    expect(find.text('行程详情'), findsWidgets);
  }

  testWidgets('行程弹层显示单次交易后余额', (tester) async {
    await pumpSheet(tester, controller.trips.first);
    expect(find.text('交易后余额'), findsOneWidget);
    expect(find.text('¥86.50'), findsOneWidget);
  });

  testWidgets('进站事件不伪造交易后余额', (tester) async {
    final event = controller.trips.firstWhere((t) => t['kind'] == 'event');
    await pumpSheet(tester, event);
    expect(find.text('交易后余额'), findsNothing);
  });
}