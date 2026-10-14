// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:transit_card_analyzer/app.dart';

void main() {
  testWidgets('App 启动冒烟测试', (WidgetTester tester) async {
    await tester.pumpWidget(const TransitCardAnalyzerApp());
    await tester.pump();

    expect(find.text('TrafArch'), findsOneWidget);
    expect(find.text('首页'), findsOneWidget);

    // 卸载组件树并清空挂起定时器：卡片档案数据流（Drift）取消订阅时
    // 会留出一次事件循环的收尾定时器，避免测试结束报 Timer 未清理。
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
