import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/trips/journey_transport_icon.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';
import 'package:transit_card_analyzer/gallery/gallery_design.dart';
import 'package:transit_card_analyzer/gallery/gallery_rail_line_catalog.dart';
import 'package:transit_card_analyzer/gallery/gallery_theme.dart';

import 'support/gallery_scroll.dart';

void main() {
  late GalleryRailLineCatalog bundledRailLineCatalog;
  late GalleryController controller;
  setUpAll(() async {
    bundledRailLineCatalog = await GalleryRailLineCatalog.load(rootBundle);
  });
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

  Future<void> mount(
    WidgetTester tester, {
    GalleryRailLineCatalog? railLineCatalog,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 892);
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      GalleryApp(controller: controller, railLineCatalog: railLineCatalog),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('trip reference typography bolds stations and trims the clock', (
    tester,
  ) async {
    await mount(tester, railLineCatalog: GalleryRailLineCatalog.empty());
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
      FontWeight.w400,
    );
    expect(
      tester.widget<Text>(find.text('徐家汇').first).style!.fontWeight,
      FontWeight.w600,
    );
    for (final (value, size, lineHeight, weight) in [
      ('今天', 18.0, 26.0, FontWeight.w600),
      ('08:07', 14.0, 20.0, FontWeight.w400),
      ('08:42', 14.0, 20.0, FontWeight.w400),
      ('未记录', 14.0, 20.0, FontWeight.w400),
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
      expect(text.style!.fontSize, 14);
      expect(text.style!.fontWeight, FontWeight.w400);
    }
    controller.back();
    await tester.pumpAndSettle();
    controller.openCard(controller.current);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.text('今天')).style!.fontSize, 18);
    expect(
      tester.widget<Text>(find.text('08:42')).style!.fontWeight,
      FontWeight.w400,
    );
  });

  testWidgets('date group headings track the section role and large fonts', (
    tester,
  ) async {
    await mount(tester);
    final heading = find.byKey(const ValueKey('trip-date-今天'));
    expect(heading, findsOneWidget);
    final label = find.descendant(of: heading, matching: find.text('今天'));
    final style = tester.widget<Text>(label).style!;
    expect(style.fontSize, GalleryTypography.section.fontSize);
    expect(style.height, 26 / 18);
    expect(style.fontWeight, FontWeight.w600);
    for (final scale in [1.5, 2.0]) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$scale');
      final box = tester.getRect(heading);
      final text = tester.getRect(label);
      // 标题在自身留白内完整绘制，未被裁切。
      expect(box.contains(text.topLeft), isTrue, reason: '$scale');
      expect(
        box.contains(text.bottomRight - const Offset(.1, .1)),
        isTrue,
        reason: '$scale',
      );
      expect(text.height, greaterThanOrEqualTo(18 * scale));
    }
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    controller.openCard(controller.current);
    await tester.pumpAndSettle();
    for (final text in tester.widgetList<Text>(find.text('今天'))) {
      expect(text.style!.fontSize, GalleryJourneyTypography.date.fontSize);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('trip rows drop seconds from recorded clock times', (
    tester,
  ) async {
    final sample = {
      ...controller.trips.first,
      'entryTime': '08:07:45',
      'time': '08:42:10',
    };
    controller.trips
      ..clear()
      ..add(sample);
    await mount(tester);
    expect(find.text('08:07'), findsWidgets);
    expect(find.text('08:42'), findsWidgets);
    expect(find.text('08:07:45'), findsNothing);
    expect(find.text('08:42:10'), findsNothing);
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
    'rail endpoints use local SVG art and fall back to the pinned line colour',
    (tester) async {
      final base = controller.trips.first;
      controller.trips
        ..clear()
        ..add({
          ...base,
          'kind': 'rail',
          'city': '福州',
          'isCrossCity': false,
          'entryLine': '4号线',
          'exitLine': '滨海快线',
          'entryLineCity': {'system': 'tu', 'code': '3910', 'name': '福州'},
          'exitLineCity': {'system': 'tu', 'code': '3910', 'name': '福州'},
        });
      await mount(tester, railLineCatalog: bundledRailLineCatalog);

      for (final (key, asset) in [
        ('trip-entry-line-badge', 'assets/Line_Icon/3910/3910_Line_4.svg'),
        ('trip-exit-line-badge', 'assets/Line_Icon/3910/3910_Line_F1.svg'),
      ]) {
        final badge = find.byKey(ValueKey(key));
        final picture = find.descendant(
          of: badge,
          matching: find.byType(SvgPicture),
        );
        for (
          var attempt = 0;
          attempt < 20 && picture.evaluate().isEmpty;
          attempt++
        ) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(picture, findsOneWidget);
        expect(
          (tester.widget<SvgPicture>(picture).bytesLoader as SvgAssetLoader)
              .assetName,
          asset,
        );
        final size = tester.getSize(picture);
        expect(size.height, closeTo(24, .1));
        expect(size.width / size.height, closeTo(157.6 / 94.2, .01));
      }

      controller.update(
        () => controller.trips[0] = {
          ...controller.trips[0],
          'city': '上海',
          'entryLine': '19号线',
          'exitLine': '19号线',
          'entryLineCity': {'system': 'tu', 'code': '2900', 'name': '上海'},
          'exitLineCity': {'system': 'tu', 'code': '2900', 'name': '上海'},
        },
      );
      await tester.pumpAndSettle();
      final colour = const Color(0xfff5ab78);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              (widget.decoration as BoxDecoration).color == colour,
        ),
        findsNWidgets(2),
      );
      for (final text in tester.widgetList<Text>(find.text('19号线'))) {
        expect(text.style!.color, Colors.black);
      }

      controller.update(
        () => controller.trips[0] = {
          ...controller.trips[0],
          'city': '福州',
          'entryLine': '4号线',
          'exitLine': '滨海快线',
          'entryLineCity': {'system': 'tu', 'code': '3910', 'name': '福州'},
          'exitLineCity': {'system': 'tu', 'code': '3910', 'name': '福州'},
        },
      );
      tester.view.physicalSize = const Size(240, 1000);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('trip-entry-line-badge')),
          matching: find.byType(SvgPicture),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('trip-exit-line-badge')),
          matching: find.byType(SvgPicture),
        ),
        findsOneWidget,
      );

      tester.view.physicalSize = const Size(412, 892);
      tester.platformDispatcher.textScaleFactorTestValue = 1;
      controller.update(
        () => controller.trips[0] = {
          ...controller.trips[0],
          'city': '北京',
          'entryLine': '18号线',
          'exitLine': '大兴机场线',
          'entryLineCity': {'system': 'tu', 'code': '1000', 'name': '北京'},
          'exitLineCity': {'system': 'tu', 'code': '1000', 'name': '北京'},
        },
      );
      await tester.pumpAndSettle();
      for (final (key, asset) in [
        ('trip-entry-line-badge', 'assets/Line_Icon/1000/1000_Line_12.svg'),
        ('trip-exit-line-badge', 'assets/Line_Icon/1000/1000_Line_58.svg'),
      ]) {
        final picture = find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(SvgPicture),
        );
        expect(picture, findsOneWidget);
        expect(
          (tester.widget<SvgPicture>(picture).bytesLoader as SvgAssetLoader)
              .assetName,
          asset,
        );
      }

      controller.update(
        () => controller.trips[0] = {
          ...controller.trips[0],
          'city': '厦门',
          'entryLine': '1号线',
          'exitLine': '3号线',
          'entryLineCity': {'system': 'tu', 'code': '3930', 'name': '厦门'},
          'exitLineCity': {'system': 'tu', 'code': '3930', 'name': '厦门'},
        },
      );
      await tester.pumpAndSettle();
      final xiamenOne = find.descendant(
        of: find.byKey(const ValueKey('trip-entry-line-badge')),
        matching: find.byType(SvgPicture),
      );
      final xiamenThree = find.descendant(
        of: find.byKey(const ValueKey('trip-exit-line-badge')),
        matching: find.byType(SvgPicture),
      );
      expect(xiamenOne, findsOneWidget);
      expect(xiamenThree, findsOneWidget);
      final oneSize = tester.getSize(xiamenOne);
      final threeSize = tester.getSize(xiamenThree);
      expect(oneSize.height, closeTo(24, .1));
      expect(threeSize.height, closeTo(24, .1));
      expect(oneSize.width / threeSize.width, greaterThan(.97));
    },
  );

  testWidgets('Shanghai TU and CU endpoints use bundled SVGs in dark mode', (
    tester,
  ) async {
    controller.themeMode = ThemeMode.dark;
    final base = controller.trips.first;
    controller.trips
      ..clear()
      ..add({
        ...base,
        'city': '上海',
        'entryLine': '1 号线',
        'exitLine': '机场联络线',
        'entryLineCity': {'system': 'tu', 'code': '2900'},
        'exitLineCity': {'system': 'cu', 'code': '2000'},
      });
    await mount(tester, railLineCatalog: bundledRailLineCatalog);

    for (final (endpoint, suffix, aspectRatio) in [
      ('entry', '01_black', 132.4 / 59.6),
      ('exit', '51', 43.32 / 18.19),
    ]) {
      final picture = find.descendant(
        of: find.byKey(ValueKey('trip-$endpoint-line-badge')),
        matching: find.byType(SvgPicture),
      );
      expect(picture, findsOneWidget);
      final svg = tester.widget<SvgPicture>(picture);
      expect(
        (svg.bytesLoader as SvgAssetLoader).assetName,
        'assets/Line_Icon/2900/2900_Line_$suffix.svg',
      );
      expect(svg.colorFilter, isNull);
      final size = tester.getSize(picture);
      expect(size.height, closeTo(24, .1));
      expect(size.width, closeTo(24 * aspectRatio, .1));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('rail line SVG variants follow the active app brightness', (
    tester,
  ) async {
    final base = controller.trips.first;
    controller.trips
      ..clear()
      ..add({
        ...base,
        'city': '苏州 / 上海',
        'isCrossCity': true,
        'entryLine': '11号线',
        'exitLine': '11号线',
        'entryLineCity': {'system': 'tu', 'code': '3050'},
        'exitLineCity': {'system': 'tu', 'code': '2900'},
      });
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await mount(tester, railLineCatalog: bundledRailLineCatalog);

    for (final (mode, systemBrightness, suffix) in [
      (ThemeMode.light, Brightness.dark, ''),
      (ThemeMode.dark, Brightness.light, '_black'),
      (ThemeMode.system, Brightness.dark, '_black'),
      (ThemeMode.system, Brightness.light, ''),
    ]) {
      tester.platformDispatcher.platformBrightnessTestValue = systemBrightness;
      if (controller.themeMode != mode) {
        controller.update(() => controller.themeMode = mode);
      }
      await tester.pumpAndSettle();

      for (final (endpoint, file, aspectRatio) in [
        ('entry', '3050/3050_Line_11$suffix.svg', 263.58 / 115),
        ('exit', '2900/2900_Line_11$suffix.svg', 140.8 / 59.6),
      ]) {
        final picture = find.descendant(
          of: find.byKey(ValueKey('trip-$endpoint-line-badge')),
          matching: find.byType(SvgPicture),
        );
        expect(picture, findsOneWidget);
        final svg = tester.widget<SvgPicture>(picture);
        expect(
          (svg.bytesLoader as SvgAssetLoader).assetName,
          'assets/Line_Icon/$file',
        );
        expect(svg.colorFilter, isNull);
        final size = tester.getSize(picture);
        expect(size.height, closeTo(24, .1));
        expect(size.width, closeTo(24 * aspectRatio, .1));
      }
      expect(tester.takeException(), isNull);
    }
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

  testWidgets('one-way bus keeps money in its half-modal, not the ticket', (
    tester,
  ) async {
    final index = controller.trips.indexWhere(
      (record) => record['entryLine'] == '49 路',
    );
    expect(index, greaterThanOrEqualTo(0));
    controller.trips = [
      for (final (i, record) in controller.trips.indexed)
        if (i == index)
          {...record, 'amount': '¥2.47', 'balanceAfter': '¥61.39'}
        else
          record,
    ];
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
      expect(
        find.descendant(of: row, matching: find.text(value)),
        findsOneWidget,
      );
    }
    final time = tester.widget<Text>(
      find.descendant(of: row, matching: find.text('07:52')),
    );
    // 单向公交仅记录上车，时间与常规时间同为 14dp 且不加粗。
    expect(time.style!.fontSize, 14);
    expect(time.style!.fontWeight, FontWeight.w400);
    expect(find.text('公交'), findsWidgets);
    expect(find.text('上海'), findsWidgets);
    expect(find.text('¥2.47'), findsNothing);
    expect(find.text('¥61.39'), findsNothing);
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    final sheet = find.byKey(const ValueKey('gallery-modal-surface'));
    expect(
      find.descendant(of: sheet, matching: find.text('¥2.47')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('¥61.39')),
      findsOneWidget,
    );
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
      final badge = tester.getRect(
        find.byKey(const ValueKey('trip-entry-line-badge')).first,
      );
      expect(badge.left, greaterThan(time.right));
      expect(badge.center.dy, closeTo(time.center.dy, 1.5));
      expect(badge.bottom, lessThanOrEqualTo(station.top));
      await tester.tap(find.text('陆家嘴'));
      await tester.pumpAndSettle();
      expect(controller.overlay, GalleryOverlay.trip);
      expect(find.textContaining('本行程为内置样例摘要'), findsNothing);
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
