import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/app/trafarch_app.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_name_extension.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/home/presentation/pending_save_presenter.dart';
import 'package:transit_card_analyzer/features/octopus/octopus_balance_controller.dart';
import 'package:transit_card_analyzer/features/recovery/recovery_state.dart';
import 'package:transit_card_analyzer/features/updates/update_service.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart'
    show GalleryRecord;
import 'package:transit_card_analyzer/gallery/gallery_theme.dart';
import 'package:transit_card_analyzer/gallery/gallery_preferences.dart';
import 'package:transit_card_analyzer/platform/nfc/felica_channel.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_service.dart';
import 'package:transit_card_analyzer/platform/nfc/octopus_channel.dart';
import 'package:transit_card_analyzer/platform/storage/archive_document_store.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/protocols/octopus/octopus_balance.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/shared/domain/archive_conflict_policy.dart';

import 'support/gallery_scroll.dart';
import 'support/test_database.dart';

class _MemoryFaceStore implements GalleryFaceStore {
  final values = <String, GalleryFaceSnapshot>{};

  @override
  Future<GalleryFaceSnapshot?> read(String cardId) async => values[cardId];

  @override
  Future<void> write(String cardId, GalleryFaceSnapshot snapshot) async {
    values[cardId] = snapshot;
  }

  @override
  Future<void> delete(String cardId) async => values.remove(cardId);
}

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
        if (kind == _CardKind.tu) {
          expect(find.text('3105 0600 1234 5678 900'), findsOneWidget);
          expect(find.textContaining('最近读取'), findsNothing);
        }
        expect(app.pendingCardSave, isNull);
        final saved = (await tester.runAsync(app.cardRepository.getAllCards))!;
        expect(saved, hasLength(kind == _CardKind.octopus ? 0 : 1));
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();

        await _navigate(tester, 'trips');
        expect(find.text(balanceText), findsWidgets);
        if (kind == _CardKind.octopus) {
          expect(find.text('暂无行程记录'), findsOneWidget);
        } else if (kind == _CardKind.tu || kind == _CardKind.cu) {
          // These bare debits carry no transport-mode evidence.
          expect(
            find.byKey(const ValueKey('gallery-transaction')),
            findsOneWidget,
          );
          expect(find.text('公交'), findsNothing);
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

  testWidgets(
    'Shanghai TU/CU mirrors and CU-only older recharges appear once',
    (tester) async {
      final fixture = await _showGallery(
        tester,
        _CardKind.tu,
        reader: _ShanghaiWalletReader(),
      );
      await _read(tester, '开始读取');
      await _navigate(tester, 'trips');
      final controller = _liveAdapter(tester).controller;
      void checkRecords(List<GalleryRecord> rows) {
        String amount(GalleryRecord row) =>
            (row['amount'] as String).replaceAll(' ', '');
        final credits = rows.where((row) => row['kind'] == 'recharge');
        expect(credits.map((row) => (row['isoDate'], amount(row))), [
          ('2024-05-04', '+¥20.00'),
          ('2024-05-03', '+¥50.00'),
          ('2024-05-02', '+¥20.00'),
          ('2024-05-01', '+¥10.00'),
        ]);
        expect(credits.map((row) => row['title']), everyElement('充值'));
        expect(rows.where((row) => row['kind'] != 'recharge').map(amount), [
          '-¥4.00',
        ]);
        expect(rows.map((row) => row['isoDate']), [
          '2024-05-04',
          '2024-05-04',
          '2024-05-03',
          '2024-05-02',
          '2024-05-01',
        ]);
      }

      checkRecords(controller.trips);
      await _navigate(tester, 'home');
      fixture.native.readAt = _readAt.add(const Duration(minutes: 1));
      await _read(tester, '再次读取');
      expect(fixture.native.discoveries, 2);
      checkRecords(controller.trips);
      await _navigate(tester, 'cards');
      await _settleIo(tester);
      final saved = (await tester.runAsync(
        fixture.app.cardRepository.getAllCards,
      ))!.single;
      await tester.tap(find.text(saved.displayName));
      await _settleIo(tester);
      checkRecords(controller.ledger(controller.selectedCard));

      final liveRecords = controller.trips;
      fixture.app.recoveredCapture = RecoveryCapture(
        readAt: _readAt,
        summary: {'cardName': saved.displayName},
        frames: const [],
        snapshotJson: saved.sessionDataJson,
      );
      await fixture.app.setAutoSaveEnabled(false);
      await _settleIo(tester);
      expect(identical(controller.trips, liveRecords), isFalse);
      checkRecords(controller.trips);
      await _unmount(tester);
    },
  );

  testWidgets(
    'skipping a saved card keeps its new recharge in the current read',
    (tester) async {
      final fixture = await _showGallery(tester, _CardKind.tu);
      final app = fixture.app;
      final previous = _Reader._transaction.toList()..[9] = 0x02;
      fixture.native.transactions = [previous];
      await _read(tester, '开始读取');
      await _settleIo(tester);
      final saved = (await tester.runAsync(app.cardRepository.getAllCards))!
          .single;
      await app.setArchiveConflictPolicy(ArchiveConflictPolicy.skip);

      final next = previous.toList()
        ..[1] = 2
        ..setRange(7, 9, [0x13, 0x88])
        ..[19] = 2;
      fixture.native.transactions = [next, previous];
      fixture.native.readAt = _readAt.add(const Duration(minutes: 1));
      await _read(tester, '再次读取');
      await _settleIo(tester);
      expect(fixture.native.discoveries, 2);
      expect(app.pendingCardSave, isNull);
      final existing = (await tester.runAsync(app.cardRepository.getAllCards))!
          .single;
      expect(existing.sessionDataJson, saved.sessionDataJson);

      await _navigate(tester, 'trips');
      final controller = _liveAdapter(tester).controller;
      List<String> credits(List<GalleryRecord> rows) => [
        for (final row in rows)
          if (row['kind'] == 'recharge')
            (row['amount'] as String).replaceAll(' ', ''),
      ];
      expect(credits(controller.trips), ['+¥50.00', '+¥10.00']);
      await _navigate(tester, 'cards');
      await _settleIo(tester);
      await tester.tap(find.text(saved.displayName));
      await _settleIo(tester);
      expect(credits(controller.ledger(controller.selectedCard)), ['+¥10.00']);
      await _unmount(tester);
    },
  );

  testWidgets('2.x keeps a wallet recharge between its adjacent transactions', (
    tester,
  ) async {
    final fixture = await _showGallery(tester, _CardKind.tu);
    // The wallet stores the newest record first. All three share a minute.
    List<int> transaction(int sequence, int type, int seconds) =>
        _Reader._transaction.toList()
          ..[1] = sequence
          ..[9] = type
          ..[22] = seconds;
    fixture.native.transactions = [
      transaction(3, 0x06, 3),
      transaction(2, 0x02, 2),
      transaction(1, 0x06, 1),
    ];
    await _read(tester, '开始读取');
    await _navigate(tester, 'trips');
    expect(find.text('充值'), findsOneWidget);
    final credit = find.text('+¥ 10.00');
    expect(credit, findsOneWidget);
    expect(find.text('公交'), findsNothing);
    expect(find.byIcon(Icons.directions_bus_outlined), findsNothing);
    final controller = _liveAdapter(tester).controller;
    expect(controller.trips.map((record) => record['kind']), [
      'other',
      'recharge',
      'other',
    ]);
    expect(controller.trips.map((record) => record['time']), [
      '08:30:03',
      '08:30:02',
      '08:30:01',
    ]);
    await tester.tap(find.text('全部方式'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-option-充值')));
    await tester.pumpAndSettle();
    expect(controller.filteredTrips, hasLength(1));
    await tester.tap(credit);
    await tester.pumpAndSettle();
    expect(find.text('交易类型'), findsOneWidget);
    expect(find.text('08:30:02'), findsOneWidget);
    expect(find.text('交通方式'), findsNothing);
    controller.back();
    await tester.pumpAndSettle();
    await _navigate(tester, 'cards');
    await _settleIo(tester);
    final saved = (await tester.runAsync(
      fixture.app.cardRepository.getAllCards,
    ))!.single;
    await tester.tap(find.text(saved.displayName));
    await _settleIo(tester);
    expect(find.text('充值'), findsOneWidget);
    expect(credit, findsOneWidget);
    expect(find.text('公交'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('2.x preserves mixed-precision Suica block order', (
    tester,
  ) async {
    final fixture = await _showGallery(tester, _CardKind.suica);
    fixture.native.suicaBlocks = [
      _Reader._suicaBlock.toList()
        ..[1] = 0x02
        ..[14] = 2,
      _Reader._suicaBlock.toList()
        ..[1] = 0x46
        ..[6] = 0x49
        ..[7] = 0xE0,
    ];
    await _read(tester, '开始读取');
    await _navigate(tester, 'trips');
    final records = _liveAdapter(tester).controller.trips;
    expect(records, hasLength(2));
    final record = records.first;
    expect(record['kind'], 'recharge');
    expect(record['isoDate'], isNotNull);
    expect(record['time'], '时刻未记录');
    expect(record.containsKey('entryTime'), isFalse);
    expect(records.last['time'], '09:15');
    expect(records.last['isoDate'], record['isoDate']);
    expect(find.text('充值'), findsOneWidget);
    expect(find.text('00:00'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('2.x retains a CU recharge date when the card clock is invalid', (
    tester,
  ) async {
    final fixture = await _showGallery(tester, _CardKind.cu);
    fixture.native.cuRecharge = _Reader._transaction.toList()
      ..[9] = 0x02
      ..[20] = 0xFF;
    await _read(tester, '开始读取');
    await _navigate(tester, 'trips');
    final record = _liveAdapter(tester).controller.trips
        .singleWhere((row) => row['kind'] == 'recharge');
    expect(record['isoDate'], '2024-05-01');
    expect(record['time'], '交易时间未知');
    expect(record.containsKey('entryTime'), isFalse);
    expect(record.containsKey('exitTime'), isFalse);
    await _unmount(tester);
  });

  testWidgets('2.x shows application probes only in expert information', (
    tester,
  ) async {
    final fixture = await _showGallery(
      tester,
      _CardKind.tu,
      reader: _ShanghaiWalletReader(),
    );
    await _read(tester, '开始读取');
    await _navigate(tester, 'expert');
    await tester.tap(find.text('信息获取'));
    await tester.pumpAndSettle();
    expect(find.text('逐应用探测'), findsOneWidget);
    expect(find.text('查看记录原码'), findsWidgets);

    await _navigate(tester, 'cards');
    await _settleIo(tester);
    final saved = (await tester.runAsync(
      fixture.app.cardRepository.getAllCards,
    ))!.single;
    await tester.tap(find.text(saved.displayName));
    await _settleIo(tester);
    await tester.tap(find.text('卡片信息'));
    await tester.pumpAndSettle();
    expect(find.text('完整卡号'), findsOneWidget);
    await tester.ensureVisible(find.text('协议'));
    await tester.pumpAndSettle();
    expect(find.text('逐应用探测'), findsNothing);
    expect(find.text('查看记录原码'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('saved card information omits captured frame JSON and raw actions', (
    tester,
  ) async {
    final fixture = await _showGallery(tester, _CardKind.tu);
    await _read(tester, '开始读取');
    await _navigate(tester, 'cards');
    await _settleIo(tester);
    final saved = (await tester.runAsync(
      fixture.app.cardRepository.getAllCards,
    ))!.single;
    final snapshot = CardSessionSnapshot.decode(saved.sessionDataJson!)!;
    expect(
      snapshot.rawEvidence.any((row) => row['kind'] == 'physical_frame'),
      isTrue,
    );

    await tester.tap(find.text(saved.displayName));
    await _settleIo(tester);
    await tester.tap(find.text('卡片信息'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('协议'));
    await tester.pumpAndSettle();
    expect(find.text('完整卡号'), findsOneWidget);
    expect(find.text('原始数据'), findsNothing);
    expect(find.text('捕获时的原始读取证据'), findsNothing);
    expect(find.textContaining('physical_frame'), findsNothing);
    expect(find.byTooltip('复制原始数据'), findsNothing);
    expect(find.byTooltip('原始数据反馈预览'), findsNothing);
    await _unmount(tester);
  });

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

  testWidgets('2.x provider information uses the standard expert section', (
    tester,
  ) async {
    final fixture = await _showGallery(tester, _CardKind.tu);
    fixture.native.historicalBytes = '4D 54 00 8C 00 30 86 65 12 34 56 78';
    await _read(tester, '开始读取');
    await _navigate(tester, 'expert');

    expect(find.text('机构信息'), findsOneWidget);
    expect(find.text('芯片提供机构'), findsOneWidget);
    expect(find.text('IC卡提供机构'), findsOneWidget);
    expect(find.text('北京清华同方微电子（008C）'), findsOneWidget);
    expect(find.text('金邦达（8665）'), findsOneWidget);

    await tester.tap(find.text('机构信息'));
    await tester.pumpAndSettle();
    expect(find.text('芯片提供机构'), findsNothing);
    await tester.tap(find.text('机构信息'));
    await tester.pumpAndSettle();
    expect(find.text('芯片提供机构'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('expert read time uses the device-local instant', (tester) async {
    final fixture = await _showGallery(tester, _CardKind.tu);
    fixture.native.readAt = DateTime.utc(2026, 11, 21, 2, 42);
    await _read(tester, '开始读取');
    await _navigate(tester, 'expert');

    final local = fixture.native.readAt.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    final expected =
        '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
    await tester.scrollUntilVisible(
      find.text('读取时间'),
      260,
      scrollable: galleryVerticalScroll(),
    );
    await tester.ensureVisible(find.text('读取时间'));
    await tester.pumpAndSettle();
    expect(find.text('读取时间'), findsOneWidget);
    expect(find.text(expected), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('2.x shows the Shenzhen local wallet when TU balance is absent', (
    tester,
  ) async {
    final fixture = await _showGallery(
      tester,
      _CardKind.tu,
      autoSave: false,
      shenzhen: true,
    );
    await _read(tester, '开始读取');

    expect(fixture.app.parsedCard?.parserId, CardParserIds.shenzhenTunion);
    expect(fixture.app.parsedCard?.info.balanceFen, isNull);
    expect(fixture.app.parsedCard?.localCard?.info.observedBalance, 12345);
    expect(find.text('余额未知'), findsNothing);
    expect(find.text('123.45'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image ==
                const AssetImage('assets/gallery/shenzhen-tong-logo.png'),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('交通联合 CHINA T-UNION'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('2.x shows a standalone Shenzhen local wallet balance', (
    tester,
  ) async {
    final fixture = await _showGallery(
      tester,
      _CardKind.tu,
      autoSave: false,
      shenzhen: true,
      tuWallet: false,
    );
    await _read(tester, '开始读取');

    expect(fixture.app.parsedCard?.parserId, CardParserIds.localCard);
    expect(fixture.app.parsedCard?.localCard?.info.observedBalance, 12345);
    expect(find.text('余额未知'), findsNothing);
    expect(find.text('123.45'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image ==
                const AssetImage('assets/gallery/shenzhen-tong-logo.png'),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('交通联合 CHINA T-UNION'), findsNothing);
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
      expect(find.byKey(const ValueKey('gallery-transaction')), findsOneWidget);
      expect(find.text('公交'), findsNothing);
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
    'turning NFC off ends the waiting prompt and turning it on restores manual reading',
    (tester) async {
      final states = StreamController<NfcAdapterState>.broadcast(sync: true);
      addTearDown(states.close);
      final fixture = await _showGallery(
        tester,
        _CardKind.suica,
        nfcAdapterStates: states.stream,
      );
      final start = find.widgetWithText(TextButton, '开始读取');
      final response = fixture.native.response = Completer<NfcScanResult?>();
      await tester.tap(start);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('home-read-progress')), findsOneWidget);

      states.add(NfcAdapterState.disabled);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('请先打开系统 NFC'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-read-progress')), findsNothing);
      expect(tester.widget<TextButton>(start).onPressed, isNull);

      states.add(NfcAdapterState.enabled);
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(start).onPressed, isNotNull);
      expect(fixture.native.discoveries, 1);
      response.complete(fixture.native.tag);
      fixture.native.response = null;
      await tester.pumpAndSettle();
      expect(fixture.app.hasCompletedRead, isFalse);
      await _read(tester, '开始读取');
      expect(find.text('1,000'), findsWidgets);

      states.add(NfcAdapterState.disabled);
      await tester.pumpAndSettle();
      expect(find.text('1,000'), findsWidgets);
      expect(find.textContaining('请先打开系统 NFC'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '再次读取'))
            .onPressed,
        isNull,
      );
      await _unmount(tester);
    },
  );

  testWidgets(
    'NFC off after close preserves the successful read and its pending auto-save',
    (tester) async {
      final states = StreamController<NfcAdapterState>.broadcast(sync: true);
      addTearDown(states.close);
      final fixture = await _showGallery(
        tester,
        _CardKind.suica,
        nfcAdapterStates: states.stream,
      );
      final app = fixture.app;
      var switchedOff = false;
      void switchOffDuringSave() {
        if (!switchedOff &&
            app.hasCompletedRead &&
            app.scanning &&
            app.pendingCardSave != null) {
          switchedOff = true;
          states.add(NfcAdapterState.disabled);
        }
      }

      app.addListener(switchOffDuringSave);
      await _read(tester, '开始读取');
      app.removeListener(switchOffDuringSave);
      expect(switchedOff, isTrue);
      expect(find.textContaining('请先打开系统 NFC'), findsOneWidget);
      expect(find.text('1,000'), findsOneWidget);
      expect(find.text('已自动保存'), findsOneWidget);
      expect(
        await tester.runAsync(app.cardRepository.getAllCards),
        hasLength(1),
      );

      states.add(NfcAdapterState.enabled);
      await tester.pumpAndSettle();
      expect(find.text('读取失败，保留上次结果'), findsNothing);
      expect(find.text('再次读取'), findsOneWidget);
      await _unmount(tester);
    },
  );

  testWidgets(
    'failed repeat retains the previous summary without exposing stale trips',
    (tester) async {
      final states = StreamController<NfcAdapterState>.broadcast(sync: true);
      addTearDown(states.close);
      final fixture = await _showGallery(
        tester,
        _CardKind.suica,
        autoSave: false,
        nfcAdapterStates: states.stream,
      );
      await _read(tester, '开始读取');
      fixture.native.noTag = true;
      await _read(tester, '再次读取');
      expect(find.text('读取失败，保留上次结果'), findsOneWidget);
      expect(find.text('1,000'), findsOneWidget);
      states.add(NfcAdapterState.disabled);
      await tester.pumpAndSettle();
      states.add(NfcAdapterState.enabled);
      await tester.pumpAndSettle();
      expect(find.text('1,000'), findsOneWidget);
      expect(find.text('重新读取'), findsOneWidget);
      expect(fixture.app.pendingCardSave, isNull);

      final response = fixture.native.response = Completer<NfcScanResult?>();
      await tester.tap(find.text('重新读取'));
      await tester.pump();
      states.add(NfcAdapterState.disabled);
      await tester.pumpAndSettle();
      expect(find.textContaining('请先打开系统 NFC'), findsOneWidget);
      expect(find.text('1,000'), findsOneWidget);
      expect(find.text('保存卡片'), findsNothing);
      states.add(NfcAdapterState.enabled);
      response.complete(fixture.native.tag);
      await tester.pumpAndSettle();
      expect(find.text('重新读取'), findsOneWidget);
      expect(find.text('保存卡片'), findsNothing);
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

    /// 「导入卡片记录」先弹来源选择：选 TrafArch 数据才进入文件预览。
    Future<void> openImportSource() async {
      await tester.tap(importRow);
      await _settleIo(tester);
      expect(find.text('选择导入来源'), findsOneWidget);
    }

    Future<void> preview() async {
      await openImportSource();
      await tester.tap(find.byKey(const ValueKey('import-source-archive')));
      await _settleIo(tester);
      expect(find.text('导入卡片 JSON'), findsOneWidget);
    }

    await preview();
    expect(fixture.documents.opens, 1);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await _settleIo(tester);
    expect(await tester.runAsync(app.cardRepository.getAllCards), isEmpty);
    // 读卡识途来源在 live 模式下只提示开发中，不得触发任何文件选择。
    await openImportSource();
    final opensBeforeTripReader = fixture.documents.opens;
    await tester.tap(find.byKey(const ValueKey('import-source-trip-reader')));
    await _settleIo(tester);
    expect(find.text('选择导入来源'), findsNothing);
    expect(find.text('正在开发中，敬请期待'), findsOneWidget);
    expect(
      fixture.documents.opens,
      opensBeforeTripReader,
      reason: '读卡识途来源不得调用 pickImport',
    );
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
    expect(find.byType(AppShell), findsNothing);
    expect(find.text('开始读取'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      tester.widget<GalleryApp>(find.byType(GalleryApp)).liveApp,
      same(fixture.app),
    );
    expect(fixture.native.discoveries, 0);
    expect(created, 1);
    await _unmount(tester);
  });

  testWidgets(
    'production toggle shares dependencies and waits for successful close',
    (tester) async {
      _size(tester);
      final fixture = _Fixture(_CardKind.suica);
      final app = fixture.app;
      var created = 0;
      await tester.pumpWidget(
        TransitCardAnalyzerApp(
          enableUpdateChecks: false,
          enableLiveBeta: true,
          initialLiveUi: true,
          createDependencies: () {
            created++;
            return app;
          },
        ),
      );
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
      final fallbackSwitch = find.widgetWithText(SwitchListTile, '使用 1.x 备用界面');
      await _openSettingsControl(tester, fallbackSwitch);
      await tester.tap(fallbackSwitch);
      await tester.pumpAndSettle();
      expect(find.text('NFC 尚未关闭，无法切换。请重试。'), findsOneWidget);
      expect(find.byType(GalleryApp), findsOneWidget);

      fixture.native.closeFails = false;
      final close = fixture.native.close = Completer<void>();
      await tester.ensureVisible(fallbackSwitch);
      await tester.pumpAndSettle();
      await tester.tap(fallbackSwitch);
      await tester.pump();
      expect(find.text('正在切换到 1.x 备用界面…'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(fallbackSwitch).onChanged, isNull);
      expect(find.byType(GalleryApp), findsOneWidget);
      close.complete();
      response.complete(fixture.native.tag);
      await tester.pumpAndSettle();
      expect(find.byType(GalleryApp), findsNothing);
      expect(tester.widget<AppShell>(find.byType(AppShell)).app, same(app));
      expect(app.disposed, isFalse);
      expect(app.hasCompletedRead, isFalse);

      final mainUiSwitch = find.widgetWithText(SwitchListTile, '返回 2.x 主界面');
      await _openSettingsControl(tester, mainUiSwitch);
      await tester.tap(mainUiSwitch);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(AppShell), findsNothing);
      expect(
        tester.widget<GalleryApp>(find.byType(GalleryApp)).liveApp,
        same(app),
      );
      expect(fixture.native.discoveries, 1);
      expect(created, 1);
      await _unmount(tester);
      expect(app.disposed, isTrue);
    },
  );

  testWidgets(
    '2.x offers configured updates and only prompts once per launch',
    (tester) async {
      _size(tester);
      var checks = 0;
      final service = UpdateService(
        currentBuild: 1,
        manifestUrl: 'https://example.com/manifest.json',
        fetch: (_, _) async => Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'format_version': 1,
              'app': {
                'build': ++checks == 1 ? 2 : 1,
                'version': '2.0.0',
                'notes': '更新说明',
                'download_url': 'https://example.com/app.apk',
              },
            }),
          ),
        ),
      );
      final fixture = _Fixture(_CardKind.suica, updateService: service);
      await tester.pumpWidget(
        TransitCardAnalyzerApp(
          enableLiveBeta: true,
          initialLiveUi: true,
          createDependencies: () => fixture.app,
        ),
      );
      await tester.pumpAndSettle();
      final updateDialog = find.byType(AlertDialog);
      expect(find.text('发现新版本 2.0.0'), findsOneWidget);
      expect(
        Theme.of(tester.element(updateDialog)).extension<GalleryTokens>(),
        isNotNull,
      );
      await tester.tap(find.text('暂不更新'));
      await tester.pumpAndSettle();

      final checkUpdates = find.text('检查更新');
      await _openSettingsControl(tester, checkUpdates);
      await tester.tap(checkUpdates);
      await tester.pumpAndSettle();
      expect(find.text('暂无更新'), findsOneWidget);
      expect(checks, 2);

      final fallbackSwitch = find.widgetWithText(SwitchListTile, '使用 1.x 备用界面');
      await tester.scrollUntilVisible(
        fallbackSwitch,
        250,
        scrollable: galleryVerticalScroll(),
      );
      await tester.ensureVisible(fallbackSwitch);
      await tester.pumpAndSettle();
      await tester.tap(fallbackSwitch);
      await tester.pumpAndSettle();
      expect(find.byType(AppShell), findsOneWidget);
      expect(updateDialog, findsNothing);
      expect(checks, 2);
      await _unmount(tester);
    },
  );

  group('settings toggles after a completed read', () {
    testWidgets('keep the read projection and publish once per tap', (
      tester,
    ) async {
      final fixture = await _showGallery(tester, _CardKind.tu, autoSave: false);
      await _read(tester, '开始读取');
      await _settleIo(tester);
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();

      final autoSave = find.widgetWithText(SwitchListTile, '读取后自动保存');
      await tester.scrollUntilVisible(
        autoSave,
        200,
        scrollable: galleryVerticalScroll(),
      );
      await tester.ensureVisible(autoSave);
      await tester.pumpAndSettle();
      final overdraft = find.widgetWithText(SwitchListTile, '上海交通卡可透支余额');
      final logs = find.widgetWithText(SwitchListTile, '记录运行日志');

      final live = _liveAdapter(tester);
      final controller = live.controller;
      var liveNotifies = 0;
      live.notifier.addListener(() => liveNotifies++);
      var prefsNotifies = 0;
      fixture.preferences.addListener(() => prefsNotifies++);

      final trips = controller.trips;
      final cards = controller.cards;
      final ledgers = controller.liveLedgers;
      expect(trips, isNotEmpty);
      expect(prefsNotifies, 0);

      // Toggling a setting must publish the switch in the same frame while the
      // read projection stays untouched: trips, cards and ledgers are the
      // expensive objects that used to be rebuilt on every notification.
      await tester.tap(autoSave);
      await tester.pump();
      expect(controller.autoSave, isTrue);
      expect(tester.widget<SwitchListTile>(autoSave).value, isTrue);
      expect(identical(controller.trips, trips), isTrue);
      expect(identical(controller.cards, cards), isTrue);
      expect(identical(controller.liveLedgers, ledgers), isTrue);
      expect(prefsNotifies, 0, reason: 'card faces must not be restored again');
      expect(
        liveNotifies,
        1,
        reason: 'one publish per tap, not one per listener',
      );

      await tester.tap(autoSave);
      await tester.pump();
      expect(controller.autoSave, isFalse);
      expect(liveNotifies, 2);
      expect(prefsNotifies, 0);
      expect(identical(controller.trips, trips), isTrue);
      await tester.pumpAndSettle();

      // Rapid reversals stay one publish per intent.
      for (final expected in [true, false, true, false]) {
        await tester.tap(autoSave);
        await tester.pump();
        expect(tester.widget<SwitchListTile>(autoSave).value, expected);
        expect(controller.autoSave, expected);
      }
      expect(liveNotifies, 6);
      expect(prefsNotifies, 0);
      expect(identical(controller.trips, trips), isTrue);
      await tester.pumpAndSettle();

      // The overdraft interpretation genuinely reprojects the records, but only
      // once per change and still without duplicate publishes.
      final beforeOverdraft = liveNotifies;
      final projected = controller.trips;
      await tester.tap(overdraft);
      await tester.pump();
      expect(controller.includeOverdraft, isTrue);
      expect(find.textContaining('总余额包含固定 8 元额度'), findsOneWidget);
      expect(identical(controller.trips, projected), isFalse);
      expect(liveNotifies, beforeOverdraft + 1);
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        logs,
        200,
        scrollable: galleryVerticalScroll(),
      );
      await tester.ensureVisible(logs);
      await tester.pumpAndSettle();
      final loggedTrips = controller.trips;
      final beforeLogs = liveNotifies;
      final beforeLogsPrefs = prefsNotifies;
      await tester.tap(logs);
      await tester.pump();
      expect(controller.logsEnabled, isTrue);
      expect(tester.widget<SwitchListTile>(logs).value, isTrue);
      expect(identical(controller.trips, loggedTrips), isTrue);
      expect(prefsNotifies, beforeLogsPrefs);
      expect(liveNotifies, beforeLogs + 1);
      await tester.pumpAndSettle();
      await _unmount(tester);
    });

    testWidgets('publish the new value before the write completes', (
      tester,
    ) async {
      final store = _PendingSettingsStore({
        SettingsKeys.autoSaveEnabled: 'true',
      });
      final fixture = await _showGallery(
        tester,
        _CardKind.tu,
        settingsStore: store,
      );
      await _read(tester, '开始读取');
      await _settleIo(tester);
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();

      final autoSave = find.widgetWithText(SwitchListTile, '读取后自动保存');
      await tester.scrollUntilVisible(
        autoSave,
        200,
        scrollable: galleryVerticalScroll(),
      );
      await tester.ensureVisible(autoSave);
      await tester.pumpAndSettle();

      await tester.tap(autoSave);
      await tester.pump();
      expect(tester.widget<SwitchListTile>(autoSave).value, isFalse);
      expect(fixture.app.autoSaveEnabled, isFalse);
      expect(store.pendingWrites, 1);
      expect(
        store.values[SettingsKeys.autoSaveEnabled],
        'true',
        reason: 'the UI must not wait for the queued disk write',
      );
      store.releaseAll();
      await tester.pumpAndSettle();
      expect(store.values[SettingsKeys.autoSaveEnabled], 'false');

      final logs = find.widgetWithText(SwitchListTile, '记录运行日志');
      await tester.scrollUntilVisible(
        logs,
        200,
        scrollable: galleryVerticalScroll(),
      );
      await tester.ensureVisible(logs);
      await tester.pumpAndSettle();
      await tester.tap(logs);
      await tester.pump();
      expect(tester.widget<SwitchListTile>(logs).value, isTrue);
      expect(fixture.app.loggingEnabled, isTrue);
      expect(store.values.containsKey(SettingsKeys.loggingEnabled), isFalse);
      store.releaseAll();
      await tester.pumpAndSettle();
      expect(store.values[SettingsKeys.loggingEnabled], 'true');
      await _unmount(tester);
    });

    testWidgets('recovery capture reprojects when the overdraft flag changes', (
      tester,
    ) async {
      final fixture = await _showGallery(tester, _CardKind.tu, autoSave: false);
      await _read(tester, '开始读取');
      await _settleIo(tester);
      final pending = fixture.app.pendingCardSave;
      expect(pending?.sessionDataJson, isNotNull);
      // A recovered capture replays the same snapshot after a restart: the
      // projection is memoized while nothing changes, but the overdraft flag
      // still decides how the records are read.
      fixture.app.recoveredCapture = RecoveryCapture(
        readAt: _readAt,
        summary: {'cardName': pending!.displayName, 'balanceText': '余额未知'},
        frames: const [],
        pending: pending,
        snapshotJson: pending.sessionDataJson,
        canSave: true,
      );
      final live = _liveAdapter(tester);
      final controller = live.controller;
      final autoSave = find.widgetWithText(SwitchListTile, '读取后自动保存');
      await _openSettingsControl(tester, autoSave);
      // The first tap after the capture is installed publishes the recovery
      // projection; the next one must still reproject because the overdraft
      // flag decides how those records are read.
      await tester.tap(autoSave);
      await tester.pump();
      final projected = controller.trips;
      expect(projected, isNotEmpty);
      final overdraft = find.widgetWithText(SwitchListTile, '上海交通卡可透支余额');
      expect(overdraft, findsOneWidget);
      await tester.tap(overdraft);
      await tester.pump();
      expect(controller.includeOverdraft, isTrue);
      expect(
        identical(controller.trips, projected),
        isFalse,
        reason: 'the overdraft flag is part of the projection signature',
      );
      await tester.pumpAndSettle();
      await _unmount(tester);
    });
  });
}

/// The live shell is created inside [GalleryApp]; its adapter exposes the
/// controller and the notifier the settings page listens to.
({Listenable notifier, GalleryController controller}) _liveAdapter(
  WidgetTester tester,
) {
  final notifier = tester
      .widgetList<InheritedNotifier>(
        find.byWidgetPredicate((widget) => widget is InheritedNotifier),
      )
      .map((widget) => widget.notifier)
      .firstWhere((candidate) => '$candidate'.contains('GalleryLiveRead'))!;
  return (
    notifier: notifier,
    controller: (notifier as dynamic).navigation as GalleryController,
  );
}

class _PendingSettingsStore implements SettingsStore {
  _PendingSettingsStore(this.values);

  final Map<String, String> values;
  final List<(String, String, Completer<void>)> _pending = [];

  int get pendingWrites => _pending.length;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) {
    final completer = Completer<void>();
    _pending.add((key, value, completer));
    return completer.future;
  }

  void releaseAll() {
    final writes = List.of(_pending);
    _pending.clear();
    for (final (key, value, completer) in writes) {
      values[key] = value;
      completer.complete();
    }
  }
}

Future<void> _openSettingsControl(WidgetTester tester, Finder control) async {
  await tester.tap(find.byTooltip('设置'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    control,
    250,
    scrollable: galleryVerticalScroll(),
  );
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
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
  _Reader? reader,
  bool shenzhen = false,
  bool tuWallet = true,
  SettingsStore? settingsStore,
  Stream<NfcAdapterState>? nfcAdapterStates,
}) async {
  _size(tester);
  final fixture = _Fixture(
    kind,
    reader: reader,
    autoSave: autoSave,
    shenzhen: shenzhen,
    tuWallet: tuWallet,
    settingsStore: settingsStore,
    nfcAdapterStates: nfcAdapterStates,
  );
  addTearDown(fixture.app.dispose);
  await tester.runAsync(fixture.app.init);
  expect(fixture.app.autoSaveEnabled, autoSave);
  final preferences = GalleryPreferences(faceStore: _MemoryFaceStore());
  addTearDown(preferences.dispose);
  fixture.preferences = preferences;
  await tester.pumpWidget(
    GalleryApp(liveApp: fixture.app, preferences: preferences),
  );
  await tester.pumpAndSettle();
  return fixture;
}

enum _CardKind { tu, cu, suica, octopus }

final _readAt = DateTime(2026, 11, 21, 10, 42);
const _idmBytes = [1, 2, 3, 4, 5, 6, 7, 8];
const _idm = '0102030405060708';

class _Fixture {
  _Fixture(
    _CardKind kind, {
    bool autoSave = true,
    _Reader? reader,
    bool shenzhen = false,
    bool tuWallet = true,
    UpdateService? updateService,
    SettingsStore? settingsStore,
    Stream<NfcAdapterState>? nfcAdapterStates,
  }) : native =
           reader ??
           (shenzhen ? _ShenzhenReader(withTu: tuWallet) : _Reader(kind)) {
    app = AppDependencies(
      database: testDatabase(),
      bundle: MissingTestAssets(),
      channel: native,
      nfcAdapterStates: nfcAdapterStates,
      felicaChannel: native,
      logger: AppLogger(store: MemoryLogStore()),
      updateService: updateService,
      archiveDocumentStore: documents,
      settingsStore:
          settingsStore ??
          MemorySettingsStore({SettingsKeys.autoSaveEnabled: '$autoSave'}),
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
  late GalleryPreferences preferences;
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
  List<List<int>> transactions = [_transaction];
  List<List<int>> suicaBlocks = [_suicaBlock];
  List<int>? cuRecharge;
  String? historicalBytes;

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
    historicalBytes: historicalBytes,
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
      if (cu && frame[3] == 0x84 && frame[2] == 1 && cuRecharge != null) {
        return _ok(cuRecharge!);
      }
      if (frame[3] == 0xC4 &&
          frame[2] >= 1 &&
          frame[2] <= transactions.length) {
        return _ok(transactions[frame[2] - 1]);
      }
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
    final blocks = [
      for (var index = 0; index < count; index++)
        frame[countOffset + 2 + index * 2],
    ];
    return _packet([
      0x07,
      ..._idmBytes,
      0,
      0,
      count,
      for (final block in blocks)
        ...(block < suicaBlocks.length
            ? suicaBlocks[block]
            : List<int>.filled(16, 0)),
    ]);
  }

  static const _suicaBlock = [
    0x16,
    1,
    0,
    2,
    0x35,
    0x70,
    1,
    2,
    1,
    3,
    0xE8,
    3,
    0,
    0,
    1,
    0,
  ];

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

// Synthetic responses reproduce the Shanghai capture's overlapping file
// windows without retaining its card, terminal or transaction details.
class _ShanghaiWalletReader extends _Reader {
  _ShanghaiWalletReader() : super(_CardKind.tu);

  String? application;
  static List<int> _record(int sequence, int type, int fen, int day) =>
      _Reader._transaction.toList()
        ..[1] = sequence
        ..[7] = fen >> 8
        ..[8] = fen & 0xff
        ..[9] = type
        ..[19] = day;
  final _credits = [
    _record(6, 0x02, 2000, 4),
    _record(5, 0x02, 5000, 3),
    _record(4, 0x02, 2000, 2),
    _record(3, 0x02, 1000, 1),
  ];

  @override
  List<int> _apdu(List<int> frame) {
    const rejected = [0x6A, 0x82];
    if (frame[1] == 0xA4) {
      final aid = frame.skip(5).take(frame[4]).toList();
      if (listEquals(aid, [0x3F, 0x00])) {
        application = null;
        return _Reader._ok([]);
      }
      application = listEquals(aid, [0xA0, 0, 0, 6, 0x32, 1, 1, 5])
          ? 'tu'
          : listEquals(aid, [0xA0, 0, 0, 0, 3, 0x86, 0x98, 7, 1])
          ? 'cu'
          : null;
      if (application == null) return rejected;
      // Each application explicitly identifies its own AID in its FCI.
      return _Reader._ok([0x6F, aid.length + 2, 0x84, aid.length, ...aid]);
    }
    if (application == null) return rejected;
    if (frame[1] == 0x5C) return _Reader._ok([0, 0, 0x20, 0x08]);
    if (frame[1] == 0xB0 && frame[2] == 0x95) {
      final public = application == 'cu'
          ? (_Reader._cuPublic.toList()..setRange(2, 4, [0x20, 0]))
          : (_Reader._tuPublic.toList()
              ..setRange(0, 4, [0x02, 0, 0x29, 0])
              ..setRange(10, 20, [3, 0x10, 0x47, 0x70, 0, 0, 0, 0, 0, 1]));
      return _Reader._ok(public);
    }
    if (frame[1] != 0xB2) return rejected;
    final rows = switch (frame[3]) {
      // The same wallet purchase and two recent credits are visible in both
      // applications. The purchase shares the latest credit's clock and POS.
      0xC4 => [_record(7, 0x09, 400, 4), ..._credits.take(2)],
      0x34 when application == 'cu' => _credits,
      _ => const <List<int>>[],
    };
    final index = frame[2] - 1;
    return index >= 0 && index < rows.length
        ? _Reader._ok(rows[index])
        : [0x6A, 0x83];
  }
}

class _ShenzhenReader extends _Reader {
  _ShenzhenReader({required this.withTu}) : super(_CardKind.tu);

  final bool withTu;
  String? _application;

  @override
  bool get isIsoDep => true;

  @override
  List<int> _apdu(List<int> frame) {
    const rejected = [0x6A, 0x82];
    const missing = [0x6A, 0x83];
    if (frame[1] == 0xA4) {
      final aid = frame.skip(5).take(frame[4]).toList();
      if (listEquals(aid, [0x3F, 0x00])) {
        _application = null;
        return _Reader._ok(const []);
      }
      if (listEquals(aid, [0xA0, 0, 0, 6, 0x32, 1, 1, 5])) {
        if (!withTu) return rejected;
        _application = 'TU';
        return _Reader._ok(const []);
      }
      if (listEquals(aid, [0x50, 0x41, 0x59, 0x2E, 0x53, 0x5A, 0x54])) {
        _application = 'SZT';
        return _Reader._ok(const []);
      }
      return rejected;
    }
    if (_application == 'TU') {
      if (frame[1] == 0x5C) return [0x69, 0x85];
      if (frame[1] == 0xB0 && frame[2] == 0x95) {
        const data =
            '0221584012345678010103104870400000000001'
            '2024010120291231AABB';
        return _Reader._ok([
          for (var index = 0; index < data.length; index += 2)
            int.parse(data.substring(index, index + 2), radix: 16),
        ]);
      }
    }
    if (_application == 'SZT') {
      if (frame[1] == 0x5C) return _Reader._ok(const [0, 0, 0x30, 0x39]);
      if (frame[1] == 0xB0 && frame[2] == 0x95) {
        final basic = List<int>.filled(32, 0)
          ..setRange(16, 20, [0x67, 0x45, 0x23, 0xF1])
          ..setRange(20, 24, [0x20, 0x24, 0x01, 0x02])
          ..setRange(24, 28, [0x20, 0x30, 0x12, 0x31]);
        return _Reader._ok(basic);
      }
      if (frame[1] == 0xB2 && frame[3] == 0xC4) {
        if (frame[2] == 1 || frame[2] == 2) {
          final kind = frame[2] == 1 ? 0x09 : 0x02;
          return _Reader._ok([
            0,
            0x17,
            0,
            0,
            0,
            0,
            0,
            0x01,
            0x2C,
            kind,
            0,
            0x12,
            0x34,
            0x56,
            0x78,
            0x90,
            0x20,
            0x26,
            0x10,
            0x31,
            0x12,
            0x34,
            0x56,
          ]);
        }
        return missing;
      }
    }
    return rejected;
  }
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
