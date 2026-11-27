import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/legal_consent_gate.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/shared/app_support.dart';

void main() {
  const browser = MethodChannel('transit_card_analyzer/browser');
  const home = Key('protected-app');
  final messenger =
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
  const analytics = MethodChannel('transit_card_analyzer/analytics');
  setUp(() {
    messenger.setMockMethodCallHandler(
      analytics,
      (call) async => call.method == 'isAvailable' ? true : null,
    );
  });

  Widget gate(SettingsStore store) => LegalConsentGate(
    settingsStore: store,
    child: const SizedBox(key: home),
  );

  tearDown(() {
    messenger.setMockMethodCallHandler(analytics, null);
    messenger.setMockMethodCallHandler(browser, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('首次使用可以阅读两份全文；关闭网页、点按遮罩、返回和拒绝都不视为同意', (tester) async {
    final store = MemorySettingsStore();
    final opened = <String>[];
    final copied = <String>[];
    var exits = 0;
    messenger.setMockMethodCallHandler(browser, (call) async {
      expect(call.method, 'openCustomTab');
      opened.add((call.arguments as Map)['url'] as String);
      return opened.length == 1 ? 'default_browser' : null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.pop') exits++;
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    await tester.pumpWidget(gate(store));
    await tester.pumpAndSettle();
    expect(find.text(LegalConsentPrompt.title), findsOneWidget);
    await tester.tap(find.text(AppSupport.eulaLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('隐私政策'));
    await tester.pumpAndSettle();
    expect(opened, [
      'https://www.trafarch.top/eula.html',
      'https://www.trafarch.top/privacy.html',
    ]);
    expect(copied, [AppSupport.privacy]);
    expect(find.text('链接已复制到剪贴板，请前往浏览器打开'), findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    final exitsBeforeDecline = exits;
    await tester.tap(find.text('不同意并退出'));
    await tester.pumpAndSettle();
    expect(exits, exitsBeforeDecline + 1);
    expect(find.byKey(home), findsNothing);
    expect(store.values, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(gate(store));
    await tester.pumpAndSettle();
    expect(find.text(LegalConsentPrompt.title), findsOneWidget);
  });

  testWidgets('同意记录写入成功才启动，重新启动后不再询问', (tester) async {
    final store = _DelayedStore();
    await tester.pumpWidget(gate(store));
    expect(find.byKey(home), findsNothing);
    await tester.pumpAndSettle();
    await tester.tap(find.text('同意并继续'));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(find.byKey(home), findsNothing);
    store.allowWrite.complete();
    await tester.pumpAndSettle();
    expect(store.values[SettingsKeys.legalConsent], 'v2:analytics-on');
    expect(find.byKey(home), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(gate(store));
    await tester.pumpAndSettle();
    expect(find.byKey(home), findsOneWidget);
    expect(find.text(LegalConsentPrompt.title), findsNothing);
  });

  testWidgets('无法读取或保存时不会放行，保存失败后可以重试', (tester) async {
    final store = _FailingStore();
    await tester.pumpWidget(gate(store));
    await tester.pumpAndSettle();
    expect(find.text('无法读取同意记录，请重新确认。'), findsOneWidget);
    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();
    expect(find.text('未能保存同意记录，请重试。'), findsOneWidget);
    expect(find.byKey(home), findsNothing);
    store.failWrites = false;
    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();
    expect(find.byKey(home), findsOneWidget);
  });
}

class _DelayedStore extends MemorySettingsStore {
  final allowWrite = Completer<void>();

  @override
  Future<void> write(String key, String value) async {
    await allowWrite.future;
    await super.write(key, value);
  }
}

class _FailingStore extends MemorySettingsStore {
  bool failWrites = true;

  @override
  Future<String?> read(String key) async => throw StateError('read failed');

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('write failed');
    await super.write(key, value);
  }
}
