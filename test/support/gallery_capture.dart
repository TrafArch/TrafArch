import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every review scenario runs in CI with Flutter's test fonts. An explicitly
/// requested artifact may additionally use readable fonts installed locally.
Future<void> prepareGalleryCapture(
  WidgetTester tester, {
  String? outputDirectory,
}) async {
  await tester.runAsync(() async {
    final loaders = <FontLoader>[
      FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')),
    ];
    if (outputDirectory != null) {
      if (Platform.isWindows) {
        for (final (family, path) in [
          ('sans-serif', 'C:/Windows/Fonts/msyh.ttc'),
          ('monospace', 'C:/Windows/Fonts/consola.ttf'),
        ]) {
          final file = File(path);
          if (await file.exists()) {
            loaders.add(
              FontLoader(family)..addFont(
                Future.value(ByteData.sublistView(await file.readAsBytes())),
              ),
            );
          }
        }
      }
      await Directory(outputDirectory).create(recursive: true);
    }
    await Future.wait(loaders.map((loader) => loader.load()));
  });
}

/// Render the real widget tree even when no export directory was requested.
/// PNG writing is optional; rendering failures remain normal test failures.
Future<void> captureGalleryFrame(
  WidgetTester tester, {
  required GlobalKey boundary,
  required String name,
  String? outputDirectory,
}) async {
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 2);
    try {
      expect(image.width, (render.size.width * 2).ceil(), reason: name);
      expect(image.height, (render.size.height * 2).ceil(), reason: name);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(bytes, isNotNull, reason: name);
      final png = bytes!.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      expect(png.take(8), [137, 80, 78, 71, 13, 10, 26, 10], reason: name);
      if (outputDirectory != null) {
        await File('$outputDirectory/$name.png').writeAsBytes(png);
      }
    } finally {
      image.dispose();
    }
  });
}
