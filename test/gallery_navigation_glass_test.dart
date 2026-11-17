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
import 'package:transit_card_analyzer/platform/translucency/translucency_platform.dart';

class _FakeTranslucency implements TranslucencyPlatform {
  const _FakeTranslucency(this.supported);

  final bool supported;

  @override
  Future<TranslucencyCapability> probe() async =>
      TranslucencyCapability(supported: supported, nativeGlass: false);
}

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
    required bool translucent,
    required bool docked,
  }) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    controller.update(() {
      controller.monet = false;
      controller.docked = docked;
    });
    await tester.pumpWidget(
      GalleryApp(
        controller: controller,
        translucencyPlatform: _FakeTranslucency(translucent),
      ),
    );
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
      await pumpGallery(tester, translucent: false, docked: docked);
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

  testWidgets('无通透支持时底栏保持 design.md 的材质', (tester) async {
    await pumpGallery(tester, translucent: false, docked: false);
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
      tester
          .widget<BackdropFilter>(find.byKey(const ValueKey('nav-glass')))
          .filter,
      ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
    );

    await pumpGallery(tester, translucent: false, docked: true);
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

  testWidgets('支持通透后悬浮底栏改用更透的玻璃材质与更强模糊', (tester) async {
    await pumpGallery(tester, translucent: true, docked: false);
    final tokens = Theme.of(
      tester.element(find.byKey(const ValueKey('gallery-navigation'))),
    ).extension<GalleryTokens>()!;
    final fill =
        (tester
                    .widget<Container>(find.byKey(const ValueKey('nav-bar')))
                    .decoration!
                as BoxDecoration)
            .color!;
    expect(fill.a, closeTo(tokens.dark ? .52 : .62, .001));
    expect(
      tester
          .widget<BackdropFilter>(find.byKey(const ValueKey('nav-glass')))
          .filter,
      ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
    );
  });

  testWidgets('支持通透后下沉底栏透出画布并带背景模糊', (tester) async {
    await pumpGallery(tester, translucent: true, docked: true);
    final tokens = Theme.of(
      tester.element(find.byKey(const ValueKey('gallery-navigation'))),
    ).extension<GalleryTokens>()!;
    final bar = tester.widget<Container>(find.byKey(const ValueKey('nav-bar')));
    final fill = (bar.decoration! as BoxDecoration).color!;
    expect(fill.a, closeTo(tokens.dark ? .58 : .70, .001));
    expect(fill.a, lessThan(1));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('gallery-navigation')),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );
  });

  test('原生通透探测读取文档的 supported 标记并启用原生玻璃', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidTranslucencyPlatform.channel, (
          call,
        ) async {
          expect(call.method, 'getSupport');
          return {'supported': true, 'mode': 3};
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AndroidTranslucencyPlatform.channel, null),
    );
    final capability = await const AndroidTranslucencyPlatform().probe();
    expect(capability.supported, isTrue);
    expect(capability.nativeGlass, isTrue);
  });

  test('原生通透探测在未实现或异常格式时回退为全部关闭', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      AndroidTranslucencyPlatform.channel,
      (call) async => {'supported': 'yes', 'mode': '3'},
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        AndroidTranslucencyPlatform.channel,
        null,
      ),
    );
    final capability = await const AndroidTranslucencyPlatform().probe();
    expect(capability.supported, isFalse);
    expect(capability.nativeGlass, isFalse);
  });

  test('原生玻璃材质不再叠加 Flutter 模糊，只保留可读染色', () {
    final tokens = GalleryTokens.from(controller.data, false, 'blue');
    final glass = GalleryGlass.forBar(
      tokens,
      translucent: true,
      docked: false,
      native: true,
    )!;
    expect(glass.native, isTrue);
    expect(glass.blurSigma, 0);
    expect(glass.fill.a, closeTo(.24, .001));
  });
}
