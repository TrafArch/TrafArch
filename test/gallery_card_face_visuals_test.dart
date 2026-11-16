import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';
import 'package:transit_card_analyzer/gallery/gallery_design.dart';
import 'package:transit_card_analyzer/gallery/gallery_theme.dart';

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
    await tester.pumpWidget(GalleryApp(controller: c));
    await tester.pumpAndSettle();
  }

  GalleryTokens tokensAt(WidgetTester tester, Finder finder) =>
      Theme.of(tester.element(finder)).extension<GalleryTokens>()!;

  Color? textColor(WidgetTester tester, Finder finder) =>
      tester.widget<Text>(finder).style?.color;

  double contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    return (math.max(la, lb) + .05) / (math.min(la, lb) + .05);
  }

  Uint8List faceImage() => File('assets/icon/app_icon.png').readAsBytesSync();

  testWidgets('wallet balance follows the card tokens in both themes', (
    tester,
  ) async {
    c.navigate(GalleryPage.cards);
    await mount(tester);
    final card = c.savedCards.first;
    final number = find.byKey(ValueKey('wallet-number-${card.id}'));
    final currency = find.byKey(ValueKey('wallet-currency-${card.id}'));
    expect(number, findsOneWidget);
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      c.update(() => c.themeMode = mode);
      await tester.pumpAndSettle();
      final t = tokensAt(tester, number);
      expect(textColor(tester, number), t.cardTextPrimary);
      expect(
        contrast(t.cardTextPrimary, t.cardSurface),
        greaterThanOrEqualTo(4.5),
      );
      if (currency.evaluate().isNotEmpty) {
        expect(textColor(tester, currency), t.cardTextSecondary);
        expect(
          contrast(t.cardTextSecondary, t.cardSurface),
          greaterThanOrEqualTo(4.5),
        );
      }
    }
    // The old dark-on-light face foreground must never leak into dark mode.
    expect(textColor(tester, number), isNot(const Color(0xff18263a)));
  });

  testWidgets(
    'custom image scrim is lighter in light mode, unchanged in dark',
    (tester) async {
      final card = c.savedCards.first;
      c.update(() => card.image = faceImage());
      c.navigate(GalleryPage.cards);
      await mount(tester);
      final scrim = find.byKey(const ValueKey('face-image-scrim'));
      expect(scrim, findsWidgets);

      LinearGradient gradient() {
        final box = tester.widget<DecoratedBox>(scrim.first);
        return (box.decoration as BoxDecoration).gradient! as LinearGradient;
      }

      double baseAlpha() {
        final colors = gradient().colors;
        return colors[colors.length ~/ 2].a;
      }

      c.update(() => c.themeMode = ThemeMode.light);
      await tester.pumpAndSettle();
      final light = baseAlpha();
      c.update(() => c.themeMode = ThemeMode.dark);
      await tester.pumpAndSettle();
      final dark = baseAlpha();
      expect(light, lessThan(dark));
      expect(light, closeTo(GalleryCardImageStyle.light.overlayAlpha, 1e-6));
      expect(dark, closeTo(0x99 / 255, 1e-6));
      expect(
        GalleryCardImageStyle.light.overlayAlpha,
        lessThan(GalleryCardImageStyle.dark.overlayAlpha),
      );
    },
  );

  testWidgets('image card surfaces drop the duplicate border, plain keep one', (
    tester,
  ) async {
    final card = c.savedCards.first;
    c.navigate(GalleryPage.cards);
    await mount(tester);
    BoxDecoration decoration() =>
        tester
                .widget<Container>(
                  find.byKey(ValueKey('wallet-card-${card.id}')),
                )
                .decoration!
            as BoxDecoration;
    expect(decoration().border, isNotNull);
    c.update(() => card.image = faceImage());
    await tester.pumpAndSettle();
    expect(decoration().border, isNull);
  });
}
