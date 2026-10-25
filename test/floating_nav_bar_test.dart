import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/navigation/floating_nav_bar.dart';
import 'package:transit_card_analyzer/shared/presentation/ui_constants.dart';

const icons = [
  Icons.home_outlined,
  Icons.directions_transit_outlined,
  Icons.credit_card_outlined,
  Icons.science_outlined,
];
const labels = ['首页', '行程', '卡片', '专家'];

Future<void> mountBar(
  WidgetTester tester, {
  bool reduceMotion = false,
  ValueChanged<int>? onSelect,
}) async {
  var index = 0;
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) => SizedBox(
                width: UiConstants.floatingNavBarWidth,
                child: FloatingNavBar(
                  index: index,
                  onSelect: (i) {
                    onSelect?.call(i);
                    setState(() => index = i);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Finder itemAncestor(int index, Type type) => find
    .ancestor(of: find.byIcon(icons[index]), matching: find.byType(type))
    .first;

double opacity(WidgetTester tester, int index) => tester
    .widget<Opacity>(
      find.ancestor(
        of: find.text(labels[index]),
        matching: find.byType(Opacity),
      ),
    )
    .opacity;

double scale(WidgetTester tester, int index) => tester
    .widget<ScaleTransition>(itemAncestor(index, ScaleTransition))
    .scale
    .value;

void main() {
  testWidgets('底栏高度 56、宽度 280、圆角 28', (tester) async {
    await mountBar(tester);
    expect(tester.getSize(find.byType(FloatingNavBar)), const Size(280, 56));
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

  testWidgets('立即回调，胶囊颜色间距和标签共享平滑进度', (tester) async {
    int? selected;
    await mountBar(tester, onSelect: (i) => selected = i);
    await tester.tap(find.byIcon(icons[1]));
    expect(selected, 1);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump(const Duration(milliseconds: 110));
    final progress = opacity(tester, 1);
    expect(progress, greaterThan(0));
    expect(progress, lessThan(1));
    expect(opacity(tester, 0) + progress, closeTo(1, 0.00001));
    final container = tester.widget<Container>(itemAncestor(1, Container));
    expect(
      container.padding,
      EdgeInsets.symmetric(horizontal: 12 + 4 * progress),
    );
    final scheme = Theme.of(tester.element(find.byIcon(icons[1]))).colorScheme;
    expect(
      tester.widget<Icon>(find.byIcon(icons[1])).color,
      Color.lerp(scheme.onSurfaceVariant, scheme.primary, progress),
    );
    expect(
      (container.decoration! as BoxDecoration).color,
      scheme.primary.withValues(alpha: 0.16 * progress),
    );
    await tester.pumpAndSettle();
    expect(opacity(tester, 1), 1);
    expect(opacity(tester, 0), 0);
    expect(
      tester.getRect(find.text(labels[1])).left,
      greaterThanOrEqualTo(tester.getRect(find.byIcon(icons[1])).right),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('按下缩放，松手和取消恢复，取消不触发选择', (tester) async {
    var calls = 0;
    await mountBar(tester, onSelect: (_) => calls++);
    for (final cancel in [false, true]) {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(icons[1])),
      );
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 90));
      expect(scale(tester, 1), closeTo(0.95, 0.00001));
      if (cancel) {
        await gesture.cancel();
      } else {
        await gesture.up();
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      expect(scale(tester, 1), greaterThan(0.95));
      expect(scale(tester, 1), lessThan(1));
      await tester.pumpAndSettle();
      expect(scale(tester, 1), 1);
    }
    expect(calls, 1);
  });

  testWidgets('快速切换维持总展开量且无溢出，最终状态正确', (tester) async {
    await mountBar(tester);
    for (final i in [1, 2, 3, 0, 2, 1, 3]) {
      await tester.tap(find.byIcon(icons[i]));
      await tester.pump();
      for (var frame = 0; frame < 3; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          List.generate(4, (j) => opacity(tester, j)).reduce((a, b) => a + b),
          closeTo(1, 0.00001),
        );
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byType(FloatingNavBar)),
          const Size(280, 56),
        );
      }
    }
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      expect(opacity(tester, i), i == 3 ? 1 : 0);
    }
  });

  testWidgets('减少动画时无按压缩放且选择直接完成', (tester) async {
    await mountBar(tester, reduceMotion: true);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(icons[1])),
    );
    await tester.pump(const Duration(milliseconds: 120));
    expect(scale(tester, 1), 1);
    expect(
      tester.widget<AnimatedScale>(itemAncestor(1, AnimatedScale)).duration,
      Duration.zero,
    );
    await gesture.up();
    await tester.pump();
    expect(opacity(tester, 0), 0);
    expect(opacity(tester, 1), 1);
    expect(scale(tester, 1), 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('语义标签唯一、选中按钮正确，每次仅回调一次且重复点击不振动', (tester) async {
    final semantics = tester.ensureSemantics();
    var calls = 0;
    var haptics = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics++;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await mountBar(tester, onSelect: (_) => calls++);
    for (var i = 0; i < 4; i++) {
      expect(find.bySemanticsLabel(labels[i]), findsOneWidget);
      final node = tester.getSemantics(find.bySemanticsLabel(labels[i]));
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.flagsCollection.isSelected.toBoolOrNull(), i == 0);
    }
    await tester.tap(find.byIcon(icons[0]));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(haptics, 0);
    final node = tester.getSemantics(find.bySemanticsLabel(labels[2]));
    tester
        .element(find.byType(FloatingNavBar))
        .findRenderObject()!
        .owner!
        .semanticsOwner!
        .performAction(node.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(haptics, 1);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel(labels[2]))
          .flagsCollection
          .isSelected
          .toBoolOrNull(),
      isTrue,
    );
    await tester.tap(find.byIcon(icons[2]));
    await tester.pumpAndSettle();
    expect(calls, 3);
    expect(haptics, 1);
    semantics.dispose();
  });
}
