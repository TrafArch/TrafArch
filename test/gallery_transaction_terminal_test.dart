import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';
import 'package:transit_card_analyzer/gallery/gallery_preferences.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_service.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';

import 'qingdao_cu_wallet_regression_test.dart' show qingdaoMetroReplay;
import 'support/test_database.dart';

void main() {
  for (final cu in [false, true]) {
    final system = cu ? 'CU' : 'TU';
    testWidgets('$system 实时读卡和已存档案逐笔显示各自的终端编号', (tester) async {
      const first = '000012345601';
      final last = cu ? '0000AB345602' : '000012345602';
      final app = await _readCard(
        tester,
        _TerminalReader(
          _walletReplay(cu: cu, terminals: [first, '000000000000', last]),
        ),
      );
      expect(await tester.runAsync(app.cardRepository.getAllCards), isEmpty);
      await tester.tap(find.byKey(const ValueKey('nav-trips')));
      await tester.pumpAndSettle();
      await _checkThreeTransactions(tester, first, last);

      final pending = app.pendingCardSave!;
      expect(
        await tester.runAsync(
          () => app.acceptPendingSave(pending.pendingSaveId),
        ),
        isTrue,
      );
      final saved = (await tester.runAsync(app.cardRepository.getAllCards))!
          .single;
      final archivedCard = find.byKey(ValueKey('wallet-card-${saved.id}'));
      await tester.tap(find.byKey(const ValueKey('nav-cards')));
      await _waitFor(tester, () => archivedCard.evaluate().isNotEmpty);
      expect(archivedCard, findsOneWidget);
      await tester.tap(archivedCard);
      await tester.pumpAndSettle();
      expect(find.text('最近交易'), findsOneWidget);
      await _checkThreeTransactions(tester, first, last);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  testWidgets('实卡同构 CU 双端行程分别显示进出站终端', (tester) async {
    await _readCard(
      tester,
      _TerminalReader(qingdaoMetroReplay(withExitClock: true)),
    );
    await tester.tap(find.byKey(const ValueKey('nav-trips')));
    await tester.pumpAndSettle();
    const entry = '123456780003';
    const exit = '123456780001';
    expect(find.text(entry), findsNothing);
    expect(find.text(exit), findsNothing);
    await _openTicket(tester, find.byKey(const ValueKey('trip-endpoints')));
    expect(_sheetText('终端编号'), findsOneWidget);
    _expectField('CU 0x18 #2 · 进站', entry);
    _expectField('CU 0x18 #1 · 出站', exit);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('合并不同来源时每个编号与自己的来源同列展示', (tester) async {
    _size(tester);
    final controller = GalleryController(
      GalleryData(
        jsonDecode(File('assets/gallery/fixtures.json').readAsStringSync())
            as GalleryRecord,
      ),
    );
    addTearDown(controller.dispose);
    final sample = controller.trips.first;
    controller
      ..hasRead = true
      ..monet = false
      ..trips = [
        {
          ...sample,
          'source': '0x18 交易明细',
          'sources': ['0x18 交易明细', '0x1E 过程记录'],
          'terminalNumbers': const <(String, String?, String)>[
            ('0x18 交易明细', '进站', '000012343001'),
            ('0x1E 过程记录', '出站', '000000AF12343002'),
          ],
        },
      ]
      ..navigate(GalleryPage.trips);
    await tester.pumpWidget(GalleryApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('终端编号'), findsNothing);
    expect(find.text('000012343001'), findsNothing);
    expect(find.text('000000AF12343002'), findsNothing);
    await _openTicket(tester, find.text('陆家嘴'));
    expect(_sheetText('终端编号'), findsOneWidget);
    _expectField('0x18 交易明细 · 进站', '000012343001');
    _expectField('0x1E 过程记录 · 出站', '000000AF12343002');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

final _sheet = find.byKey(const ValueKey('gallery-modal-surface'));
Finder _sheetText(String value) =>
    find.descendant(of: _sheet, matching: find.text(value));

void _expectField(String label, String value) {
  final row = find.ancestor(of: _sheetText(label), matching: find.byType(Row));
  expect(row, findsOneWidget);
  expect(find.descendant(of: row, matching: find.text(value)), findsOneWidget);
}

Future<void> _openTicket(WidgetTester tester, Finder ticket) async {
  expect(ticket, findsOneWidget);
  await tester.ensureVisible(ticket);
  await tester.pumpAndSettle();
  await tester.tap(ticket);
  await tester.pumpAndSettle();
  expect(_sheet, findsOneWidget);
}

Future<void> _checkThreeTransactions(
  WidgetTester tester,
  String first,
  String last,
) async {
  final tickets = find.byKey(const ValueKey('gallery-transaction'));
  expect(tickets, findsNWidgets(3));
  for (final (index, expected) in [first, '未记录', last].indexed) {
    expect(find.text('终端编号'), findsNothing);
    expect(find.text(first), findsNothing);
    expect(find.text(last), findsNothing);
    await _openTicket(tester, tickets.at(index));
    expect(_sheetText('交易详情'), findsOneWidget);
    _expectField('终端编号', expected);
    for (final other in [
      first,
      last,
      '000000000000',
    ].where((v) => v != expected)) {
      expect(_sheetText(other), findsNothing);
    }
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    expect(tester.takeException(), isNull);
  }
}

void _size(WidgetTester tester) {
  // Keep all three records within the lazy list's viewport/cache on both pages.
  tester.view.physicalSize = const Size(412, 1024);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<AppDependencies> _readCard(
  WidgetTester tester,
  NfcChannel reader,
) async {
  _size(tester);
  final app = AppDependencies(
    database: testDatabase(),
    bundle: MissingTestAssets(),
    channel: reader,
    logger: AppLogger(store: MemoryLogStore()),
    settingsStore: MemorySettingsStore({
      SettingsKeys.autoSaveEnabled: 'false',
      SettingsKeys.monetEnabled: 'false',
    }),
  );
  addTearDown(app.dispose);
  final preferences = GalleryPreferences(faceStore: _NoFaces());
  addTearDown(preferences.dispose);
  await tester.runAsync(app.init);
  await tester.pumpWidget(GalleryApp(liveApp: app, preferences: preferences));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(TextButton, '开始读取'));
  await _waitFor(tester, () => app.hasCompletedRead && !app.scanning);
  expect(app.hasCompletedRead, isTrue, reason: '${app.error}');
  expect(app.scanning, isFalse);
  return app;
}

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  await tester.pump();
  for (var attempt = 0; attempt < 50 && !ready(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
}

class _NoFaces implements GalleryFaceStore {
  @override
  Future<GalleryFaceSnapshot?> read(String cardId) async => null;

  @override
  Future<void> write(String cardId, GalleryFaceSnapshot snapshot) async {}

  @override
  Future<void> delete(String cardId) async {}
}

class _TerminalReader implements NfcChannel {
  const _TerminalReader(this.replay);

  final Future<List<int>> Function(List<int>) replay;

  @override
  Future<NfcScanResult?> scanOnce() async => NfcScanResult(
    uid: '0102030405060708',
    technologies: const ['IsoDep'],
    isoDepConnected: true,
    timestamp: DateTime(2026, 11, 21, 10, 42),
  );

  @override
  Future<void> stopScan() async {}

  @override
  Future<List<int>> transceive(List<int> apdu) => replay(apdu);
}

Future<List<int>> Function(List<int>) _walletReplay({
  required bool cu,
  required List<String> terminals,
}) {
  final aid = cu ? 'A00000000386980701' : 'A000000632010105';
  var selected = false;
  String hex(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
  return (apdu) async {
    final ins = apdu[1];
    final slot = apdu[2];
    final sfi = apdu[3];
    final body = switch (ins) {
      0xA4 when slot == 0 => '9000',
      0xA4 =>
        (selected = hex(apdu.skip(5).take(apdu[4]).toList()) == aid)
            ? '9000'
            : '6A82',
      _ when !selected => '6A82',
      0x5C => '000027109000',
      0xB0 when slot & 0x1F == 0x15 =>
        cu
            ? '01230A010126000001020A011122334455667788202401012030123100009000'
            : '0000305000000000010103105060012345678900202401012029123100009000',
      0xB0 when !cu && slot & 0x1F == 0x16 => '${'00' * 55}9000',
      0xB0 when !cu && slot & 0x1F == 0x17 => '${'00' * 60}9000',
      0xB2 when sfi == 0xC4 && slot >= 1 && slot <= terminals.length =>
        '000${4 - slot}000000000003E806${terminals[slot - 1]}'
            '20240501083${4 - slot}009000',
      0xB2 => '6A83',
      _ => '6A82',
    };
    return [
      for (var i = 0; i < body.length; i += 2)
        int.parse(body.substring(i, i + 2), radix: 16),
    ];
  };
}
