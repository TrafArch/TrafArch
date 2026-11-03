import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_balance_presentation.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';

void main() {
  late GalleryController c;
  setUp(() {
    c = GalleryController(
      GalleryData(
        jsonDecode(File('assets/gallery/fixtures.json').readAsStringSync())
            as GalleryRecord,
      ),
    );
    c.monet = false;
    c.themeMode = ThemeMode.light;
  });
  tearDown(() => c.dispose());

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(GalleryApp(controller: c));
    await tester.pumpAndSettle();
  }

  testWidgets('wallet currency, numbers and counts share aligned columns', (
    tester,
  ) async {
    for (final (id, balance) in [
      ('usd-sample', r'USD $0.00'),
      ('mop-sample', 'MOP ¥-123,456.78'),
    ]) {
      c.cards.add(
        GalleryCard.fromJson({
          ...c.data.cards.first,
          'id': id,
          'saved': true,
          'name': id,
          'balance': balance,
        }),
      );
    }
    c.cards[1].rawBalance = '-1,234,567.89';
    final originalBalances = [for (final card in c.cards) card.rawBalance];
    c.navigate(GalleryPage.cards);
    await mount(tester);
    for (final width in [320.0, 360.0, 412.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        tester.view.physicalSize = Size(width, 2400);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await tester.pumpAndSettle();
        double? center;
        double? numberHeight;
        for (final card in c.savedCards) {
          final number = tester.getRect(
            find.byKey(ValueKey('wallet-number-${card.id}')),
          );
          final count = tester.getRect(
            find.byKey(ValueKey('wallet-count-${card.id}')),
          );
          center ??= number.center.dx;
          numberHeight ??= number.height;
          expect(number.center.dx, closeTo(center, .1));
          expect(count.center.dx, closeTo(center, .1));
          expect(number.height, closeTo(numberHeight, .1));
          expect(count.top, greaterThan(number.bottom));
          final label = tester.widget<Text>(
            find.byKey(ValueKey('wallet-currency-${card.id}')),
          );
          final value = GalleryBalancePresentation.parse(
            card.balance(c.includeOverdraft),
            currencyCode: card.currency?.name.toUpperCase(),
          );
          expect(label.data, value.currencyLabel);
          final thumbnail = tester.getSize(
            find.byKey(ValueKey('card-thumbnail-${card.id}')),
          );
          expect(
            thumbnail.width / thumbnail.height,
            closeTo(85.60 / 53.98, .001),
          );
          expect(thumbnail.width, 60);
        }
        expect(tester.takeException(), isNull, reason: '$width / $scale');
      }
    }
    expect([for (final card in c.cards) card.rawBalance], originalBalances);
  });

  testWidgets(
    'card face keeps its fields separate for long and unknown money',
    (tester) async {
      c.openCard(c.current);
      await mount(tester);
      for (final width in [320.0, 360.0, 412.0]) {
        for (final scale in [1.0, 1.5, 2.0]) {
          tester.view.physicalSize = Size(width, 2400);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          for (final balance in ['86.50', '-1,234,567.89', '—']) {
            c.update(() {
              c.current.rawBalance = balance;
              c.current.name = balance == '86.50'
                  ? '上海公共交通卡'
                  : '上海公共交通卡 交通联合纪念版';
            });
            await tester.pumpAndSettle();
            final face = tester.getRect(
              find.byKey(const ValueKey('card-face-shanghai')),
            );
            final title = tester.getRect(
              find.byKey(const ValueKey('face-title-shanghai')),
            );
            final tail = tester.getRect(
              find.byKey(const ValueKey('face-tail-shanghai')),
            );
            final amount = tester.getRect(
              find.byKey(
                ValueKey(
                  'face-${balance == '—' ? 'unknown' : 'number'}-shanghai',
                ),
              ),
            );
            for (final field in [title, tail, amount]) {
              expect(face.contains(field.topLeft), isTrue);
              expect(
                face.contains(field.bottomRight - const Offset(.01, .01)),
                isTrue,
              );
            }
            expect(amount.top, greaterThan(title.bottom));
            expect(tail.top, greaterThan(title.bottom));
            expect(amount.overlaps(tail), isFalse);
            expect(find.text('当前余额'), findsNothing);
            expect(find.textContaining('最近读取'), findsNothing);
            if (balance == '—') {
              expect(
                find.byKey(const ValueKey('face-currency-shanghai')),
                findsNothing,
              );
            } else {
              expect(find.text('CNY ¥'), findsOneWidget);
            }
            if (scale >= 1.5) expect(tail.top, greaterThan(amount.bottom));
            expect(
              tester.takeException(),
              isNull,
              reason: '$width / $scale / $balance',
            );
          }
        }
      }
    },
  );
}
