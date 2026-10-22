import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/expert/raw_data_panel.dart';

void main() {
  testWidgets('Raw Data保留完整读取过程和最初的余额查询', (tester) async {
    const balance = '>> 80 5C 00 02 04\n<< 00 00 10 81 90 00';
    const finalCheck = '== 余额核对：parsedFen=4225 ==';
    final log = [
      '>> 00 A4 04 00 08 A0 00 00 06 32 01 01 05 00',
      balance,
      for (var i = 1; i <= 40; i++) '>> READ RECORD $i\n<< 00 00 90 00',
      finalCheck,
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RawDataPanel(apduLog: log, processRecords: const []),
          ),
        ),
      ),
    );
    expect(find.text(balance), findsOneWidget);
    expect(find.text(log.first), findsOneWidget);
    expect(find.text(finalCheck), findsOneWidget);
    expect(find.text('>> READ RECORD 1\n<< 00 00 90 00'), findsOneWidget);
    expect(find.text('>> READ RECORD 40\n<< 00 00 90 00'), findsOneWidget);
  });
}
