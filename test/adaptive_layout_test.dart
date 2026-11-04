import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/app/navigation/app_shell.dart';
import 'package:transit_card_analyzer/app/navigation/recovery_route_observer.dart';
import 'package:transit_card_analyzer/app/navigation/floating_nav_bar.dart';
import 'package:transit_card_analyzer/features/home/home_page.dart';
import 'package:transit_card_analyzer/features/cards/cards_page.dart';
import 'package:transit_card_analyzer/features/archive/presentation/card_detail_page.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_identity.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_types.dart';
import 'package:transit_card_analyzer/features/trips/trip_cards_view.dart';
import 'package:transit_card_analyzer/features/trips/trip_filters.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_presenter.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_card.dart';
import 'package:transit_card_analyzer/shared/presentation/adaptive_layout.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_service.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';

import 'support/test_database.dart';

Future<void> resize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.pump();
}

void main() {
  testWidgets('真实档案详情收窄后保留当前卡片及筛选，再展开可切换卡片', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await resize(tester, const Size(1000, 800));
    final app = AppDependencies(
      database: testDatabase(),
      logger: AppLogger(store: MemoryLogStore()),
    );
    for (final name in ['通勤卡甲', '通勤卡乙']) {
      await app.cardRepository.saveIdentity(
        fingerprint: name,
        identity: CardArchiveIdentity(
          cardType: CardTypes.chinaTunion,
          officialName: name,
        ),
        cardNumber: name == '通勤卡甲' ? '0001' : '0002',
      );
    }
    final cards = await app.cardRepository.getAllCards();
    final first = cards.singleWhere((card) => card.officialName == '通勤卡甲');
    app.recoveryFilters['card:${first.id}'] = ['mode:bus'];
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [RecoveryRouteObserver(app)],
        home: Scaffold(body: CardsPage(app: app)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('通勤卡甲'));
    await tester.pumpAndSettle();
    final detailState = tester.state(find.byType(CardDetailPage));
    expect(find.text('卡片列表'), findsOneWidget);
    await resize(tester, const Size(390, 800));
    await tester.pumpAndSettle();
    expect(find.text('卡片列表'), findsNothing);
    expect(find.text('卡片信息'), findsOneWidget);
    expect(
      identical(detailState, tester.state(find.byType(CardDetailPage))),
      isTrue,
    );
    expect(app.recoveryFilters['card:${first.id}'], ['mode:bus']);
    await resize(tester, const Size(1000, 800));
    await tester.pumpAndSettle();
    await tester.tap(find.text('通勤卡乙'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CardDetailPage>(find.byType(CardDetailPage)).cardId,
      cards.singleWhere((card) => card.officialName == '通勤卡乙').id,
    );
    final expectedRoute = app.recoveryRoute;
    await tester.tap(find.byTooltip('自定义名称'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(app.recoveryRoute, expectedRoute);
    expect(
      app.recoveryRoute,
      '/card/${Uri.encodeComponent(cards.singleWhere((card) => card.officialName == '通勤卡乙').id)}',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets('行程筛选在单双窗格切换后保留', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await resize(tester, const Size(1000, 800));
    final filters = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveListDetail(
          hasSelection: true,
          list: const SizedBox(),
          detail: Material(
            child: SingleChildScrollView(
              child: TripCardsView<TripSourceFilter>(
                summaryText: '两条记录',
                sourceLabels: tripSourceLabels,
                onFiltersChanged: (values) {
                  filters
                    ..clear()
                    ..addAll(values);
                },
                entries: const [
                  TripCardPresentation(
                    info: TripEntryInfo(
                      sourceLabel: '公交',
                      title: '公交行程',
                      isConsume: true,
                    ),
                    source: TripSourceFilter.transaction,
                    mode: TripModeFilter.bus,
                    dateText: '',
                    remote: false,
                  ),
                  TripCardPresentation(
                    info: TripEntryInfo(
                      sourceLabel: '地铁',
                      title: '地铁行程',
                      isConsume: true,
                    ),
                    source: TripSourceFilter.transaction,
                    mode: TripModeFilter.rail,
                    dateText: '',
                    remote: false,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部方式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('公共汽电车').last);
    await tester.pumpAndSettle();
    expect(filters, ['mode:bus']);
    for (final size in [const Size(390, 800), const Size(1000, 800)]) {
      await resize(tester, size);
      await tester.pumpAndSettle();
      expect(filters, ['mode:bus']);
      expect(find.byType(TripEntryCard), findsOneWidget);
      expect(
        tester.widget<TripEntryCard>(find.byType(TripEntryCard)).info.title,
        '公交行程',
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('导航跨600dp与矮横窗切换保留页面和等待中的NFC', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await resize(tester, const Size(390, 800));
    final nfc = _WaitingNfc();
    final app = AppDependencies(
      database: testDatabase(),
      bundle: MissingTestAssets(),
      channel: nfc,
      settingsStore: MemorySettingsStore(),
      logger: AppLogger(store: MemoryLogStore()),
    );
    await tester.runAsync(app.init);
    await tester.pumpWidget(MaterialApp(home: AppShell(app: app)));
    await tester.pump(const Duration(milliseconds: 100));
    final homeState = tester.state(find.byType(HomePage));
    expect(nfc.scans, 1);
    for (final size in [
      const Size(599, 800),
      const Size(600, 800),
      const Size(840, 800),
      const Size(1200, 900),
      const Size(900, 400),
      const Size(390, 800),
    ]) {
      await resize(tester, size);
      await tester.pump(const Duration(milliseconds: 250));
      final rail = size.width >= 600 && size.height >= 480;
      expect(find.byType(NavigationRail), rail ? findsOneWidget : findsNothing);
      expect(find.byType(FloatingNavBar), rail ? findsNothing : findsOneWidget);
      expect(identical(homeState, tester.state(find.byType(HomePage))), isTrue);
      expect(nfc.scans, 1);
      expect(nfc.stops, 0);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    app.dispose();
    nfc.discovery.complete(null);
    await tester.pump();
  });

  testWidgets('列表详情缩放保留选择、输入及滚动，系统返回先退出详情', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await resize(tester, const Size(1000, 800));
    final input = TextEditingController();
    final scroll = ScrollController();
    var backs = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveListDetail(
          hasSelection: true,
          onBackToList: () => backs++,
          list: const Material(child: Text('列表窗格')),
          detail: Material(
            child: ListView(
              controller: scroll,
              children: [
                TextField(controller: input),
                for (var i = 0; i < 60; i++)
                  SizedBox(height: 40, child: Text('记录$i')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '选中卡片的备注');
    scroll.jumpTo(280);
    await tester.pump();
    for (final size in [const Size(390, 800), const Size(1000, 800)]) {
      await resize(tester, size);
      expect(input.text, '选中卡片的备注');
      expect(scroll.offset, 280);
      expect(
        find.text('列表窗格'),
        size.width < 840 ? findsNothing : findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
    await resize(tester, const Size(390, 800));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(backs, 1);
    await tester.pumpWidget(const SizedBox());
    input.dispose();
    scroll.dispose();
  });

  for (final horizontal in [false, true]) {
    testWidgets('半折${horizontal ? '桌面' : '书本'}窗格避开折痕', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await resize(tester, const Size(1000, 800));
      final hinge = horizontal
          ? const Rect.fromLTWH(0, 390, 1000, 20)
          : const Rect.fromLTWH(490, 0, 20, 800);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(1000, 800),
              displayFeatures: [
                ui.DisplayFeature(
                  bounds: hinge,
                  type: ui.DisplayFeatureType.fold,
                  state: ui.DisplayFeatureState.postureHalfOpened,
                ),
              ],
            ),
            child: const AdaptiveListDetail(
              hasSelection: true,
              list: ColoredBox(
                key: ValueKey('list-content'),
                color: Colors.blue,
                child: Text('列表'),
              ),
              detail: ColoredBox(
                key: ValueKey('detail-content'),
                color: Colors.green,
                child: Text('详情'),
              ),
            ),
          ),
        ),
      );
      final detail = tester.getRect(
        find.byKey(const ValueKey('detail-content')),
      );
      expect(detail.overlaps(hinge), isFalse);
      if (!horizontal) {
        expect(detail.left, 510);
        expect(
          tester.getRect(find.byKey(const ValueKey('list-content'))).right,
          490,
        );
      } else {
        expect(detail.bottom, 390);
      }
      expect(tester.takeException(), isNull);
    });
  }
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
