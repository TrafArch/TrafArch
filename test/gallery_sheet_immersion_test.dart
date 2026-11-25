import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';
import 'package:transit_card_analyzer/gallery/gallery_preferences.dart';

import 'support/gallery_scroll.dart';

/// 半模态沉浸式覆盖：表面必须延伸到屏幕物理底边（含系统导航栏手势区），
/// 而可交互内容继续避让 bottom inset。所有用例锁定 412×892 逻辑像素。
const _screen = Size(412, 892);
const _pickChannel = MethodChannel('transit_card_analyzer/qr_image');

void main() {
  late GalleryController c;
  late GalleryPreferences preferences;

  setUp(() {
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pickChannel, null);
  });

  Future<void> mount(
    WidgetTester tester,
    double bottom, {
    GalleryPage page = GalleryPage.cards,
  }) async {
    tester.view.physicalSize = _screen;
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = FakeViewPadding(bottom: bottom);
    tester.view.padding = FakeViewPadding(bottom: bottom);
    addTearDown(tester.view.reset);
    c.hasRead = true;
    c.navigate(page);
    await tester.pumpWidget(
      GalleryApp(controller: c, preferences: preferences),
    );
    await tester.pumpAndSettle();
  }

  Rect buttonRect(WidgetTester tester, String label) => tester.getRect(
    find
        .ancestor(of: find.text(label), matching: find.byType(TextButton))
        .first,
  );

  for (final inset in [24.0, 48.0]) {
    testWidgets('更换卡面半模态表面覆盖导航区，底部按钮留在手势区外（$inset）', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await mount(tester, inset);
      c.showOverlay(GalleryOverlay.face, card: c.current);
      await tester.pumpAndSettle();

      final surface = find.byKey(const ValueKey('gallery-face-surface'));
      expect(surface, findsOneWidget);
      expect(tester.getRect(surface).bottom, _screen.height);

      // 导航栏区域填充的就是表面色，小黑条不再露出别的底色。
      final fill = tester.widget<Material>(surface).color!;
      final style =
          calls
                  .lastWhere(
                    (call) =>
                        call.method == 'SystemChrome.setSystemUIOverlayStyle',
                  )
                  .arguments
              as Map<dynamic, dynamic>;
      expect(style['systemNavigationBarColor'], fill.toARGB32());

      // 滚动正文被内层 SafeArea 顶起，整个内容区不进入手势区。
      final body = find.descendant(
        of: surface,
        matching: find.byType(SingleChildScrollView),
      );
      expect(tester.getRect(body).bottom, closeTo(_screen.height - inset, .1));

      await tester.ensureVisible(find.text('从相册选择图片'));
      await tester.pumpAndSettle();
      expect(
        buttonRect(tester, '从相册选择图片').bottom,
        lessThanOrEqualTo(_screen.height - inset),
      );

      await tester.ensureVisible(find.text('完成'));
      await tester.pumpAndSettle();
      expect(
        buttonRect(tester, '完成').bottom,
        lessThanOrEqualTo(_screen.height - inset),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('裁切器表面同样覆盖导航区，「完成」留在手势区外', (tester) async {
    const inset = 24.0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pickChannel, (call) async {
          expect(call.method, 'pickImage');
          return File('assets/icon/app_icon.png').absolute.path;
        });

    await mount(tester, inset);
    c.showOverlay(GalleryOverlay.face, card: c.current);
    await tester.pumpAndSettle();

    // 图片读取与解码必须在 fake async 之外完成。
    await tester.runAsync(() async {
      await tester.tap(find.text('从相册选择图片'));
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      do {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        if (find.text('正在打开相册…').evaluate().isEmpty) return;
      } while (DateTime.now().isBefore(deadline));
      fail('The gallery image operation did not finish');
    });
    await tester.pumpAndSettle();

    expect(find.text('调整图片'), findsOneWidget);
    final surface = find.byKey(const ValueKey('gallery-face-surface'));
    expect(tester.getRect(surface).bottom, _screen.height);
    expect(
      buttonRect(tester, '完成').bottom,
      lessThanOrEqualTo(_screen.height - inset),
    );
    // 裁切交互保持不变。
    expect(
      find.byKey(const ValueKey('face-crop-region-detail')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('face-crop-region-list')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final inset in [24.0, 48.0]) {
    testWidgets('贡献者半模态表面覆盖导航区，末位条目可完整读出（$inset）', (tester) async {
      await mount(tester, inset, page: GalleryPage.settings);
      await tester.scrollUntilVisible(
        find.text('贡献者'),
        300,
        scrollable: galleryVerticalScroll(),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('贡献者'));
      await tester.pumpAndSettle();
      expect(c.overlay, GalleryOverlay.contributors);

      final sheet = find.byKey(const ValueKey('gallery-sheet'));
      final material = find
          .descendant(of: sheet, matching: find.byType(Material))
          .first;
      expect(tester.getRect(material).bottom, _screen.height);

      final list = tester.widget<ListView>(
        find.descendant(of: sheet, matching: find.byType(ListView)),
      );
      expect((list.padding! as EdgeInsets).bottom, greaterThanOrEqualTo(inset));

      final scrollable = find.descendant(
        of: sheet,
        matching: find.byType(Scrollable),
      );
      for (var i = 0; i < 6; i++) {
        await tester.drag(scrollable.first, const Offset(0, -400));
        await tester.pumpAndSettle();
      }
      final last = find.text('全栈开发者，为2.0界面设计提供大量帮助');
      expect(last, findsOneWidget);
      expect(
        tester.getRect(last).bottom,
        lessThanOrEqualTo(_screen.height - inset),
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final inset in [24.0, 48.0]) {
    testWidgets('居中确认弹窗保持原有留白，操作按钮避开手势区（$inset）', (tester) async {
      await mount(tester, inset);
      c.showOverlay(GalleryOverlay.delete, card: c.current);
      await tester.pumpAndSettle();

      final surface = find.byKey(const ValueKey('gallery-modal-surface'));
      expect(surface, findsOneWidget);
      final rect = tester.getRect(surface);
      // 非半模态不改行为：不延伸进导航区，仍整体留在安全区内。
      expect(rect.bottom, lessThan(_screen.height));
      expect(rect.bottom, lessThanOrEqualTo(_screen.height - inset));
      expect(
        buttonRect(tester, '删除').bottom,
        lessThanOrEqualTo(_screen.height - inset),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('行程半模态在 48px 底部安全区下仍覆盖导航区并同步导航栏颜色', (tester) async {
    const inset = 48.0;
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await mount(tester, inset, page: GalleryPage.trips);
    await tester.tap(find.text('陆家嘴'));
    await tester.pumpAndSettle();
    expect(c.overlay, GalleryOverlay.trip);

    final surface = find.byKey(const ValueKey('gallery-modal-surface'));
    expect(tester.getRect(surface).bottom, _screen.height);
    final body = find.descendant(
      of: surface,
      matching: find.byType(SingleChildScrollView),
    );
    expect(tester.getRect(body).bottom, closeTo(_screen.height - inset, .1));
    final fill = tester.widget<Material>(surface).color!;
    final style =
        calls
                .lastWhere(
                  (call) =>
                      call.method == 'SystemChrome.setSystemUIOverlayStyle',
                )
                .arguments
            as Map<dynamic, dynamic>;
    expect(style['systemNavigationBarColor'], fill.toARGB32());
    expect(tester.takeException(), isNull);
  });
}
