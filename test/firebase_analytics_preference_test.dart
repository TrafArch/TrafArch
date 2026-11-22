import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/app/legal_consent_gate.dart';
import 'package:transit_card_analyzer/features/settings/presentation/settings_page.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_consent_screen.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';

import 'support/gallery_scroll.dart';
import 'support/test_database.dart';

void main() {
  const channel = MethodChannel('transit_card_analyzer/analytics');
  final messenger =
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
  final changes = <bool>[];
  var available = true;
  var failEnabling = false;
  final tile = find.widgetWithText(SwitchListTile, 'Firebase 分析');

  setUp(() {
    changes.clear();
    available = true;
    failEnabling = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'isAvailable') return available;
      expect(call.method, 'setCollectionEnabled');
      final enabled = call.arguments as bool;
      if (enabled && failEnabling) throw PlatformException(code: 'UNAVAILABLE');
      changes.add(enabled);
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('预选开启不等于采集；拒绝、取消选择或保存失败都不会启用 SDK', (tester) async {
    final store = _WriteFailingStore();
    await tester.pumpWidget(
      LegalConsentGate(settingsStore: store, child: const SizedBox()),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    expect(changes, [false]);
    await tester.tap(find.text('不同意并退出'));
    await tester.pumpAndSettle();
    expect(changes, [false]);
    expect(store.values, isEmpty);
    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();
    expect(changes, [false]);
    expect(find.text('未能保存同意记录，请重试。'), findsOneWidget);
    store.fail = false;
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(store.values, isEmpty);
    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();
    expect(changes, [false, false]);
  });

  testWidgets('旧同意记录不自动授权分析，两个设置页可切换且重启保留', (tester) async {
    final store = MemorySettingsStore({SettingsKeys.legalConsent: 'true'});
    final app = AppDependencies(database: testDatabase(), settingsStore: store);
    addTearDown(app.dispose);
    final gallery = GalleryController(
      GalleryData(
        jsonDecode(File('assets/gallery/fixtures.json').readAsStringSync())
            as GalleryRecord,
      ),
    );
    addTearDown(gallery.dispose);
    gallery.navigate(GalleryPage.settings);
    Future<void> start({required bool preview}) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        LegalConsentGate(
          settingsStore: store,
          screenBuilder: preview ? GalleryConsentScreen.new : null,
          child: preview
              ? GalleryApp(controller: gallery)
              : MaterialApp(home: SettingsPage(app: app)),
        ),
      );
      await tester.pumpAndSettle();
    }

    await start(preview: true);
    expect(changes, [false]);
    final analyticsIcon = find.descendant(
      of: tile,
      matching: find.byIcon(Icons.analytics_outlined),
    );
    expect(analyticsIcon, findsNothing);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();
    expect(changes, [false, true]);
    await tester.scrollUntilVisible(
      tile,
      180,
      scrollable: galleryVerticalScroll(),
    );
    await tester.pumpAndSettle();
    expect(analyticsIcon, findsOneWidget);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(changes.last, isFalse);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    await start(preview: false);
    expect(find.text(LegalConsentPrompt.title), findsNothing);
    expect(changes.last, isFalse);
    await tester.scrollUntilVisible(tile, 160);
    await tester.pumpAndSettle();
    expect(analyticsIcon, findsOneWidget);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    failEnabling = true;
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    expect(find.text('未能更新 Firebase 分析，请重试。'), findsOneWidget);
    expect(store.values[SettingsKeys.legalConsent], 'v2:analytics-off');
    failEnabling = false;
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(changes.last, isTrue);
    await start(preview: true);
    expect(changes.last, isTrue);
    expect(find.text(LegalConsentPrompt.title), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('未配置 Firebase 的构建显示不可用，不尝试采集也不阻塞使用', (tester) async {
    available = false;
    final store = MemorySettingsStore();
    const home = Key('home');
    await tester.pumpWidget(
      LegalConsentGate(
        settingsStore: store,
        child: const SizedBox(key: home),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(tile).onChanged, isNull);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(find.byKey(home), findsOneWidget);
  });
}

class _WriteFailingStore extends MemorySettingsStore {
  bool fail = true;
  @override
  Future<void> write(String key, String value) async {
    if (fail) throw StateError('write failed');
    await super.write(key, value);
  }
}
