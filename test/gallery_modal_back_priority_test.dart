import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';
import 'package:transit_card_analyzer/gallery/gallery_preferences.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/log_exporter.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/shared/diagnostics/diagnostic_event.dart';

import 'support/gallery_scroll.dart';
import 'support/test_database.dart';

final _logs = find.text('诊断日志');
final _logManager = find.text('日志管理器');
final _sheet = find.byKey(const ValueKey('gallery-modal-surface'));

void main() {
  testWidgets('实卡设置返回：日志管理器先关，滚动位置不变，再返回才退出设置', (tester) async {
    final (_, exporter) = await _mountLive(tester);
    await tester.tap(find.byTooltip('设置'));
    await _settle(tester);
    await _revealLogs(tester);
    final logsRow = _logs.hitTestable();
    expect(logsRow, findsOneWidget);
    ScrollableState settingsScroll() =>
        Scrollable.of(tester.element(logsRow), axis: Axis.vertical);
    final scrollable = settingsScroll();
    final position = scrollable.position;
    final pixels = position.pixels;
    expect(pixels, greaterThan(0));

    void expectRetainedScroll() {
      expect(scrollable.mounted, isTrue);
      expect(scrollable.position, same(position));
      expect(position.pixels, closeTo(pixels, .01));
    }

    await _openLogs(tester);
    expect(find.text('暂无日志记录'), findsOneWidget);
    expect(logsRow, findsNothing);
    expectRetainedScroll();
    final context = tester.element(_logManager);
    expect(
      ModalRoute.of(context)!.navigator,
      Navigator.of(context, rootNavigator: true),
    );
    await _startSwipe(tester);
    await _gesture(tester, 'cancelBackGesture');
    await _settle(tester);
    expect(_logManager, findsOneWidget);
    expect(find.text('暂无日志记录'), findsOneWidget);
    expect(logsRow, findsNothing);
    expectRetainedScroll();

    void expectSameSettings() {
      expect(_logManager, findsNothing);
      expect(logsRow, findsOneWidget);
      expect(settingsScroll().position, same(position));
      expectRetainedScroll();
    }

    await _finishSwipe(tester);
    expectSameSettings();
    await _openLogs(tester);
    expect(logsRow, findsNothing);
    expectRetainedScroll();
    await _ordinaryBack(tester);
    expectSameSettings();
    expect(exporter.writes, 0);

    await _ordinaryBack(tester);
    expect(_logs, findsNothing);
    expect(find.byTooltip('设置').hitTestable(), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('实卡日志清理确认叠层先退，保留选中项且不清理或导出', (tester) async {
    final (store, exporter) = await _mountLive(tester, withLogs: true);
    await tester.tap(find.byTooltip('设置'));
    await _settle(tester);
    await _revealLogs(tester);
    await _openLogs(tester);
    await tester.tap(find.text('全选记录'));
    await _settle(tester);
    expect(find.text('取消全选'), findsOneWidget);
    final sessionsBefore = Map<String, String>.of(store.sessions);
    expect(sessionsBefore.keys, unorderedEquals(['test-first', 'test-second']));

    final clear = find.widgetWithText(TextButton, '清理所选');
    final confirmation = find.text('清理所选日志？');
    await tester.tap(clear);
    await _settle(tester);
    expect(confirmation, findsOneWidget);
    await _startSwipe(tester);
    await _gesture(tester, 'cancelBackGesture');
    await _settle(tester);
    expect(confirmation, findsOneWidget);
    await _finishSwipe(tester);
    expect(confirmation, findsNothing);
    expect(_logManager.hitTestable(), findsOneWidget);
    expect(find.text('取消全选'), findsOneWidget);

    await tester.tap(clear);
    await _settle(tester);
    expect(confirmation, findsOneWidget);
    await _ordinaryBack(tester);
    expect(confirmation, findsNothing);
    expect(_logManager, findsOneWidget);
    expect(find.text('取消全选'), findsOneWidget);
    expect(store.sessions, sessionsBefore);
    expect(exporter.writes, 0);

    await _ordinaryBack(tester);
    expect(_logManager, findsNothing);
    expect(_logs.hitTestable(), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('详情日期弹窗取消保留草稿，提交返回不应用日期且保留详情', (tester) async {
    final c = _fixture();
    c.openCard(c.current);
    final selectedId = c.selectedCardId;
    await _mountFixture(tester, c);
    await tester.tap(find.text('消费统计'));
    await _settle(tester);
    final position = tester
        .state<ScrollableState>(galleryVerticalScroll())
        .position;
    position.jumpTo(48);
    await _settle(tester);
    final pixels = position.pixels;
    final custom = find.byKey(const ValueKey('spending-period-custom'));
    await tester.tap(custom);
    await _settle(tester);
    final picker = find.byKey(const ValueKey('spending-range-dialog'));
    final month = find.byKey(const ValueKey('range-month-label'));
    final initialMonth = tester.widget<Text>(month).data;
    await tester.tap(find.byKey(const ValueKey('range-prev-month')));
    await _settle(tester);
    final draftMonth = tester.widget<Text>(month).data;
    expect(draftMonth, isNot(initialMonth));
    final day = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('range-day-');
    }).first;
    Decoration? dayDecoration() => tester
        .widget<Container>(
          find.descendant(of: day, matching: find.byType(Container)).first,
        )
        .decoration;
    final initialDecoration = dayDecoration();
    await tester.tap(day);
    await _settle(tester);
    final draftDecoration = dayDecoration();
    expect(draftDecoration, isNot(initialDecoration));

    await _startSwipe(tester);
    await _gesture(tester, 'cancelBackGesture');
    await _settle(tester);
    expect(picker, findsOneWidget);
    expect(tester.widget<Text>(month).data, draftMonth);
    expect(dayDecoration(), draftDecoration);

    await _finishSwipe(tester);
    expect(picker, findsNothing);
    expect(c.page, GalleryPage.detail);
    expect(c.selectedCardId, selectedId);
    expect(c.detailTab, 1);
    expect(find.text('全部已保留记录'), findsOneWidget);
    expect(position.pixels, closeTo(pixels, .01));
    await _ordinaryBack(tester);
    expect(c.page, GalleryPage.home);
    await _unmount(tester);
  });

  testWidgets('内层半模态、筛选菜单及中途换层共享返回优先级', (tester) async {
    final c = _fixture()
      ..hasRead = true
      ..navigate(GalleryPage.trips);
    await _mountFixture(tester, c);
    final filter = find.byKey(const ValueKey('filter-source'));
    await tester.tap(filter);
    await _settle(tester);
    expect(c.overlay, GalleryOverlay.source);
    await _finishSwipe(tester);
    expect(c.overlay, isNull);
    expect(c.source, '全部来源');
    expect(filter.hitTestable(), findsOneWidget);

    final trip = find.byKey(const ValueKey('trip-endpoints')).first;
    await tester.ensureVisible(trip);
    await _settle(tester);
    await tester.tap(trip);
    await _settle(tester);
    expect(_sheet, findsOneWidget);
    expect(c.overlay, GalleryOverlay.trip);
    final context = tester.element(_sheet);
    final sheetRoute = ModalRoute.of(context)!;
    final root = Navigator.of(context, rootNavigator: true);
    void showRoot(String label, {bool canPop = true}) {
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => PopScope(
            canPop: canPop,
            child: AlertDialog(title: Text(label)),
          ),
        ),
      );
    }

    showRoot('业务弹窗');
    await _settle(tester);
    await _finishSwipe(tester);
    expect(find.text('业务弹窗'), findsNothing);
    expect(_sheet, findsOneWidget);

    // A gesture that starts on the sheet must not pop it or a newly opened
    // root route. Its partially advanced preview is restored.
    await _startSwipe(tester);
    expect(sheetRoute.animation!.value, closeTo(.45, .01));
    showRoot('正在处理', canPop: false);
    await _settle(tester);
    await _gesture(tester, 'commitBackGesture');
    await _settle(tester);
    expect(find.text('正在处理'), findsOneWidget);
    expect(sheetRoute.animation!.value, 1);
    await _ordinaryBack(tester);
    await _finishSwipe(tester);
    expect(find.text('正在处理'), findsOneWidget);
    expect(c.overlay, GalleryOverlay.trip);
    root.pop(); // The test simulates completion of the non-cancellable flow.
    await _settle(tester);

    // If the original root dialog goes away, a late commit must not fall
    // through to the sheet, even though it is now the visible top layer.
    showRoot('将由业务关闭');
    await _settle(tester);
    await _startSwipe(tester);
    root.pop();
    await _settle(tester);
    await _gesture(tester, 'commitBackGesture');
    await _settle(tester);
    expect(_sheet, findsOneWidget);
    expect(c.overlay, GalleryOverlay.trip);
    await _ordinaryBack(tester);
    expect(_sheet, findsNothing);
    expect(c.page, GalleryPage.trips);
    await _unmount(tester);
  });

  for (final mode in ['普通返回', '预测动画', '关闭预测动画', '系统减少动效']) {
    testWidgets('$mode：先退出裁切编辑，再退更换卡面，不保存图片', (tester) async {
      final c = _fixture()..navigate(GalleryPage.cards);
      final preferences = GalleryPreferences(faceStore: _MemoryFaces());
      addTearDown(preferences.dispose);
      if (mode == '关闭预测动画') await preferences.setEnabled(false);
      if (mode == '系统减少动效') {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
      }
      await _mountFixture(tester, c, preferences: preferences);
      c.showOverlay(GalleryOverlay.face, card: c.current);
      c.beginFaceCrop(
        c.current.id,
        File('assets/icon/app_icon.png').readAsBytesSync(),
        const Size(512, 512),
      );
      await _settle(tester);
      expect(
        find.byKey(const ValueKey('face-crop-region-detail')),
        findsOneWidget,
      );
      final draft = c.faceCrop!;
      if (mode == '预测动画') {
        await _startSwipe(tester);
        await _gesture(tester, 'cancelBackGesture');
        await _settle(tester);
        expect(c.faceCrop, same(draft));
        expect(draft.editing, isTrue);
      }
      final back = mode == '普通返回' ? _ordinaryBack : _finishSwipe;
      await back(tester);
      expect(c.faceCrop, same(draft));
      expect(draft.editing, isFalse);
      expect(find.text('更换卡面'), findsOneWidget);
      expect(c.current.image, isNull);
      await back(tester);
      expect(c.overlay, isNull);
      expect(c.faceCrop, isNull);
      expect(c.current.image, isNull);
      expect(c.page, GalleryPage.cards);
      await _unmount(tester);
    });
  }
}

Future<(MemoryLogStore, _RecordingExporter)> _mountLive(
  WidgetTester tester, {
  bool withLogs = false,
}) async {
  _size(tester, const Size(412, 892));
  final store = MemoryLogStore();
  final logger = AppLogger(store: store);
  final exporter = _RecordingExporter();
  final app = AppDependencies(
    database: testDatabase(),
    bundle: MissingTestAssets(),
    settingsStore: MemorySettingsStore({SettingsKeys.monetEnabled: 'false'}),
    nfcAdapterStates: const Stream.empty(),
    logger: logger,
    logExporter: exporter,
  );
  addTearDown(app.dispose);
  final preferences = GalleryPreferences(faceStore: _MemoryFaces());
  addTearDown(preferences.dispose);
  await tester.runAsync(() => app.init().timeout(const Duration(seconds: 5)));
  await tester.pumpWidget(GalleryApp(liveApp: app, preferences: preferences));
  await _waitFor(tester, find.byTooltip('设置'));
  if (withLogs) {
    logger.enabled = true;
    logger.startSession('test-first').end(DiagnosticOutcome.success);
    logger.startSession('test-second').end(DiagnosticOutcome.success);
  }
  return (store, exporter);
}

GalleryController _fixture() {
  final c = GalleryController(
    GalleryData(
      jsonDecode(File('assets/gallery/fixtures.json').readAsStringSync())
          as GalleryRecord,
    ),
  )..monet = false;
  addTearDown(c.dispose);
  return c;
}

Future<void> _mountFixture(
  WidgetTester tester,
  GalleryController controller, {
  GalleryPreferences? preferences,
}) async {
  _size(tester, const Size(412, 1000));
  await tester.pumpWidget(
    GalleryApp(controller: controller, preferences: preferences),
  );
  await _settle(tester);
}

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _revealLogs(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    _logs,
    200,
    scrollable: galleryVerticalScroll(),
  );
  await tester.ensureVisible(_logs);
  await _settle(tester);
  expect(_logs.hitTestable(), findsOneWidget);
}

Future<void> _openLogs(WidgetTester tester) async {
  await tester.tap(_logs);
  await _waitFor(tester, _logManager);
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 50 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(finder, findsOneWidget);
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 20),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 3),
  );
  expect(tester.takeException(), isNull);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

Future<void> _ordinaryBack(WidgetTester tester) async {
  // The framework dispatches the same root Navigator.maybePop used for Android
  // button back and for commits with no predictor claiming the gesture.
  expect(await tester.binding.handlePopRoute(), isTrue);
  await _settle(tester);
}

Future<void> _startSwipe(WidgetTester tester) async {
  await _gesture(tester, 'startBackGesture');
  await _gesture(tester, 'updateBackGestureProgress', .55);
}

Future<void> _finishSwipe(WidgetTester tester) async {
  await _startSwipe(tester);
  await _gesture(tester, 'commitBackGesture');
  await _settle(tester);
}

Future<void> _gesture(
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

class _RecordingExporter implements LogExporter {
  int writes = 0;

  @override
  Future<String> saveToDownloads(String fileName, String content) async {
    writes++;
    return 'Download/$fileName';
  }
}

class _MemoryFaces implements GalleryFaceStore {
  @override
  Future<GalleryFaceSnapshot?> read(String cardId) async => null;

  @override
  Future<void> write(String cardId, GalleryFaceSnapshot snapshot) async =>
      fail('System back should not save a card face');

  @override
  Future<void> delete(String cardId) async =>
      fail('System back should not delete a card face');
}
