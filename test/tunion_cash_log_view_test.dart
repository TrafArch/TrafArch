import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/trips/tunion_cash_log_view.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_cash_log.dart';

void main() {
  testWidgets('shows only verified cash purchases without a journey', (
    tester,
  ) async {
    final log = TUnionCashLog(
      confirmed: true,
      records: [
        const TUnionCashLogRecord(recordNumber: 1, rawHex: 'ABCDEF'),
        TUnionCashLogRecord(
          recordNumber: 2,
          rawHex: '261114203801000000000180015600',
          time: DateTime(2026, 11, 14, 20, 38, 1),
          amountFen: 180,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TUnionCashLogView(log: log)),
      ),
    );
    expect(find.text('交通联合电子现金消费'), findsOneWidget);
    expect(find.text('-¥1.80'), findsOneWidget);
    expect(find.text('2026-11-14 20:38:01'), findsOneWidget);
    expect(find.text('公共汽电车'), findsNothing);
    expect(find.text('轨道交通'), findsNothing);
    await tester.tap(find.text('-¥1.80'));
    await tester.pumpAndSettle();
    expect(find.text('记录来源：交通联合电子现金 · 0x0B'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('原始数据（HEX）'), findsOneWidget);
  });
}
