import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/app/beta_ui_scope.dart';
import 'package:transit_card_analyzer/app/internal_preview_app.dart';
import 'package:transit_card_analyzer/app/theme/app_theme.dart';
import 'package:transit_card_analyzer/app/trafarch_app.dart';
import 'package:transit_card_analyzer/features/settings/presentation/settings_page.dart';
import 'package:transit_card_analyzer/features/updates/update_prompt.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_service.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';

import 'support/test_database.dart';
import 'support/gallery_scroll.dart';

AppDependencies createTestApp() => AppDependencies(
  database: testDatabase(),
  bundle: MissingTestAssets(),
  settingsStore: MemorySettingsStore(),
  logger: AppLogger(store: MemoryLogStore()),
  channel: _NoopNfcChannel(),
);

final _betaSwitch = find.widgetWithText(SwitchListTile, '启用新界面（beta）');
final _warning = find.byType(AlertDialog);
final _decline = find.widgetWithText(TextButton, '不开启');
final _confirm = find.widgetWithText(FilledButton, '确认开启');

void _expectCountdown(WidgetTester tester, int seconds) {
  final button = find.widgetWithText(FilledButton, '确认开启（$seconds 秒）');
  expect(tester.widget<FilledButton>(button).onPressed, isNull);
}

void main() {
  testWidgets('current settings hides beta switch outside internal host', (
    tester,
  ) async {
    final app = createTestApp();
    addTearDown(app.dispose);
    await tester.pumpWidget(MaterialApp(home: SettingsPage(app: app)));
    await tester.scrollUntilVisible(find.text('莫奈取色'), 250);
    expect(_betaSwitch, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('preview requires explicit confirmation after ten seconds', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var created = 0;
    await tester.pumpWidget(
      InternalPreviewApp(
        previewSettingsStore: MemorySettingsStore(),
        createDependencies: () {
          created++;
          return createTestApp();
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TransitCardAnalyzerApp), findsOneWidget);
    expect(find.byType(UpdatePrompt), findsNothing);

    Future<void> openBetaSettings() async {
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        _betaSwitch,
        250,
        scrollable: galleryVerticalScroll(),
      );
      await tester.pumpAndSettle();
    }

    await openBetaSettings();
    await tester.tap(_betaSwitch);
    await tester.pump();
    expect(_warning, findsOneWidget);
    expect(tester.widget<SwitchListTile>(_betaSwitch).value, isFalse);
    _expectCountdown(tester, 10);
    await tester.pump(const Duration(milliseconds: 9999));
    _expectCountdown(tester, 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.widget<FilledButton>(_confirm).onPressed, isNotNull);
    expect(tester.widget<SwitchListTile>(_betaSwitch).value, isFalse);
    expect(find.byType(GalleryApp), findsNothing);

    await tester.tap(_confirm);
    await tester.pumpAndSettle();
    expect(find.byType(GalleryApp), findsOneWidget);
    expect(find.byType(TransitCardAnalyzerApp), findsNothing);
    expect(created, 1);

    await openBetaSettings();
    expect(tester.widget<SwitchListTile>(_betaSwitch).value, isTrue);
    await tester.tap(_betaSwitch);
    await tester.pumpAndSettle();
    expect(find.byType(TransitCardAnalyzerApp), findsOneWidget);
    expect(find.byType(GalleryApp), findsNothing);
    expect(_warning, findsNothing);
    expect(created, 2);

    await openBetaSettings();
    await tester.tap(_betaSwitch);
    await tester.pumpAndSettle();
    expect(_warning, findsOneWidget);
    _expectCountdown(tester, 10);
    await tester.tap(_decline);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'red warning highlights preview data and can always be declined',
    (tester) async {
      tester.view.physicalSize = const Size(320, 560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = createTestApp();
      addTearDown(app.dispose);
      final changes = <bool>[];
      final theme = AppTheme.dark(null);
      await tester.pumpWidget(
        BetaUiScope(
          enabled: false,
          onChanged: changes.add,
          child: MaterialApp(
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: SettingsPage(app: app),
          ),
        ),
      );
      await tester.scrollUntilVisible(_betaSwitch, 250);
      await tester.pumpAndSettle();
      expect(_betaSwitch.hitTestable(), findsOneWidget);

      Future<void> attempt() async {
        await tester.tap(_betaSwitch);
        await tester.pumpAndSettle();
        expect(_warning, findsOneWidget);
        _expectCountdown(tester, 10);
      }

      await attempt();
      expect(
        tester.widget<AlertDialog>(_warning).backgroundColor,
        theme.colorScheme.errorContainer,
      );
      final copy =
          tester
                  .widget<Text>(
                    find.descendant(
                      of: _warning,
                      matching: find.textContaining('模拟数据'),
                    ),
                  )
                  .textSpan!
              as TextSpan;
      expect(
        copy.children!
            .whereType<TextSpan>()
            .where((span) => span.style?.fontWeight == FontWeight.bold)
            .map((span) => span.text),
        containsAll(['UI预览', '模拟数据']),
      );
      expect(copy.toPlainText(), contains('不会读取实体卡，也不会写入真实档案'));
      expect(tester.widget<TextButton>(_decline).onPressed, isNotNull);
      await tester.tap(_decline);
      await tester.pumpAndSettle();
      expect(_warning, findsNothing);
      expect(changes, isEmpty);

      await attempt();
      await tester.pump(const Duration(seconds: 5));
      _expectCountdown(tester, 5);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_warning, findsNothing);
      expect(changes, isEmpty);

      await attempt();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(changes, isEmpty);
    },
  );

  testWidgets(
    'preview return preference survives UI switching and host recreation',
    (tester) async {
      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemorySettingsStore();
      Future<void> enterPreview() async {
        final scope = BetaUiScope.maybeOf(
          tester.element(find.byType(TransitCardAnalyzerApp)),
        )!;
        scope.onChanged(true);
        await tester.pumpAndSettle();
      }

      Future<void> openSettings() async {
        await tester.tap(find.byTooltip('设置'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('预测性返回手势'),
          250,
          scrollable: galleryVerticalScroll(),
        );
        await tester.pumpAndSettle();
      }

      Finder toggle() => find.widgetWithText(SwitchListTile, '预测性返回手势');
      await tester.pumpWidget(
        InternalPreviewApp(
          createDependencies: createTestApp,
          previewSettingsStore: store,
        ),
      );
      await tester.pumpAndSettle();
      await enterPreview();
      await openSettings();
      expect(tester.widget<SwitchListTile>(toggle()).value, isTrue);
      await tester.tap(toggle());
      await tester.pumpAndSettle();
      expect(store.values[SettingsKeys.galleryPredictiveBackEnabled], 'false');
      expect(tester.widget<SwitchListTile>(toggle()).value, isFalse);
      BetaUiScope.maybeOf(tester.element(find.byType(GalleryApp)))!
          .onChanged(false);
      await tester.pumpAndSettle();
      await enterPreview();
      await openSettings();
      expect(tester.widget<SwitchListTile>(toggle()).value, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(
        InternalPreviewApp(
          createDependencies: createTestApp,
          previewSettingsStore: store,
        ),
      );
      await tester.pumpAndSettle();
      await enterPreview();
      await openSettings();
      expect(tester.widget<SwitchListTile>(toggle()).value, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}

class _NoopNfcChannel implements NfcChannel {
  @override
  Future<NfcScanResult?> scanOnce() async => null;
  @override
  Future<void> stopScan() async {}
  @override
  Future<List<int>> transceive(List<int> apdu) async => const [0x6a, 0x82];
}
