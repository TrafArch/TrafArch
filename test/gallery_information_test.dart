import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_info.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';
import 'package:transit_card_analyzer/shared/app_support.dart';

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
  });
  tearDown(() => c.dispose());

  testWidgets(
    'settings opens separate information pages with nested back navigation',
    (tester) async {
      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      c.navigate(GalleryPage.settings);
      await tester.pumpWidget(GalleryApp(controller: c));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('版本 ${AppInfo.version}'),
        450,
        scrollable: galleryVerticalScroll(),
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('版本 ${AppInfo.version}')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('版本 ${AppInfo.version}'));
      await tester.pumpAndSettle();
      expect(c.page, GalleryPage.about);
      expect(c.overlay, isNull);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey(GalleryPage.about)),
          matching: find.byType(ModalBarrier),
        ),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('nav-home')), findsNothing);
      expect(find.text('kajolno'), findsOneWidget);
      await tester.tap(find.text('致谢'));
      await tester.pumpAndSettle();
      expect(c.page, GalleryPage.acknowledgements);
      expect(find.text('读卡识途数据源'), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(c.page, GalleryPage.about);
      LicenseRegistry.addLicense(
        () => Stream.value(
          const LicenseEntryWithLineBreaks([
            'information-test-package',
          ], 'Sample license terms'),
        ),
      );
      addTearDown(LicenseRegistry.reset);
      await tester.tap(find.text('开放源代码许可'));
      await tester.pumpAndSettle();
      expect(c.page, GalleryPage.licenses);
      await tester.tap(find.text('information-test-package'));
      await tester.pumpAndSettle();
      expect(find.text('Sample license terms'), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(c.page, GalleryPage.settings);
      await tester.tap(find.text('问题反馈'));
      await tester.pumpAndSettle();
      expect(c.page, GalleryPage.feedback);
      expect(c.overlay, isNull);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(c.page, GalleryPage.settings);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final qqInstalled in [true, false]) {
    testWidgets(
      'feedback opens selected contact and copies exact values, QQ installed=$qqInstalled',
      (tester) async {
        final opened = <String>[];
        final copied = <String>[];
        final launched = <Uri>[];
        const launcherChannel = MethodChannel(
          'plugins.flutter.io/url_launcher',
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          launcherChannel,
          (call) async {
            final url = Uri.parse((call.arguments as Map)['url'] as String);
            launched.add(url);
            return url.scheme == 'https' || qqInstalled;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            launcherChannel,
            null,
          ),
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied.add((call.arguments as Map)['text'] as String);
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        c.navigate(GalleryPage.feedback);
        await tester.pumpWidget(
          GalleryApp(
            controller: c,
            openWebLink: (url) async => opened.add(url.toString()),
            openEmail: (email) async {
              opened.add(email);
              return true;
            },
          ),
        );
        await tester.pumpAndSettle();
        expect(opened, isEmpty);
        await tester.tap(find.text('QQ 群'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('复制群号'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('邮箱'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('复制邮箱'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('填写反馈问卷'));
        await tester.pumpAndSettle();
        expect(launched, hasLength(qqInstalled ? 1 : 2));
        if (!qqInstalled) expect(launched.last.toString(), AppSupport.qqJoin);
        expect(launched.first.scheme, 'mqqapi');
        expect(launched.first.queryParameters['uin'], AppSupport.qqGroup);
        expect(opened, [AppSupport.email, AppSupport.survey]);
        expect(copied, [AppSupport.qqGroup, AppSupport.email]);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('failed support links show a recoverable error and allow retry', (
    tester,
  ) async {
    var attempts = 0;
    c.navigate(GalleryPage.feedback);
    await tester.pumpWidget(
      GalleryApp(
        controller: c,
        openWebLink: (_) async {
          attempts++;
          if (attempts == 1) throw StateError('no browser');
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('填写反馈问卷'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('无法打开页面'),
      150,
      scrollable: galleryVerticalScroll(),
    );
    expect(find.textContaining('无法打开页面'), findsOneWidget);
    expect(find.text('复制问卷链接'), findsOneWidget);
    await tester.tap(find.text('填写反馈问卷'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.textContaining('无法打开页面'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
