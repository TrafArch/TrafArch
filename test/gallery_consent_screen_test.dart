import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/legal_consent_gate.dart';
import 'package:transit_card_analyzer/gallery/gallery_consent_screen.dart';
import 'package:transit_card_analyzer/gallery/gallery_design.dart';
import 'package:transit_card_analyzer/gallery/gallery_theme.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/shared/app_support.dart';

const _home = Key('protected-home');

Widget _gate(SettingsStore store, {bool gallery = true}) => LegalConsentGate(
  settingsStore: store,
  screenBuilder: gallery ? GalleryConsentScreen.new : null,
  child: const SizedBox(key: _home),
);

void main() {
  const analytics = MethodChannel('transit_card_analyzer/analytics');
  final messenger =
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
  setUp(() {
    messenger.setMockMethodCallHandler(
      analytics,
      (call) async => call.method == 'isAvailable' ? true : null,
    );
  });
  tearDown(() => messenger.setMockMethodCallHandler(analytics, null));
  for (final brightness in Brightness.values) {
    testWidgets('2.x $brightness：窄窗大字下使用主题模态表面、可滚动按钮和减少动画', (tester) async {
      final dispatcher = tester.platformDispatcher;
      dispatcher.platformBrightnessTestValue = brightness;
      dispatcher.textScaleFactorTestValue = 2;
      dispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(dispatcher.clearPlatformBrightnessTestValue);
      addTearDown(dispatcher.clearTextScaleFactorTestValue);
      addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 420);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 28);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_gate(MemorySettingsStore()));
      await tester.pump();
      final title = find.text(LegalConsentPrompt.title);
      final tokens = Theme.of(tester.element(title))
          .extension<GalleryTokens>()!;
      expect(tokens.scheme.brightness, brightness);
      expect(
        tester.widget<Text>(title).style?.fontSize,
        GalleryTypography.section.fontSize,
      );
      final surface = tester
          .widgetList<Material>(
            find.ancestor(of: title, matching: find.byType(Material)),
          )
          .first;
      expect(surface.color, tokens.surface);
      expect(
        (surface.shape! as RoundedRectangleBorder).side.color,
        tokens.line,
      );
      final frame = find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).boxShadow?.last.blurRadius ==
                48,
      );
      expect(frame, findsOneWidget);
      final rect = tester.getRect(frame);
      expect(rect.top, greaterThanOrEqualTo(24));
      expect(rect.bottom, lessThanOrEqualTo(420 - 28));
      expect(
        tester
            .widgetList<ScaleTransition>(
              find.ancestor(of: title, matching: find.byType(ScaleTransition)),
            )
            .first
            .scale
            .value,
        1,
      );
      for (final label in [AppSupport.eulaLabel, '隐私政策', '不同意并退出', '同意并继续']) {
        final button = find.text(label);
        await tester.ensureVisible(button);
        expect(button.hitTestable(), findsOneWidget);
      }
      await tester.tap(find.text('同意并继续'));
      await tester.pump();
      expect(find.byKey(_home), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('2.x 两份全文复用浏览器、失败时显示悬浮提示，拒绝和返回均不写入', (tester) async {
    final store = MemorySettingsStore();
    const channel = MethodChannel('transit_card_analyzer/browser');
    final messenger = tester.binding.defaultBinaryMessenger;
    final urls = <String>[];
    String? copied;
    var exits = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'openCustomTab');
      urls.add((call.arguments as Map)['url'] as String);
      return urls.length == 1 ? 'default_browser' : null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.pop') exits++;
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
    await tester.pumpWidget(_gate(store));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppSupport.eulaLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('隐私政策'));
    await tester.pumpAndSettle();
    expect(urls, [AppSupport.eula, AppSupport.privacy]);
    expect(copied, AppSupport.privacy);
    expect(find.text('链接已复制到剪贴板，请前往浏览器打开'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    final beforeDecline = exits;
    await tester.tap(find.text('不同意并退出'));
    expect(exits, beforeDecline + 1);
    expect(store.values, isEmpty);
    expect(find.byKey(_home), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('2.x 保存成功后退出弹窗，1.x 与 2.x 共用同意记录', (tester) async {
    final store = _PendingConsentStore();
    await tester.pumpWidget(_gate(store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同意并继续'));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(find.byKey(_home), findsNothing);
    store.pending.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    expect(find.byKey(_home), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byKey(_home), findsOneWidget);
    for (final gallery in [false, true]) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_gate(store, gallery: gallery));
      await tester.pumpAndSettle();
      expect(find.byKey(_home), findsOneWidget);
      expect(find.text(LegalConsentPrompt.title), findsNothing);
    }
  });
}

class _PendingConsentStore extends MemorySettingsStore {
  final pending = Completer<void>();
  @override
  Future<void> write(String key, String value) async {
    await pending.future;
    await super.write(key, value);
  }
}
