import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/octopus/octopus_balance_controller.dart';
import 'package:transit_card_analyzer/features/settings/application/diagnostic_export.dart';
import 'package:transit_card_analyzer/features/recovery/recovery_state.dart';
import 'package:transit_card_analyzer/platform/memory/memory_platform.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_service.dart';
import 'package:transit_card_analyzer/platform/nfc/octopus_channel.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/protocols/octopus/octopus_balance.dart';

import 'support/test_database.dart';

import 'package:transit_card_analyzer/platform/nfc/felica_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('统一读取的余额读取失败仍进入原日志导出且不包含余额卡片数据', () async {
    final f = _Fixture(
      execute: (_, _) async {
        throw const OctopusBalanceException(
          'raw failure',
          code: 'invalid_response',
        );
      },
    );
    await f.app.settings.initialize();
    await f.app.setLoggingEnabled(true);
    await f.app.scanOnce();
    final all = await f.app.diagnostics.sessions();
    final balance = all
        .where((s) => s.cardInfo?['cardName'] == '八达通余额读取')
        .toList();
    expect(balance, hasLength(1));
    expect(balance.single.outcome, 'failed');
    final exported = buildFullDiagnostics(balance, DateTime.utc(2026, 11, 17));
    expect(exported, contains('invalid_response'));
    expect(exported, isNot(contains('0102030405060708')));
    expect(f.app.felicaResult, isNotNull);
  });
  test('新读卡等待旧余额连接关闭并拒绝旧余额迟到结果', () async {
    final entered = Completer<bool Function()>();
    final late = Completer<OctopusBalanceResult>();
    var executions = 0;
    final f = _Fixture(
      execute: (idm, cancelled) {
        if (executions++ == 0) return Future.value(_result(idm));
        entered.complete(cancelled);
        return late.future;
      },
    );
    await f.app.scanOnce();
    expect(f.app.currentOctopusResult?.balanceMinor, 5000);
    final balance = f.app.readOctopus();
    final cancelled = await entered.future;
    f.closeGate = Completer<void>();
    f.octopusCard = false;
    final next = f.app.scanOnce();
    try {
      await Future<void>.delayed(Duration.zero);
      expect(cancelled(), isTrue);
      expect(f.events.where((e) => e == 'plain-scan'), hasLength(1));
    } finally {
      f.closeGate!.complete();
      await next;
      late.complete(_result('0102030405060708'));
      await balance;
    }
    expect(f.app.isOctopusCard, isFalse);
    expect(f.app.currentOctopusResult, isNull);
    expect(f.app.octopus.result, isNull);
  });
  test('HONOR KILL 取消统一读取的余额读取阶段但保留已读普通结果', () async {
    final entered = Completer<bool Function()>();
    final late = Completer<OctopusBalanceResult>();
    final memory = _RecoveryMemory();
    final f = _Fixture(
      memoryPlatform: memory,
      execute: (_, cancelled) {
        entered.complete(cancelled);
        return late.future;
      },
    );
    await f.app.init();
    final reading = f.app.scanOnce();
    final cancelled = await entered.future;
    final close = f.closeGate = Completer<void>();
    try {
      expect(await f.app.handleMemoryPressure(true), isTrue);
      expect(cancelled(), isTrue);
      expect(RecoveryState.decode(memory.text!).capture, isNotNull);
    } finally {
      late.complete(_result('0102030405060708'));
      close.complete();
      await reading;
    }
    expect(f.app.currentOctopusResult, isNull);
  });
}

OctopusBalanceResult _result(String idm) => OctopusBalanceResult(
  balanceMinor: 5000,
  idmHex: idm,
  readAt: DateTime.utc(2026, 11, 17),
);

class _Fixture implements OctopusNfcChannel, NfcChannel, FelicaChannel {
  _Fixture({
    Future<OctopusBalanceResult> Function(String, bool Function())? execute,
    MemorySettingsStore? settings,
    MemoryPlatform? memoryPlatform,
  }) : settings = settings ?? MemorySettingsStore() {
    final logger = AppLogger(store: MemoryLogStore());
    app = AppDependencies(
      channel: this,
      felicaChannel: this,
      database: testDatabase(),
      bundle: MissingTestAssets(),
      settingsStore: this.settings,
      logger: logger,
      memoryPlatform: memoryPlatform,
      octopusController: OctopusBalanceController(
        channel: this,
        diagnostics: logger,
        execute:
            ({
              required transceiveFelica,
              required isCancelled,
              expectedCardIdm,
            }) async {
              await transceiveFelica([6, 0, 0x80, 8, 1, 0]);
              if (execute != null) {
                return execute('0102030405060708', isCancelled);
              }
              return _result('0102030405060708');
            },
      ),
    );
    addTearDown(app.dispose);
  }

  late final AppDependencies app;
  final MemorySettingsStore settings;
  final events = <String>[];
  Completer<void>? closeGate;
  bool octopusCard = true;

  @override
  Future<NfcScanResult?> scanSession(String sessionId) async {
    events.add('octopus-scan');
    return NfcScanResult(
      sessionId: sessionId,
      uid: '01 02 03 04 05 06 07 08',
      technologies: const ['NfcF'],
      isoDepConnected: false,
      felicaConnected: true,
      timestamp: DateTime.utc(2026, 11, 17),
    );
  }

  @override
  Future<List<int>> exchangeSession(String sessionId, List<int> frame) async {
    expect(frame, [6, 0, 0x80, 8, 1, 0]);
    return [20, 1, 1, 2, 3, 4, 5, 6, 7, 8, ...List.filled(8, 0), 0x80, 8];
  }

  @override
  Future<void> closeSession(String sessionId) async {
    events.add('octopus-close');
    await closeGate?.future;
  }

  @override
  Future<NfcScanResult?> scanOnce() async {
    events.add('plain-scan');
    return NfcScanResult(
      uid: '0102030405060708',
      technologies: ['NfcF'],
      isoDepConnected: false,
      felicaConnected: octopusCard,
      nfcFSystemCode: '8008',
      timestamp: DateTime.utc(2026, 11, 17),
    );
  }

  @override
  Future<void> stopScan() async {
    events.add('plain-close');
  }

  @override
  Future<List<int>> transceive(List<int> frame) async {
    const id = [1, 2, 3, 4, 5, 6, 7, 8];
    if (frame[1] == 0) return [20, 1, ...id, ...List.filled(8, 0), 0x80, 8];
    if (frame[1] == 0x0c) return [13, 0x0d, ...id, 1, 0x80, 8];
    throw StateError('Unexpected ordinary command');
  }
}

class _RecoveryMemory extends NoopMemoryPlatform {
  String? text;

  @override
  Future<void> writeRecovery(String content) async {
    text = content;
  }
}
