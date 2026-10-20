import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/core/data/settings_store.dart';
import 'package:transit_card_analyzer/core/qr/gms_qr_scanner.dart';
import 'package:transit_card_analyzer/state/app_state.dart';
import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(gmsQrScannerChannel, null);
  });

  group('isGmsQrScanAvailable', () {
    test('GMS 可用：返回 true', () async {
      messenger.setMockMethodCallHandler(gmsQrScannerChannel, (call) async {
        expect(call.method, 'isAvailable');
        return true;
      });

      expect(await isGmsQrScanAvailable(), isTrue);
    });

    test('GMS 不可用：返回 false', () async {
      messenger.setMockMethodCallHandler(gmsQrScannerChannel, (call) async {
        return false;
      });

      expect(await isGmsQrScanAvailable(), isFalse);
    });

    test('通道不可用（非 Android / 未注册）：降级为 false', () async {
      // 不注册 mock handler：invokeMethod 抛出 MissingPluginException
      expect(await isGmsQrScanAvailable(), isFalse);
    });
  });

  group('scanQrWithGms', () {
    test('识别成功：返回原始载荷字节', () async {
      messenger.setMockMethodCallHandler(gmsQrScannerChannel, (call) async {
        expect(call.method, 'scan');
        return Uint8List.fromList(const [0x91, 0x00, 0x12, 0x34]);
      });

      expect(await scanQrWithGms(), [0x91, 0x00, 0x12, 0x34]);
    });

    test('用户取消 / 未识别：返回 null', () async {
      messenger.setMockMethodCallHandler(gmsQrScannerChannel, (call) async {
        return null;
      });

      expect(await scanQrWithGms(), isNull);
    });

    test('扫码失败：PlatformException 向上传播（调用方提示不回退）', () async {
      messenger.setMockMethodCallHandler(gmsQrScannerChannel, (call) async {
        throw PlatformException(code: 'SCAN_FAILED', message: 'Google 扫码失败');
      });

      await expectLater(scanQrWithGms(), throwsA(isA<PlatformException>()));
    });
  });

  group('warmUpGmsQrScanner', () {
    test('调用原生 warmUp 方法', () async {
      String? invokedMethod;
      messenger.setMockMethodCallHandler(gmsQrScannerChannel, (call) async {
        invokedMethod = call.method;
        return null;
      });

      await warmUpGmsQrScanner();

      expect(invokedMethod, 'warmUp');
    });

    test('预热失败（PlatformException）：静默不抛出', () async {
      messenger.setMockMethodCallHandler(gmsQrScannerChannel, (call) async {
        throw PlatformException(code: 'WARMUP_FAILED', message: '预热失败');
      });

      await warmUpGmsQrScanner();
    });

    test('通道不可用（非 Android / 未注册）：静默不抛出', () async {
      // 不注册 mock handler：invokeMethod 抛出 MissingPluginException
      await warmUpGmsQrScanner();
    });
  });

  group('AppState 扫码模块决策：开启系统扫码即整体屏蔽应用内相机', () {
    test('检测到 GMS + 开关默认关闭：使用应用内相机扫码', () async {
      messenger.setMockMethodCallHandler(gmsQrScannerChannel, (call) async {
        return call.method == 'isAvailable' ? true : null;
      });

      final app = AppState(database: testDatabase(), bundle: MissingTestAssets(), settingsStore: MemorySettingsStore());
      await app.init();
      await pumpEventQueue();

      expect(app.gmsAvailable, isTrue);
      expect(app.useGmsScanner, isFalse);
    });

    test('开关显式开启：应用内相机扫码被整体屏蔽', () async {
      messenger.setMockMethodCallHandler(gmsQrScannerChannel, (call) async {
        return call.method == 'isAvailable' ? true : null;
      });

      final app = AppState(
        database: testDatabase(),
        bundle: MissingTestAssets(),
        settingsStore:
            MemorySettingsStore({SettingsKeys.gmsScanEnabled: 'true'}),
      );
      await app.init();

      expect(app.useGmsScanner, isTrue);
    });

    test('未检测到 GMS + 开关开启：不依赖探测结果，保持屏蔽不回退相机', () async {
      // 不注册 mock handler：探测降级为不具备 GMS
      final app = AppState(
        database: testDatabase(),
        bundle: MissingTestAssets(),
        settingsStore:
            MemorySettingsStore({SettingsKeys.gmsScanEnabled: 'true'}),
      );
      await app.init();

      expect(app.gmsAvailable, isFalse);
      expect(app.useGmsScanner, isTrue);
    });
  });

  group('AppState 系统扫码开关', () {
    test('默认关闭', () async {
      final app = AppState(database: testDatabase(), bundle: MissingTestAssets(), settingsStore: MemorySettingsStore());
      await app.init();
      expect(app.gmsScanEnabled, isFalse);
    });

    test('读取持久化值：显式开启后启用 GMS 扫码', () async {
      final app = AppState(
        database: testDatabase(),
        bundle: MissingTestAssets(),
        settingsStore:
            MemorySettingsStore({SettingsKeys.gmsScanEnabled: 'true'}),
      );
      await app.init();
      expect(app.gmsScanEnabled, isTrue);
    });

    test('切换开关并持久化', () async {
      final store = MemorySettingsStore();
      final app = AppState(database: testDatabase(), bundle: MissingTestAssets(), settingsStore: store);
      await app.init();

      await app.setGmsScanEnabled(true);
      expect(app.gmsScanEnabled, isTrue);
      expect(await store.read(SettingsKeys.gmsScanEnabled), 'true');

      await app.setGmsScanEnabled(false);
      expect(app.gmsScanEnabled, isFalse);
      expect(await store.read(SettingsKeys.gmsScanEnabled), 'false');
    });

    test('探测到 GMS 且开关开启：启动时自动后台预热扫码器', () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(gmsQrScannerChannel, (call) async {
        calls.add(call.method);
        return call.method == 'isAvailable' ? true : null;
      });

      final app = AppState(
        database: testDatabase(),
        bundle: MissingTestAssets(),
        settingsStore:
            MemorySettingsStore({SettingsKeys.gmsScanEnabled: 'true'}),
      );
      await app.init();
      // 预热为 fire-and-forget：放行事件循环后再断言
      await pumpEventQueue();

      expect(calls, contains('isAvailable'));
      expect(calls, contains('warmUp'));
    });

    test('探测到 GMS 但开关默认关闭：不触发预热', () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(gmsQrScannerChannel, (call) async {
        calls.add(call.method);
        return call.method == 'isAvailable' ? true : null;
      });

      final app = AppState(database: testDatabase(), bundle: MissingTestAssets(), settingsStore: MemorySettingsStore());
      await app.init();
      await pumpEventQueue();

      expect(calls, contains('isAvailable'));
      expect(calls, isNot(contains('warmUp')));
    });

    test('未检测到 GMS：不触发预热', () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(gmsQrScannerChannel, (call) async {
        calls.add(call.method);
        return false;
      });

      final app = AppState(
        database: testDatabase(),
        bundle: MissingTestAssets(),
        settingsStore:
            MemorySettingsStore({SettingsKeys.gmsScanEnabled: 'true'}),
      );
      await app.init();
      await pumpEventQueue();

      expect(calls, contains('isAvailable'));
      expect(calls, isNot(contains('warmUp')));
    });
  });
}