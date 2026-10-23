import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/navigation/floating_nav_bar.dart';
import 'package:transit_card_analyzer/shared/presentation/ui_constants.dart';

void main() {
  testWidgets('底栏高度 56、圆角 28', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: UiConstants.floatingNavBarWidth,
              child: FloatingNavBar(index: 0, onSelect: (_) {}),
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(FloatingNavBar)).height, 56);

    final decoration =
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: find.byType(FloatingNavBar),
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(28));
  });

  testWidgets('选中项图标与文字并排，点按后立即切换且无待执行动画', (tester) async {
    var index = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) => SizedBox(
                width: UiConstants.floatingNavBarWidth,
                child: FloatingNavBar(
                  index: index,
                  onSelect: (i) => setState(() => index = i),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.directions_transit_outlined));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(index, 1);
    expect(find.text('行程'), findsOneWidget);
    expect(find.text('首页'), findsNothing);

    final iconRect = tester.getRect(
      find.byIcon(Icons.directions_transit_outlined),
    );
    final textRect = tester.getRect(find.text('行程'));
    expect(textRect.left, greaterThanOrEqualTo(iconRect.right));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
