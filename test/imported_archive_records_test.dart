import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/presentation/imported_archive_records.dart';

void main() {
  testWidgets('导入记录保留原始字符串与未知字段，不补造金额或站点', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ImportedArchiveRecords(
                records: const [
                  {
                    'time': '2026-10-26T10:20:30',
                    'entry_station': '示例起点',
                    'exit_station': null,
                    'entry_station_code': '0001',
                    'amount_raw': '001250',
                    'currency': null,
                    'customer_note': '客户字段',
                  },
                ],
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('导入记录 · 1 条'), findsOneWidget);
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(find.text('0001'), findsOneWidget);
    expect(find.text('001250'), findsOneWidget);
    expect(find.text('客户字段'), findsOneWidget);
    expect(find.text('未提供'), findsWidgets);
    expect(find.textContaining('CNY'), findsNothing);
    expect(find.textContaining('¥'), findsNothing);
  });

  testWidgets('长导入记录按页展示，后续记录仍可访问', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ImportedArchiveRecords(
              records: List.generate(51, (i) => {'time': '记录时间$i'}),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(ExpansionTile), findsNWidgets(50));
    await tester.scrollUntilVisible(find.text('继续显示'), 500);
    await tester.tap(find.text('继续显示'));
    await tester.pumpAndSettle();
    expect(find.byType(ExpansionTile), findsNWidgets(51));
    expect(find.text('记录时间50'), findsOneWidget);
  });
}
