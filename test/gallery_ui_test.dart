import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
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
    expect(find.byType(CheckedPopupMenuItem<String>), findsNWidgets(4));
    await tester.tap(find.text('0x1E 过程'));
    await tester.pumpAndSettle();
    expect(c.source, '0x1E 过程');
    await tester.tap(find.text('全部方式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('公共汽电车'));
    await tester.pumpAndSettle();
    expect(c.mode, '公共汽电车');
    expect(find.text('当前筛选下没有记录'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

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
