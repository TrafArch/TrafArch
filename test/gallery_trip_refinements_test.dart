import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/trips/journey_transport_icon.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';
import 'package:transit_card_analyzer/gallery/gallery_theme.dart';

import 'support/gallery_scroll.dart';

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

  testWidgets('trip reference typography keeps arrival regular', (
    tester,
  ) async {
    await mount(tester);
    for (final value in [
      '轨道交通',
      '1 号线',
      controller.trips.first['amount'] as String,
      controller.current.name,
    ]) {
      expect(find.text(value), findsWidgets);
      for (final text in tester.widgetList<Text>(find.text(value))) {
        expect(text.style!.fontWeight, FontWeight.w400, reason: value);
      }
    }
    expect(
      tester.widget<Text>(find.text('08:07')).style!.fontWeight,
      FontWeight.w600,
    );
    expect(
      tester.widget<Text>(find.text('徐家汇').first).style!.fontWeight,
      FontWeight.w600,
    );
    for (final (value, size, lineHeight, weight) in [
      ('今天', 26.0, 32.0, FontWeight.w600),
      ('08:07', 22.0, 28.0, FontWeight.w600),
      ('08:42', 22.0, 28.0, FontWeight.w400),
      ('未记录', 22.0, 28.0, FontWeight.w400),
      ('徐家汇', 18.0, 26.0, FontWeight.w600),
      ('轨道交通', 16.0, 22.0, FontWeight.w400),
      ('上海', 14.0, 20.0, FontWeight.w400),
      ('−¥4.00', 18.0, 24.0, FontWeight.w400),
      ('1 号线', 13.0, 18.0, FontWeight.w400),
    ]) {
      for (final text in tester.widgetList<Text>(find.text(value))) {
        expect(text.style!.fontSize, size, reason: value);
        expect(
          text.style!.height! * size,
          closeTo(lineHeight, .01),
          reason: value,
        );
        expect(text.style!.fontWeight, weight, reason: value);
      }
    }
    await tester.tap(find.text('陆家嘴'));
    await tester.pumpAndSettle();
    for (final text in tester.widgetList<Text>(find.text('08:42'))) {
      expect(text.style!.fontSize, 22);
      expect(text.style!.fontWeight, FontWeight.w400);
    }
    controller.back();
    await tester.pumpAndSettle();
    controller.openCard(controller.current);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.text('今天')).style!.fontSize, 26);
    expect(
      tester.widget<Text>(find.text('08:42')).style!.fontWeight,
      FontWeight.w400,
    );
  });

  testWidgets('logo follows spending city and preserves the existing badge', (
    tester,
  ) async {
    final sample = {...controller.trips.first, 'city': '北京市', 'foreign': true};
    controller.trips
      ..clear()
      ..add(sample);
    final original = jsonEncode(controller.trips);
    await mount(tester);
    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      controller.update(() => controller.themeMode = theme);
      await tester.pumpAndSettle();
      final logo = find.descendant(
        of: find.byType(JourneyTransportIcon),
        matching: find.byType(SvgPicture),
      );
      expect(logo, findsOneWidget);
      final picture = tester.widget<SvgPicture>(logo);
      expect(
        (picture.bytesLoader as SvgAssetLoader).assetName,
        'assets/metro/metro_logo_beijing.svg',
      );
      expect(picture.colorFilter, isNull);
      expect(tester.getSize(logo), const Size(23, 23));
      final badge = find.ancestor(
        of: logo,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.constraints?.maxWidth == 34 &&
              w.constraints?.maxHeight == 34,
        ),
      );
      expect(badge, findsOneWidget);
      final decoration =
          tester.widget<Container>(badge).decoration! as BoxDecoration;
      expect(decoration.color, Colors.transparent);
      expect(decoration.borderRadius, BorderRadius.circular(11));
      expect(find.text('异地用卡'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    expect(jsonEncode(controller.trips), original);
    // The card issuer remains Shanghai while the ticket uses Beijing's logo.
    expect(controller.current.city, '上海');
  });

  testWidgets(
    'unknown, multi-city and cross-city rail keep the themed fallback and bus stays unchanged',
    (tester) async {
      final base = controller.trips.first;
      controller.trips
        ..clear()
        ..add({...base});
      await mount(tester);
      for (final (city, kind, crossCity, icon) in [
        ('未知城市', 'rail', false, Icons.train_outlined),
        ('上海 / 北京', 'rail', false, Icons.train_outlined),
        ('上海', 'rail', true, Icons.train_outlined),
        ('上海', 'bus', false, Icons.directions_bus_outlined),
      ]) {
        controller.update(
          () => controller.trips[0] = {
            ...base,
            'city': city,
            'kind': kind,
            'isCrossCity': crossCity,
          },
        );
        await tester.pumpAndSettle();
        final transport = find.byType(JourneyTransportIcon);
        expect(
          find.descendant(of: transport, matching: find.byType(SvgPicture)),
          findsNothing,
        );
        final fallback = find.descendant(
          of: transport,
          matching: find.byIcon(icon),
        );
        expect(fallback, findsOneWidget);
        final tokens = Theme.of(tester.element(fallback))
            .extension<GalleryTokens>()!;
        final widget = tester.widget<Icon>(fallback);
        expect(widget.size, 23);
        expect(
          widget.color,
          kind == 'rail' ? tokens.text : tokens.onSecondaryContainer,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('one-way bus ticket shows a single boarding row without arrow', (
    tester,
  ) async {
    await mount(tester);
    final row = find.byKey(const ValueKey('trip-one-way'));
    expect(row, findsOneWidget);
    expect(
      find.descendant(
        of: row,
        matching: find.byKey(const ValueKey('trip-direction-arrow')),
      ),
      findsNothing,
    );
    for (final value in ['07:52', '49 路', '汉口路江西中路']) {
      expect(find.descendant(of: row, matching: find.text(value)), findsOneWidget);
    }
    final time = tester.widget<Text>(
      find.descendant(of: row, matching: find.text('07:52')),
    );
    // 单向公交仅记录上车，时间比常规小两号（22 → 16）且不加粗。
    expect(time.style!.fontSize, 16);
    expect(time.style!.fontWeight, FontWeight.w400);
    expect(find.text('公交'), findsWidgets);
    expect(find.text('上海'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'summary remains a single surface through scrolling, reversal and restoration',
    (tester) async {
      await mount(tester);
      final summary = find.byKey(const ValueKey('trips-summary'));
      final element = tester.element(summary);
      final initial = tester.getRect(summary);
      final scroll = tester.state<ScrollableState>(galleryVerticalScroll());
      for (final offset in [4.0, 10.0, 18.0, 30.0, 80.0, 18.0, 8.0, 0.0]) {
        scroll.position.jumpTo(offset);
        await tester.pump();
        expect(tester.element(summary), same(element));
        expect(find.text(controller.current.name), findsOneWidget);
        final rect = tester.getRect(summary);
        expect(rect.top, closeTo(initial.top, .1));
        expect(rect.height, lessThanOrEqualTo(initial.height));
        final amount = find.descendant(
          of: summary,
          matching: find.text(controller.current.balance(false)),
        );
        final text = tester.getRect(amount);
        expect(rect.right - text.right, inInclusiveRange(15.9, 18.1));
        if (offset >= 30) expect(text.right, closeTo(rect.right - 18, .1));
        expect(tester.takeException(), isNull);
      }
      scroll.position.jumpTo(100);
      await tester.pump();
      controller.navigate(GalleryPage.cards);
      await tester.pumpAndSettle();
      controller.navigate(GalleryPage.trips);
      await tester.pumpAndSettle();
      expect(tester.getRect(summary).height, lessThan(initial.height));
      expect(find.text(controller.current.name), findsOneWidget);
    },
  );

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
      // 线路徽章移到时间右侧，不再与站点同组。
      final badge = tester.getRect(find.text('1 号线').first);
      expect(badge.left, greaterThan(time.right));
      expect(badge.center.dy, closeTo(time.center.dy, 1.5));
      expect(badge.bottom, lessThanOrEqualTo(station.top));
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
          final departure = find.text('08:07');
          final timeStyle = tester.widget<Text>(departure).style!;
          // A complete time must remain one line at large system font scales.
          expect(
            tester.getSize(departure).height,
            lessThanOrEqualTo(
              scale * timeStyle.fontSize! * timeStyle.height! + 1,
            ),
          );
        }
      }
    }
    expect(jsonEncode(controller.trips), original);
  });

  testWidgets(
    'direction arrow stays centered between unequal endpoint heights',
    (tester) async {
      controller.trips.first['exitStation'] = '很长的终点站名称需要自然换行';
      controller.trips.first['entryStation'] = '徐家汇';
      await mount(tester);
      for (final width in [240.0, 320.0, 412.0]) {
        for (final scale in [1.0, 1.5, 2.0]) {
          tester.view.physicalSize = Size(width, 1800);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          await tester.pumpAndSettle();
          final endpoints = find.byKey(const ValueKey('trip-endpoints')).first;
          final arrow = find.descendant(
            of: endpoints,
            matching: find.byKey(const ValueKey('trip-direction-arrow')),
          );
          final block = tester.getRect(endpoints);
          final rect = tester.getRect(arrow);
          expect(rect.center.dx, closeTo(block.center.dx, .1));
          expect(rect.center.dy, closeTo(block.center.dy, .1));
          expect(tester.takeException(), isNull, reason: '$width $scale');
        }
      }
    },
  );
}
