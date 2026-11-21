import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/app/trafarch_app.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_name_extension.dart';
import 'package:transit_card_analyzer/features/home/presentation/pending_save_presenter.dart';
import 'package:transit_card_analyzer/features/octopus/octopus_balance_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/platform/nfc/felica_channel.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_service.dart';
import 'package:transit_card_analyzer/platform/nfc/octopus_channel.dart';
import 'package:transit_card_analyzer/platform/storage/archive_document_store.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/protocols/octopus/octopus_balance.dart';
import 'package:transit_card_analyzer/shared/domain/archive_conflict_policy.dart';

import 'support/gallery_scroll.dart';
import 'support/test_database.dart';

void main() {
  for (final kind in _CardKind.values) {
    testWidgets(
      '2.x uses one ${kind.name} result across three pages and saves supported cards',
      (tester) async {
        final fixture = await _showGallery(tester, kind);
        final app = fixture.app;
        expect(fixture.native.discoveries, 0);
        expect(find.text('模拟数据'), findsNothing);
        expect(find.text('读取自 NFC'), findsNothing);
        expect(find.byTooltip('扫码'), findsOneWidget);

        await _read(tester, '开始读取');
        expect(app.hasCompletedRead, isTrue, reason: '${app.error}');
        final balanceNumber = switch (kind) {
          _CardKind.tu || _CardKind.cu => '100.00',
          _CardKind.suica => '1,000',
          _CardKind.octopus => '50.00',
        };
        final balanceText = switch (kind) {
          _CardKind.tu || _CardKind.cu => '¥100.00',
          _CardKind.suica => 'JP￥1,000',
          _CardKind.octopus => r'HK$50.00',
        };
        expect(find.text(balanceNumber), findsWidgets);
        expect(app.pendingCardSave, isNull);
        final saved = (await tester.runAsync(app.cardRepository.getAllCards))!;
        expect(saved, hasLength(kind == _CardKind.octopus ? 0 : 1));
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();

        await _navigate(tester, 'trips');
        expect(find.text(balanceText), findsWidgets);
        if (kind == _CardKind.octopus) {
          expect(find.text('暂无行程记录'), findsOneWidget);
        } else {
          expect(
            find
                    .byKey(const ValueKey('trip-endpoints'))
                    .evaluate()
                    .isNotEmpty ||
                find
                    .byKey(const ValueKey('trip-one-way'))
                    .evaluate()
                    .isNotEmpty,
            isTrue,
          );
        }
        if (kind == _CardKind.suica) {
          expect(find.textContaining('不会补造进出站时刻'), findsOneWidget);
        }

        await _navigate(tester, 'expert');
        final raw = find.text('APDU / Raw Data');
        await tester.ensureVisible(raw);
        await tester.tap(raw);
        await tester.pumpAndSettle();
        expect(find.textContaining('APDU 命令 / 响应'), findsOneWidget);
        expect(fixture.native.discoveries, 1);
        expect(find.byTooltip('导出卡片记录'), findsNothing);

        await _navigate(tester, 'cards');
        await _settleIo(tester);
        expect(
          find.text(saved.firstOrNull?.displayName ?? '还没有保存的卡片'),
          findsOneWidget,
        );
        await _unmount(tester);
      },
    );
  }

  testWidgets('transit data parsing includes the 1.x expert fields', (
    tester,
  ) async {
    await _showGallery(tester, _CardKind.tu);
    await _read(tester, '开始读取');
    await _navigate(tester, 'expert');
    await tester.tap(find.text('交通数据解析'));
    await tester.pumpAndSettle();

    expect(find.text('交通应用信息'), findsOneWidget);
    expect(find.text('钱包与余额'), findsNothing);
    expect(find.text('读取内容'), findsNothing);
    expect(find.text('应用序列号'), findsNothing);
    expect(find.text('余额'), findsOneWidget);
    expect(find.text('币种'), findsOneWidget);
    await tester.tap(find.text('交通应用信息'));
    await tester.pumpAndSettle();
    expect(find.text('应用类型标识'), findsOneWidget);
    final applicationType = find.text('应用类型标识');
    await tester.scrollUntilVisible(
      applicationType,
      260,
      scrollable: galleryVerticalScroll(),
    );
    expect(find.text('应用类型标识'), findsOneWidget);
    expect(find.text('应用版本'), findsOneWidget);
    expect(find.text('生效日期'), findsOneWidget);
    expect(find.text('失效日期'), findsOneWidget);
    expect(find.text('发卡机构 FCI'), findsOneWidget);

    final process = find.text('过程记录 · 0x1A / 0x1E');
    await tester.scrollUntilVisible(
      process,
      260,
      scrollable: galleryVerticalScroll(),
    );
    await tester.ensureVisible(process);
    await tester.pumpAndSettle();
    await tester.tap(process);
    await tester.pumpAndSettle();
    expect(find.textContaining('未读取到过程记录'), findsOneWidget);

    final transactions = find.text('交易明细');
    await tester.scrollUntilVisible(
      transactions,
      260,
      scrollable: galleryVerticalScroll(),
    );
    await tester.ensureVisible(transactions);
    await tester.pumpAndSettle();
    await tester.tap(transactions);
    await tester.pumpAndSettle();
    expect(find.textContaining('交易 1 ·'), findsOneWidget);
    expect(find.text('交易序号'), findsOneWidget);
    expect(find.text('终端编号'), findsOneWidget);
    expect(find.text('终端解码'), findsOneWidget);
    expect(find.text('原始数据'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets(
    '2.x manually saves, shows frozen history, renames and confirms delete',
    (tester) async {
      final fixture = await _showGallery(tester, _CardKind.tu, autoSave: false);
      final app = fixture.app;
      await _read(tester, '开始读取');
      expect(find.byType(SaveCardDialog), findsNothing);
      expect(await tester.runAsync(app.cardRepository.getAllCards), isEmpty);
      await tester.tap(find.text('保存卡片'));
      await _settleIo(tester);
      expect(find.byType(TextField), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '确认'));
      await _settleIo(tester);
      expect(app.pendingCardSave, isNull);
      final card = (await tester.runAsync(app.cardRepository.getAllCards))!
          .single;

      await _navigate(tester, 'cards');
      await _settleIo(tester);
      await tester.tap(find.text(card.displayName));
      await _settleIo(tester);
      expect(find.text('最近交易'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('trip-endpoints')).evaluate().isNotEmpty ||
            find.byKey(const ValueKey('trip-one-way')).evaluate().isNotEmpty,
        isTrue,
      );
      await tester.tap(find.text('消费统计'));
      await tester.pumpAndSettle();
      expect(find.text('总消费'), findsOneWidget);
      expect(find.text('¥10.00'), findsWidgets);

      await tester.tap(find.text('卡片信息'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('${card.displayName} 管理'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重命名'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '阶段二档案');
      await tester.tap(find.widgetWithText(FilledButton, '确认'));
      await _settleIo(tester);
      final renamed = (await tester.runAsync(app.cardRepository.getAllCards))!
          .single;
      expect(renamed.id, card.id);
      expect(renamed.sessionDataJson, card.sessionDataJson);
      expect(renamed.displayName, '阶段二档案');

      final cardMenu = find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip && (widget.message?.endsWith(' 管理') ?? false),
      );
      await tester.tap(cardMenu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除本卡'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(
        await tester.runAsync(app.cardRepository.getAllCards),
        hasLength(1),
      );
      await tester.tap(cardMenu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除本卡'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await _settleIo(tester);
      expect(await tester.runAsync(app.cardRepository.getAllCards), isEmpty);
      expect(find.text('还没有保存的卡片'), findsOneWidget);
      await _unmount(tester);
    },
  );

  testWidgets(
    'failed repeat retains the previous summary without exposing stale trips',
    (tester) async {
      final fixture = await _showGallery(tester, _CardKind.suica);
      await _read(tester, '开始读取');
      fixture.native.noTag = true;
      await _read(tester, '再次读取');
      expect(find.text('读取失败，保留上次结果'), findsOneWidget);
      expect(find.text('1,000'), findsOneWidget);
      expect(find.text('重新读取'), findsOneWidget);
      expect(fixture.app.pendingCardSave, isNull);
      await _navigate(tester, 'trips');
      expect(find.text('暂无本次读取结果'), findsOneWidget);
      await _unmount(tester);
    },
  );

  test(
    'gallery auto-save cannot stage or write before NFC close succeeds',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final fixture = _Fixture(_CardKind.tu);
      final app = fixture.app;
      addTearDown(app.dispose);
      await app.init();
      final reached = fixture.native.closeReached = Completer<void>();
      final close = fixture.native.close = Completer<void>();
      fixture.native.closeFails = true;
      final reading = app.scanOnceForGallery();
      await reached.future;
      expect(app.pendingCardSave, isNull);
      expect(await app.cardRepository.getAllCards(), isEmpty);
      close.complete();
      await reading;
      expect(app.hasCompletedRead, isFalse);
      expect(app.pendingCardSave, isNull);
      expect(await app.cardRepository.getAllCards(), isEmpty);
    },
  );

  testWidgets(
    '2.x settings persist and apply ask/skip/overwrite to the same archive',
    (tester) async {
      final fixture = await _showGallery(tester, _CardKind.tu);
      final app = fixture.app;
      await _read(tester, '开始读取');
      final original = (await tester.runAsync(app.cardRepository.getAllCards))!
          .single;
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      final conflictRow = find.text('已存在的记录');
      await tester.scrollUntilVisible(
        conflictRow,
        200,
        scrollable: galleryVerticalScroll(),
      );
      await tester.tap(conflictRow);
      await tester.pumpAndSettle();
      await tester.tap(find.text('每次询问'));
      await tester.pumpAndSettle();
      expect(app.archiveConflictPolicy, ArchiveConflictPolicy.ask);
      expect(
        await app.settings.store.read(SettingsKeys.archiveConflictPolicy),
        'ask',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      fixture.native.balanceFen = 8000;
      fixture.native.readAt = _readAt.add(const Duration(minutes: 1));
      await _read(tester, '再次读取');
      await _settleIo(tester);
      await tester.tap(find.text('保存卡片'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '确认'));
      await tester.pumpAndSettle();
      expect(find.text('记录已存在'), findsOneWidget);
      expect(
        (await tester.runAsync(app.cardRepository.getAllCards))!.single,
        original,
      );
      await tester.tap(find.text('跳过'));
      await tester.pumpAndSettle();
      expect(app.pendingCardSave, isNull);

      await app.setArchiveConflictPolicy(ArchiveConflictPolicy.skip);
      await _read(tester, '再次读取');
      expect(find.text('记录已存在'), findsNothing);
      expect(
        (await tester.runAsync(app.cardRepository.getAllCards))!.single,
        original,
      );
      await app.setArchiveConflictPolicy(ArchiveConflictPolicy.overwrite);
      await _read(tester, '再次读取');
      final updated = (await tester.runAsync(app.cardRepository.getAllCards))!
          .single;
      expect(updated.id, original.id);
      expect(updated.balanceFen, 8000);
      await _unmount(tester);
    },
  );

  testWidgets('2.x local backup supports export and import cancel/confirm', (
    tester,
  ) async {
    final fixture = await _showGallery(tester, _CardKind.suica);
    final app = fixture.app;
    await _read(tester, '开始读取');
    final card = (await tester.runAsync(app.cardRepository.getAllCards))!
        .single;
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    final exportRow = find.text('导出卡片记录');
    await tester.scrollUntilVisible(
      exportRow,
      220,
      scrollable: galleryVerticalScroll(),
    );
    await tester.tap(exportRow);
    await tester.pumpAndSettle();
    await tester.tap(find.text('完整备份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择保存位置'));
    await _settleIo(tester);
    expect(fixture.documents.file!.content, contains('trafarch.archive'));
    await tester.runAsync(() => app.cardRepository.deleteCard(card.id));
    await _settleIo(tester);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    final importRow = find.text('导入卡片记录');
    await tester.scrollUntilVisible(
      importRow,
      220,
      scrollable: galleryVerticalScroll(),
    );
    Future<void> preview() async {
      await tester.tap(importRow);
      await _settleIo(tester);
      expect(find.text('导入卡片 JSON'), findsOneWidget);
    }

    await preview();
    expect(fixture.documents.opens, 1);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await _settleIo(tester);
    expect(await tester.runAsync(app.cardRepository.getAllCards), isEmpty);
    await preview();
    await tester.tap(find.widgetWithText(FilledButton, '导入'));
    await _settleIo(tester);
    final restored = (await tester.runAsync(app.cardRepository.getAllCards))!
        .single;
    expect(restored.sessionDataJson, card.sessionDataJson);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await _navigate(tester, 'cards');
    await _settleIo(tester);
    expect(find.text(card.displayName), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('Octopus close failure stops progress and permits a retry', (
    tester,
  ) async {
    final fixture = await _showGallery(tester, _CardKind.octopus);
    fixture.octopusChannel.closeFails = true;
    await _read(tester, '开始读取');
    expect(fixture.app.nfcReleaseFailed, isTrue);
    expect(fixture.app.hasCompletedRead, isFalse);
    expect(find.text('未能读到卡片'), findsOneWidget);
    expect(find.text('50.00'), findsNothing);

    fixture.octopusChannel.closeFails = false;
    await _read(tester, '重新读取');
    expect(fixture.app.hasCompletedRead, isTrue);
    expect(find.text('50.00'), findsWidgets);
    expect(fixture.native.discoveries, 2);
    expect(fixture.app.pendingCardSave, isNull);
    await _unmount(tester);
  });

  testWidgets(
    'navigate away cancels one discovery and ignores its late reply',
    (tester) async {
      final fixture = await _showGallery(tester, _CardKind.suica);
      final response = fixture.native.response = Completer<NfcScanResult?>();
      final close = fixture.native.close = Completer<void>();
      final start = find.text('开始读取');
      await tester.tap(start);
      await tester.tap(start);
      await tester.pump();
      expect(fixture.native.discoveries, 1);

      await _navigate(tester, 'expert');
      expect(fixture.native.closes, 1);
      expect(find.text('暂无本次读取结果'), findsOneWidget);
      await _navigate(tester, 'home');
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '开始读取'))
            .onPressed,
        isNull,
      );

      close.complete();
      response.complete(fixture.native.tag);
      await tester.pumpAndSettle();
      expect(fixture.app.hasCompletedRead, isFalse);
      expect(fixture.app.felicaResult, isNull);
      expect(fixture.app.pendingCardSave, isNull);
      expect(fixture.native.discoveries, 1);
      await _unmount(tester);
    },
  );

  testWidgets('initial live UI opens 2.x without the legacy screen', (
    tester,
  ) async {
    _size(tester);
    final fixture = _Fixture(_CardKind.suica);
    fixture.app.scan.autoScanConsumed = true;
    var created = 0;
    await tester.pumpWidget(
      TransitCardAnalyzerApp(
        enableUpdateChecks: false,
        enableLiveBeta: true,
        initialLiveUi: true,
        createDependencies: () {
          created++;
          return fixture.app;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(GalleryApp), findsOneWidget);
    expect(find.text('开始读取'), findsOneWidget);
    expect(find.text('启用 2.x 实卡体验'), findsNothing);
    expect(
      tester.widget<GalleryApp>(find.byType(GalleryApp)).liveApp,
      same(fixture.app),
    );
    expect(created, 1);
    await _unmount(tester);
  });

  testWidgets(
    'production toggle shares dependencies and waits for successful close',
    (tester) async {
      _size(tester);
      final fixture = _Fixture(_CardKind.suica);
      final app = fixture.app;
      app.scan.autoScanConsumed = true;
      var created = 0;
      await tester.pumpWidget(
        TransitCardAnalyzerApp(
          enableUpdateChecks: false,
          enableLiveBeta: true,
          createDependencies: () {
            created++;
            return app;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      final toggle = find.widgetWithText(SwitchListTile, '启用新界面（beta）');
      await tester.scrollUntilVisible(
        toggle,
        250,
        scrollable: galleryVerticalScroll(),
      );
      await tester.tap(toggle);
      await tester.pump();
      expect(find.text('启用 2.x 实卡体验'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      await tester.tap(find.text('确认开启'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<GalleryApp>(find.byType(GalleryApp)).liveApp,
        same(app),
      );
      expect(fixture.native.discoveries, 0);

      final response = fixture.native.response = Completer<NfcScanResult?>();
      fixture.native.closeFails = true;
      await tester.tap(find.text('开始读取'));
      await tester.pump();
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      final returnToOldUi = find.widgetWithText(SwitchListTile, '启用新界面（beta）');
      await tester.scrollUntilVisible(
        returnToOldUi,
        250,
        scrollable: galleryVerticalScroll(),
      );
      await tester.ensureVisible(returnToOldUi);
      await tester.pumpAndSettle();
      await tester.tap(returnToOldUi);
      await tester.pumpAndSettle();
      expect(find.text('NFC 尚未关闭，无法切换。请重试。'), findsOneWidget);
      expect(find.byType(GalleryApp), findsOneWidget);

      fixture.native.closeFails = false;
      final close = fixture.native.close = Completer<void>();
      await tester.ensureVisible(returnToOldUi);
      await tester.pumpAndSettle();
      await tester.tap(returnToOldUi);
      await tester.pump();
      expect(find.text('正在关闭读卡连接…'), findsOneWidget);
      expect(find.byType(GalleryApp), findsOneWidget);
      close.complete();
      response.complete(fixture.native.tag);
      await tester.pumpAndSettle();
      expect(find.byType(GalleryApp), findsNothing);
      expect(app.disposed, isFalse);
      expect(app.hasCompletedRead, isFalse);
      expect(fixture.native.discoveries, 1);
      expect(created, 1);
      await _unmount(tester);
      expect(app.disposed, isTrue);
    },
  );
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

Future<void> _read(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(TextButton, label));
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 40)),
  );
  await tester.pumpAndSettle();
}

Future<void> _navigate(WidgetTester tester, String page) async {
  await tester.tap(find.byKey(ValueKey('nav-$page')));
  await tester.pumpAndSettle();
}

Future<void> _settleIo(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.runAsync(
    () async => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  await tester.pumpAndSettle();
}

void _size(WidgetTester tester) {
  tester.view.physicalSize = const Size(412, 892);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<_Fixture> _showGallery(
  WidgetTester tester,
  _CardKind kind, {
  bool autoSave = true,
}) async {
  _size(tester);
  final fixture = _Fixture(kind, autoSave: autoSave);
  addTearDown(fixture.app.dispose);
  await tester.runAsync(fixture.app.init);
  expect(fixture.app.autoSaveEnabled, autoSave);
  await tester.pumpWidget(GalleryApp(liveApp: fixture.app));
  await tester.pumpAndSettle();
  return fixture;
}

enum _CardKind { tu, cu, suica, octopus }

final _readAt = DateTime(2026, 11, 21, 10, 42);
const _idmBytes = [1, 2, 3, 4, 5, 6, 7, 8];
const _idm = '0102030405060708';

class _Fixture {
  _Fixture(_CardKind kind, {bool autoSave = true}) : native = _Reader(kind) {
    app = AppDependencies(
      database: testDatabase(),
      bundle: MissingTestAssets(),
      channel: native,
      felicaChannel: native,
      logger: AppLogger(store: MemoryLogStore()),
      archiveDocumentStore: documents,
      settingsStore: MemorySettingsStore({
        SettingsKeys.autoSaveEnabled: '$autoSave',
      }),
      octopusController: OctopusBalanceController(
        channel: octopusChannel,
        execute:
            ({
              required transceiveFelica,
              required isCancelled,
              expectedCardIdm,
            }) async => OctopusBalanceResult(
              balanceMinor: 5000,
              idmHex: _idm,
              readAt: _readAt,
            ),
      ),
    );
  }

  final _Reader native;
  final documents = _ArchiveFiles();
  final octopusChannel = _OctopusChannel();
  late final AppDependencies app;
}

class _Reader implements NfcChannel, FelicaChannel {
  _Reader(this.kind);
  final _CardKind kind;
  bool get isIsoDep => kind == _CardKind.tu || kind == _CardKind.cu;
  bool noTag = false;
  bool closeFails = false;
  bool _selected = false;
  int discoveries = 0;
  int closes = 0;
  Completer<NfcScanResult?>? response;
  Completer<void>? close;
  Completer<void>? closeReached;
  DateTime readAt = _readAt;
  int balanceFen = 10000;

  NfcScanResult get tag => NfcScanResult(
    uid: _idm,
    technologies: [isIsoDep ? 'IsoDep' : 'NfcF'],
    isoDepConnected: isIsoDep,
    felicaConnected: !isIsoDep,
    nfcFSystemCode: isIsoDep
        ? null
        : kind == _CardKind.suica
        ? '0003'
        : '8008',
    timestamp: readAt,
  );

  @override
  Future<NfcScanResult?> scanOnce() async {
    discoveries++;
    return response == null ? (noTag ? null : tag) : await response!.future;
  }

  @override
  Future<void> stopScan() async {
    closes++;
    if (closeReached case final reached? when !reached.isCompleted) {
      reached.complete();
    }
    await close?.future;
    if (closeFails) throw StateError('close failed');
  }

  @override
  Future<List<int>> transceive(List<int> frame) async =>
      isIsoDep ? _apdu(frame) : _felica(frame);

  List<int> _apdu(List<int> frame) {
    final cu = kind == _CardKind.cu;
    const rejected = [0x6A, 0x82];
    const missing = [0x6A, 0x83];
    if (frame[1] == 0xA4) {
      final aid = frame.skip(5).take(frame[4]).toList();
      _selected = listEquals(
        aid,
        cu
            ? [0xA0, 0, 0, 0, 3, 0x86, 0x98, 7, 1]
            : [0xA0, 0, 0, 6, 0x32, 1, 1, 5],
      );
      return _selected || frame[2] == 0 ? _ok(const []) : rejected;
    }
    if (!_selected) return rejected;
    if (frame[1] == 0x5C) {
      return _ok([0, 0, balanceFen >> 8, balanceFen & 0xFF]);
    }
    if (frame[1] == 0xB0) {
      return switch (frame[2] & 0x1F) {
        0x15 => _ok(cu ? _cuPublic : _tuPublic),
        0x16 when !cu => _ok(List.filled(55, 0)),
        0x17 when !cu => _ok(List.filled(60, 0)),
        _ => rejected,
      };
    }
    if (frame[1] == 0xB2) {
      if (frame[3] == 0xC4 && frame[2] == 1) return _ok(_transaction);
      return missing;
    }
    return rejected;
  }

  List<int> _felica(List<int> frame) {
    final system = kind == _CardKind.suica ? [0, 3] : [0x80, 8];
    return switch (frame[1]) {
      0 => _packet([1, ..._idmBytes, ...List.filled(8, 0), ...system]),
      0x0C => _packet([0x0D, ..._idmBytes, 1, ...system]),
      0x02 => _packet([0x03, ..._idmBytes, 1, 0, 0]),
      0x06 => _suicaBlocks(frame),
      _ => throw StateError('Unexpected command'),
    };
  }

  List<int> _suicaBlocks(List<int> frame) {
    final countOffset = 11 + frame[10] * 2;
    final count = frame[countOffset];
    return _packet([
      0x07,
      ..._idmBytes,
      0,
      0,
      count,
      for (var index = 0; index < count; index++)
        ...(frame[countOffset + 2 + index * 2] == 0
            ? [0x16, 1, 0, 2, 0x35, 0x70, 1, 2, 1, 3, 0xE8, 3, 0, 0, 1, 0]
            : List<int>.filled(16, 0)),
    ]);
  }

  static List<int> _ok(List<int> payload) => [...payload, 0x90, 0];
  static List<int> _packet(List<int> payload) => [
    payload.length + 1,
    ...payload,
  ];

  static const _tuPublic = [
    0,
    0,
    0x30,
    0x50,
    0,
    0,
    0,
    0,
    1,
    1,
    0x03,
    0x10,
    0x50,
    0x60,
    1,
    0x23,
    0x45,
    0x67,
    0x89,
    0,
    0x20,
    0x24,
    1,
    1,
    0x20,
    0x29,
    0x12,
    0x31,
    0,
    0,
  ];
  static const _cuPublic = [
    1,
    0x23,
    0x0A,
    1,
    1,
    0x26,
    0,
    0,
    1,
    2,
    0x0A,
    1,
    0x11,
    0x22,
    0x33,
    0x44,
    0x55,
    0x66,
    0x77,
    0x88,
    0x20,
    0x24,
    1,
    1,
    0x20,
    0x30,
    0x12,
    0x31,
    0,
    0,
  ];
  static const _transaction = [
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    3,
    0xE8,
    6,
    0x12,
    0x34,
    0x56,
    0x78,
    0x90,
    0x12,
    0x20,
    0x24,
    5,
    1,
    8,
    0x30,
    0,
  ];
}

class _OctopusChannel implements OctopusNfcChannel {
  bool closeFails = false;

  @override
  Future<NfcScanResult?> scanSession(String sessionId) async => NfcScanResult(
    sessionId: sessionId,
    uid: _idm,
    technologies: const ['NfcF'],
    isoDepConnected: false,
    felicaConnected: true,
    timestamp: _readAt,
  );

  @override
  Future<List<int>> exchangeSession(String sessionId, List<int> frame) async =>
      [11, 5, ..._idmBytes, 0];

  @override
  Future<void> closeSession(String sessionId) async {
    if (closeFails) throw StateError('close failed');
  }
}

class _ArchiveFiles implements ArchiveDocumentStore {
  PickedArchiveDocument? file;
  int opens = 0;

  @override
  Future<PickedArchiveDocument?> openJson() async {
    opens++;
    return file;
  }

  @override
  Future<String?> saveJson(String fileName, String content) async {
    file = PickedArchiveDocument(name: fileName, content: content);
    return fileName;
  }
}
