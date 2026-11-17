import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/octopus/octopus_balance_controller.dart';
import 'package:transit_card_analyzer/platform/nfc/felica_channel.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_service.dart';
import 'package:transit_card_analyzer/platform/nfc/octopus_channel.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/protocols/octopus/octopus_balance.dart';

import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('默认合并读取，无需联网开关且普通物理关闭后才读港币余额', () async {
    final f = _Fixture();
    await f.app.scanOnce();
    expect(f.events, [
      'plain-scan',
      'plain-close',
      'balance-scan',
      'balance-close',
    ]);
    expect(f.operations, ['balance']);
    expect(f.app.currentOctopusResult?.balanceMinor, 5000);
    expect(f.app.octopusReadNotice, isNull);
    expect(f.app.octopusBalanceText, r'HK$50.00');
    expect(f.app.scanning, isFalse);
  });
  test('系统码元数据缺失时仍用普通读取的 IDm 绑定余额', () async {
    final f = _Fixture()..nfcFSystemCode = null;
    await f.app.scanOnce();
    expect(f.suppliedIdm, _idm);
    expect(f.app.currentOctopusResult?.balanceMinor, 5000);
    expect(f.app.octopusBalanceText, r'HK$50.00');
  });

  test('普通关闭屏障期间仍 busy 且不会提前读取余额', () async {
    final f = _Fixture()..plainCloseGate = Completer<void>();
    final reading = f.app.scanOnce();
    await f.plainCloseStarted.future;
    try {
      expect(f.operations, isEmpty);
      expect(f.app.scanning, isTrue);
    } finally {
      f.plainCloseGate!.complete();
      await reading;
    }
    expect(f.operations, ['balance']);
  });
  test('普通关闭失败保留识别结果并阻止余额会话', () async {
    final f = _Fixture()..failPlainClose = true;
    await f.app.scanOnce();
    expect(f.operations, isEmpty);
    expect(f.app.isOctopusCard, isTrue);
    expect(f.app.currentOctopusResult, isNull);
    expect(f.app.octopusReadNotice, contains('连接'));
  });
  test('关闭屏障期间停止不会迟到进入余额读取阶段', () async {
    final f = _Fixture()..plainCloseGate = Completer<void>();
    final reading = f.app.scanOnce();
    await f.plainCloseStarted.future;
    final stopping = f.app.stop();
    f.plainCloseGate!.complete();
    await Future.wait([reading, stopping]);
    expect(f.operations, isEmpty);
    expect(f.app.currentOctopusResult, isNull);
    expect(f.app.scanning, isFalse);
  });
  test('下一张普通卡清除绑定且不触发八达通读取', () async {
    final f = _Fixture();
    await f.app.scanOnce();
    expect(f.app.currentOctopusResult, isNotNull);
    f.octopusCard = false;
    await f.app.scanOnce();
    expect(f.app.isOctopusCard, isFalse);
    expect(f.operations, ['balance']);
    expect(f.app.currentOctopusResult, isNull);
    expect(f.app.octopusBalanceText, isNull);
  });
  test('已有 8008 IDm 与余额结果不符时拒绝回填', () async {
    final f = _Fixture()..balanceId = List.filled(8, 9);
    await f.app.scanOnce();
    expect(f.app.currentOctopusResult, isNull);
    expect(f.app.octopusReadNotice, contains('同一'));
  });
  test('余额读取失败保留普通读取与明确错误，下一张卡清除错误', () async {
    final f = _Fixture(
      execute: (_, _) async {
        throw const OctopusBalanceException(
          'raw failure',
          code: 'invalid_response',
        );
      },
    );
    await f.app.scanOnce();
    expect(f.app.felicaResult, isNotNull);
    expect(f.app.currentOctopusResult, isNull);
    expect(f.app.octopusReadNotice, contains('数据无效'));
    expect(f.app.octopusReadFailure, contains('数据无效'));
    f.octopusCard = false;
    await f.app.scanOnce();
    expect(f.app.octopusReadFailure, isNull);
  });
  test('余额读取中停止，迟到结果不回填', () async {
    final entered = Completer<bool Function()>();
    final late = Completer<OctopusBalanceResult>();
    final f = _Fixture(
      execute: (_, cancelled) {
        entered.complete(cancelled);
        return late.future;
      },
    );
    final reading = f.app.scanOnce();
    final cancelled = await entered.future.timeout(const Duration(seconds: 5));
    await f.app.stop();
    expect(cancelled(), isTrue);
    late.complete(_result(_idm));
    await reading;
    expect(f.app.currentOctopusResult, isNull);
    expect(f.app.scanning, isFalse);
  });
  test('尚未识别八达通时不能单独读取余额', () async {
    final f = _Fixture();
    await f.app.readOctopus();
    expect(f.operations, isEmpty);
    expect(f.events, isEmpty);
  });
  test('余额已返回但 NFC 尚未关闭时停止，不绑定迟到结果', () async {
    final f = _Fixture()..balanceCloseGate = Completer<void>();
    final reading = f.app.scanOnce();
    await f.balanceCloseStarted.future;
    final stopping = f.app.stop();
    f.balanceCloseGate!.complete();
    await Future.wait([reading, stopping]);
    expect(f.app.currentOctopusResult, isNull);
    expect(f.app.scanning, isFalse);
  });
}

const _idm = '0102030405060708';
const _id = [1, 2, 3, 4, 5, 6, 7, 8];
OctopusBalanceResult _result(String idm) => OctopusBalanceResult(
  balanceMinor: 5000,
  idmHex: idm,
  readAt: DateTime.utc(2026, 11, 17),
);

class _Fixture implements OctopusNfcChannel, NfcChannel, FelicaChannel {
  _Fixture({
    Future<OctopusBalanceResult> Function(String, bool Function())? execute,
  }) {
    final logger = AppLogger(store: MemoryLogStore());
    app = AppDependencies(
      channel: this,
      felicaChannel: this,
      database: testDatabase(),
      bundle: MissingTestAssets(),
      settingsStore: settings,
      logger: logger,
      octopusController: OctopusBalanceController(
        channel: this,
        diagnostics: logger,
        execute:
            ({
              required transceiveFelica,
              required isCancelled,
              expectedCardIdm,
            }) async {
              suppliedIdm = expectedCardIdm;
              final response = await transceiveFelica([6, 0, 0x80, 8, 1, 0]);
              final idm = response
                  .sublist(2, 10)
                  .map((b) => b.toRadixString(16).padLeft(2, '0'))
                  .join()
                  .toUpperCase();
              operations.add('balance');
              return execute != null ? execute(idm, isCancelled) : _result(idm);
            },
      ),
    );
    addTearDown(app.dispose);
  }
  late final AppDependencies app;
  final settings = MemorySettingsStore();
  final events = <String>[];
  final operations = <String>[];
  final plainCloseStarted = Completer<void>();
  Completer<void>? plainCloseGate;
  final balanceCloseStarted = Completer<void>();
  Completer<void>? balanceCloseGate;
  bool failPlainClose = false;
  bool octopusCard = true;
  String? nfcFSystemCode = '8008';
  String? suppliedIdm;
  List<int> balanceId = _id;
  @override
  Future<NfcScanResult?> scanOnce() async {
    events.add('plain-scan');
    return NfcScanResult(
      uid: _idm,
      technologies: octopusCard ? ['NfcF'] : ['Unknown'],
      isoDepConnected: false,
      felicaConnected: octopusCard,
      nfcFSystemCode: octopusCard ? nfcFSystemCode : null,
      timestamp: DateTime.utc(2026, 11, 17),
    );
  }

  @override
  Future<List<int>> transceive(List<int> frame) async {
    if (frame[1] == 0) return [20, 1, ..._id, ...List.filled(8, 0), 0x80, 8];
    if (frame[1] == 0x0c) return [13, 0x0d, ..._id, 1, 0x80, 8];
    throw StateError('unexpected ordinary command');
  }

  @override
  Future<void> stopScan() async {
    events.add('plain-close');
    if (!plainCloseStarted.isCompleted) plainCloseStarted.complete();
    await plainCloseGate?.future;
    if (failPlainClose) throw StateError('close failed');
  }

  @override
  Future<NfcScanResult?> scanSession(String sessionId) async {
    events.add('balance-scan');
    return NfcScanResult(
      sessionId: sessionId,
      uid: _idm,
      technologies: ['NfcF'],
      isoDepConnected: false,
      felicaConnected: true,
      timestamp: DateTime.utc(2026, 11, 17),
    );
  }

  @override
  Future<List<int>> exchangeSession(String sessionId, List<int> frame) async =>
      frame[1] == 4
      ? [11, 5, ...balanceId, 0]
      : [20, 1, ...balanceId, ...List.filled(8, 0), 0x80, 8];
  @override
  Future<void> closeSession(String sessionId) async {
    events.add('balance-close');
    if (!balanceCloseStarted.isCompleted) balanceCloseStarted.complete();
    await balanceCloseGate?.future;
  }
}
