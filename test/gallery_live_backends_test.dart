import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_service.dart';
import 'package:transit_card_analyzer/platform/qr/qr_image_picker.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/log_exporter.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/shared/app_support.dart';
import 'package:transit_card_analyzer/shared/diagnostics/diagnostic_event.dart';

import 'support/gallery_scroll.dart';
import 'support/test_database.dart';

void main() {
  testWidgets('2.x blocks QR on NFC failure and keeps one local picker owner', (
    tester,
  ) async {
    final native = _Nfc();
    final app = _App(channel: native);
    final picker = Completer<String?>();
    var pickCalls = 0;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(qrImagePickerChannel, (call) {
      expect(call.method, 'pickImage');
      pickCalls++;
      return picker.future;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(qrImagePickerChannel, null),
    );
    await _show(tester, app);
    app.parseQrBytes([0x91, 0xfe]);
    await tester.tap(find.text('开始读取'));
    await tester.pump();
    final closing = native.close = Completer<void>();
    native.failClose = true;
    await tester.tap(find.byTooltip('扫码'));
    await tester.pump();
    expect(native.closes, 1);
    expect(find.text('乘车码解析'), findsNothing);
    closing.complete();
    await tester.pumpAndSettle();
    expect(find.text('NFC 尚未关闭，无法进入扫码。请重试。'), findsOneWidget);
    expect(pickCalls, 0);

    native.failClose = false;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('扫码'));
    await tester.pumpAndSettle();
    expect(find.text('乘车码解析'), findsOneWidget);
    expect(app.recoveryRoute, '/qr');
    expect(pickCalls, 0);
    await tester.tap(find.text('从相册导入'));
    await tester.pump();
    expect(pickCalls, 1);
    expect(app.qrAcquiring, isTrue);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '扫描二维码'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(app.recoveryRoute, isNull);
    await app.scanOnceForGallery();
    expect(native.scans, 1);

    picker.complete(null);
    native.discovery.complete(null);
    await tester.pumpAndSettle();
    expect(app.qrAcquiring, isFalse);
    expect(app.qrRaw, [0x91, 0xfe]);
    expect(native.scans, 1);
    await _unmount(tester);
  });

  testWidgets(
    '2.x browse and search use the active package, not the Gallery loader',
    (tester) async {
      final temp = Directory.systemTemp.createTempSync(
        'trafarch-live-knowledge-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final path = '${temp.path}/tu-test.sqlite';
      final database = sqlite3.open(path);
      try {
        database.execute(
          'CREATE TABLE regions (region_id INTEGER, region_code TEXT, region_name TEXT, province TEXT)',
        );
        database.execute(
          "INSERT INTO regions VALUES (1, '0900', '生效包测试市', '测试地区')",
        );
        database.execute(
          'CREATE TABLE region_aliases (region_id INTEGER, source_region_name TEXT)',
        );
        database.execute(
          'CREATE TABLE all_records (region_id INTEGER, station_id INTEGER, line_name TEXT, station_name TEXT, source_key TEXT, source_field TEXT)',
        );
        database.execute(
          "INSERT INTO all_records VALUES (1, 1, '测试线路', '离线试验站', '090000001234', 'original-field')",
        );
      } finally {
        database.close();
      }
      final empty = KnowledgeBase.empty();
      final active = KnowledgeBase(
        cities: empty.cities,
        issuers: empty.issuers,
        terminalRules: empty.terminalRules,
        packagePaths: {'TU': path},
        packageVersions: const {'TU': 'active-test-v3'},
      );
      final app = _App(channel: _Nfc(), active: active);
      var previewCalls = 0;
      await _show(
        tester,
        app,
        widget: GalleryApp(
          liveApp: app,
          loadKnowledgeIndex: () async {
            previewCalls++;
            throw StateError('preview loader must not be called');
          },
        ),
      );
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('知识库'));
      await tester.pump();
      await _waitFor(tester, find.text('生效包测试市'));
      expect(find.text('active-test-v3'), findsOneWidget);
      expect(find.textContaining('数据快照'), findsNothing);
      final entry = find.byKey(const ValueKey('knowledge-search-entry'));
      await tester.tap(entry);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('knowledge-search-input')),
        '090000001234',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      final result = find.widgetWithText(ListTile, '090000001234');
      await _waitFor(tester, result);
      await tester.tap(result);
      await tester.pumpAndSettle();
      expect(find.text('离线试验站'), findsOneWidget);
      expect(find.text('original-field'), findsWidgets);
      expect(previewCalls, 0);
      await _unmount(tester);
    },
  );

  testWidgets(
    '2.x diagnostics exports only after selection, feedback sends no archive',
    (tester) async {
      final logger = AppLogger(store: MemoryLogStore());
      final exporter = _Exports();
      final app = _App(channel: _Nfc(), logger: logger, exporter: exporter);
      final links = <Uri>[];
      await _show(
        tester,
        app,
        widget: GalleryApp(
          liveApp: app,
          openWebLink: (url) async {
            links.add(url);
          },
        ),
      );
      logger.enabled = true;
      logger.startSession('local-test').end(DiagnosticOutcome.success);
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      final logs = find.text('导出诊断日志');
      await tester.scrollUntilVisible(
        logs,
        200,
        scrollable: galleryVerticalScroll(),
      );
      await tester.ensureVisible(logs);
      await tester.pumpAndSettle();
      await tester.tap(logs);
      await _waitFor(tester, find.text('日志管理器'));
      expect(exporter.content, isNull);
      expect(links, isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, '导出'));
      await tester.pumpAndSettle();
      expect(
        (jsonDecode(exporter.content!)['sessions'] as List).single['sessionId'],
        'local-test',
      );
      expect(links, isEmpty);
      final feedback = find.text('问题反馈');
      await tester.scrollUntilVisible(
        feedback,
        220,
        scrollable: galleryVerticalScroll(),
      );
      await tester.ensureVisible(feedback);
      await tester.pumpAndSettle();
      await tester.tap(feedback);
      await tester.pumpAndSettle();
      expect(links, isEmpty);
      await tester.tap(find.text('填写反馈问卷'));
      await tester.pumpAndSettle();
      expect(links, [Uri.parse(AppSupport.survey)]);
      expect(exporter.writes, 1);
      await _unmount(tester);
    },
  );
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 50 && finder.evaluate().isEmpty; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(finder, findsOneWidget);
  await tester.pumpAndSettle();
}

Future<void> _show(WidgetTester tester, _App app, {GalleryApp? widget}) async {
  tester.view.physicalSize = const Size(412, 892);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(app.dispose);
  await tester.runAsync(app.init);
  await tester.pumpWidget(widget ?? GalleryApp(liveApp: app));
  await tester.pumpAndSettle();
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

class _App extends AppDependencies {
  _App({
    required super.channel,
    AppLogger? logger,
    LogExporter? exporter,
    this.active,
  }) : super(
         bundle: MissingTestAssets(),
         database: testDatabase(),
         settingsStore: MemorySettingsStore(),
         logger: logger ?? AppLogger(store: MemoryLogStore()),
         logExporter: exporter,
       );
  final KnowledgeBase? active;
  @override
  KnowledgeBase? get knowledgeBase => active ?? super.knowledgeBase;
}

class _Nfc implements NfcChannel {
  int scans = 0;
  int closes = 0;
  bool failClose = false;
  Completer<void>? close;
  final discovery = Completer<NfcScanResult?>();

  @override
  Future<NfcScanResult?> scanOnce() {
    scans++;
    return discovery.future;
  }

  @override
  Future<void> stopScan() async {
    closes++;
    await close?.future;
    if (failClose) throw StateError('close failed');
  }

  @override
  Future<List<int>> transceive(List<int> apdu) async => const [0x6a, 0x82];
}

class _Exports implements LogExporter {
  String? content;
  int writes = 0;

  @override
  Future<String> saveToDownloads(String fileName, String content) async {
    writes++;
    this.content = content;
    return 'Download/$fileName';
  }
}
