import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/expert/expert_page.dart';
import 'package:transit_card_analyzer/features/expert/expert_widgets.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

import 'support/test_database.dart';

void _singleLine(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final content = paragraph.text.toPlainText();
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: content.length),
  );
  expect(boxes.map((box) => box.top).toSet(), hasLength(1));
  expect(paragraph.didExceedMaxLines, isFalse);
}

void main() {
  testWidgets('专家信息获取在手机和分屏宽度下将解析器标签与短结果放在同一行', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    final app = _ExpertApp();
    addTearDown(app.dispose);
    for (final width in [320.0, 360.0, 390.0, 600.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpWidget(MaterialApp(home: ExpertPage(app: app)));
      await tester.pumpAndSettle();
      final label = find.text('解析器：');
      final value = find.text('交通联合电子钱包');
      expect(tester.getTopLeft(label).dy, tester.getTopLeft(value).dy);
      _singleLine(tester, value);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('较长字段名不挤压短结果，放大字体后能容纳的字段仍保持同行', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    for (final scale in [1.0, 1.5, 2.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const Scaffold(
              body: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    ExpertField('版本', '0x80'),
                    ExpertField('发卡机构名称', '交通联合电子钱包'),
                    ExpertField('单次消费金额上限', '20.00 元'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getTopLeft(find.text('版本：')).dy,
        tester.getTopLeft(find.text('0x80')).dy,
      );
      if (scale <= 1.5) {
        expect(
          tester.getTopLeft(find.text('单次消费金额上限：')).dy,
          tester.getTopLeft(find.text('20.00 元')).dy,
        );
      }
      _singleLine(tester, find.text('20.00 元'));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('长公钥和多行诊断使用整行宽度，窄窗大字体保留完整内容', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    final publicKey = '02${'1234567890ABCDEF' * 4}';
    const diagnostic = '第一行原始证据\n第二行原始证据';
    for (final width in [240.0, 320.0, 390.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      ExpertField('支付账户用户公钥', publicKey),
                      const ExpertField('诊断', diagnostic),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final value = tester.getRect(find.text(publicKey));
      expect(value.width, closeTo(width - 32, 0.1));
      expect(
        value.top,
        greaterThan(tester.getRect(find.text('支付账户用户公钥：')).bottom),
      );
      expect(find.text(diagnostic), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}

class _ExpertApp extends AppDependencies {
  _ExpertApp()
    : super(
        database: testDatabase(),
        bundle: MissingTestAssets(),
        settingsStore: MemorySettingsStore(),
        logger: AppLogger(store: MemoryLogStore()),
      );

  @override
  ParsedCard get parsedCard => const ParsedCard(
    parserId: CardParserIds.tunion,
    parserName: '交通联合电子钱包',
    info: TUnionCardInfo(),
    transactions: [],
  );
}
