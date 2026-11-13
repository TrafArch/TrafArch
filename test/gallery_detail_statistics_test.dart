import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';

import 'support/gallery_scroll.dart';

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
    c.openCard(c.current);
  });
  tearDown(() => c.dispose());

  Future<void> mount(
    WidgetTester tester, {
    double width = 412,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(GalleryApp(controller: c));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'card contracts continuously and keeps the selector and all capsule fields',
    (tester) async {
      final sample = c.trips.first;
      c.trips.addAll(
        List.generate(30, (index) => {...sample, 'entryStation': '站点 $index'}),
      );
      await mount(tester);
      final face = find.byKey(const ValueKey('card-face-shanghai'));
      final tabs = find.byKey(const ValueKey('segments-detail-tabs-indicator'));
      final faceElement = tester.element(face);
      final tabsElement = tester.element(tabs);
      final expanded = tester.getRect(face);
      final scroll = tester.state<ScrollableState>(galleryVerticalScroll());
      var previousHeight = expanded.height;
      for (final offset in [20.0, 60.0, 120.0, 220.0, 360.0]) {
        scroll.position.jumpTo(offset);
        await tester.pump();
        final rect = tester.getRect(face);
        expect(rect.top, closeTo(expanded.top, .1));
        expect(rect.height, lessThanOrEqualTo(previousHeight));
        previousHeight = rect.height;
        expect(tester.element(face), same(faceElement));
        expect(tester.element(tabs), same(tabsElement));
        expect(find.text('最近交易').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      expect(tester.getSize(face).height, lessThan(80));
      final tail = find.byKey(const ValueKey('face-tail-shanghai'));
      final number = find.byKey(const ValueKey('face-number-shanghai'));
      expect(tester.getRect(face).contains(tester.getCenter(tail)), isTrue);
      expect(tester.getRect(face).contains(tester.getCenter(number)), isTrue);
      scroll.position.jumpTo(60);
      await tester.pump();
      expect(tester.getSize(face).height, greaterThan(previousHeight));
      expect(tester.element(face), same(faceElement));
    },
  );

  testWidgets(
    'statistics defaults to all history and date navigation survives tab switches',
    (tester) async {
      c.detailTab = 1;
      await mount(tester);
      expect(find.text('消费统计'), findsOneWidget);
      expect(find.text('本周消费'), findsNothing);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '全部'))
            .selected,
        isTrue,
      );
      final overview = find.byKey(const ValueKey('spending-overview'));
      expect(
        find.descendant(of: overview, matching: find.text('¥12.00')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: overview, matching: find.text('4 次')),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(ChoiceChip, '本月'));
      await tester.pumpAndSettle();
      expect(find.text('2026-10-01 ～ 2026-10-31'), findsOneWidget);
      await tester.tap(find.byTooltip('上一时段'));
      await tester.pumpAndSettle();
      expect(find.text('2026-09-01 ～ 2026-09-30'), findsOneWidget);
      c.update(() => c.detailTab = 2);
      await tester.pumpAndSettle();
      c.update(() => c.detailTab = 1);
      await tester.pumpAndSettle();
      expect(find.text('2026-09-01 ～ 2026-09-30'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'custom date picker cancels without changes and applies both inclusive dates',
    (tester) async {
      c.detailTab = 1;
      final original = jsonEncode(c.trips);
      await mount(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, '自定义'));
      await tester.pumpAndSettle();
      final picker = find.byType(DateRangePickerDialog);
      expect(picker, findsOneWidget);
      Navigator.of(tester.element(picker)).pop();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '全部'))
            .selected,
        isTrue,
      );
      await tester.tap(find.widgetWithText(ChoiceChip, '自定义'));
      await tester.pumpAndSettle();
      final labels = MaterialLocalizations.of(tester.element(picker));
      await tester.tap(find.byTooltip(labels.inputDateModeButtonLabel));
      await tester.pumpAndSettle();
      final inputs = find.descendant(
        of: picker,
        matching: find.byType(TextField),
      );
      expect(inputs, findsNWidgets(2));
      await tester.enterText(
        inputs.at(0),
        labels.formatCompactDate(DateTime(2026, 10, 26)),
      );
      await tester.enterText(
        inputs.at(1),
        labels.formatCompactDate(DateTime(2026, 10, 27)),
      );
      await tester.tap(find.text(labels.okButtonLabel));
      await tester.pumpAndSettle();
      expect(picker, findsNothing);
      expect(find.text('2026-10-26 ～ 2026-10-27'), findsOneWidget);
      final overview = find.byKey(const ValueKey('spending-overview'));
      expect(
        find.descendant(of: overview, matching: find.text('¥10.00')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: overview, matching: find.text('3 次')),
        findsOneWidget,
      );
      expect(jsonEncode(c.trips), original);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'raw actions sit beside their title and duplicate management buttons are removed',
    (tester) async {
      c.detailTab = 2;
      await mount(tester);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('detail-raw-header')),
        150,
        scrollable: galleryVerticalScroll(),
      );
      await tester.pumpAndSettle();
      final header = tester.getRect(
        find.byKey(const ValueKey('detail-raw-header')),
      );
      for (final label in ['复制原始数据', '原始数据反馈预览']) {
        expect(
          header.contains(tester.getCenter(find.byTooltip(label))),
          isTrue,
        );
      }
      for (final label in ['重命名', '更换卡面', '导出记录', '删除本卡']) {
        expect(find.text(label), findsNothing);
      }
      await tester.tap(find.byTooltip('原始数据反馈预览'));
      await tester.pumpAndSettle();
      expect(c.overlay, GalleryOverlay.rawFeedback);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'detail and statistics fit narrow windows and system font scaling',
    (tester) async {
      await mount(tester);
      for (final width in [240.0, 320.0, 412.0]) {
        for (final scale in [1.0, 2.0]) {
          tester.view.physicalSize = Size(width, 1000);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          for (final tab in [0, 1, 2]) {
            c.update(() => c.detailTab = tab);
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '$width $scale $tab',
            );
          }
        }
      }
    },
  );

  testWidgets(
    'custom image produces a colored capsule and replacing it refreshes the palette',
    (tester) async {
      Future<ui.Image> image(Color color) async {
        final recorder = ui.PictureRecorder();
        Canvas(
          recorder,
        ).drawRect(const Rect.fromLTWH(0, 0, 16, 16), Paint()..color = color);
        final picture = recorder.endRecording();
        final result = await picture.toImage(16, 16);
        picture.dispose();
        return result;
      }

      Future<void> setImage(Color color) async {
        await tester.runAsync(() async {
          final bitmap = await image(color);
          final data = (await bitmap.toByteData(
            format: ui.ImageByteFormat.png,
          ))!;
          bitmap.dispose();
          c.update(() => c.current.image = data.buffer.asUint8List());
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 250));
        });
        await tester.pumpAndSettle();
      }

      await mount(tester);
      await setImage(Colors.red);
      final scroll = tester.state<ScrollableState>(galleryVerticalScroll());
      scroll.position.jumpTo(350);
      await tester.pumpAndSettle();
      Color capsuleColor() =>
          (tester
                      .widget<Container>(
                        find.byKey(const ValueKey('card-face-shanghai')),
                      )
                      .decoration!
                  as BoxDecoration)
              .gradient!
              .colors
              .first;
      final red = capsuleColor();
      await setImage(Colors.green);
      expect(capsuleColor(), isNot(red));
      c.update(() => c.themeMode = ThemeMode.dark);
      await tester.pumpAndSettle();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
