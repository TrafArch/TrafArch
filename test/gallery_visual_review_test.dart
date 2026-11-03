import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';

/// Opt-in artifact capture; normal CI does not depend on installed desktop fonts.
void main() {
  final output = Platform.environment['GALLERY_CAPTURE_DIR'];
  testWidgets('capture the full design review with readable local fonts', (
    tester,
  ) async {
    final previousShadows = debugDisableShadows;
    try {
      debugDisableShadows = false;
      final c = GalleryController(
        GalleryData(
          jsonDecode(File('assets/gallery/fixtures.json').readAsStringSync())
              as GalleryRecord,
        ),
      );
      addTearDown(c.dispose);
      tester.view.physicalSize = Size(
        double.tryParse(Platform.environment['GALLERY_CAPTURE_WIDTH'] ?? '') ??
            412,
        892,
      );
      tester.view.devicePixelRatio = 1;
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.runAsync(() async {
        final sans = FontLoader('sans-serif')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                await File('C:/Windows/Fonts/msyh.ttc').readAsBytes(),
              ),
            ),
          );
        final mono = FontLoader('monospace')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                await File('C:/Windows/Fonts/consola.ttf').readAsBytes(),
              ),
            ),
          );
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await Future.wait([sans.load(), mono.load(), icons.load()]);
        await Directory(output!).create(recursive: true);
      });
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: GalleryApp(controller: c),
        ),
      );
      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: name);
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await render.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$output/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      for (final dark in [false, true]) {
        final mode = dark ? 'dark' : 'light';
        c.reset();
        c.update(() {
          c.monet = false;
          c.themeMode = dark ? ThemeMode.dark : ThemeMode.light;
        });
        await capture('$mode-home');
        c.update(() {
          c.hasRead = true;
          c.current.saved = true;
        });
        await capture('$mode-home-card');
        c.navigate(GalleryPage.cards);
        await capture('$mode-wallet');
        await tester.tap(find.byTooltip('深圳通 管理'));
        await capture('$mode-card-menu');
        c.back();
        c.navigate(GalleryPage.trips);
        await capture('$mode-trips');
        c.showOverlay(
          GalleryOverlay.source,
          anchor: const Rect.fromLTWH(16, 120, 145, 42),
        );
        await capture('$mode-filter-menu');
        c.back();
        c.navigate(GalleryPage.expert);
        await capture('$mode-expert');
        for (final card in [c.cards[1], c.cards[2]]) {
          c.openCard(card);
          await capture('$mode-detail-${card.id}');
          c.back();
        }
        c.openCard(c.current);
        c.update(() => c.detailTab = 1);
        await capture('$mode-weekly');
        c.update(() => c.detailTab = 2);
        await capture('$mode-detail-info');
        c.back();
        c.navigate(GalleryPage.knowledge);
        await capture('$mode-knowledge');
        c.back();
        c.navigate(GalleryPage.home);
        c.showOverlay(GalleryOverlay.save, card: c.current);
        await capture('$mode-save-popup');
        c.back();
        c.navigate(GalleryPage.footprints);
        await capture('$mode-footprints');
        c.navigate(GalleryPage.settings);
        await tester.scrollUntilVisible(find.text('莫奈取色'), 250);
        await capture('$mode-settings');
        c.back();
        c.navigate(GalleryPage.cards);
        c.update(() => c.docked = true);
        await capture('$mode-wallet-docked');
        final normalSize = tester.view.physicalSize;
        tester.view.physicalSize = const Size(320, 1000);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        c.update(() => c.docked = false);
        await capture('$mode-wallet-320-2x');
        c.openCard(c.cards[1]);
        c.update(() {
          c.cards[1].name = '深圳通 全国交通一卡通互联互通版';
          c.cards[1].rawBalance = '-1,234,567.89';
        });
        await capture('$mode-detail-long-320-2x');
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        tester.view.physicalSize = normalSize;
      }
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      debugDisableShadows = previousShadows;
    }
  }, skip: output == null);
}
