import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/trip_reader_import.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';
import 'package:transit_card_analyzer/gallery/gallery_preferences.dart';

import 'support/gallery_scroll.dart';

const _archiveChannel = MethodChannel(
  'transit_card_analyzer/archive_documents',
);

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
  });

  /// 拦截系统平台通道，收集触感反馈调用。
  List<Object?> interceptHaptics(WidgetTester tester) {
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
    return haptics;
  }

  Future<void> mount(
    WidgetTester tester, {
    GalleryPage page = GalleryPage.home,
  }) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    c.navigate(page);
    await tester.pumpWidget(
      GalleryApp(controller: c, preferences: preferences),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, String label) async {
    await tester.scrollUntilVisible(
      find.text(label),
      300,
      scrollable: galleryVerticalScroll(),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openImportSourceDialog(WidgetTester tester) async {
    await reveal(tester, '导入卡片记录');
    await tester.tap(find.text('导入卡片记录'));
    await tester.pumpAndSettle();
    expect(find.text('选择导入来源'), findsOneWidget);
  }

  testWidgets('外观区标题为界面与外观并包含受控的震动开关', (tester) async {
    final haptics = interceptHaptics(tester);
    await mount(tester, page: GalleryPage.settings);

    await reveal(tester, '界面与外观');
    expect(find.text('界面与外观'), findsOneWidget);
    expect(find.text('外观'), findsNothing);
    expect(find.text('外观主题'), findsOneWidget);

    await reveal(tester, '震动');
    expect(
      find.widgetWithText(SwitchListTile, '震动'),
      findsOneWidget,
      reason: '震动开关必须在界面与外观区存在',
    );
    expect(find.text('控制开关点击与底栏切换的系统触感反馈'), findsOneWidget);
    expect(c.hapticEnabled, isTrue);

    // 点击时仍开启：这一次点击振一次，随后开关关闭。
    await tester.tap(find.text('震动'));
    await tester.pumpAndSettle();
    expect(c.hapticEnabled, isFalse);
    expect(haptics, ['HapticFeedbackType.selectionClick']);

    // 从关闭状态重新开启：点击前已关闭，不应振动。
    await tester.tap(find.text('震动'));
    await tester.pumpAndSettle();
    expect(c.hapticEnabled, isTrue);
    expect(haptics, hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('底栏切换的震动受震动开关控制', (tester) async {
    final haptics = interceptHaptics(tester);
    await mount(tester);
    expect(c.mainPage, GalleryPage.home);

    c.setHaptic(false);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('nav-trips')));
    await tester.pumpAndSettle();
    expect(c.mainPage, GalleryPage.trips);
    expect(haptics, isEmpty, reason: '关闭震动后底栏切换不得振动');

    // 重复点当前页本来就不振，关闭状态同样保持静默。
    await tester.tap(find.byKey(const ValueKey('nav-trips')));
    await tester.pumpAndSettle();
    expect(haptics, isEmpty);

    c.setHaptic(true);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('nav-cards')));
    await tester.pumpAndSettle();
    expect(c.mainPage, GalleryPage.cards);
    expect(haptics, ['HapticFeedbackType.selectionClick']);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('导入弹窗展示两个来源，读卡识途只提示开发中且不导入', (tester) async {
    interceptHaptics(tester);
    var archiveCalls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _archiveChannel,
      (call) async {
        archiveCalls++;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _archiveChannel,
        null,
      ),
    );
    await mount(tester, page: GalleryPage.settings);
    await openImportSourceDialog(tester);

    expect(find.text('TrafArch 数据'), findsOneWidget);
    expect(find.text('从读卡识途数据导入'), findsOneWidget);
    expect(find.text('正在开发中，敬请期待'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('import-source-trip-reader')));
    await tester.pumpAndSettle();

    expect(find.text('选择导入来源'), findsNothing);
    expect(c.overlay, isNull);
    expect(archiveCalls, 0, reason: '读卡识途选项不得触发任何真实导入');
    expect(find.text('正在开发中，敬请期待'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('取消导入来源弹窗不产生副作用', (tester) async {
    interceptHaptics(tester);
    var archiveCalls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _archiveChannel,
      (call) async {
        archiveCalls++;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _archiveChannel,
        null,
      ),
    );
    await mount(tester, page: GalleryPage.settings);
    await openImportSourceDialog(tester);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('选择导入来源'), findsNothing);
    expect(c.overlay, isNull);
    expect(c.page, GalleryPage.settings);
    expect(archiveCalls, 0);
    expect(find.text('正在开发中，敬请期待'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('点遮罩关闭导入来源弹窗不产生副作用', (tester) async {
    interceptHaptics(tester);
    var archiveCalls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _archiveChannel,
      (call) async {
        archiveCalls++;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _archiveChannel,
        null,
      ),
    );
    await mount(tester, page: GalleryPage.settings);
    await openImportSourceDialog(tester);
    final overlayBefore = c.overlay;

    // 弹窗是 showDialog 的 barrierDismissible 默认值，点弹窗外的遮罩即取消。
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    expect(find.text('选择导入来源'), findsNothing);
    expect(c.overlay, overlayBefore);
    expect(c.overlay, isNull);
    expect(c.page, GalleryPage.settings);
    expect(archiveCalls, 0, reason: '遮罩关闭不得触发导入');
    expect(find.text('正在开发中，敬请期待'), findsNothing);
    expect(find.text('导入卡片 JSON'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('选择 TrafArch 数据仍进入原有导入预览', (tester) async {
    final backup = jsonEncode({
      'cards': [
        {'name': '上海公共交通卡', 'number': '1234'},
      ],
    });
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _archiveChannel,
      (call) async {
        if (call.method == 'openJson') {
          return {'name': 'backup.json', 'content': backup};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _archiveChannel,
        null,
      ),
    );
    await mount(tester, page: GalleryPage.settings);
    await openImportSourceDialog(tester);

    await tester.tap(find.byKey(const ValueKey('import-source-archive')));
    await tester.pumpAndSettle();

    expect(c.overlay, GalleryOverlay.importPreview);
    expect(find.text('文件内容预览 · 不会修改当前样例'), findsOneWidget);
    expect(find.textContaining('识别到 1 张卡片记录'), findsOneWidget);
    expect(find.textContaining('backup.json'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('读卡识途导入占位实现明确返回开发中', () async {
    const service = UnavailableTripReaderImportService();
    await expectLater(
      service.pickImport(),
      throwsA(isA<TripReaderImportUnavailable>()),
    );
    await expectLater(
      service.confirmImport(
        const TripReaderImportPreview(name: 'demo', summary: 'demo'),
      ),
      throwsA(
        isA<TripReaderImportUnavailable>().having(
          (error) => '$error',
          'toString',
          contains('正在开发中，敬请期待'),
        ),
      ),
    );
  });
}
