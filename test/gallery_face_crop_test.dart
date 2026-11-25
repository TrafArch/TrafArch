import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';
import 'package:transit_card_analyzer/gallery/gallery_preferences.dart';

Future<void> backGesture(
  WidgetTester tester,
  String method, [
  double progress = 0,
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
                'swipeEdge': 0,
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
  const channel = MethodChannel('transit_card_analyzer/qr_image');
  final imagePath = File('assets/icon/app_icon.png').absolute.path;

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
        .setMockMethodCallHandler(channel, null);
  });

  void mockPicker(Future<String?> Function() pick) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'pickImage');
          return pick();
        });
  }

  Future<void> mountFace(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    c.navigate(GalleryPage.cards);
    await tester.pumpWidget(
      GalleryApp(controller: c, preferences: preferences),
    );
    await tester.pumpAndSettle();
    c.showOverlay(GalleryOverlay.face, card: c.current);
    await tester.pumpAndSettle();
  }

  // File reads and the engine codec must complete outside fake async time.
  Future<void> pickAndFinish(WidgetTester tester) async {
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
    expect(tester.takeException(), isNull);
  }

  Future<void> dragRegion(WidgetTester tester, String key, Offset delta) async {
    await tester.dragFrom(tester.getCenter(find.byKey(ValueKey(key))), delta);
    await tester.pumpAndSettle();
  }

  Future<void> pinchRegion(WidgetTester tester, String key) async {
    final center = tester.getCenter(find.byKey(ValueKey(key)));
    final first = await tester.startGesture(center - const Offset(30, 0));
    final second = await tester.startGesture(center + const Offset(30, 0));
    await tester.pump();
    await first.moveBy(const Offset(-40, 0));
    await second.moveBy(const Offset(40, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
  }

  testWidgets('picking converts the same sheet into a two-region cropper', (
    tester,
  ) async {
    mockPicker(() async => imagePath);
    await mountFace(tester);
    final routes = c.navigationStack.length;
    await pickAndFinish(tester);
    // 不创建第二层半模态：路由数量不变，原 sheet 转为裁切器。
    expect(c.navigationStack.length, routes);
    expect(c.overlay, GalleryOverlay.face);
    expect(find.text('调整图片'), findsOneWidget);
    expect(find.text('分别调整图片在两个页面中的显示范围'), findsNothing);
    expect(find.text('拖动图片 · 双指缩放'), findsNothing);
    expect(
      find.byKey(const ValueKey('face-crop-region-detail')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('face-crop-region-list')), findsOneWidget);
    final session = c.faceCrop!;
    expect(session.editing, isTrue);
    expect(session.detail.scale, 1);
    expect(session.list.scale, 1);
    expect(c.current.image, isNull);
    // 两个区域共用同一张原图。
    final images = tester
        .widgetList<Image>(find.byType(Image))
        .where((image) => image.image is MemoryImage)
        .toList();
    expect(images, isNotEmpty);
    for (final image in images) {
      expect((image.image as MemoryImage).bytes, same(session.image));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('regions crop independently and never uncover the window', (
    tester,
  ) async {
    mockPicker(() async => imagePath);
    await mountFace(tester);
    await pickAndFinish(tester);
    await dragRegion(tester, 'face-crop-region-detail', const Offset(0, 60));
    final afterDetail = c.faceCrop!;
    expect(afterDetail.detail.offsetY, isNot(0));
    expect(afterDetail.list.offsetX, 0);
    expect(afterDetail.list.offsetY, 0);
    expect(afterDetail.list.scale, 1);
    await dragRegion(tester, 'face-crop-region-list', const Offset(0, -40));
    final afterList = c.faceCrop!;
    expect(afterList.list.offsetY, isNot(0));
    expect(afterList.detail.offsetY, afterDetail.detail.offsetY);
    // 归一化偏移始终限制在覆盖范围内，图片不会露出空白。
    await dragRegion(tester, 'face-crop-region-detail', const Offset(0, 4000));
    expect(c.faceCrop!.detail.offsetY.abs(), lessThanOrEqualTo(1));
    await pinchRegion(tester, 'face-crop-region-detail');
    expect(c.faceCrop!.detail.scale, greaterThan(1));
    expect(c.faceCrop!.detail.scale, lessThanOrEqualTo(4));
    expect(c.faceCrop!.list.scale, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('single-region reset and confirmed reset-all restore cover', (
    tester,
  ) async {
    mockPicker(() async => imagePath);
    await mountFace(tester);
    await pickAndFinish(tester);
    await dragRegion(tester, 'face-crop-region-detail', const Offset(0, 60));
    await dragRegion(tester, 'face-crop-region-list', const Offset(0, 60));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('face-crop-region-detail')),
        matching: find.text('恢复默认'),
      ),
    );
    await tester.pumpAndSettle();
    expect(c.faceCrop!.detail.offsetY, 0);
    expect(c.faceCrop!.list.offsetY, isNot(0));
    await tester.tap(find.text('重置全部'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final action = find.byKey(const ValueKey('gallery-feedback-action'));
    expect(action, findsOneWidget);
    await tester.tap(action);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.faceCrop!.detail.offsetY, 0);
    expect(c.faceCrop!.list.offsetY, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back keeps the session; the outer 完成 commits both crops', (
    tester,
  ) async {
    mockPicker(() async => imagePath);
    await mountFace(tester);
    await pickAndFinish(tester);
    await dragRegion(tester, 'face-crop-region-detail', const Offset(0, 60));
    final edited = c.faceCrop!.detail;
    await tester.tap(find.byTooltip('返回更换卡面'));
    await tester.pumpAndSettle();
    expect(find.text('更换卡面'), findsOneWidget);
    expect(c.faceCrop, isNotNull);
    expect(c.faceCrop!.editing, isFalse);
    expect(c.current.image, isNull);
    // 返回后预览使用临时裁切结果，并可再次进入裁切器。
    expect(
      find.byKey(const ValueKey('face-list-card-shanghai')),
      findsOneWidget,
    );
    await tester.tap(find.text('调整图片'));
    await tester.pumpAndSettle();
    expect(c.faceCrop!.detail.offsetY, edited.offsetY);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('完成'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(c.overlay, isNull);
    expect(c.faceCrop, isNull);
    expect(c.current.image, isNotNull);
    expect(c.current.detailCrop.offsetY, edited.offsetY);
    expect(c.current.listCrop.scale, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing the sheet discards the uncommitted session', (
    tester,
  ) async {
    mockPicker(() async => imagePath);
    await mountFace(tester);
    await pickAndFinish(tester);
    await tester.tap(find.byTooltip('返回更换卡面'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(c.overlay, isNull);
    expect(c.faceCrop, isNull);
    expect(c.current.image, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('predictive back exits the cropper before closing the sheet', (
    tester,
  ) async {
    mockPicker(() async => imagePath);
    await mountFace(tester);
    await pickAndFinish(tester);
    await backGesture(tester, 'startBackGesture');
    await backGesture(tester, 'updateBackGestureProgress', .5);
    await backGesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(c.overlay, GalleryOverlay.face);
    expect(c.faceCrop, isNotNull);
    expect(c.faceCrop!.editing, isFalse);
    expect(find.text('更换卡面'), findsOneWidget);
    await backGesture(tester, 'startBackGesture');
    await backGesture(tester, 'updateBackGestureProgress', .6);
    await backGesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(c.overlay, isNull);
    expect(c.faceCrop, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('canceling the picker keeps the change-face sheet untouched', (
    tester,
  ) async {
    mockPicker(() async => null);
    await mountFace(tester);
    await pickAndFinish(tester);
    expect(c.faceCrop, isNull);
    expect(find.text('更换卡面'), findsOneWidget);
    expect(find.text('从相册选择图片'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cropper previews share the card scrim without an idle outline', (
    tester,
  ) async {
    mockPicker(() async => imagePath);
    await mountFace(tester);
    await pickAndFinish(tester);
    // Both preview regions render the same image layer as the final card.
    expect(find.byKey(const ValueKey('face-image-scrim')), findsNWidgets(2));
    for (final key in ['face-crop-region-detail', 'face-crop-region-list']) {
      final region = find.byKey(ValueKey(key));
      final container = tester.widget<AnimatedContainer>(
        find
            .descendant(of: region, matching: find.byType(AnimatedContainer))
            .first,
      );
      expect((container.decoration! as BoxDecoration).border, isNull);
    }
    // Theme switching only recolours the scrim; crop coordinates stay put.
    final detail = c.faceCrop!.detail;
    final list = c.faceCrop!.list;
    c.update(() => c.themeMode = ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(c.faceCrop!.detail.scale, detail.scale);
    expect(c.faceCrop!.detail.offsetX, detail.offsetX);
    expect(c.faceCrop!.detail.offsetY, detail.offsetY);
    expect(c.faceCrop!.list.scale, list.scale);
    expect(c.faceCrop!.list.offsetX, list.offsetX);
    expect(c.faceCrop!.list.offsetY, list.offsetY);
    expect(find.byKey(const ValueKey('face-image-scrim')), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
