import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_balance_presentation.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';
import 'package:transit_card_analyzer/gallery/gallery_theme.dart';

import 'support/gallery_scroll.dart';

void main() {
  late GalleryController c;
  setUp(() {
    c = GalleryController(
      GalleryData(
        jsonDecode(File('assets/gallery/fixtures.json').readAsStringSync())
            as GalleryRecord,
      ),
    );
    c.themeMode = ThemeMode.light;
    c.monet = false;
  });
  tearDown(() => c.dispose());

  Future<void> mount(
    WidgetTester tester, {
    double width = 360,
    bool reduceMotion = false,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: reduceMotion);
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(GalleryApp(controller: c));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'wallet keeps balances beside identities when four title characters fit, otherwise stacks uniformly',
    (tester) async {
      c.navigate(GalleryPage.cards);
      await mount(tester);
      for (final width in [320.0, 360.0, 412.0]) {
        tester.view.physicalSize = Size(width, 1000);
        await tester.pumpAndSettle();
        for (final card in c.savedCards) {
          final title = tester.getRect(find.text(card.name));
          final number = tester.getRect(
            find.byKey(ValueKey('wallet-number-${card.id}')),
          );
          if (width == 320) {
            expect(number.top, greaterThan(title.bottom));
            expect(
              tester
                  .renderObject<RenderBox>(find.text(card.name))
                  .constraints
                  .maxWidth,
              greaterThanOrEqualTo(4 * 17),
            );
          } else {
            expect(number.left, greaterThan(title.right));
            expect(number.top, lessThan(title.bottom + 10));
          }
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'footprint metrics stay in one row at narrow widths and large text',
    (tester) async {
      c.navigate(GalleryPage.footprints);
      await mount(tester, width: 320);
      for (final scale in [1.0, 1.5, 2.0]) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await tester.pumpAndSettle();
        final summary = find.byKey(const ValueKey('footprint-summary'));
        final labels = ['去过站点', '累计到访', '本月新站点']
            .map(
              (s) => tester.getRect(
                find.descendant(of: summary, matching: find.text(s)),
              ),
            )
            .toList();
        expect(labels[0].top, closeTo(labels[1].top, .1));
        expect(labels[1].top, closeTo(labels[2].top, .1));
        expect(labels[0].right, lessThan(labels[1].left));
        expect(labels[1].right, lessThan(labels[2].left));
        expect(tester.takeException(), isNull);
      }
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    },
  );

  testWidgets('light segment track stays pale while the capsule is distinct', (
    tester,
  ) async {
    c.navigate(GalleryPage.settings);
    await mount(tester);
    await tester.scrollUntilVisible(
      find.text('外观主题'),
      250,
      scrollable: galleryVerticalScroll(),
    );
    final indicator = find.byKey(const ValueKey('segments-跟随系统-indicator'));
    final tokens = Theme.of(tester.element(indicator))
        .extension<GalleryTokens>()!;
    expect(tokens.segmentTrack.computeLuminance(), greaterThan(.8));
    expect(
      tokens.segmentTrack.computeLuminance() - tokens.tone.computeLuminance(),
      greaterThan(.08),
    );
  });

  testWidgets(
    'detail face retains card number beside name, union mark and balance',
    (tester) async {
      c.openCard(c.current);
      await mount(tester, width: 320);
      for (final scale in [1.0, 2.0]) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await tester.pumpAndSettle();
        final face = find.byKey(ValueKey('card-face-${c.current.id}'));
        final texts = tester
            .widgetList<Text>(
              find.descendant(of: face, matching: find.byType(Text)),
            )
            .map((w) => w.data)
            .toList();
        expect(texts, [
          c.current.name,
          'CNY ¥',
          GalleryBalancePresentation.parse(
            c.current.balance(c.includeOverdraft),
            currencyCode: 'CNY',
          ).number,
          '**** ${c.current.tail}',
        ]);
        final title = tester.getRect(
          find.byKey(ValueKey('face-title-${c.current.id}')),
        );
        final number = tester.getRect(
          find.byKey(ValueKey('face-tail-${c.current.id}')),
        );
        expect(number.top, greaterThan(title.bottom));
        expect(
          find.descendant(of: face, matching: find.byType(SvgPicture)),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    },
  );

  for (final reduceMotion in [false, true]) {
    for (final autoSave in [false, true]) {
      testWidgets(
        'read smoothly reveals a compact identified card, reduce=$reduceMotion autoSave=$autoSave',
        (tester) async {
          c.autoSave = autoSave;
          await mount(tester, reduceMotion: reduceMotion);
          final card = find.byKey(const ValueKey('home-card-expansion'));
          final before = tester.getSize(card).height;
          await tester.tap(find.text('开始读取'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 1600));
          expect(c.hasRead, isTrue);
          await tester.pump(const Duration(milliseconds: 280));
          final partial = tester.getSize(card).height;
          if (!reduceMotion) {
            final fade = tester.widget<FadeTransition>(
              find
                  .ancestor(
                    of: find.byKey(const ValueKey('card-face-shanghai')),
                    matching: find.byType(FadeTransition),
                  )
                  .first,
            );
            expect(fade.opacity.value, inExclusiveRange(.1, .9));
          }
          await tester.pumpAndSettle();
          final after = tester.getSize(card).height;
          expect(after, lessThan(before));
          final face = tester.getSize(
            find.byKey(const ValueKey('card-face-shanghai')),
          );
          expect(face.width, 328);
          expect(face.height, lessThan(240));
          if (reduceMotion) {
            expect(partial, after);
          } else {
            expect(partial, inExclusiveRange(after, before));
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
