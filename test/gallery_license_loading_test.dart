import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';

import 'support/gallery_scroll.dart';

class _ObservedLicense extends LicenseEntry {
  _ObservedLicense(this.index);
  final int index;
  int reads = 0;
  String get name => 'package-${index.toString().padLeft(3, '0')}';
  @override
  Iterable<String> get packages => [name];
  @override
  Iterable<LicenseParagraph> get paragraphs {
    reads++;
    return [LicenseParagraph('License terms for $name', 0)];
  }
}

void main() {
  late GalleryController c;
  setUp(() {
    LicenseRegistry.reset();
    c = GalleryController(
      GalleryData(
        jsonDecode(File('assets/gallery/fixtures.json').readAsStringSync())
            as GalleryRecord,
      ),
    )..monet = false;
  });
  tearDown(() {
    c.dispose();
    LicenseRegistry.reset();
  });

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    c.navigate(GalleryPage.about);
    await tester.pumpWidget(GalleryApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开放源代码许可'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'opening a long license list parses no closed body and only builds nearby rows',
    (tester) async {
      final entries = List.generate(120, _ObservedLicense.new);
      LicenseRegistry.addLicense(
        () => Stream<LicenseEntry>.fromIterable(entries),
      );
      await mount(tester);
      expect(c.page, GalleryPage.licenses);
      expect(entries.fold(0, (sum, item) => sum + item.reads), 0);
      expect(find.byKey(const ValueKey('license-row-119')), findsNothing);
      await tester.tap(find.text(entries.first.name));
      await tester.pumpAndSettle();
      expect(entries.first.reads, 1);
      expect(
        find.text('License terms for ${entries.first.name}'),
        findsOneWidget,
      );
      c.update(() => c.themeMode = ThemeMode.dark);
      await tester.pumpAndSettle();
      await tester.tap(find.text(entries.first.name));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entries.first.name));
      await tester.pumpAndSettle();
      expect(
        entries.first.reads,
        1,
        reason: 'Repeated expansion reuses parsed paragraphs',
      );
      await tester.scrollUntilVisible(
        find.text(entries.last.name),
        600,
        scrollable: galleryVerticalScroll(),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(entries.last.name));
      await tester.pumpAndSettle();
      expect(entries.last.reads, 1);
      expect(entries.fold(0, (sum, item) => sum + item.reads), 2);
      expect(
        find.text('License terms for ${entries.last.name}'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed license collection can be retried without parsing collapsed text',
    (tester) async {
      var attempts = 0;
      final entry = _ObservedLicense(1);
      LicenseRegistry.addLicense(() {
        attempts++;
        return attempts == 1
            ? Stream<LicenseEntry>.error(
                StateError('temporary license read failure'),
              )
            : Stream<LicenseEntry>.value(entry);
      });
      await mount(tester);
      expect(find.text('重新加载许可'), findsOneWidget);
      await tester.tap(find.text('重新加载许可'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.text(entry.name), findsOneWidget);
      expect(entry.reads, 0);
      await tester.tap(find.text(entry.name));
      await tester.pumpAndSettle();
      expect(entry.reads, 1);
      expect(find.text('License terms for ${entry.name}'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
