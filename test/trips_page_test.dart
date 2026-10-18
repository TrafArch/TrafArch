// 文件整体重写：原行程卡 / 0x1A / 0x1E 渲染测试改为模型级管道断言
// （scanOnce → TUnionParser → AnalysisEngine 的解析结果直接断言）；
// 新增卡片列表、卡片详情与首页保存确认对话框的组件测试。
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show DatabaseConnection, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/core/data/settings_store.dart';
import 'package:transit_card_analyzer/core/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/core/nfc/nfc_service.dart';
import 'package:transit_card_analyzer/database/app_database.dart';
import 'package:transit_card_analyzer/features/card_archive/models/card_archive_identity.dart';
import 'package:transit_card_analyzer/features/card_archive/models/card_types.dart';
import 'package:transit_card_analyzer/features/home/home_page.dart';
import 'package:transit_card_analyzer/features/cards/cards_page.dart';
import 'package:transit_card_analyzer/features/trips/trips_page.dart';
import 'package:transit_card_analyzer/state/app_state.dart';

/// 行程模块链路测试：
/// - 模型级：假 NFC 通道 + 假资产包驱动完整管道（scanOnce → TUnionParser
///   → AnalysisEngine），断言终端解码 / 0x1A / 0x1E 配对与八达通货币口径；
/// - 组件级：卡片列表展示、详情页、首页保存确认对话框与落库快照。
void main() {
  // 每个测试各开一个内存数据库：关闭多数据库调试警告。
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('行程解析管道（模型级）', () {
    test('命中站点代码表：解析出城市 / 线路 / 站点 / 类型', () async {
      final app = await _scan(
        _FakeNfcChannel()
          ..enqueueWalletScript(record: _record(terminal: '391002003100')),
      );
      final trip = app.analysis!.trips.single;
      expect(trip.cityName, '福州市');
      expect(trip.lineLabel, '2号线');
      expect(trip.stationLabel, '苏洋');
      expect(trip.stationType, '地铁');
      expect(trip.hasLocation, isTrue);
    });

    test('终端未匹配规则：保持无位置（不猜测）', () async {
      final app = await _scan(
        _FakeNfcChannel()..enqueueWalletScript(record: _record()),
      );
      final trip = app.analysis!.trips.single;
      expect(trip.isConsume, isTrue);
      expect(trip.hasLocation, isFalse);
      expect(trip.lineLabel, isNull);
      expect(trip.stationLabel, isNull);
      expect(trip.cityName, isNull);
    });

    test('充值交易（0x02）：类型与 + 金额', () async {
      final app = await _scan(
        _FakeNfcChannel()
          ..enqueueWalletScript(
            record: _record(terminal: '123456789012', rawType: 0x02),
          ),
      );
      final trip = app.analysis!.trips.single;
      expect(trip.typeName, '充值');
      expect(trip.isConsume, isFalse);
      expect(trip.sequence, 1);
      expect(trip.amountText, '+¥46.60');
    });

    test('充值交易配对 0x1E：补充交易后余额与行业', () async {
      final app = await _scan(
        _FakeNfcChannel()
          ..enqueueWalletScript(
            record: _record(terminal: '123456789012', rawType: 0x02),
            cycleRecord: _cycleRecord(typeCode: 0x09),
          ),
      );
      final trip = app.analysis!.trips.single;
      expect(trip.typeName, '充值');
      expect(trip.balanceAfterFen, 5340);
      expect(trip.balanceAfterText, '¥53.40');
      expect(trip.appTypeName, '城市轨道交通');
    });

    test('站点编码未收录：线路命中名称、站点回退原始编码', () async {
      final app = await _scan(
        _FakeNfcChannel()
          ..enqueueWalletScript(record: _record(terminal: '391002999999')),
      );
      final trip = app.analysis!.trips.single;
      expect(trip.lineLabel, '2号线');
      expect(trip.stationLabel, '99');
    });

    test('终端未命中：0x1E 出站记录按时间 + 金额配对补齐位置 / 分类 / 余额',
        () async {
      final app = await _scan(
        _FakeNfcChannel()
          ..enqueueWalletScript(
            record: _record(terminal: '123456789012'),
            cycleRecord: _cycleRecord(),
          ),
      );
      final trip = app.analysis!.trips.single;
      expect(trip.cityName, '福州市');
      expect(trip.lineLabel, '2号线');
      expect(trip.stationLabel, '苏洋');
      expect(trip.stationType, '地铁');
      expect(trip.appTypeName, '城市轨道交通');
      expect(trip.balanceAfterFen, 5340);
    });

    test('复合消费（0x09）配对 0x1E 出站：状态短名与站点', () async {
      final app = await _scan(
        _FakeNfcChannel()
          ..enqueueWalletScript(
            record: _record(terminal: '123456789012', rawType: 0x09),
            cycleRecord: _cycleRecord(),
          ),
      );
      final trip = app.analysis!.trips.single;
      expect(trip.rideStatusName, '出站');
      expect(trip.stationLabel, '苏洋');
      expect(app.isRemoteUse(trip.cityCode), isFalse);
    });

    test('复合消费（0x09）未配对 0x1E：无状态短名（不猜测）', () async {
      final app = await _scan(
        _FakeNfcChannel()
          ..enqueueWalletScript(
            record: _record(terminal: '123456789012', rawType: 0x09),
          ),
      );
      final trip = app.analysis!.trips.single;
      expect(trip.typeName, '复合消费');
      expect(trip.rideStatusName, isNull);
    });

    test('异地用卡：0x1E 交易城市与卡片城市不同', () async {
      final app = await _scan(
        _FakeNfcChannel()
          ..enqueueWalletScript(
            record: _record(terminal: '123456789012'),
            cycleRecord: _cycleRecord(cityCode: '1100'),
          ),
      );
      expect(app.isRemoteUse(app.analysis!.trips.single.cityCode), isTrue);
    });

    test('异地用卡：0x1A 进出站记录按出闸城市判定', () async {
      final app = await _scan(
        _FakeNfcChannel()
          ..enqueueWalletScript(
            record: _record(terminal: '123456789012'),
            varRecord: _railRecord(),
          ),
      );
      expect(app.isRemoteUse(app.railTransitRecord?.exitCityCode), isTrue);
    });

    test('0 元交易配对 0x1E 进站：进入进站态', () async {
      final app = await _scan(
        _FakeNfcChannel()
          ..enqueueWalletScript(
            record: _record(terminal: '123456789012', amountFen: 0),
            cycleRecord: _cycleRecord(typeCode: 0x01, amountFen: 0),
          ),
      );
      final trip = app.analysis!.trips.single;
      expect(trip.isEntry, isTrue);
      expect(trip.amountFen, 0);
      expect(trip.timeText, '2024-05-01 08:30:00');
      expect(trip.stationLabel, '苏洋');
      expect(trip.lineLabel, '2号线');
    });

    test('0 元交易未配对进站记录：保持普通行程（不猜测）', () async {
      final app = await _scan(
        _FakeNfcChannel()
          ..enqueueWalletScript(
            record: _record(terminal: '123456789012', amountFen: 0),
          ),
      );
      expect(app.analysis!.trips.single.isEntry, isFalse);
    });

    test('0 元交易配对 0x1E 出站：不误判为进站', () async {
      final app = await _scan(
        _FakeNfcChannel()
          ..enqueueWalletScript(
            record: _record(terminal: '123456789012', amountFen: 0),
            cycleRecord: _cycleRecord(typeCode: 0x04, amountFen: 0),
          ),
      );
      final trip = app.analysis!.trips.single;
      expect(trip.isEntry, isFalse);
      expect(trip.stationLabel, '苏洋');
    });

    test('0 元交易配对 0x1A 记录 1 进站：补齐进站城市与站点', () async {
      final app = await _scan(
        _FakeNfcChannel()
          ..enqueueWalletScript(
            record: _record(terminal: '123456789012', amountFen: 0),
            varRecord: _railRecord(entryTime: DateTime(2024, 5, 1, 8, 30)),
          ),
      );
      final trip = app.analysis!.trips.single;
      expect(trip.isEntry, isTrue);
      expect(trip.timeText, '2024-05-01 08:30:00');
      expect(trip.cityName, '福州市');
      expect(trip.stationLabel, '0800190030000123');
    });

    test('0 元交易未配对上 0x1A：不补齐（不猜测）', () async {
      final app = await _scan(
        _FakeNfcChannel()
          ..enqueueWalletScript(
            record: _record(terminal: '123456789012', amountFen: 0),
            varRecord: _railRecord(), // 进站 2026-08-08 09:06:02，与交易不同分钟
          ),
      );
      final trip = app.analysis!.trips.single;
      expect(trip.isEntry, isFalse);
      expect(trip.cityName, isNull);
      expect(trip.stationLabel, isNull);
    });

    test('0x1A 记录 1：解析出城市轨道进出站记录', () async {
      final app = await _scan(
        _FakeNfcChannel()
          ..enqueueWalletScript(
            record: _record(terminal: '123456789012'),
            varRecord: _railRecord(),
          ),
      );
      final rec = app.railTransitRecord!;
      expect(rec.statusName, '出闸');
      expect(rec.entryTime, DateTime(2026, 8, 8, 9, 6, 2));
      expect(rec.exitTime, DateTime(2026, 8, 8, 9, 12, 31));
      expect(rec.exitCityCode, '3501');
      expect(rec.exitStationId, '0800190030000456');
      expect(rec.entryStationId, '0800190030000123');
      expect(rec.entryBalanceFen, 2500);
      expect(rec.exitAmountFen, 300);
      expect(rec.entryBalanceFen! - rec.exitAmountFen!, 2200); // 出站钱包余额推算
    });

    test('0x1A 记录 1 未写入：不产出进出站记录', () async {
      final app = await _scan(
        _FakeNfcChannel()
          ..enqueueWalletScript(
            record: _record(terminal: '123456789012'),
            varRecord: List.filled(85, 0x00), // 初始值（全 0）
          ),
      );
      expect(app.railTransitRecord, isNull);
      expect(app.analysis!.trips.single.hasLocation, isFalse);
    });

    test('0x1A 逐条读取不可用：按整体数据前缀解析', () async {
      final app = await _scan(
        _FakeNfcChannel()
          ..enqueueWalletScript(
            record: _record(terminal: '123456789012'),
            varBlob: _railRecord(), // 整体读取兜底：85 字节裸字段体
          ),
      );
      final rec = app.railTransitRecord!;
      expect(rec.entryTime, DateTime(2026, 8, 8, 9, 6, 2));
      expect(rec.exitTime, DateTime(2026, 8, 8, 9, 12, 31));
      expect(rec.entryBalanceFen, 2500);
      expect(rec.exitAmountFen, 300);
    });

    test('0x1A 与 0x1E 同时出现（城市轨道）：以 0x1E 为准', () async {
      final app = await _scan(
        _FakeNfcChannel()
          ..enqueueWalletScript(
            record: _record(terminal: '123456789012'),
            varRecord: _railRecord(),
            cycleRecord: _cycleRecord(), // 0x1E：城市轨道交通行业
          ),
      );
      expect(app.railTransitRecord, isNull); // 0x1A 记录被抑制
      final trip = app.analysis!.trips.single;
      expect(trip.appTypeName, '城市轨道交通');
      expect(trip.cityName, '福州市');
      expect(trip.timeText, '2024-05-01 08:30:00');
      expect(trip.balanceAfterFen, 5340);
    });

    test('0x1A 与 0x1E 同时出现（公共汽电车）：不抑制 0x1A', () async {
      final app = await _scan(
        _FakeNfcChannel()
          ..enqueueWalletScript(
            record: _record(terminal: '123456789012'),
            varRecord: _railRecord(),
            cycleRecord: _cycleRecord(appTypeCode: 0x02), // 0x1E：公共汽电车行业
          ),
      );
      expect(app.railTransitRecord, isNotNull); // 行业不匹配不抑制
      expect(app.railTransitRecord!.entryBalanceFen, 2500);
      expect(app.analysis!.trips.single.appTypeName, '公共汽电车');
    });

    test('0x1A 记录 2：解析出公共汽电车上下车记录', () async {
      final app = await _scan(
        _FakeNfcChannel()
          ..enqueueWalletScript(
            record: _record(terminal: '123456789012'),
            busRecord: _busRecord(), // 记录 1 缺省为初始值
          ),
      );
      final rec = app.busTransitRecord!;
      expect(rec.statusName, '未知(0x02)'); // 实测取值未收录，显式未知
      expect(rec.entryTime, DateTime(2026, 8, 8, 9, 6, 2));
      expect(rec.exitTime, DateTime(2026, 8, 8, 9, 12, 31));
      expect(rec.exitCityCode, '3501');
      expect(rec.exitStationCode, '03');
      expect(rec.directionName, '未知方向');
      expect(rec.transactionAmountFen, 300);
      expect(rec.mileage, 5);
      expect(app.railTransitRecord, isNull); // 记录 1 未写入
    });

    test('0x1A 记录 2 未写入：不产出上下车记录', () async {
      final app = await _scan(
        _FakeNfcChannel()
          ..enqueueWalletScript(
            record: _record(terminal: '123456789012'),
            varRecord: _railRecord(),
            busRecord: List.filled(88, 0x00), // 记录 2 初始值（全 0）
          ),
      );
      expect(app.busTransitRecord, isNull);
      expect(app.railTransitRecord, isNotNull);
    });

    test('0x1A 记录 2 与 0x1E（公共汽电车）：以 0x1E 为准', () async {
      final app = await _scan(
        _FakeNfcChannel()
          ..enqueueWalletScript(
            record: _record(terminal: '123456789012'),
            busRecord: _busRecord(),
            cycleRecord: _cycleRecord(appTypeCode: 0x02), // 0x1E：公共汽电车行业
          ),
      );
      expect(app.busTransitRecord, isNull); // 0x1A 记录 2 被抑制
      final trip = app.analysis!.trips.single;
      expect(trip.appTypeName, '公共汽电车');
      expect(trip.balanceAfterFen, 5340);
    });

    test('0x1A 记录 2 与 0x1E（城市轨道）：不抑制公交记录', () async {
      final app = await _scan(
        _FakeNfcChannel()
          ..enqueueWalletScript(
            record: _record(terminal: '123456789012'),
            busRecord: _busRecord(),
            cycleRecord: _cycleRecord(), // 0x1E：城市轨道交通行业
          ),
      );
      expect(app.busTransitRecord, isNotNull); // 行业不匹配不抑制
      expect(app.busTransitRecord!.transactionAmountFen, 300);
      expect(app.analysis!.trips.single.appTypeName, '城市轨道交通');
    });

    test('0x1A 仅有整体数据：轨道按记录 1 前缀解析，公交不猜测', () async {
      final app = await _scan(
        _FakeNfcChannel()
          ..enqueueWalletScript(
            record: _record(terminal: '123456789012'),
            varBlob: [..._railRecord(), ..._busRecord()], // 85 + 88 字节拼接
          ),
      );
      expect(app.railTransitRecord, isNotNull); // 前缀按记录 1 解析
      expect(app.busTransitRecord, isNull); // 记录 2 起始位置不可定位
    });

    test('八达通-全国通卡：金额按港币（HK\$）口径', () async {
      final app = await _scan(
        _FakeNfcChannel()
          ..enqueueWalletScript(
            record: _record(terminal: '123456789012'),
            varRecord: _railRecord(),
            publicFile: _octopusPublicFile(),
          ),
        assets: _octopusAssets,
      );
      final trip = app.analysis!.trips.single;
      expect(trip.amountText, '-HK\$46.60');
      expect(app.cardCurrency.code, 'HKD');
      expect(app.cardCurrency.symbol, 'HK\$');
      expect(app.railTransitRecord!.entryBalanceFen, 300);
    });
  });

  group('卡片列表与保存流程', () {
    testWidgets('首页：解析完成弹出保存确认框（名称 + 卡号），不保存不落库',
        (tester) async {
      final channel = _FakeNfcChannel()
        ..enqueueWalletScript(record: _record(terminal: '391002003100'));
      final database = _memoryDatabase();
      final app = AppState(
        channel: channel,
        bundle: _FakeBundle(_assets),
        settingsStore: MemorySettingsStore(),
        database: database,
      );
      await app.init();
      await app.scanOnce(); // 解析完成 → 产生待保存结果

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: HomePage(app: app, active: true))),
      );
      await tester.pumpAndSettle();

      // 对话框包含卡片名称与卡号（首页「最近扫描」面板同样展示卡片
      // 名称与完整卡号，故两处断言均限定在对话框范围内）
      expect(find.text('保存卡片'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('福路通·榕城通'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('3105060012345678900'),
        ),
        findsOneWidget,
      );

      // 不保存：不落库
      await tester.tap(find.text('不保存'));
      await tester.pumpAndSettle();
      expect(find.text('保存卡片'), findsNothing);
      expect(await database.select(database.savedCards).get(), isEmpty);

      // 再读一次并确认保存：落库并记录余额快照与交易条数
      channel
        ..reset()
        ..enqueueWalletScript(record: _record(terminal: '391002003100'));
      await app.scanOnce();
      await tester.pumpAndSettle();
      expect(find.text('保存卡片'), findsOneWidget);

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final rows = await database.select(database.savedCards).get();
      expect(rows.length, 1);
      expect(rows.single.officialName, '福路通·榕城通');
      expect(rows.single.cardNumber, '3105060012345678900');
      expect(rows.single.balanceFen, 10000); // GET BALANCE 10000 分

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('重复读取：快照更新、自定义名称保留、不重复建档',
        (tester) async {
      final channel = _FakeNfcChannel()
        ..enqueueWalletScript(record: _record(terminal: '391002003100'));
      final database = _memoryDatabase();
      final app = await _scan(channel, database: database);

      await app.acceptPendingSave();
      final first = (await database.select(database.savedCards).get()).single;
      await app.cardRepository.renameCard(first.id, '上学用的卡');

      // 重新读取同一张卡：识别结果与快照刷新，自定义名称保留
      channel
        ..reset()
        ..enqueueWalletScript(record: _record(terminal: '391002003100'));
      await app.scanOnce();
      await app.acceptPendingSave();

      final rows = await database.select(database.savedCards).get();
      expect(rows.length, 1); // 同一指纹不重复建档
      expect(rows.single.customName, '上学用的卡');
      expect(rows.single.officialName, '福路通·榕城通');
      expect(rows.single.balanceFen, 10000);
    });

    testWidgets('读取新卡片后：老卡片详情仍展示已保存的行程记录',
        (tester) async {
      final channel = _FakeNfcChannel()
        ..enqueueWalletScript(
          record: _record(terminal: '391002003100'),
          varRecord: _railRecord(),
        );
      final database = _memoryDatabase();
      final app = await _scan(channel, database: database);

      // 第一张卡：保存并改名，确认档案记录了行程快照
      await app.acceptPendingSave();
      final first = (await database.select(database.savedCards).get()).single;
      expect(first.sessionDataJson, isNotNull);
      await app.cardRepository.renameCard(first.id, '老卡片');

      // 读取另一张卡（应用序列号不同 → 不同指纹）并保存
      channel
        ..reset()
        ..enqueueWalletScript(
          record: _record(terminal: '391002003100'),
          varRecord: _railRecord(),
          publicFile: _secondPublicFile(),
        );
      await app.scanOnce();
      await app.acceptPendingSave();
      expect(app.lastCardFingerprint, isNot(first.cardFingerprint));

      // 打开老卡片详情：回退档案快照展示，记录不因读取新卡片消失
      await tester.pumpWidget(MaterialApp(home: CardsPage(app: app)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('老卡片'));
      await tester.pumpAndSettle();

      expect(find.text('最近读取记录'), findsOneWidget);
      expect(find.text('消费 · 苏洋 · 序号 1'), findsOneWidget);
      expect(find.text('城市轨道交通 · 进出站记录'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('卡片列表：展示名称 / 卡号 / 最近读取时间 / 余额 / 记录条数',
        (tester) async {
      final database = _memoryDatabase();
      final app = AppState(database: database);
      await app.cardRepository.saveIdentity(
        fingerprint: 'tunion:1:2',
        identity: const CardArchiveIdentity(
          cardType: CardTypes.chinaTunion,
          officialName: '福路通·榕城通',
          issuerName: '示例运营方',
          cityName: '福州市',
          identificationSource: CardIdentificationSources.cardCatalog,
        ),
        cardNumber: '3105060012345678900',
        balanceFen: 200,
        currencyCode: 'CNY',
        transactionCount: 41,
        readAt: DateTime(2026, 10, 14, 21, 40),
      );

      await tester.pumpWidget(MaterialApp(home: CardsPage(app: app)));
      await tester.pumpAndSettle();

      expect(find.text('卡片列表'), findsOneWidget);
      expect(find.text('福路通·榕城通'), findsOneWidget);
      expect(find.text('3105060012345678900'), findsOneWidget);
      expect(find.text('10月14日 21:40'), findsOneWidget);
      expect(find.text('¥ 2.00'), findsOneWidget);
      expect(find.text('41条'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('卡片列表：空状态提示', (tester) async {
      final app = AppState(database: _memoryDatabase());
      await tester.pumpWidget(MaterialApp(home: CardsPage(app: app)));
      await tester.pumpAndSettle();

      expect(find.text('还没有保存的卡片'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('卡片列表：按最近读取时间倒序', (tester) async {
      final database = _memoryDatabase();
      final app = AppState(database: database);
      await app.cardRepository.saveIdentity(
        fingerprint: 'tunion:1:1',
        identity: const CardArchiveIdentity(
          cardType: CardTypes.chinaTunion,
          officialName: '旧卡',
        ),
        readAt: DateTime(2026, 10, 1, 8, 0),
      );
      await app.cardRepository.saveIdentity(
        fingerprint: 'tunion:1:2',
        identity: const CardArchiveIdentity(
          cardType: CardTypes.chinaTunion,
          officialName: '新卡',
        ),
        readAt: DateTime(2026, 10, 14, 21, 40),
      );

      await tester.pumpWidget(MaterialApp(home: CardsPage(app: app)));
      await tester.pumpAndSettle();

      final newerY = tester.getTopLeft(find.text('新卡')).dy;
      final olderY = tester.getTopLeft(find.text('旧卡')).dy;
      expect(newerY, lessThan(olderY));

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('点击卡片进入详情：展示读取快照，编辑名称同步到列表',
        (tester) async {
      final database = _memoryDatabase();
      final app = AppState(database: database);
      await app.cardRepository.saveIdentity(
        fingerprint: 'tunion:1:2',
        identity: const CardArchiveIdentity(
          cardType: CardTypes.chinaTunion,
          officialName: '福路通·榕城通',
          issuerName: '示例运营方',
          cityName: '福州市',
          identificationSource: CardIdentificationSources.cardCatalog,
        ),
        cardNumber: '3105060012345678900',
        balanceFen: 200,
        currencyCode: 'CNY',
        transactionCount: 41,
        readAt: DateTime(2026, 10, 14, 21, 40),
      );

      await tester.pumpWidget(MaterialApp(home: CardsPage(app: app)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('福路通·榕城通'));
      await tester.pumpAndSettle();

      // 详情页展示读取快照
      expect(find.text('卡片信息'), findsOneWidget);
      expect(find.text('卡号'), findsOneWidget);
      expect(find.text('3105060012345678900'), findsOneWidget);
      expect(find.text('余额'), findsOneWidget);
      expect(find.text('¥ 2.00'), findsOneWidget);
      expect(find.text('交易记录'), findsOneWidget);
      expect(find.text('41条'), findsOneWidget);
      expect(find.text('最近读取'), findsOneWidget);
      expect(find.text('2026-10-14 21:40:00'), findsOneWidget);

      // 编辑自定义名称
      await tester.tap(find.text('编辑卡片名称'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '上学用的卡');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('上学用的卡'), findsOneWidget);
      expect(find.textContaining('福路通·榕城通'), findsOneWidget);

      // 返回列表：自定义名称同步展示
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('上学用的卡'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}

/// 注入假通道、假资产包、内存设置存储与内存数据库（卡片档案），
/// 走一次完整扫描（scanOnce → 解析 → 识别）并返回应用状态。
Future<AppState> _scan(
  _FakeNfcChannel channel, {
  Map<String, String>? assets,
  AppDatabase? database,
}) async {
  final app = AppState(
    channel: channel,
    bundle: _FakeBundle(assets ?? _assets),
    settingsStore: MemorySettingsStore(),
    database: database ?? _memoryDatabase(),
  );
  await app.init();
  await app.scanOnce();
  return app;
}

/// 内存数据库：挂件测试需 closeStreamsSynchronously 避免流取消定时器残留。
AppDatabase _memoryDatabase() => AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );

/// 最小知识库资产：卡前缀库条目（发卡机构代码 01283910 后 4 位即城市
/// 代码 3910 → 福州市）+ 指纹与终端规则。
final Map<String, String> _assets = {
  'assets/data/tunion_issuer_fingerprints.json': jsonEncode({
    'entries': [
      {
        'issuerId': '1122334455667788',
        'cityCode': '3910',
        'cityName': '福州市',
        'operator': '示例运营方',
        'cardFamily': '测试卡',
      }
    ]
  }),
  'assets/data/tunion_terminal_rules.json': jsonEncode({
    'rules': [
      {
        'id': 'test-fuzhou',
        'match': {'terminalPrefix': '3910'},
        'layout': {
          'cityCode': [0, 4],
          'lineCode': [4, 6],
          'stationCode': [8, 10],
        },
      }
    ]
  }),
  'assets/data/tunion_card_prefixes.json': jsonEncode({
    'entries': [
      {
        'prefix': '31050600',
        'issuer': '01283910',
        'cardName': '福路通·榕城通',
        'city': '福州市',
      }
    ]
  }),
};

/// 八达通-全国通卡资产：卡号前缀库声明钱包货币 HKD（香港）。
final Map<String, String> _octopusAssets = {
  ..._assets,
  'assets/data/tunion_card_prefixes.json': jsonEncode({
    'entries': [
      {
        'prefix': '31048500',
        'cardName': '八达通-全国通卡',
        'city': '香港',
        'currency': 'HKD',
      }
    ]
  }),
};

/// 按 INS 脚本化的假 NFC 通道：队列耗尽后返回 6A82（记录未找到）。
class _FakeNfcChannel implements NfcChannel {
  final Map<int, List<List<int>>> _queues = {};

  void enqueue(int ins, List<int> response) =>
      _queues.putIfAbsent(ins, () => []).add(response);

  /// 清空脚本队列（同一测试内重复扫描前调用，保证脚本从头对齐）。
  void reset() => _queues.clear();

  /// 电子钱包完整读取脚本：选择 MF → 选择钱包 AID → 读三个标准文件
  /// → GET BALANCE → 0x18 交易明细整体读取。
  /// 传入 [varRecord] 时 0x1A 逐条读取记录 1 命中；传入 [busRecord] 时
  /// 记录 2 追加命中（记录 1 缺省为未写入的初始值），随后以记录未找到终止；
  /// 传入 [varBlob] 时 0x1A 逐条读取失败、整体读取兜底返回该数据；
  /// 均未传入时 0x1A 逐条与整体兜底都以记录未找到终止。
  /// 传入 [cycleRecord] 时追加 0x1E 循环记录 1（整体读取命中）。
  /// 传入 [publicFile] 时替换公共应用信息文件（模拟其他卡号段卡片）。
  void enqueueWalletScript({
    required List<int> record,
    List<int>? varRecord,
    List<int>? varBlob,
    List<int>? busRecord,
    List<int>? cycleRecord,
    List<int>? publicFile,
  }) {
    enqueue(0xA4, const [0x90, 0x00]);
    enqueue(0xA4, _sw9000(const []));
    enqueue(0xB0, _sw9000(publicFile ?? _publicFile()));
    enqueue(0xB0, _sw9000(_holderFile()));
    enqueue(0xB0, _sw9000(_managementFile()));
    enqueue(0x5C, const [0x00, 0x00, 0x27, 0x10, 0x90, 0x00]); // 余额 10000 分
    enqueue(0xB2, _sw9000(record)); // 0x18 交易明细整体读取
    if (busRecord != null) {
      enqueue(0xB2, _sw9000(varRecord ?? List.filled(85, 0x00))); // 0x1A 记录 1
      enqueue(0xB2, _sw9000(busRecord)); // 0x1A 记录 2 命中
      enqueue(0xB2, const [0x6A, 0x83]); // 0x1A 记录 3：记录未找到
    } else if (varRecord != null) {
      enqueue(0xB2, _sw9000(varRecord)); // 0x1A 记录 1 命中
      enqueue(0xB2, const [0x6A, 0x83]); // 0x1A 记录 2：记录未找到
    } else if (varBlob != null) {
      enqueue(0xB2, const [0x6A, 0x83]); // 0x1A 逐条读取：记录未找到
      enqueue(0xB2, _sw9000(varBlob)); // 0x1A 整体读取兜底命中
    } else {
      enqueue(0xB2, const [0x6A, 0x83]); // 0x1A 逐条读取：记录未找到
      enqueue(0xB2, const [0x6A, 0x83]); // 0x1A 整体读取兜底：同样终止
    }
    if (cycleRecord != null) {
      enqueue(0xB2, _sw9000(cycleRecord)); // 0x1E 循环记录 1（整体读取）
    }
  }

  @override
  Future<NfcScanResult?> scanOnce() async => NfcScanResult(
        uid: '04A1B2C3',
        technologies: const ['IsoDep'],
        isoDepConnected: true,
        timestamp: DateTime(2026, 10, 8),
      );

  @override
  Future<void> stopScan() async {}

  @override
  Future<List<int>> transceive(List<int> apdu) async {
    final ins = apdu.length > 1 ? apdu[1] : -1;
    final queue = _queues[ins];
    if (queue == null || queue.isEmpty) return const [0x6A, 0x82];
    return queue.removeAt(0);
  }
}

/// 内存资产包：按 Key 返回预置 JSON 字符串。
class _FakeBundle extends CachingAssetBundle {
  final Map<String, String> _texts;
  _FakeBundle(this._texts);

  @override
  Future<ByteData> load(String key) async {
    final text = _texts[key];
    if (text == null) throw FlutterError('资产不存在：$key');
    return ByteData.view(Uint8List.fromList(utf8.encode(text)).buffer);
  }
}

List<int> _sw9000(List<int> data) => [...data, 0x90, 0x00];

/// 公共应用信息文件：应用序列号 3105060012345678900（IIN 31050600 命中
/// 卡前缀库「福路通·榕城通」条目），发卡机构标识 1122334455667788。
List<int> _publicFile() {
  final b = List.filled(30, 0);
  for (var i = 0; i < 8; i++) {
    b[i] = 0x11 * (i + 1);
  }
  b[8] = 0x01;
  b[9] = 0x01;
  const serial = [0x03, 0x10, 0x50, 0x60, 0x01, 0x23, 0x45, 0x67, 0x89, 0x00];
  for (var i = 0; i < 10; i++) {
    b[10 + i] = serial[i];
  }
  b[20] = 0x20;
  b[21] = 0x24;
  b[22] = 0x01;
  b[23] = 0x01; // 20240101
  b[24] = 0x20;
  b[25] = 0x29;
  b[26] = 0x12;
  b[27] = 0x31; // 20291231
  b[28] = 0xAA;
  b[29] = 0xBB;
  return b;
}

/// 八达通-全国通卡公共应用信息文件：应用序列号前 8 位 31048500（IIN）
/// 命中前缀库八达通条目，其余字段与 [_publicFile] 一致。
List<int> _octopusPublicFile() {
  final b = _publicFile();
  const serial = [0x03, 0x10, 0x48, 0x50, 0x00, 0x00, 0x00, 0x00, 0x12, 0x34];
  for (var i = 0; i < 10; i++) {
    b[10 + i] = serial[i];
  }
  return b;
}

List<int> _holderFile() {
  final b = List.filled(55, 0);
  b[0] = 0x01;
  b[54] = 0x01;
  return b;
}

List<int> _managementFile() {
  final b = List.filled(60, 0);
  b[6] = 0x39;
  b[7] = 0x10; // 城市代码 3910
  b[10] = 0x01;
  return b;
}

/// 23 字节交易明细记录（SFI 0x18），终端号为 6 字节 BCD。
List<int> _record({
  int seq = 1,
  int amountFen = 4660,
  int day = 1,
  String terminal = '123456789012',
  int rawType = 0x06,
}) =>
    [
      (seq >> 8) & 0xFF,
      seq & 0xFF,
      0,
      0,
      0,
      (amountFen >> 24) & 0xFF,
      (amountFen >> 16) & 0xFF,
      (amountFen >> 8) & 0xFF,
      amountFen & 0xFF,
      rawType,
      ..._bcd(terminal),
      0x20,
      0x24,
      0x05,
      day, // 2024050d
      0x08,
      0x30,
      0x00, // 08:30:00
    ];

List<int> _bcd(String digits) => [
      for (var i = 0; i < digits.length; i += 2)
        int.parse(digits.substring(i, i + 2), radix: 16),
    ];

/// 7 字节 BCD 时间戳（YYYYMMDDhhmmss，如 0x20 0x26 … 即 2026 年）。
List<int> _bcdTime(DateTime t) => [
      0x20,
      _bcd2(t.year % 100),
      _bcd2(t.month),
      _bcd2(t.day),
      _bcd2(t.hour),
      _bcd2(t.minute),
      _bcd2(t.second),
    ];

int _bcd2(int v) => ((v ~/ 10) << 4) | (v % 10);

/// 0x1A 记录 1（城市轨道应用信息记录，85 字节裸字段体）：
/// 出闸 · 进闸城市 3910（福州市）· 出闸城市 3501（未收录）·
/// 2026-08-08 09:06:02 进站 / 09:12:31 出站 ·
/// 进站钱包余额 2500 分 · 出闸交易金额 300 分。
List<int> _railRecord({DateTime? entryTime}) => [
      0x02, // [00] 交易状态：出闸
      0x39, 0x10, // [01-02] 进闸城市代码 3910
      0x35, 0x01, // [03-04] 出闸城市代码 3501
      ...List.filled(7, 0), 0x10, // [05-0C] 进闸机构标识
      ...List.filled(7, 0), 0x08, // [0D-14] 出闸机构标识
      0x08, 0x00, 0x19, 0x00, 0x30, 0x00, 0x01, 0x23, // [15-1C] 进闸站点
      0x08, 0x00, 0x19, 0x00, 0x30, 0x00, 0x04, 0x56, // [1D-24] 出闸站点
      ...List.filled(7, 0), 0x0A, // [25-2C] 进闸终端编号
      ...List.filled(7, 0), 0x0B, // [2D-34] 出闸终端编号
      ..._bcdTime(entryTime ?? DateTime(2026, 8, 8, 9, 6, 2)), // [35-3B] 进站时间
      0x20, 0x26, 0x08, 0x08, 0x09, 0x12, 0x31, // [3C-42] 出站时间
      0x00, 0x00, 0x01, 0x2C, // [43-46] 标注金额 300 分
      0x02, // [47] 入站线路号
      0x02, // [48] 出站线路号
      0x00, 0x00, 0x00, 0x00, // [49-4C] 进站交易金额
      0x00, 0x00, 0x01, 0x2C, // [4D-50] 进站钱包余额 2500 分
      0x00, 0x00, 0x01, 0x2C, // [51-54] 出闸交易金额 300 分
    ];

/// 0x1A 记录 2（公共汽电车应用信息记录，88 字节裸记录体）：
/// 交易状态 0x02（未收录，显式未知）· 上车城市 3910 · 下车城市 3501（未收录）·
/// 2026-08-08 09:06:02 上车 / 09:12:31 下车 · 交易金额 300 分 · 乘车里程 5。
List<int> _busRecord() => [
      0x02, // [00] 交易状态
      0x39, 0x10, // [01-02] 上车城市代码 3910
      ...List.filled(7, 0), 0x10, // [03-0A] 上车机构标识
      0x00, 0x01, // [0B-0C] 上车运营商代码
      0x00, 0x08, // [0D-0E] 上车线路号
      0x02, // [0F] 上车站点
      ...List.filled(7, 0), 0x23, // [10-17] 上车车辆号
      ...List.filled(6, 0), 0x1A, 0x5A, // [18-1F] 上车终端编号
      0x20, 0x26, 0x08, 0x08, 0x09, 0x06, 0x02, // [20-26] 上车时间
      0x00, 0x00, 0x01, 0x2C, // [27-2A] 标注金额 300 分
      0x00, // [2B] 方向标识
      0x35, 0x01, // [2C-2D] 下车城市代码 3501
      ...List.filled(7, 0), 0x08, // [2E-35] 下车机构标识
      0x00, 0x01, // [36-37] 下车运营商代码
      0x00, 0x08, // [38-39] 下车线路号
      0x03, // [3A] 下车站点
      ...List.filled(7, 0), 0x36, // [3B-42] 下车车辆号
      ...List.filled(6, 0), 0x15, 0x68, // [43-4A] 下车终端编号
      0x20, 0x26, 0x08, 0x08, 0x09, 0x12, 0x31, // [4B-51] 下车时间
      0x00, 0x00, 0x01, 0x2C, // [52-55] 交易金额 300 分
      0x00, 0x05, // [56-57] 乘车里程 5
    ];

/// 0x1E 循环记录（48 字节）：出站 · 2024-05-01 08:30:00 · 4660 分 ·
/// 应用分类码 [appTypeCode]（默认 0x01 城市轨道交通）。线路站点字段
/// "90020031000000" 按福州布局解析（第 3-4 位线路 "02" + 第 7-8 位站点
/// "31" → 编码 "0231" 查表得 2号线 · 苏洋）；城市代码默认 3910。
List<int> _cycleRecord({
  int typeCode = 0x04,
  int amountFen = 4660,
  int day = 1,
  int appTypeCode = 0x01,
  String cityCode = '3910',
}) {
  const balanceFen = 5340;
  return [
    typeCode, // [00] 交易类型：出站
    ..._bcd('0000300089000340'), // [01-08] 终端编号
    appTypeCode, // [09] 应用分类码（0x01 城市轨道交通 / 0x02 公共汽电车）
    ..._bcd('90020031000000'), // [0A-10] 线路和站点代码
    (amountFen >> 24) & 0xFF,
    (amountFen >> 16) & 0xFF,
    (amountFen >> 8) & 0xFF,
    amountFen & 0xFF, // [11-14] 交易金额（分）
    (balanceFen >> 24) & 0xFF,
    (balanceFen >> 16) & 0xFF,
    (balanceFen >> 8) & 0xFF,
    balanceFen & 0xFF, // [15-18] 交易后余额
    0x20, 0x24, 0x05, day, 0x08, 0x30, 0x00, // [19-1F] 交易时间
    ..._bcd(cityCode), // [20-21] 城市代码
    ..._bcd('0000000000000000'), // [22-29] 收单机构
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // [2A-2F] 保留
  ];
}

/// 公共应用信息文件（应用序列号 …8901，与 [_publicFile] 不同的一张卡）：
/// 模拟读取另一张车卡以验证老卡片记录不消失。
List<int> _secondPublicFile() {
  final b = _publicFile();
  b[19] = 0x01; // 序列号末位 0 → 1
  return b;
}
