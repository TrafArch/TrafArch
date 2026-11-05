import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/settings/presentation/settings_page.dart';
import 'package:transit_card_analyzer/features/settings/presentation/diagnostic_export_dialog.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/log_exporter.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/shared/diagnostics/diagnostic_event.dart';

import 'support/test_database.dart';

void main() {
  for (final size in const [
    Size(360, 400),
    Size(320, 480),
    Size(280, 400),
    Size(240, 320),
    Size(600, 320),
  ]) {
    testWidgets('日志管理器在 $size 可滚动选择并导出，缩窗保留选择', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final logger = AppLogger(store: MemoryLogStore())..enabled = true;
      logger.startSession('finished').end(DiagnosticOutcome.success);
      final exporter = _Exporter();
      final app = AppDependencies(
        database: testDatabase(),
        bundle: MissingTestAssets(),
        settingsStore: MemorySettingsStore(),
        logger: logger,
        logExporter: exporter,
      );
      addTearDown(app.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDiagnosticExportDialog(context, app),
                child: const Text('打开日志'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开日志'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final row = find.byType(CheckboxListTile);
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(row).value, isFalse);
      final export = find.widgetWithText(FilledButton, '导出');
      expect(tester.widget<FilledButton>(export).onPressed, isNull);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(row).value, isFalse);
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(export.hitTestable(), findsOneWidget);
      await tester.tap(export);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        (jsonDecode(exporter.content!)['sessions'] as List).single['sessionId'],
        'finished',
      );
    });
  }

  testWidgets('原导出按钮改名日志管理器且开关关闭也可管理导出已有记录', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final logger = AppLogger(store: MemoryLogStore())..enabled = true;
    logger.startSession('finished').end(DiagnosticOutcome.success);
    logger
        .startSession(
          'application-old',
          kind: DiagnosticSessionKind.application,
        )
        .end(DiagnosticOutcome.success);
    logger.enabled = false;
    final exporter = _Exporter();
    final app = AppDependencies(
      database: testDatabase(),
      bundle: MissingTestAssets(),
      settingsStore: MemorySettingsStore(),
      logger: logger,
      logExporter: exporter,
    );
    addTearDown(app.dispose);
    await tester.pumpWidget(MaterialApp(home: SettingsPage(app: app)));
    final entry = find.widgetWithText(ListTile, '日志管理器');
    final toggle = find.widgetWithText(SwitchListTile, '启用运行日志');
    expect(entry, findsOneWidget);
    expect(find.widgetWithText(ListTile, '导出日志'), findsNothing);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(app.loggingEnabled, isTrue);
    expect(entry, findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(app.loggingEnabled, isFalse);
    expect(entry, findsOneWidget);
    await tester.ensureVisible(entry);
    await tester.drag(find.byType(ListView), const Offset(0, -160));
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.textContaining('卡号、卡片名称、卡种'), findsOneWidget);
    expect(find.text('问题摘要'), findsNothing);
    expect(find.byType(SegmentedButton), findsNothing);
    expect(find.byType(CheckboxListTile), findsOneWidget);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.ancestor(
              of: find.textContaining('读取完成'),
              matching: find.byType(CheckboxListTile),
            ),
          )
          .value,
      isTrue,
    );
    await tester.tap(find.widgetWithText(FilledButton, '导出'));
    await tester.pumpAndSettle();
    expect(exporter.name, endsWith('.json'));
    final document = jsonDecode(exporter.content!) as Map;
    expect(document['kind'], 'full');
    expect((document['sessions'] as List).single['sessionId'], 'finished');
    expect(find.byType(AlertDialog), findsNothing);
  });
}

class _Exporter implements LogExporter {
  String? name;
  String? content;
  @override
  Future<String> saveToDownloads(String fileName, String content) async {
    name = fileName;
    this.content = content;
    return 'Download/$fileName';
  }
}
