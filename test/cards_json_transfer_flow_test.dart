import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/archive/presentation/card_detail_page.dart';
import 'package:transit_card_analyzer/features/cards/cards_page.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/archive_document_store.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';

import 'support/test_database.dart';

void main() {
  AppDependencies appFor(_Documents documents) {
    final app = AppDependencies(
      database: testDatabase(),
      archiveDocumentStore: documents,
      settingsStore: MemorySettingsStore(),
      logger: AppLogger(store: MemoryLogStore()),
    );
    addTearDown(() async {
      app.dispose();
      await app.archiveTransfer.finishWrites();
    });
    return app;
  }

  Future<void> mount(WidgetTester tester, AppDependencies app) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CardsPage(app: app)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('空卡片列表导入预览确认后出现卡片，详情显示所选字段', (tester) async {
    final documents = _Documents()..next = _file();
    final app = appFor(documents);
    await mount(tester, app);
    expect(find.text('还没有保存的卡片'), findsOneWidget);
    await tester.tap(find.byTooltip('导入卡片 JSON'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('通勤记录.json'), findsOneWidget);
    expect(await app.cardRepository.getAllCards(), isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, '导入'));
    await tester.pumpAndSettle();
    expect(find.text('示例通勤卡'), findsOneWidget);
    expect(find.text('0000123'), findsOneWidget);
    expect(find.text('还没有保存的卡片'), findsNothing);
    await tester.tap(find.text('示例通勤卡'));
    await tester.pumpAndSettle();
    expect(find.byType(CardDetailPage), findsOneWidget);
    expect(find.text('导入记录 · 1 条'), findsOneWidget);
    await tester.ensureVisible(find.byType(ExpansionTile));
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(find.text('001号站'), findsWidgets);
    expect(find.text('0000123'), findsWidgets);
    expect(find.text('来自 JSON 文件，仅显示文件提供的字段。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('文件选择取消与预览取消都不写入卡片', (tester) async {
    final documents = _Documents();
    final app = appFor(documents);
    await mount(tester, app);
    await tester.tap(find.byTooltip('导入卡片 JSON'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('导入失败'), findsNothing);
    documents.next = _file();
    await tester.tap(find.byTooltip('导入卡片 JSON'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await app.cardRepository.getAllCards(), isEmpty);
    expect(find.text('还没有保存的卡片'), findsOneWidget);
  });

  testWidgets('单卡菜单导出限制卡片范围并遵守字段选择', (tester) async {
    final documents = _Documents()..next = _file(twoCards: true);
    final app = appFor(documents);
    await app.archiveTransfer.confirmImport(
      (await app.archiveTransfer.pickImport())!,
    );
    await mount(tester, app);
    final tile = find.ancestor(
      of: find.text('示例通勤卡'),
      matching: find.byType(Card),
    );
    await tester.tap(
      find.descendant(of: tile, matching: find.byTooltip('卡片操作')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出此卡 JSON'));
    await tester.pumpAndSettle();
    expect(find.text('导出：示例通勤卡'), findsOneWidget);
    await tester.tap(find.text('清空选择'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, '卡片名称'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '选择保存位置'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('选择保存位置'));
    await tester.pumpAndSettle();
    await tester.runAsync(app.archiveTransfer.finishWrites);
    await tester.pumpAndSettle();
    expect(
      documents.saved,
      isNotNull,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .join(' | '),
    );
    final output = jsonDecode(documents.saved!) as Map<String, dynamic>;
    expect(output['fields'], ['card_name']);
    expect(output['records'], [
      {'card_name': '示例通勤卡'},
    ]);
    expect(documents.saved, isNot(contains('0000123')));
    expect(documents.saved, isNot(contains('第二张卡')));
  });
}

PickedArchiveDocument _file({bool twoCards = false}) => PickedArchiveDocument(
  name: '通勤记录.json',
  content: jsonEncode({
    'format': 'trafarch.records',
    'version': 1,
    'exportedAt': '2026-10-26T12:00:00Z',
    'fields': ['card_name', 'card_number', 'entry_station', 'amount'],
    'records': [
      {
        'card_name': '示例通勤卡',
        'card_number': '0000123',
        'entry_station': '001号站',
        'amount': '2.50',
      },
      if (twoCards)
        {
          'card_name': '第二张卡',
          'card_number': '0000456',
          'entry_station': '002号站',
          'amount': '3.00',
        },
    ],
  }),
);

class _Documents implements ArchiveDocumentStore {
  PickedArchiveDocument? next;
  String? saved;
  @override
  Future<PickedArchiveDocument?> openJson() async => next;
  @override
  Future<String?> saveJson(String fileName, String content) async {
    saved = content;
    return fileName;
  }
}
