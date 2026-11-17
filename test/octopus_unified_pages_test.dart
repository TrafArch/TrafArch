import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/archive/application/card_identification_service.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_identity.dart';
import 'package:transit_card_analyzer/features/home/home_page.dart';
import 'package:transit_card_analyzer/features/home/presentation/felica_summary_panel.dart';
import 'package:transit_card_analyzer/features/home/presentation/transit_summary_panel.dart';
import 'package:transit_card_analyzer/features/home/presentation/scan_controls.dart';
import 'package:transit_card_analyzer/features/trips/trips_page.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/protocols/felica/models/cross_border_payment.dart';
import 'package:transit_card_analyzer/protocols/felica/models/felica_card_type.dart';
import 'package:transit_card_analyzer/protocols/felica/models/felica_models.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

import 'support/test_database.dart';

// These tests exercise page projections. Coordinator tests separately prove
// that only the current physical read owns the supplied balance and status.
class _PageApp extends AppDependencies {
  _PageApp({
    this.hasScan = true,
    this.octopusCard = true,
    this.felicaOnly = false,
    this.identified = true,
    this.balance = r'HK$50.00 (￥42.05)',
    this.notice,
    this.readFailure,
  }) : super(
         database: testDatabase(),
         bundle: MissingTestAssets(),
         settingsStore: MemorySettingsStore(),
         logger: AppLogger(store: MemoryLogStore()),
       );

  final bool hasScan, octopusCard, felicaOnly, identified;
  final String balance;
  final String? notice, readFailure;
  int scanRequests = 0;

  @override
  Future<void> scanOnce() async {
    scanRequests++;
  }

  @override
  bool get isOctopusCard => hasScan && octopusCard;
  @override
  String? get octopusBalanceText => isOctopusCard ? balance : null;
  @override
  String? get octopusReadNotice => isOctopusCard ? notice : null;
  @override
  String? get octopusReadFailure => isOctopusCard ? readFailure : null;
  @override
  IdentifiedCard? get lastIdentified => isOctopusCard && identified
      ? const IdentifiedCard(
          fingerprint: 'octopus-ui-fixture',
          identity: CardArchiveIdentity(
            cardType: 'octopus_tunion',
            officialName: '八达通全国通卡',
          ),
          cardNumber: '310485000000000001',
        )
      : null;

  @override
  NfcScanResult? get lastResult => hasScan
      ? NfcScanResult(
          uid: '0102030405060708',
          technologies: felicaOnly ? const ['NfcF'] : const ['IsoDep'],
          isoDepConnected: !felicaOnly,
          felicaConnected: felicaOnly,
          timestamp: DateTime(2026, 11, 17),
        )
      : null;
  @override
  ParsedCard? get parsedCard => !hasScan || felicaOnly
      ? null
      : const ParsedCard(
          parserId: CardParserIds.tunion,
          parserName: '交通联合',
          selectedAidHex: 'A000000632010105',
          info: TUnionCardInfo(
            applicationSerial: '00310485000000000001',
            balanceFen: 4205,
          ),
          transactions: [],
        );
  @override
  FelicaScanResult? get felicaResult => hasScan && felicaOnly
      ? FelicaScanResult(
          cardType: 'octopus',
          displayName: '八达通',
          cardProductType: FelicaCardType.octopus,
          idm: '0102030405060708',
          systemCodes: const [0x8008],
          wallets: const [
            FelicaWallet(
              walletId: 'octopus.main',
              kind: FelicaWalletKind.octopusHkd,
              name: '八达通钱包',
              currency: 'HKD',
              fractionDigits: 2,
              errorMessage: '港币钱包待读取',
            ),
          ],
          scannedAt: DateTime(2026, 11, 17),
        )
      : null;
}

Future<void> _show(
  WidgetTester tester,
  Widget page, {
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(360, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(body: page),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('余额读取失败保留基础结果和唯一再次读取入口', (tester) async {
    const failure = '未检测到八达通 NFC-F 接口，请移开卡片后重新贴卡。';
    final app = _PageApp(
      balance: r'港币余额未读取 (￥42.05)',
      notice: failure,
      readFailure: failure,
    );
    addTearDown(app.dispose);
    await _show(tester, HomePage(app: app, active: false));
    final controls = tester.widget<ScanControls>(find.byType(ScanControls));
    expect(controls.statusText, contains(failure));
    expect(find.text('读取完成，再次读取请点击下方按钮'), findsNothing);
    expect(find.text(r'港币余额未读取 (￥42.05)'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '再次读取'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
  });

  testWidgets('首页再次读取使用唯一普通扫描入口并保留组合余额', (tester) async {
    final app = _PageApp();
    addTearDown(app.dispose);
    await _show(tester, HomePage(app: app, active: true));
    expect(find.widgetWithText(FilledButton, '再次读取'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.text(r'HK$50.00 (￥42.05)'), findsOneWidget);
    expect(find.textContaining('汇率'), findsNothing);
    expect(find.text('八达通联网查询'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, '再次读取'));
    await tester.pump();
    expect(app.scanRequests, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('初始首页唯一的开始读取按钮调用普通扫描', (tester) async {
    final app = _PageApp(hasScan: false);
    addTearDown(app.dispose);
    await _show(tester, HomePage(app: app, active: true));
    expect(find.widgetWithText(FilledButton, '开始读取'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.text('联网读取八达通'), findsNothing);
    expect(find.text('更新汇率'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, '开始读取'));
    await tester.pump();
    expect(app.scanRequests, 1);
  });

  testWidgets('纯 NFC-F 八达通摘要只显示一次余额和读取提示', (tester) async {
    final app = _PageApp(
      felicaOnly: true,
      balance: '港币余额未读取',
      notice: '再次读取可查询八达通港币余额。',
    );
    addTearDown(app.dispose);
    await _show(tester, TransitSummaryPanel(app: app));
    expect(find.text('八达通'), findsOneWidget);
    expect(find.text('港币余额未读取'), findsOneWidget);
    expect(find.text('港币钱包待读取'), findsNothing);
    expect(find.textContaining('汇率'), findsNothing);
    expect(find.textContaining('再次读取可查询'), findsOneWidget);
    expect(find.text(r'HK$0.00'), findsNothing);
  });

  testWidgets('无行程八达通保留身份与组合余额，不再显示更新操作', (tester) async {
    final app = _PageApp();
    addTearDown(app.dispose);
    await _show(tester, TripsPage(app: app));
    expect(find.text('暂无行程数据'), findsOneWidget);
    expect(find.text('八达通全国通卡'), findsOneWidget);
    expect(find.text('310485000000000001'), findsOneWidget);
    expect(find.text(r'HK$50.00 (￥42.05)'), findsOneWidget);
    expect(find.text('记录 0 条'), findsOneWidget);
    expect(find.textContaining('汇率'), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('纯 NFC-F 行程摘要使用卡片名称与 IDm', (tester) async {
    final app = _PageApp(
      felicaOnly: true,
      identified: false,
      balance: r'HK$50.00',
    );
    addTearDown(app.dispose);
    await _show(tester, TripsPage(app: app));
    expect(find.text('八达通'), findsOneWidget);
    expect(find.text('0102030405060708'), findsOneWidget);
    expect(find.text(r'HK$50.00'), findsOneWidget);
    expect(find.textContaining('汇率'), findsNothing);
  });

  testWidgets('未读港币余额时长 TU 金额与大字体不溢出', (tester) async {
    final app = _PageApp(
      balance: r'港币余额未读取 (￥1234567890.12)',
      notice: '再次读取可查询八达通港币余额。',
    );
    addTearDown(app.dispose);
    await _show(tester, TripsPage(app: app), textScale: 2);
    expect(find.text(r'港币余额未读取 (￥1234567890.12)'), findsOneWidget);
    expect(find.textContaining('再次读取可查询'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('首页最近扫描的长金额在大字体下完整保留', (tester) async {
    final app = _PageApp(balance: r'HK$1234567890.12 (￥1234567890.12)');
    addTearDown(app.dispose);
    await _show(tester, HomePage(app: app, active: false), textScale: 2);
    expect(find.text(r'HK$1234567890.12 (￥1234567890.12)'), findsOneWidget);
    expect(find.textContaining('汇率'), findsNothing);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('当前普通卡不显示八达通摘要数值或操作', (tester) async {
    final app = _PageApp(octopusCard: false);
    addTearDown(app.dispose);
    await _show(tester, TripsPage(app: app));
    expect(find.text('暂无行程数据'), findsOneWidget);
    expect(find.textContaining('汇率'), findsNothing);
    expect(find.textContaining(r'HK$'), findsNothing);
    expect(find.text('联网读取八达通'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FeliCa 摘要保留跨境钱包语义但不再展示汇率数值', (tester) async {
    await _show(
      tester,
      FelicaSummaryPanel(
        felica: FelicaScanResult(
          cardType: 'octopus_tunion',
          displayName: '八达通全国通卡',
          cardProductType: FelicaCardType.octopusTUnion,
          crossBorder: const CrossBorderPaymentInfo(
            sourceCurrency: 'HKD',
            targetCurrency: 'CNY',
            exchangeRateNumerator: 91,
            exchangeRateDenominator: 100,
          ),
          scannedAt: DateTime(2026, 11, 17),
        ),
      ),
    );
    expect(find.text('跨境支付'), findsOneWidget);
    expect(find.text('汇率'), findsNothing);
    expect(find.textContaining('1 HKD ='), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
