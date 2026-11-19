import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/app/navigation/app_shell.dart';
import 'package:transit_card_analyzer/app/navigation/floating_nav_bar.dart';
import 'package:transit_card_analyzer/features/settings/presentation/settings_page.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';

import 'support/test_database.dart';

class _NavigationApp extends AppDependencies {
  _NavigationApp()
    : super(
        database: testDatabase(),
        bundle: MissingTestAssets(),
        settingsStore: MemorySettingsStore(),
        logger: AppLogger(store: MemoryLogStore()),
      );

  final events = <String>[];
  Completer<void>? closeGate;

  @override
  bool get autoScanConsumed => true;

  // AppDependencies.stop invalidates operations synchronously, while physical
  // NFC close can finish later. Navigation must invoke that boundary at once.
  @override
  Future<void> stop() {
    events.add('stop');
    return closeGate?.future ?? Future.value();
  }
}

class _RouteEvents extends NavigatorObserver {
  _RouteEvents(this.events);
  final List<String> events;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name == '/settings') events.add('settings');
  }
}

Future<_NavigationApp> _showTrips(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final app = _NavigationApp()..recoveryTab = 1;
  addTearDown(app.dispose);
  await tester.runAsync(app.init);
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [_RouteEvents(app.events)],
      home: AppShell(app: app),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.widget<FloatingNavBar>(find.byType(FloatingNavBar)).index, 1);
  // The initial restoration can deactivate Home. Exercise subsequent
  // navigation from Trips, where HomePage's lifecycle cannot cancel for us.
  app.events.clear();
  return app;
}

Finder _navIcon(IconData icon) => find.descendant(
  of: find.byType(FloatingNavBar),
  matching: find.byIcon(icon),
);

void main() {
  testWidgets('行程切换其他标签时立即停止，不等待 NFC 关闭完成', (tester) async {
    final app = await _showTrips(tester);
    final close = app.closeGate = Completer<void>();
    try {
      await tester.tap(_navIcon(Icons.science_outlined));
      // No pump: the navigation event itself must invalidate the operation.
      expect(app.events, ['stop']);
      expect(close.isCompleted, isFalse);

      await tester.pumpAndSettle();
      expect(
        tester.widget<FloatingNavBar>(find.byType(FloatingNavBar)).index,
        3,
      );
      expect(app.events, ['stop']);
      expect(tester.takeException(), isNull);
    } finally {
      close.complete();
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('重复点击当前行程标签不停止当前操作', (tester) async {
    final app = await _showTrips(tester);

    await tester.tap(_navIcon(Icons.directions_transit_outlined));
    await tester.pumpAndSettle();
    expect(app.events, isEmpty);
    expect(tester.widget<FloatingNavBar>(find.byType(FloatingNavBar)).index, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('行程通过返回操作切回首页时立即停止', (tester) async {
    final app = await _showTrips(tester);

    await tester.binding.handlePopRoute();
    expect(app.events, ['stop']);
    await tester.pumpAndSettle();
    expect(tester.widget<FloatingNavBar>(find.byType(FloatingNavBar)).index, 0);
    expect(app.events, ['stop']);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('行程进入设置前立即停止，设置展示不等待 NFC 关闭', (tester) async {
    final app = await _showTrips(tester);
    final close = app.closeGate = Completer<void>();
    try {
      await tester.tap(find.byTooltip('设置'));
      expect(app.events, ['stop', 'settings']);
      expect(close.isCompleted, isFalse);

      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(app.events, ['stop', 'settings']);
      expect(tester.takeException(), isNull);
    } finally {
      close.complete();
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
