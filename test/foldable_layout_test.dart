import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/app/navigation/floating_nav_bar.dart';
import 'package:transit_card_analyzer/app/trafarch_app.dart';
import 'package:transit_card_analyzer/features/home/home_page.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_details.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_presenter.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_service.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/shared/presentation/adaptive_layout.dart';

import 'support/test_database.dart';

const _states = [
  ui.DisplayFeatureState.unknown,
  ui.DisplayFeatureState.postureFlat,
  ui.DisplayFeatureState.postureHalfOpened,
];

AppDependencies _app(NfcChannel channel) => AppDependencies(
  database: testDatabase(),
  bundle: MissingTestAssets(),
  channel: channel,
  settingsStore: MemorySettingsStore(),
  logger: AppLogger(store: MemoryLogStore()),
);

void main() {
  for (final horizontal in [false, true]) {
    testWidgets('完整页面忽略${horizontal ? '横向' : '竖向'}折痕及半折姿态，保留完整窗口和安全区', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 800);
      const insets = EdgeInsets.fromLTRB(24, 32, 16, 48);
      MediaQueryData? pageMedia;
      for (final state in _states) {
        // Some devices report a non-zero crease even though it covers no pixels.
        for (final thickness in [0.0, 20.0]) {
          final crease = horizontal
              ? Rect.fromLTWH(0, 390, 1000, thickness)
              : Rect.fromLTWH(490, 0, thickness, 800);
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: const Size(1000, 800),
                  padding: insets,
                  viewPadding: insets,
                  displayFeatures: [
                    ui.DisplayFeature(
                      bounds: crease,
                      type: ui.DisplayFeatureType.fold,
                      state: state,
                    ),
                  ],
                ),
                child: FoldSafePage(
                  child: Builder(
                    builder: (context) {
                      pageMedia = MediaQuery.of(context);
                      return const SizedBox.expand(key: ValueKey('whole-page'));
                    },
                  ),
                ),
              ),
            ),
          );
          expect(
            tester.getRect(find.byKey(const ValueKey('whole-page'))),
            const Rect.fromLTWH(0, 0, 1000, 800),
          );
          expect(pageMedia!.size, const Size(1000, 800));
          expect(pageMedia!.padding, insets);
          expect(pageMedia!.displayFeatures, isEmpty);
          expect(tester.takeException(), isNull);
        }
      }
    });
  }

  testWidgets('列表详情只按窗口宽度切换，折痕方向及半折姿态不改变分栏', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    for (final width in [700.0, 1000.0]) {
      tester.view.physicalSize = Size(width, 800);
      for (final horizontal in [false, true]) {
        for (final state in _states) {
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 800),
                  displayFeatures: [
                    ui.DisplayFeature(
                      bounds: horizontal
                          ? Rect.fromLTWH(0, 390, width, 20)
                          : Rect.fromLTWH(width / 2, 0, 20, 800),
                      type: ui.DisplayFeatureType.fold,
                      state: state,
                    ),
                  ],
                ),
                child: const AdaptiveListDetail(
                  hasSelection: true,
                  list: SizedBox.expand(key: ValueKey('list-pane')),
                  detail: SizedBox.expand(key: ValueKey('detail-pane')),
                ),
              ),
            ),
          );
          final detail = tester.getRect(
            find.byKey(const ValueKey('detail-pane')),
          );
          expect(detail.top, 0);
          expect(detail.bottom, 800);
          expect(detail.right, width);
          expect(detail.left, width < 840 ? 0 : 361);
          expect(
            find.byKey(const ValueKey('list-pane')),
            width < 840 ? findsNothing : findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

  testWidgets('折叠与展开保留页面和NFC，半折信号不移动悬浮导航、对话框及详情弹层', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.padding = const FakeViewPadding(top: 32, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 32, bottom: 24);
    final nfc = _WaitingNfc();
    final app = _app(nfc);
    // NFC remains pending, so the scan indicator continuously schedules frames.
    Future<void> settleLayout() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
    }

    await tester.runAsync(app.init);
    await tester.pumpWidget(
      TransitCardAnalyzerApp(createDependencies: () => app),
    );
    await settleLayout();
    final homeState = tester.state(find.byType(HomePage));
    for (final size in [
      const Size(1000, 800),
      const Size(390, 844),
      const Size(1000, 800),
    ]) {
      tester.view.physicalSize = size;
      await settleLayout();
      expect(identical(homeState, tester.state(find.byType(HomePage))), isTrue);
      expect(nfc.scans, 1);
      expect(nfc.stops, 0);
    }
    for (final horizontal in [false, true]) {
      Rect? navigationRect;
      Rect? dialogRect;
      Rect? sheetRect;
      for (final state in _states) {
        tester.view.displayFeatures = [
          ui.DisplayFeature(
            bounds: horizontal
                ? const Rect.fromLTWH(0, 400, 1000, 0)
                : const Rect.fromLTWH(500, 0, 0, 800),
            type: ui.DisplayFeatureType.fold,
            state: state,
          ),
        ];
        await settleLayout();
        expect(
          identical(homeState, tester.state(find.byType(HomePage))),
          isTrue,
        );
        final bar = tester.getRect(find.byType(FloatingNavBar));
        navigationRect ??= bar;
        expect(bar, navigationRect);
        expect(bar.center.dx, 500);
        expect(bar.bottom, 756);
        final context = tester.element(find.byType(AppShell));
        final dialog = showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(title: Text('折叠屏回归')),
        );
        await settleLayout();
        final bounds = tester.getRect(find.byType(Dialog));
        dialogRect ??= bounds;
        expect(bounds, dialogRect);
        expect(bounds.center.dx, 500);
        Navigator.of(context).pop();
        await settleLayout();
        await dialog;
        showTripEntryDetails(
          context,
          const TripEntryInfo(
            sourceLabel: '测试',
            title: '记录详情',
            isConsume: true,
          ),
        );
        await settleLayout();
        final sheet = tester.getRect(find.byType(BottomSheet));
        sheetRect ??= sheet;
        expect(sheet, sheetRect);
        expect(sheet.center.dx, 500);
        expect(sheet.bottom, 800);
        Navigator.of(context).pop();
        await settleLayout();
        expect(tester.takeException(), isNull);
      }
    }
    expect(nfc.scans, 1);
    expect(nfc.stops, 0);
    await tester.pumpWidget(const SizedBox());
    nfc.discovery.complete(null);
    await tester.pump();
  });
}

class _WaitingNfc implements NfcChannel {
  final discovery = Completer<NfcScanResult?>();
  int scans = 0;
  int stops = 0;

  @override
  Future<NfcScanResult?> scanOnce() {
    scans++;
    return discovery.future;
  }

  @override
  Future<void> stopScan() async {
    stops++;
  }

  @override
  Future<List<int>> transceive(List<int> apdu) async => const [0x6a, 0x82];
}
