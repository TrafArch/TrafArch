import 'dart:async';
import 'dart:convert';

import 'package:transit_card_analyzer/features/expert/expert_formatters.dart'
    show hexBytes;
import 'package:transit_card_analyzer/features/qr/presentation/qr_page.dart';
import 'package:transit_card_analyzer/features/qr/presentation/qr_scan_page.dart';
import 'package:transit_card_analyzer/features/settings/presentation/settings_page.dart';

import 'dart:io';

import 'support/published_reference_fixture.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_service.dart';
import 'package:transit_card_analyzer/features/qr/presentation/jt_t1179_qr_display.dart';
import 'package:transit_card_analyzer/protocols/transit/qr/jt_t1179_qr_parser.dart';
import 'package:transit_card_analyzer/features/expert/expert_page.dart';
import 'package:transit_card_analyzer/features/home/home_page.dart';
import 'package:transit_card_analyzer/platform/qr/qr_image_picker.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';

import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory referenceDirectory;
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  setUpAll(() {
    referenceDirectory = Directory.systemTemp.createTempSync(
      'trafarch-qr-reference-',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async {
          if (call.method == 'getApplicationSupportDirectory') {
            return referenceDirectory.path;
          }
          throw MissingPluginException(call.method);
        });
  });
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    referenceDirectory.deleteSync(recursive: true);
  });
  group('JT/T 1179 二维码解析与展示扩展', () {
    test('样例二维码：表 2 全字段解析正确', () {
      final sample = _sampleQr();
      final data = JtT1179QrParser.parse(sample);

      expect(data.raw.length, 335);
      expect(data.versionHex, '0x80');
      expect(data.declaredLength, sample.length - 3);
      expect(data.issuerCertificate.issuerId, '01283910');
      expect(data.issuerCertificate.expiryYear, 2030);
      expect(data.issuerCertificate.expiryMonth, 12);
      expect(data.userAccountNumberText, '1380013800');
      expect(data.issuerCodeText, 'SHML');
      expect(data.platformCodeText, 'UNIO');
      expect(data.userAccountType, 0x01);
      expect(data.singleConsumptionLimitFen, 2000);
      expect(data.qrValiditySeconds, 300);
      expect(
        data.generationTimeUtc,
        DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000, isUtc: true),
      );
      expect(
        data.qrValidUntilUtc,
        data.generationTimeUtc.add(const Duration(seconds: 300)),
      );
    });

    test('签名数据不解析：格式字节取任意值仍可解析', () {
      final sample = _sampleQr();
      sample[201] = 0x00; // 第 15 项签名格式字节（原 0x15）
      sample[270] = 0x00; // 第 17 项签名格式字节（原 0x15）
      final data = JtT1179QrParser.parse(sample);
      expect(data.declaredLength, sample.length - 3);
      expect(
        data.generationTimeUtc,
        DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000, isUtc: true),
      );
    });

    test('展示扩展：BCD 发卡机构与 Cn 支付账户号安全解码', () {
      final data = JtT1179QrParser.parse(_sampleQr());
      expect(data.issuerIdText, '01283910');
      expect(data.paymentAccountDigits, '6225880123456789');
    });
  });

  group('AppDependencies 二维码状态', () {
    test('parseQrBytes 成功：保存结果并清空错误', () {
      final app = _newApp();
      expect(app.hasQrData, isFalse);

      expect(app.parseQrBytes(_sampleQr()), isTrue);
      expect(app.hasQrData, isTrue);
      expect(app.qrError, isNull);
      expect(app.qrRaw!.length, 335);
    });

    test('parseQrText：HEX 与 Base64 均可解析', () {
      final hexApp = _newApp();
      expect(hexApp.parseQrText(_hexOf(_sampleQr())), isTrue);
      expect(hexApp.qrData!.issuerIdText, '01283910');

      final base64App = _newApp();
      expect(base64App.parseQrText(base64.encode(_sampleQr())), isTrue);
      expect(base64App.qrData!.paymentAccountDigits, '6225880123456789');
    });

    test('parseQrText：无法识别的文本返回 false 并记录错误', () {
      final app = _newApp();
      expect(app.parseQrText('你好，世界'), isFalse);
      expect(app.qrData, isNull);
      expect(app.qrRaw, isNull);
      expect(app.qrError, contains('无法识别'));
    });

    test('parseQrBytes 失败：保留原始字节并记录错误', () {
      final app = _newApp();
      final broken = _sampleQr().sublist(0, 100);
      expect(app.parseQrBytes(broken), isFalse);
      expect(app.hasQrData, isFalse);
      expect(app.qrRaw!.length, 100);
      expect(app.qrError, contains('二维码'));
    });

    test('clearQr：清空全部二维码状态', () {
      final app = _newApp();
      expect(app.parseQrBytes(_sampleQr()), isTrue);
      app.clearQr();
      expect(app.hasQrData, isFalse);
      expect(app.qrRaw, isNull);
      expect(app.qrError, isNull);
    });
  });

  group('独立扫码页', () {
    testWidgets('首页仅保留 NFC，扫码按钮停止读卡并导航返回', (tester) async {
      final channel = _TrackingNfcChannel();
      final app = _newApp(channel: channel);
      await _pumpPage(tester, app, HomePage(app: app, active: false));
      expect(find.text('请将卡片贴近手机背面'), findsOneWidget);
      expect(find.text('扫描二维码'), findsNothing);
      expect(find.text('从相册导入'), findsNothing);
      expect(find.text('扫码读取乘车码'), findsNothing);
      expect(find.text('最近扫描'), findsNothing);
      expect(find.byTooltip('扫码'), findsOneWidget);
      expect(find.byTooltip('设置'), findsOneWidget);
      final pendingScan = app.scanOnce();
      await tester.pump();
      expect(app.scanning, isTrue);
      await tester.tap(find.byTooltip('扫码'));
      await tester.pumpAndSettle();
      expect(channel.stops, 1);
      expect(app.scanning, isFalse);
      await pendingScan;
      expect(find.byType(QrPage), findsOneWidget);
      expect(find.textContaining('尚未获取二维码'), findsOneWidget);
      expect(find.text('扫描二维码'), findsOneWidget);
      expect(find.text('从相册导入'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(QrPage), findsNothing);
      expect(find.byType(HomePage), findsOneWidget);
    });

    for (final expert in [false, true]) {
      testWidgets('${expert ? '专家' : '首页'} NFC 信息不受二维码成功或失败影响', (tester) async {
        final app = _newApp(channel: _CardNfcChannel());
        await tester.runAsync(app.init);
        await tester.runAsync(app.scanOnce);
        await _pumpPage(
          tester,
          app,
          expert ? ExpertPage(app: app) : HomePage(app: app, active: false),
          initialize: false,
        );
        final card = app.lastResult;
        for (final bytes in [
          _sampleQr(),
          <int>[0x80, 0, 1],
        ]) {
          app.parseQrBytes(bytes);
          await tester.pumpAndSettle();
          expect(app.lastResult, same(card));
          expect(app.lastResult!.uid, '04A1B2C3D4');
          expect(find.text(expert ? '解析器' : '卡号'), findsOneWidget);
          expect(find.text('6225880123456789'), findsNothing);
          expect(find.text('二维码'), findsNothing);
          expect(find.text('乘车码二维码'), findsNothing);
          expect(find.text('二维码解析失败'), findsNothing);
          expect(find.textContaining('尚未获取乘车码'), findsNothing);
          expect(find.text('发卡机构公钥证书（117 字节）'), findsNothing);
          expect(find.text('扫描二维码'), findsNothing);
          expect(find.text('从相册导入'), findsNothing);
        }
      });
    }

    testWidgets('专家空态只提示读取卡片，不提示二维码', (tester) async {
      final app = _newApp();
      await _pumpPage(tester, app, ExpertPage(app: app));
      expect(find.text('尚未读取卡片，请先在首页贴卡读取'), findsOneWidget);
      expect(find.textContaining('尚未获取乘车码'), findsNothing);
      expect(find.widgetWithText(Tab, '二维码'), findsNothing);
    });

    testWidgets('扫码页监听解析结果，展示完整字段、证书和原始 HEX，可清除', (tester) async {
      final app = _newApp();
      await _pumpPage(tester, app, QrPage(app: app));
      expect(find.textContaining('尚未获取二维码'), findsOneWidget);
      app.parseQrBytes(_sampleQr());
      await tester.pumpAndSettle();
      for (final value in [
        '0x80',
        '332 字节（数据体，自证书起）',
        '335 字节',
        '福路通·榕城通',
        '6225880123456789',
        '1380013800',
        'SHML',
        'UNIO',
        '20.00 元',
        '300 秒',
        '支付账户用户公钥',
        '授权过期时间',
        '二维码生成时间',
        '发卡机构自定义域',
      ]) {
        expect(find.text(value), findsOneWidget, reason: value);
      }
      expect(find.textContaining('已超出生成时间'), findsOneWidget);
      await tester.ensureVisible(find.text('发卡机构公钥证书（117 字节）'));
      await tester.tap(find.text('发卡机构公钥证书（117 字节）'));
      await tester.pumpAndSettle();
      for (final label in [
        '记录头',
        '服务标识',
        '中心 CA 公钥索引',
        '证书格式',
        '证书失效日期',
        '证书序列号',
        '公钥签名算法',
        '公钥加密算法（保留）',
        '公钥参数标识',
        '公钥长度',
        '发卡机构公钥',
        '证书原始数据（117 字节）',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text(hexBytes(_sampleCertificate())), findsOneWidget);
      await tester.ensureVisible(find.text('二维码原始数据'));
      await tester.tap(find.text('二维码原始数据'));
      await tester.pumpAndSettle();
      expect(find.text(hexBytes(_sampleQr())), findsOneWidget);
      await tester.ensureVisible(find.text('清除'));
      await tester.tap(find.text('清除'));
      await tester.pumpAndSettle();
      expect(app.qrData, isNull);
      expect(app.qrRaw, isNull);
      expect(find.textContaining('尚未获取二维码'), findsOneWidget);
    });

    testWidgets('扫码页解析失败保留原始 HEX，清除恢复空态', (tester) async {
      final app = _newApp();
      await _pumpPage(tester, app, QrPage(app: app));
      app.parseQrBytes(const [0x80, 0, 1]);
      await tester.pumpAndSettle();
      expect(find.text('解析失败'), findsOneWidget);
      expect(find.text(app.qrError!), findsOneWidget);
      expect(find.text(hexBytes([0x80, 0, 1])), findsOneWidget);
      await tester.tap(find.text('清除'));
      await tester.pumpAndSettle();
      expect(app.qrError, isNull);
      expect(app.qrRaw, isNull);
      expect(find.text('解析失败'), findsNothing);
      expect(find.textContaining('尚未获取二维码'), findsOneWidget);
    });

    for (final fail in [false, true]) {
      testWidgets('相册${fail ? '失败' : '取消'}保留先前结果，等待时双按钮禁用', (tester) async {
        final response = Completer<Object?>();
        var picks = 0;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(qrImagePickerChannel, (call) {
          expect(call.method, 'pickImage');
          picks++;
          return response.future;
        });
        addTearDown(
          () => messenger.setMockMethodCallHandler(qrImagePickerChannel, null),
        );
        final app = _newApp();
        await _pumpPage(tester, app, QrPage(app: app));
        app.parseQrBytes(_sampleQr());
        await tester.pumpAndSettle();
        final previous = app.qrData;
        final raw = List<int>.of(app.qrRaw!);
        await tester.tap(find.text('从相册导入'));
        await tester.pump();
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '扫描二维码'))
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, '从相册导入'),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.text('从相册导入'));
        await tester.tap(find.text('扫描二维码'));
        expect(picks, 1);
        expect(find.byType(QrScanPage), findsNothing);
        if (fail) {
          response.completeError(
            PlatformException(code: 'picker_failed', message: '测试选图失败'),
          );
        } else {
          response.complete(null);
        }
        await tester.pumpAndSettle();
        expect(app.qrData, same(previous));
        expect(app.qrRaw, orderedEquals(raw));
        expect(app.qrError, isNull);
        expect(find.text('6225880123456789'), findsOneWidget);
        expect(find.byType(SnackBar), fail ? findsOneWidget : findsNothing);
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '扫描二维码'))
              .onPressed,
          isNotNull,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, '从相册导入'),
              )
              .onPressed,
          isNotNull,
        );
      });
    }

    testWidgets('相机路由 pop 原始 bytes 经 scanQrAndParse 回传并展示', (tester) async {
      final app = _newApp();
      await _pumpPage(tester, app, QrPage(app: app));
      await tester.tap(find.text('扫描二维码'));
      await tester.pumpAndSettle();
      expect(find.byType(QrScanPage), findsOneWidget);
      Navigator.of(tester.element(find.byType(QrScanPage)))
          .pop<List<int>>(_sampleQr());
      await tester.pumpAndSettle();
      expect(find.byType(QrScanPage), findsNothing);
      expect(find.byType(QrPage), findsOneWidget);
      expect(app.qrRaw, orderedEquals(_sampleQr()));
      expect(find.text('6225880123456789'), findsOneWidget);
      expect(find.text('二维码解析成功'), findsOneWidget);
    });

    testWidgets('设置不再提供使用系统扫码项', (tester) async {
      final app = _newApp();
      await _pumpPage(tester, app, SettingsPage(app: app));
      expect(find.text('读取后自动保存'), findsOneWidget);
      expect(find.textContaining('使用系统扫码'), findsNothing);
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  AppDependencies app,
  Widget page, {
  bool initialize = true,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (initialize) await tester.runAsync(app.init);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: page)));
  await tester.pumpAndSettle();
}

class _TrackingNfcChannel extends _NoopNfcChannel {
  int stops = 0;
  final pending = Completer<NfcScanResult?>();

  @override
  Future<NfcScanResult?> scanOnce() => pending.future;

  @override
  Future<void> stopScan() async {
    stops++;
    if (!pending.isCompleted) pending.complete(null);
  }
}

AppDependencies _newApp({NfcChannel? channel}) {
  final app = AppDependencies(
    database: testDatabase(),
    channel: channel ?? _NoopNfcChannel(),
    bundle: _FakeBundle(_assets),
    settingsStore: MemorySettingsStore(),
  );
  addTearDown(app.dispose);
  return app;
}

String _hexOf(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// JT/T 1179 表 18 证书样例（117 字节）：发卡机构 cn8 '01283910' ·
/// 失效 2030-12 · 序列号 010203 · SM2 公钥与签名字节占位（不解析）。
List<int> _sampleCertificate() => [
  0x24, // 记录头
  0x01, 0x01, 0x00, 0x00, // 服务标识（交通电子现金）
  0x01, // 中心 CA 公钥索引
  0x12, // 证书格式
  0x01, 0x28, 0x39, 0x10, // 发卡机构标识 BCD '01283910'
  0x12, 0x30, // 失效日期 MMYY：2030-12
  0x01, 0x02, 0x03, // 证书序列号
  0x04, // 公钥签名算法（SM2）
  0x04, // 公钥加密算法（保留）
  0x00, // 公钥参数标识
  0x21, // 公钥长度（33 字节）
  0x02, ...List.filled(32, 0x22), // 发卡机构公钥
  ...List.filled(64, 0x33), // 数字签名
];

/// JT/T 1179 表 2 二维码样例（335 字节）：
/// 支付账户号 Cn '6225880123456789'（右补 FF）· 用户账户号 ASCII
/// '1380013800' · 单次消费上限 2000 分 · 生成时间 1700000000 · 有效 300 秒。
List<int> _sampleQr() {
  final body = <int>[
    ..._sampleCertificate(), // 3. 发卡机构公钥证书
    0x62, 0x25, 0x88, 0x01, 0x23, 0x45, 0x67, 0x89, // 4. 支付账户号
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
    ...'1380013800'.codeUnits, // 5. 用户账户号（ASCII）
    ...'SHML'.codeUnits, // 6. 发卡机构代码
    ...'UNIO'.codeUnits, // 7. 发码平台代码
    0x01, // 8. 用户账户类型
    0x00, 0x07, 0xD0, // 9. 单次消费金额上限 2000 分
    0x02, ...List.filled(32, 0x11), // 10. 支付账户用户公钥
    0x77, 0x35, 0x94, 0x00, // 11. 授权过期时间 2000000000
    0x01, 0x2C, // 12. 二维码有效时间 300 秒
    0x03, // 13. 发卡机构自定义域长度
    0xAA, 0xBB, 0xCC, // 14. 发卡机构自定义域
    0x15, ...List.filled(64, 0x44), // 15. 发卡机构授权签名
    0x65, 0x53, 0xF1, 0x00, // 16. 生成时间 1700000000
    0x15, ...List.filled(64, 0x55), // 17. 支付账户用户私钥签名
  ];
  return [0x80, (body.length >> 8) & 0xFF, body.length & 0xFF, ...body];
}

/// 最小知识库资产：卡前缀库条目（issuer 01283910 → 福路通·榕城通 / 福州市）。
final Map<String, String> _assets = {
  'assets/data/tunion_issuer_fingerprints.json': jsonEncode({
    'entries': [
      {
        'issuerId': '1122334455667788',
        'cityCode': '3910',
        'cityName': '福州市',
        'operator': '示例运营方',
        'cardFamily': '测试卡',
      },
    ],
  }),
  'assets/data/tunion_terminal_rules.json': jsonEncode({'rules': []}),
  'assets/data/tunion_card_prefixes.json': jsonEncode({
    'entries': [
      {
        'prefix': '31050600',
        'issuer': '01283910',
        'cardName': '福路通·榕城通',
        'city': '福州市',
      },
    ],
  }),
};

/// 假资产包：按 Key 返回预置 JSON 字符串。
class _FakeBundle extends CachingAssetBundle {
  final Map<String, String> _texts;
  _FakeBundle(this._texts);
  late final _published = publishTuFixture(null, _texts);

  @override
  Future<ByteData> load(String key) async {
    final published = _published[key];
    if (published != null) return ByteData.sublistView(published);
    final text = _texts[key];
    if (text == null) throw FlutterError('资产不存在：$key');
    return ByteData.view(Uint8List.fromList(utf8.encode(text)).buffer);
  }
}

/// 空操作 NFC 通道：仅承载 AppDependencies 构造，测试中不触发扫描。
class _NoopNfcChannel implements NfcChannel {
  @override
  Future<NfcScanResult?> scanOnce() async => null;

  @override
  Future<void> stopScan() async {}

  @override
  Future<List<int>> transceive(List<int> apdu) async => const [0x6A, 0x82];
}

/// 假 NFC 通道：返回一张未连接 ISO-DEP 的卡（触发摘要展示，不触发解析）。
class _CardNfcChannel extends _NoopNfcChannel {
  @override
  Future<NfcScanResult?> scanOnce() async => NfcScanResult(
    uid: '04A1B2C3D4',
    technologies: const ['IsoDep'],
    cardType: 'Mifare Classic',
    isoDepConnected: false,
    timestamp: DateTime(2026, 1, 1),
  );
}
