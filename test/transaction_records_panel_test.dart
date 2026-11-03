import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/expert/transaction_records_panel.dart';

void main() {
  testWidgets('transaction details expand without mixing independent wallets', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                TransactionRecordsPanel(
                  storageKey: 'tu',
                  records: [
                    ExpertTransactionRecord(
                      time: '未知',
                      amount: 'CNY -1.00',
                      type: '消费',
                      sequence: '未知',
                      terminal: '010203',
                      extraFields: [('终端解码', '未知')],
                      rawHex: '00010203',
                    ),
                  ],
                ),
                TransactionRecordsPanel(storageKey: 'lnt', records: []),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('未读取到交易记录'), findsOneWidget);
    await tester.tap(find.text('交易明细记录').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('交易记录 1'));
    await tester.pumpAndSettle();
    expect(find.text('CNY -1.00'), findsOneWidget);
    expect(find.text('终端解码'), findsOneWidget);
    expect(find.text('00010203'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
