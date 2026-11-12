import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
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
    )..monet = false;
  });
  tearDown(() => c.dispose());

  Future<void> mount(WidgetTester tester, {bool reduced = false}) async {
    tester.view.physicalSize = const Size(360, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: reduced);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    c.navigate(GalleryPage.cards);
    await tester.pumpWidget(GalleryApp(controller: c));
    await tester.pumpAndSettle();
  }

  test(
    'reordering only saved slots retains card objects, selection and reset',
    () {
      final original = List.of(c.cards);
      c.selectedCardId = 'suica';
      c.reorderSavedCards(0, 2);
      expect(c.savedCards.map((card) => card.id), [
        'suica',
        'octopus',
        'shenzhen',
      ]);
      expect(c.cards.first, same(original.first));
      expect(c.selectedCard, same(original[2]));
      c.reorderSavedCards(2, 0);
      expect(c.cards, original);
      c.reorderSavedCards(-1, 0);
      c.reorderSavedCards(0, 99);
      expect(c.cards, original);
      c.reorderSavedCards(1, 0);
      c.reset();
      expect(c.savedCards.map((card) => card.id), [
        'shenzhen',
        'suica',
        'octopus',
      ]);
    },
  );

  testWidgets('drag dots require a long press and animate a real reorder', (
    tester,
  ) async {
    await mount(tester);
    final handle = find.byKey(const ValueKey('wallet-drag-shenzhen'));
    await tester.tap(handle);
    await tester.pumpAndSettle();
    expect(c.page, GalleryPage.cards);
    final start = tester.getCenter(handle);
    final targetY =
        tester
            .getBottomLeft(find.byKey(const ValueKey('wallet-card-octopus')))
            .dy +
        tester
            .getSize(find.byKey(const ValueKey('wallet-card-shenzhen')))
            .height;
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(Offset(start.dx, targetY));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.moveBy(const Offset(0, 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.page, GalleryPage.cards);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(c.savedCards.map((card) => card.id), [
      'suica',
      'octopus',
      'shenzhen',
    ]);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('wallet-card-shenzhen'))).dy,
      greaterThan(
        tester.getTopLeft(find.byKey(const ValueKey('wallet-card-octopus'))).dy,
      ),
    );
    c.navigate(GalleryPage.home);
    await tester.pumpAndSettle();
    c.navigate(GalleryPage.cards);
    await tester.pumpAndSettle();
    expect(c.savedCards.first.id, 'suica');
    await tester.tap(find.byKey(const ValueKey('wallet-card-suica')));
    await tester.pumpAndSettle();
    expect(c.page, GalleryPage.detail);
    expect(c.selectedCard.id, 'suica');
    expect(find.byTooltip('Suica 管理'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'undo retains the original object and position and rejects stale removals',
    () {
      c.reorderSavedCards(2, 0);
      final card = c.savedCards[1];
      final image = card.image = File('assets/icon/app_icon.png')
          .readAsBytesSync();
      card.name = '我的通勤卡';
      card.face = 'amber';
      final rawBalance = card.rawBalance;
      final ledger = jsonEncode(c.ledger(card));
      final removed = c.deleteCard(card)!;
      c.reorderSavedCards(0, 1);
      expect(c.restoreCard(removed), isTrue);
      expect(c.savedCards.map((card) => card.id), [
        'suica',
        'shenzhen',
        'octopus',
      ]);
      expect(c.savedCards[1], same(card));
      expect(card.image, same(image));
      expect(card.name, '我的通勤卡');
      expect(card.face, 'amber');
      expect(card.rawBalance, rawBalance);
      expect(jsonEncode(c.ledger(card)), ledger);
      expect(c.restoreCard(removed), isFalse);
      final newer = c.deleteCard(card)!;
      expect(c.restoreCard(removed), isFalse);
      expect(c.restoreCard(newer), isTrue);
      final stale = c.deleteCard(card)!;
      c.reset();
      expect(c.restoreCard(stale), isFalse);
      expect(c.savedCards.map((card) => card.id), [
        'shenzhen',
        'suica',
        'octopus',
      ]);
    },
  );

  Future<void> reveal(WidgetTester tester, String id) async {
    final row = tester.getRect(find.byKey(ValueKey('wallet-card-$id')));
    await tester.dragFrom(
      Offset(row.center.dx, row.top + 24),
      const Offset(-280, 0),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('wallet-delete-$id')).hitTestable(),
      findsOneWidget,
    );
  }

  testWidgets(
    'left swipe reveals a button, deletion collapses and undo expands the same card',
    (tester) async {
      final card = c.savedCards.first;
      final image = card.image = File('assets/icon/app_icon.png')
          .readAsBytesSync();
      await mount(tester);
      final row = find.byKey(ValueKey('wallet-item-${card.id}'));
      final originalHeight = tester.getSize(row).height;
      final next = find.byKey(const ValueKey('wallet-item-suica'));
      final nextY = tester.getTopLeft(next).dy;
      await reveal(tester, card.id);
      expect(c.savedCards, hasLength(3));
      expect(find.text('撤销'), findsNothing);
      await tester.tap(find.byKey(ValueKey('wallet-delete-${card.id}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getSize(row).height, inExclusiveRange(0, originalHeight));
      expect(tester.getTopLeft(next).dy, lessThan(nextY));
      await tester.pumpAndSettle();
      expect(c.savedCards, hasLength(2));
      expect(find.byKey(const ValueKey('gallery-feedback')), findsOneWidget);
      expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
      expect(find.text('已删除“${card.name}”'), findsOneWidget);
      await tester.tap(find.text('撤销'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(c.savedCards.first, same(card));
      expect(tester.getSize(row).height, inExclusiveRange(0, originalHeight));
      await tester.pumpAndSettle();
      expect(tester.getSize(row).height, closeTo(originalHeight, .1));
      expect(card.image, same(image));
      expect(find.byKey(ValueKey('wallet-delete-${card.id}')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'closing a reveal keeps the card and deletion can be undone after navigation',
    (tester) async {
      await mount(tester);
      await reveal(tester, 'shenzhen');
      final translated = tester.getRect(
        find.byKey(const ValueKey('wallet-card-shenzhen')),
      );
      await tester.tapAt(Offset(80, translated.top + 24));
      await tester.pumpAndSettle();
      expect(c.page, GalleryPage.cards);
      expect(c.savedCards, hasLength(3));
      expect(
        find.byKey(const ValueKey('wallet-delete-shenzhen')),
        findsNothing,
      );
      await reveal(tester, 'shenzhen');
      await tester.tap(find.byKey(const ValueKey('wallet-delete-shenzhen')));
      await tester.pumpAndSettle();
      c.navigate(GalleryPage.trips);
      await tester.pumpAndSettle();
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(c.savedCards.first.id, 'shenzhen');
      expect(c.page, GalleryPage.trips);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'consecutive same-name deletions each retain their own undo action',
    (tester) async {
      c.savedCards[0].name = c.savedCards[1].name = '通勤卡';
      await mount(tester);
      for (final id in ['shenzhen', 'suica']) {
        await reveal(tester, id);
        await tester.tap(find.byKey(ValueKey('wallet-delete-$id')));
        await tester.pumpAndSettle();
      }
      expect(c.savedCards.map((card) => card.id), ['octopus']);
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(c.savedCards.map((card) => card.id), ['shenzhen', 'octopus']);
      expect(find.text('撤销'), findsOneWidget);
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(c.savedCards.map((card) => card.id), [
        'shenzhen',
        'suica',
        'octopus',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reduced motion deletes immediately and expired feedback cannot restore a card',
    (tester) async {
      await mount(tester, reduced: true);
      await reveal(tester, 'shenzhen');
      await tester.tap(find.byKey(const ValueKey('wallet-delete-shenzhen')));
      await tester.pump();
      expect(c.savedCards, hasLength(2));
      expect(find.text('撤销'), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      expect(find.text('撤销'), findsNothing);
      expect(c.savedCards, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );
}
