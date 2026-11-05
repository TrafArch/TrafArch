import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/domain/archive_export_options.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_transfer_dialogs.dart';

void main() {
  for (final size in const [
    Size(360, 400),
    Size(320, 480),
    Size(280, 400),
    Size(240, 320),
    Size(600, 320),
  ]) {
    testWidgets('导出弹窗在 $size 可滚动选择末项并保留缩窗状态', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      ArchiveExportOptions? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showArchiveExportDialog(context);
                },
                child: const Text('打开导出'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开导出'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('清空选择'));
      await tester.tap(find.text('清空选择'));
      await tester.pumpAndSettle();
      final lastField = find.widgetWithText(CheckboxListTile, '终端编码');
      await tester.ensureVisible(lastField);
      await tester.pumpAndSettle();
      await tester.tap(lastField);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(lastField).value, isTrue);
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final save = find.widgetWithText(FilledButton, '选择保存位置');
      expect(save.hitTestable(), findsOneWidget);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(result?.fields, {ArchiveExportField.terminal});

      await tester.tap(find.text('打开导出'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('完整备份'));
      await tester.tap(find.text('完整备份'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(result?.mode, ArchiveExportMode.fullBackup);
    });
  }

  testWidgets('字段导出至少选择一项，取消选择后不能导出', (tester) async {
    ArchiveExportOptions? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showArchiveExportDialog(context);
              },
              child: const Text('打开导出'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开导出'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空选择'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '选择保存位置'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.widgetWithText(CheckboxListTile, '卡片名称'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择保存位置'));
    await tester.pumpAndSettle();
    expect(result?.mode, ArchiveExportMode.selectedRecords);
    expect(result?.fields, {ArchiveExportField.cardName});
  });

  testWidgets('完整备份无需逐字段选择，单卡范围明确显示', (tester) async {
    ArchiveExportOptions? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showArchiveExportDialog(
                  context,
                  cardName: '通勤卡',
                );
              },
              child: const Text('打开导出'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开导出'));
    await tester.pumpAndSettle();
    expect(find.text('导出：通勤卡'), findsOneWidget);
    await tester.tap(find.text('清空选择'));
    await tester.tap(find.text('完整备份'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNothing);
    await tester.tap(find.text('选择保存位置'));
    await tester.pumpAndSettle();
    expect(result?.mode, ArchiveExportMode.fullBackup);
  });

  testWidgets('取消导出不产生配置且小屏幕不溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var returned = false;
    ArchiveExportOptions? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showArchiveExportDialog(context);
                returned = true;
              },
              child: const Text('打开导出'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开导出'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(returned, isTrue);
    expect(result, isNull);
  });
}
