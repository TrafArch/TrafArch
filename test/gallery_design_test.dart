import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_design.dart';
import 'package:transit_card_analyzer/gallery/gallery_layout.dart';
import 'package:transit_card_analyzer/gallery/gallery_theme.dart';

double contrast(Color foreground, Color background) {
  final a = Color.alphaBlend(foreground, background).computeLuminance();
  final b = background.computeLuminance();
  return (math.max(a, b) + .05) / (math.min(a, b) + .05);
}

void main() {
  for (final palette in GalleryPalette.values) {
    for (final dark in [false, true]) {
      test('${palette.id} $dark readable text on all used surface roles', () {
        final t = GalleryTokens(scheme: palette.scheme(dark));
        for (final background in [t.bg, t.surface, t.surface2, t.raised]) {
          for (final foreground in [t.text, t.muted, t.danger, t.ok, t.warn]) {
            expect(contrast(foreground, background), greaterThanOrEqualTo(4.5));
          }
        }
        for (final pair in [
          (t.onAction, t.action),
          (t.onTone, t.tone),
          (t.onSecondaryContainer, t.secondaryContainer),
          (t.onAccentContainer, t.accentContainer),
          (t.onDangerContainer, t.dangerContainer),
        ]) {
          expect(contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
        }
        expect(t.action, isNot(palette.scheme(!dark).primary));
        expect(t.raised, isNot(t.surface));
      });
    }
  }
  test('theme colors interpolate instead of switching at the middle', () {
    final a = GalleryTokens(scheme: GalleryPalette.values.first.scheme(false));
    final b = GalleryTokens(scheme: GalleryPalette.values.last.scheme(true));
    for (final progress in [.25, .5, .75]) {
      final middle = a.lerp(b, progress);
      expect(middle.action, Color.lerp(a.action, b.action, progress));
      expect(middle.surface, Color.lerp(a.surface, b.surface, progress));
      expect(middle.ok, Color.lerp(a.ok, b.ok, progress));
      expect(middle.warn, Color.lerp(a.warn, b.warn, progress));
    }
    final before = a
        .lerp(b, .49)
        .shadows(GalleryElevation.floating)
        .first
        .color;
    final after = a.lerp(b, .51).shadows(GalleryElevation.floating).first.color;
    expect((after.a - before.a).abs(), lessThan(.03));
  });
  test('new card faces keep text readable across each gradient', () {
    for (final face in GalleryCardFace.values) {
      for (final background in [face.start, face.end]) {
        expect(
          contrast(face.foreground, background),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(face.secondaryForeground, background),
          greaterThanOrEqualTo(4.5),
        );
      }
    }
  });
  test('semantic elevation separates cards, floating objects and modals', () {
    final light = GalleryTokens(
      scheme: GalleryPalette.values.first.scheme(false),
    );
    final dark = GalleryTokens(
      scheme: GalleryPalette.values.first.scheme(true),
    );
    expect(light.shadows(GalleryElevation.flat), isEmpty);
    expect(light.shadows(GalleryElevation.card).single.blurRadius, 8);
    expect(light.shadows(GalleryElevation.floating).length, 2);
    expect(
      light.shadows(GalleryElevation.modal).last.blurRadius,
      greaterThan(light.shadows(GalleryElevation.floating).last.blurRadius),
    );
    expect(
      light.shadows(GalleryElevation.floating).first.color,
      isNot(dark.shadows(GalleryElevation.floating).first.color),
    );
  });
  for (final docked in [false, true]) {
    test('navigation geometry $docked accounts for safe area and IME once', () {
      for (final safe in [0.0, 24.0, 48.0]) {
        for (final keyboard in [0.0, 300.0]) {
          for (final scale in [1.0, 1.5, 2.0]) {
            final layout = GalleryNavigationLayout(
              MediaQueryData(
                viewPadding: EdgeInsets.only(bottom: safe),
                viewInsets: EdgeInsets.only(bottom: keyboard),
                textScaler: TextScaler.linear(scale),
              ),
              docked: docked,
            );
            expect(layout.safeBottom, keyboard > 0 ? 0 : safe);
            expect(layout.contentHeight, (docked ? 65 : 62) + (scale - 1) * 20);
            expect(layout.listBottom, layout.occupiedHeight + 16);
            expect(layout.toastBottom, layout.occupiedHeight + 12);
          }
        }
      }
    });
  }
}
