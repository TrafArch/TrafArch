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

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
}
