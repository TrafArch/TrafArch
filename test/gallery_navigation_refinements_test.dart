import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';
import 'package:transit_card_analyzer/gallery/gallery_theme.dart';

const _destinations = {
  GalleryPage.home: Icons.home_outlined,
  GalleryPage.trips: Icons.route_outlined,
  GalleryPage.expert: Icons.science_outlined,
  GalleryPage.cards: Icons.credit_card_outlined,
};

void main() {
  late GalleryController controller;
  setUp(() {
    controller = GalleryController(
      GalleryData(
        jsonDecode(File('assets/gallery/fixtures.json').readAsStringSync())
            as GalleryRecord,
      ),
    );
  });
  tearDown(() => controller.dispose());

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    for (final reduceMotion in [false, true]) {
      testWidgets(
        'docked indicators keep their color through touch transitions '
        '$mode reduced=$reduceMotion',
        (tester) async {
          tester.view.physicalSize = const Size(412, 892);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              FakeAccessibilityFeatures(disableAnimations: reduceMotion);
          addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
          );
          controller.update(() {
            controller.themeMode = mode;
            controller.monet = false;
            controller.docked = true;
          });
          await tester.pumpWidget(GalleryApp(controller: controller));
          await tester.pumpAndSettle();
          final navigation = find.byKey(const ValueKey('gallery-navigation'));
          final tokens = Theme.of(tester.element(navigation))
              .extension<GalleryTokens>()!;

          Future<Map<GalleryPage, Color>> sampleBackgrounds() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              navigation,
            );
            final origin = tester.getTopLeft(navigation);
            final positions = {
              for (final destination in _destinations.entries)
                destination.key:
                    tester.getCenter(
                      find.descendant(
                        of: find.byKey(ValueKey('nav-${destination.key.name}')),
                        matching: find.byIcon(destination.value),
                      ),
                    ) -
                    origin -
                    const Offset(20, 0),
            };
            return (await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 1);
              try {
                final bytes = (await image.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                ))!.buffer.asUint8List();
                return {
                  for (final point in positions.entries)
                    point.key: _pixelAt(bytes, image.width, point.value),
                };
              } finally {
                image.dispose();
              }
            }))!;
          }

          Future<void> expectStableBackgrounds(String phase) async {
            final pixels = await sampleBackgrounds();
            for (final entry in pixels.entries) {
              _expectColorNear(
                entry.value,
                entry.key == controller.page
                    ? tokens.tone
                    : tokens.dockedNavigationSurface,
                '$phase ${entry.key.name}',
              );
            }
          }

          Future<void> expectPaletteBackgrounds(String phase) async {
            final pixels = await sampleBackgrounds();
            for (final entry in pixels.entries) {
              final actual = _rgb(entry.value);
              final surface = _rgb(tokens.dockedNavigationSurface);
              final tone = _rgb(tokens.tone);
              for (var channel = 0; channel < 3; channel++) {
                final minimum = surface[channel] < tone[channel]
                    ? surface[channel]
                    : tone[channel];
                final maximum = surface[channel] > tone[channel]
                    ? surface[channel]
                    : tone[channel];
                expect(
                  actual[channel],
                  inInclusiveRange(minimum - 2, maximum + 2),
                  reason:
                      '$phase ${entry.key.name} channel $channel: '
                      'indicator fades between its tone and the bar surface',
                );
              }
            }
          }

          await expectStableBackgrounds('initial');
          final expert = find.byKey(const ValueKey('nav-expert'));
          final cancelled = await tester.startGesture(tester.getCenter(expert));
          await tester.pump(const Duration(milliseconds: 45));
          await expectStableBackgrounds('held before cancel');
          await cancelled.cancel();
          await tester.pump(const Duration(milliseconds: 45));
          await expectStableBackgrounds('cancelled');
          expect(controller.page, GalleryPage.home);

          final selected = await tester.startGesture(tester.getCenter(expert));
          await tester.pump(const Duration(milliseconds: 45));
          await expectStableBackgrounds('held before selection');
          await selected.up();
          await tester.pump();
          await expectPaletteBackgrounds('selection frame 0ms');
          for (var frame = 0; frame < 4; frame++) {
            await tester.pump(const Duration(milliseconds: 45));
            await expectPaletteBackgrounds('selection frame $frame');
          }
          await tester.pumpAndSettle();
          await expectStableBackgrounds('expert selected');

          await tester.tap(find.byKey(const ValueKey('nav-trips')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 45));
          await expectPaletteBackgrounds('before reversal');
          await tester.tap(expert);
          await tester.pump();
          await expectPaletteBackgrounds('rapid reversal 0ms');
          for (final elapsed in [30, 30, 60, 60]) {
            await tester.pump(Duration(milliseconds: elapsed));
            await expectPaletteBackgrounds('rapid reversal +$elapsed');
          }
          await tester.pumpAndSettle();
          await expectStableBackgrounds('reversal settled');
          expect(controller.page, GalleryPage.expert);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}

Color _pixelAt(List<int> bytes, int width, Offset point) {
  final offset = (point.dy.round() * width + point.dx.round()) * 4;
  return Color.fromARGB(
    bytes[offset + 3],
    bytes[offset],
    bytes[offset + 1],
    bytes[offset + 2],
  );
}

List<int> _rgb(Color color) => [
  (color.r * 255).round(),
  (color.g * 255).round(),
  (color.b * 255).round(),
];

void _expectColorNear(Color actual, Color expected, String reason) {
  final actualChannels = _rgb(actual);
  final expectedChannels = _rgb(expected);
  for (var channel = 0; channel < 3; channel++) {
    expect(
      actualChannels[channel],
      closeTo(expectedChannels[channel], 2),
      reason: '$reason channel $channel',
    );
  }
}
