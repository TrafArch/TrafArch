import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_info.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';
import 'package:transit_card_analyzer/gallery/gallery_preferences.dart';

import 'support/gallery_scroll.dart';

Future<void> backGesture(
  WidgetTester tester,
  String method, [
  double progress = 0,
  int swipeEdge = 0,
]) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/backgesture',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall(
        method,
        method == 'startBackGesture' || method == 'updateBackGestureProgress'
            ? {
                'touchOffset': <double>[5, 300],
                'progress': progress,
                'swipeEdge': swipeEdge,
              }
            : null,
      ),
    ),
    (_) {},
  );
  await tester.pump();
}

void main() {
  late GalleryController c;
  late GalleryPreferences preferences;

  setUp(() {
    LicenseRegistry.reset();
    c = GalleryController(
      GalleryData(
        jsonDecode(File('assets/gallery/fixtures.json').readAsStringSync())
            as GalleryRecord,
      ),
    )..monet = false;
    preferences = GalleryPreferences();
  });

  tearDown(() {
    c.dispose();
    preferences.dispose();
    LicenseRegistry.reset();
  });

  Future<void> mount(WidgetTester tester, {List<String>? links}) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    c.navigate(GalleryPage.settings);
    await tester.pumpWidget(
      GalleryApp(
        controller: c,
        preferences: preferences,
        openWebLink: links == null
            ? null
            : (url) async => links.add(url.toString()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSettingsRow(WidgetTester tester, String label) async {
    await tester.scrollUntilVisible(
      find.text(label),
      300,
      scrollable: galleryVerticalScroll(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('settings keeps the 2.3 information architecture inline', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('样例管理'), findsNothing);
    expect(find.text('内置场景'), findsNothing);
    expect(find.text('恢复初始样例'), findsNothing);
    Future<void> reveal(String label) async {
      await tester.scrollUntilVisible(
        find.text(label),
        200,
        scrollable: galleryVerticalScroll(),
      );
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget, reason: label);
    }

    for (final item in [
      '读卡与数据',
      '读取后自动保存',
      '上海交通卡可透支余额',
      '知识库',
      '外观',
      '外观主题',
      '莫奈取色',
      '预测性返回手势',
      '底栏样式',
      '日志',
      '启用运行日志',
      '帮助与支持',
      '问题反馈',
    ]) {
      await reveal(item);
    }
    // About data is inline: logo, name, version and build number.
    await reveal('版本 ${AppInfo.version} (${AppInfo.buildNumber})');
    expect(find.text(AppInfo.appName), findsWidgets);
    for (final item in ['关于 TrafArch', '致谢', '开放源代码许可', '隐私政策', '贡献者']) {
      await reveal(item);
    }
    await reveal(AppInfo.copyright);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('contributor entry stacks avatars and opens the shared sheet', (
    tester,
  ) async {
    final links = <String>[];
    await mount(tester, links: links);
    await tester.scrollUntilVisible(
      find.text('贡献者'),
      300,
      scrollable: galleryVerticalScroll(),
    );
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('settings-contributors'));
    expect(row, findsOneWidget);
    expect(find.text('7 位'), findsOneWidget);
    expect(find.text('+4'), findsOneWidget);
    // Only the first three bundled avatars are stacked when collapsed.
    expect(
      find.descendant(of: row, matching: find.byType(Image)),
      findsNWidgets(3),
    );

    await openSettingsRow(tester, '贡献者');
    expect(c.overlay, GalleryOverlay.contributors);
    expect(find.text('感谢所有参与 TrafArch 建设的人'), findsOneWidget);
    for (final name in [
      'kajolno',
      'Nightingale0504',
      '林天仪',
      'mitkimi',
      'Makitoid',
      '鳄鱼宝宝',
      'DearVa',
    ]) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    // Only contributors with a verified profile show the external link.
    expect(find.text('主页'), findsNWidgets(5));
    await tester.tap(find.text('主页').first);
    await tester.pumpAndSettle();
    expect(links, ['https://github.com/kajolno']);
    // A longer list keeps its own scroll position inside the sheet.
    final sheet = find.byKey(const ValueKey('gallery-sheet'));
    await tester.scrollUntilVisible(
      find.text('DearVa'),
      200,
      scrollable: find.descendant(of: sheet, matching: galleryVerticalScroll()),
    );
    expect(find.text('DearVa'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(c.overlay, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'license rows open a medium sheet that expands and closes by drag',
    (tester) async {
      final longText = List.generate(
        80,
        (i) => 'Permission is hereby granted, free of charge, line $i',
      ).join('\n');
      LicenseRegistry.addLicense(
        () => Stream.value(
          LicenseEntryWithLineBreaks(['drag-test-package'], longText),
        ),
      );
      await mount(tester);
      await openSettingsRow(tester, '开放源代码许可');
      expect(c.page, GalleryPage.licenses);
      await tester.tap(find.text('drag-test-package'));
      await tester.pumpAndSettle();
      expect(c.overlay, GalleryOverlay.licenseDetail);

      final sheet = find.byKey(const ValueKey('gallery-sheet'));
      expect(sheet, findsOneWidget);
      expect(
        find.byKey(const ValueKey('gallery-sheet-handle')),
        findsOneWidget,
      );
      final barrier = tester.widget<ModalBarrier>(
        find.byType(ModalBarrier).last,
      );
      expect(barrier.color, const Color(0x99000000));

      final material = find
          .descendant(of: sheet, matching: find.byType(Material))
          .first;
      final shape = tester.widget<Material>(material).shape;
      expect(shape, isA<RoundedRectangleBorder>());
      expect(
        (shape! as RoundedRectangleBorder).borderRadius,
        const BorderRadius.vertical(top: Radius.circular(24)),
      );

      double fraction() => (892 - tester.getTopLeft(material).dy) / 892;
      expect(fraction(), closeTo(.57, .02));
      // The license type is derived from the bundled text and linked.
      expect(find.text('MIT'), findsOneWidget);
      expect(find.text('许可证原文链接'), findsOneWidget);

      final scrollable = find.descendant(
        of: sheet,
        matching: find.byType(Scrollable),
      );
      await tester.drag(scrollable.first, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(fraction(), closeTo(.9, .02));

      // Dragging down past the medium size dismisses through the same route.
      await tester.drag(scrollable.first, const Offset(0, 700));
      await tester.pumpAndSettle();
      expect(c.overlay, isNull);
      expect(find.byKey(const ValueKey('gallery-sheet')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'predictive back cancels without resetting scroll or sheet height',
    (tester) async {
      final longText = List.generate(
        120,
        (i) => 'Apache License Version 2.0 line $i',
      ).join('\n');
      LicenseRegistry.addLicense(
        () => Stream.value(
          LicenseEntryWithLineBreaks(['back-test-package'], longText),
        ),
      );
      await mount(tester);
      await openSettingsRow(tester, '开放源代码许可');
      await tester.tap(find.text('back-test-package'));
      await tester.pumpAndSettle();
      expect(c.overlay, GalleryOverlay.licenseDetail);
      expect(find.text('Apache License 2.0'), findsOneWidget);

      final sheet = find.byKey(const ValueKey('gallery-sheet'));
      final scrollable = find.descendant(
        of: sheet,
        matching: find.byType(Scrollable),
      );
      await tester.drag(scrollable.first, const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.drag(scrollable.first, const Offset(0, -300));
      await tester.pumpAndSettle();
      final offset = tester
          .state<ScrollableState>(scrollable.first)
          .position
          .pixels;
      expect(offset, greaterThan(0));
      final material = find
          .descendant(of: sheet, matching: find.byType(Material))
          .first;
      final height = tester.getTopLeft(material).dy;

      await backGesture(tester, 'startBackGesture');
      await backGesture(tester, 'updateBackGestureProgress', .5);
      await backGesture(tester, 'cancelBackGesture');
      await tester.pumpAndSettle();
      expect(c.overlay, GalleryOverlay.licenseDetail);
      expect(tester.getTopLeft(material).dy, closeTo(height, .1));
      expect(
        tester.state<ScrollableState>(scrollable.first).position.pixels,
        offset,
      );

      await backGesture(tester, 'startBackGesture', 0, 1);
      await backGesture(tester, 'updateBackGestureProgress', .6, 1);
      await backGesture(tester, 'commitBackGesture', 0, 1);
      await tester.pumpAndSettle();
      expect(c.overlay, isNull);
      expect(find.byKey(const ValueKey('gallery-sheet')), findsNothing);
      expect(c.page, GalleryPage.licenses);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
