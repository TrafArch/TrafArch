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

class _FaceStore implements GalleryFaceStore {
  final values = <String, GalleryFaceSnapshot>{};

  @override
  Future<GalleryFaceSnapshot?> read(String cardId) async => values[cardId];

  @override
  Future<void> write(String cardId, GalleryFaceSnapshot snapshot) async {
    values[cardId] = snapshot;
  }

  @override
  Future<void> delete(String cardId) async => values.remove(cardId);
}

void main() {
  late GalleryController c;
  late GalleryPreferences preferences;
  late _FaceStore store;
  const channel = MethodChannel('transit_card_analyzer/qr_image');
  final imagePath = File('assets/icon/app_icon.png').absolute.path;
  final otherImagePath = File('assets/gallery/city-union-logo.png')
      .absolute
      .path;
  const picking = '正在打开相册…';

  setUp(() {
    c = GalleryController(
      GalleryData(
        jsonDecode(File('assets/gallery/fixtures.json').readAsStringSync())
            as GalleryRecord,
      ),
    )..monet = false;
    store = _FaceStore();
    preferences = GalleryPreferences(faceStore: store);
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

  Future<void> mountFace(
    WidgetTester tester, {
    Size screen = const Size(412, 892),
    double topInset = 0,
    double bottomInset = 0,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    final padding = FakeViewPadding(top: topInset, bottom: bottomInset);
    tester.view.viewPadding = padding;
    tester.view.padding = padding;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    c.navigate(GalleryPage.cards);
    await tester.pumpWidget(
      GalleryApp(controller: c, preferences: preferences),
    );
    await tester.pumpAndSettle();
    c.showOverlay(GalleryOverlay.face, card: c.current);
    await tester.pumpAndSettle();
  }

  // File reads and the engine codec must complete outside fake async time.
  Future<void> waitForPicker(WidgetTester tester) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    do {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump();
      if (find.text(picking).evaluate().isEmpty) return;
    } while (DateTime.now().isBefore(deadline));
    fail('The gallery image operation did not finish');
  }

  Future<void> pickAndFinish(
    WidgetTester tester, {
    String label = '从相册选择图片',
  }) async {
    final button = find.text(label);
    if (label == '从相册选择图片') await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(button);
      await waitForPicker(tester);
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Finder cropCanvas(String key) => find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byKey(const ValueKey('face-crop-canvas')),
  );

  Future<void> dragRegion(WidgetTester tester, String key, Offset delta) async {
    await tester.dragFrom(tester.getCenter(cropCanvas(key)), delta);
    await tester.pumpAndSettle();
  }

  Future<void> pinchRegion(WidgetTester tester, String key) async {
    final center = tester.getCenter(cropCanvas(key));
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

  for (final (screen, bottom, textScale) in [
    (const Size(412, 892), 24.0, 1.0),
    (const Size(320, 568), 48.0, 1.0),
    (const Size(360, 580), 48.0, 2.0),
  ]) {
    testWidgets(
      'crop controls fit without vertical scrolling: $screen ×$textScale',
      (tester) async {
        const top = 24.0;
        mockPicker(() async => imagePath);
        await mountFace(
          tester,
          screen: screen,
          topInset: top,
          bottomInset: bottom,
          textScale: textScale,
        );
        await pickAndFinish(tester);
        final surface = find.byKey(const ValueKey('gallery-face-surface'));
        final sheet = tester.getRect(surface);
        expect(sheet.top, greaterThanOrEqualTo(top));
        expect(sheet.bottom, screen.height);
        // Wallet preview metadata may scroll sideways; the editor must not
        // require vertical scrolling to reach either canvas or its controls.
        expect(
          find.descendant(
            of: surface,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  (widget.axisDirection == AxisDirection.up ||
                      widget.axisDirection == AxisDirection.down),
            ),
          ),
          findsNothing,
        );

        Rect expectVisibleAndTouchable(Finder finder) {
          expect(finder.hitTestable(), findsOneWidget);
          final frame = tester.getRect(finder);
          expect(frame.top, greaterThanOrEqualTo(sheet.top));
          expect(frame.bottom, lessThanOrEqualTo(screen.height - bottom));
          return frame;
        }

        for (final label in ['重置全部', '换一张', '完成']) {
          expectVisibleAndTouchable(find.widgetWithText(TextButton, label));
        }
        for (final key in [
          'face-crop-region-detail',
          'face-crop-region-list',
        ]) {
          final region = find.byKey(ValueKey(key));
          final frame = expectVisibleAndTouchable(cropCanvas(key));
          expect(frame.height, greaterThan(40));
          expectVisibleAndTouchable(
            find.descendant(
              of: region,
              matching: find.widgetWithText(TextButton, '恢复默认'),
            ),
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    're-picking changes only the draft until the outer confirmation',
    (tester) async {
      mockPicker(() async => imagePath);
      await mountFace(tester);
      await pickAndFinish(tester);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      final confirm = find.text('完成');
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      final card = c.current;
      final saved = store.values[card.id]!;
      expect(card.image, same(saved.image));

      c.showOverlay(GalleryOverlay.face, card: card);
      await tester.pumpAndSettle();
      await pickAndFinish(tester);
      await dragRegion(tester, 'face-crop-region-detail', const Offset(0, 60));
      final firstDraft = c.faceCrop!;
      final route = c.navigationStack.last.id;
      expect(firstDraft.detail.offsetY, isNot(0));
      mockPicker(() async => otherImagePath);
      await pickAndFinish(tester, label: '换一张');
      final replacement = c.faceCrop!;
      expect(c.navigationStack.last.id, route);
      expect(replacement, isNot(same(firstDraft)));
      expect(replacement.image, isNot(orderedEquals(firstDraft.image)));
      expect(replacement.editing, isTrue);
      for (final crop in [replacement.detail, replacement.list]) {
        expect(crop.scale, 1);
        expect(crop.offsetX, 0);
        expect(crop.offsetY, 0);
      }
      expect(card.image, same(saved.image));
      expect(store.values[card.id], same(saved));

      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(c.overlay, isNull);
      expect(card.image, same(replacement.image));
      expect(store.values[card.id]!.image, same(replacement.image));
    },
  );

  testWidgets('canceling or failing to decode a replacement keeps both crops', (
    tester,
  ) async {
    mockPicker(() async => imagePath);
    await mountFace(tester);
    await pickAndFinish(tester);
    await dragRegion(tester, 'face-crop-region-detail', const Offset(0, 60));
    await dragRegion(tester, 'face-crop-region-list', const Offset(0, -40));
    final draft = c.faceCrop!;
    final detail = draft.detail;
    final list = draft.list;
    expect(detail.offsetY, isNot(0));
    expect(list.offsetY, isNot(0));

    mockPicker(() async => null);
    await pickAndFinish(tester, label: '换一张');
    expect(c.faceCrop, same(draft));
    expect(find.text('无法读取所选图片，请选择其他图片重试'), findsNothing);

    mockPicker(() async => File('assets/gallery/fixtures.json').absolute.path);
    await pickAndFinish(tester, label: '换一张');
    expect(c.faceCrop, same(draft));
    expect(draft.detail, same(detail));
    expect(draft.list, same(list));
    expect(draft.editing, isTrue);
    expect(find.text('无法读取所选图片，请选择其他图片重试'), findsOneWidget);
    expect(find.text('换一张').hitTestable(), findsOneWidget);
    expect(c.current.image, isNull);
    expect(store.values, isEmpty);
  });

  testWidgets('leaving and reopening the editor ignores a late replacement', (
    tester,
  ) async {
    mockPicker(() async => imagePath);
    await mountFace(tester);
    await pickAndFinish(tester);
    final original = c.faceCrop!;
    final pick = Completer<String?>();
    mockPicker(() => pick.future);
    await tester.runAsync(() async {
      await tester.tap(find.text('换一张'));
      await tester.pumpAndSettle();
      expect(find.text(picking), findsOneWidget);
      await tester.tap(find.byTooltip('返回更换卡面'));
      await tester.pumpAndSettle();
      final edit = find.text('调整图片');
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(original.editing, isTrue);
      pick.complete(otherImagePath);
      await waitForPicker(tester);
    });
    await tester.pumpAndSettle();
    expect(c.faceCrop, same(original));
    expect(c.current.image, isNull);
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
