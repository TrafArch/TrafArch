import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/scan/application/card_read_coordinator.dart';
import 'package:transit_card_analyzer/features/scan/application/scan_controller.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/platform/nfc/felica_channel.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_service.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/protocols/bank/domain/models/bank_card_result.dart';
import 'package:transit_card_analyzer/shared/diagnostics/diagnostic_event.dart';

import 'support/test_database.dart';

import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';

void main() {
  test('首页已等待贴卡时第一次开启日志立即接管原会话，无需重扫或再切开关', () async {
    final logger = AppLogger(store: MemoryLogStore());
    final channel = _Sessions();
    final app = AppDependencies(
      database: testDatabase(),
      channel: channel,
      bundle: MissingTestAssets(),
      logger: logger,
      settingsStore: MemorySettingsStore(),
    );
    addTearDown(app.dispose);
    await app.settings.initialize();
    final reading = app.scanOnce();
    final id = channel.discoveries.keys.single;
    expect(logger.enabled, isFalse);
    expect(await app.diagnostics.sessions(), isEmpty);
    await app.setLoggingEnabled(true);
    expect(app.loggingEnabled, isTrue);
    expect(channel.discoveries.keys, [id]);
    final waiting = (await app.diagnostics.sessions()).single;
    expect(waiting.id, id);
    expect(waiting.running, isTrue);
    channel.discoveries[id]!.complete(_tag(id));
    await reading;
    final finished = (await app.diagnostics.sessions()).single;
    expect(finished.events.any((e) => e.type == 'physical_frame'), isTrue);
    expect(finished.events.any((e) => e.type == 'session_end'), isTrue);
    expect(finished.incomplete, isFalse);
  });

  test('等待后直接启用写入器，发现首张卡时补接日志但不追记关闭期间数据', () async {
    final logger = AppLogger(store: MemoryLogStore());
    addTearDown(logger.close);
    final channel = _Sessions();
    final scan = ScanController(
      channel: channel,
      felicaChannel: const MethodChannelFelicaChannel(),
      coordinator: _NoIoCoordinator(),
      logEvent: (_) {},
      diagnostics: logger,
    );
    addTearDown(scan.dispose);
    final reading = scan.scanOnce();
    final id = channel.discoveries.keys.single;
    logger.enabled = true;
    channel.discoveries[id]!.complete(_tag(id));
    await reading;
    final session = (await logger.readSessions()).single;
    expect(session.events.first.type, 'session_start');
    expect(session.events.any((e) => e.type == 'tag_discovered'), isTrue);
    expect(session.incomplete, isFalse);
    final second = scan.scanOnce();
    final secondId = channel.discoveries.keys.last;
    logger.enabled = false;
    logger.enabled = true;
    scan.refreshWaitingDiagnostics();
    channel.discoveries[secondId]!.complete(_tag(secondId));
    await second;
    final interrupted = (await logger.readSessions()).singleWhere(
      (s) => s.id == secondId,
    );
    expect(interrupted.outcome, 'recordingStopped');
    expect(interrupted.events.any((e) => e.type == 'tag_discovered'), isFalse);
  });

  test('取消时迟到成功响应仍归旧会话，不能伪装成无响应', () async {
    final logger = AppLogger(store: MemoryLogStore())..enabled = true;
    addTearDown(logger.close);
    final channel = _DelayedSessions();
    final coordinator = _OneExchangeCoordinator();
    final scan = ScanController(
      channel: channel,
      felicaChannel: const MethodChannelFelicaChannel(),
      coordinator: coordinator,
      logEvent: (_) {},
      diagnostics: logger,
    );
    addTearDown(scan.dispose);
    final first = scan.scanOnce();
    final oldId = channel.discoveries.keys.single;
    channel.discoveries[oldId]!.complete(_tag(oldId));
    await channel.entered.future;
    await scan.stop();
    final second = scan.scanOnce();
    final newId = channel.discoveries.keys.last;
    channel.response.complete([0x01, 0x90, 0]);
    await first;
    channel.discoveries[newId]!.complete(_tag(newId));
    await second;
    final sessions = await logger.readSessions();
    final old = sessions.singleWhere((s) => s.id == oldId);
    expect(old.outcome, 'cancelled');
    expect(old.events.where((e) => e.type == 'physical_frame'), hasLength(1));
    expect(
      old.events
          .singleWhere((e) => e.type == 'physical_frame')
          .data['response'],
      [1, 0x90, 0],
    );
    expect(old.events.any((e) => e.type == 'late_response_ignored'), isTrue);
    expect(
      sessions
          .singleWhere((s) => s.id == newId)
          .events
          .any((e) => e.type == 'physical_frame'),
      isFalse,
    );
    expect(scan.frames, isEmpty);
  });

  test('实际协议探测掉卡仍记录已读前缀、失败命令和独立关闭错误', () async {
    final logger = AppLogger(store: MemoryLogStore())..enabled = true;
    addTearDown(logger.close);
    final channel = _Sessions()..closeFails = true;
    final scan = ScanController(
      channel: channel,
      felicaChannel: const MethodChannelFelicaChannel(),
      coordinator: CardReadCoordinator(MissingTestAssets()),
      logEvent: (_) {},
      diagnostics: logger,
    );
    addTearDown(scan.dispose);
    final pending = scan.scanOnce();
    final id = channel.discoveries.keys.single;
    channel.discoveries[id]!.complete(_tag(id));
    await pending;
    final session = (await logger.readSessions()).single;
    final frames = session.events
        .where((e) => e.type == 'physical_frame')
        .toList();
    expect(frames.length, 2);
    expect(frames.first.data['response'], [0x6A, 0x82]);
    expect(frames.first.level, DiagnosticSeverity.info);
    expect(frames.last.data['command'], channel.commands.last);
    expect(frames.last.data['response'], isNull);
    expect(frames.last.data['failureKind'], 'tagLost');
    expect(
      (frames.last.data['errorDetails'] as Map)['exception'],
      'android.nfc.TagLostException',
    );
    expect(frames.last.data['errorCode'], 'TRANSCEIVE_FAILED');
    expect(frames.last.data['durationMicros'], isA<int>());
    expect(
      session.events
          .singleWhere((e) => e.type == 'close_result')
          .data['errorCode'],
      'NFC_CLOSE_FAILED',
    );
    expect(session.outcome, 'partial');
    expect(session.incomplete, isFalse);
    expect(scan.trace.last, contains('>>'));
    expect(scan.frames.last.command, channel.commands.last);
    expect(session.events.last.type, 'session_end');
  });

  test('保留银行卡枚举诊断的会话标记为部分读取', () async {
    final logger = AppLogger(store: MemoryLogStore())..enabled = true;
    addTearDown(logger.close);
    final channel = _Sessions();
    final outcome = BankReadOutcome(
      BankCardResult(
        protocolFamily: BankCardProtocolFamily.unknown,
        analyzedAt: DateTime.utc(2026),
        parserVersion: 'test',
        status: BankCardStatus.enumerationFailed,
      ),
    );
    final scan = ScanController(
      channel: channel,
      felicaChannel: const MethodChannelFelicaChannel(),
      coordinator: _NoIoCoordinator(outcome),
      logEvent: (_) {},
      diagnostics: logger,
    );
    addTearDown(scan.dispose);
    final pending = scan.scanOnce();
    final id = channel.discoveries.keys.single;
    channel.discoveries[id]!.complete(_tag(id));
    await pending;

    final session = (await logger.readSessions()).single;
    final info = session.events.singleWhere((e) => e.type == 'card_info');
    expect(info.data['identificationState'], 'unknown');
    expect(scan.outcome, same(outcome));
    expect(session.outcome, 'partial');
  });

  test('取消后的迟到发现只写旧会话，不能污染新会话', () async {
    final logger = AppLogger(store: MemoryLogStore())..enabled = true;
    addTearDown(logger.close);
    final channel = _Sessions();
    final scan = ScanController(
      channel: channel,
      felicaChannel: const MethodChannelFelicaChannel(),
      coordinator: _NoIoCoordinator(),
      logEvent: (_) {},
      diagnostics: logger,
    );
    addTearDown(scan.dispose);
    final old = scan.scanOnce();
    final oldId = channel.discoveries.keys.single;
    await scan.stop();
    final next = scan.scanOnce();
    final newId = channel.discoveries.keys.last;
    channel.discoveries[oldId]!.complete(_tag(oldId));
    await old;
    channel.discoveries[newId]!.complete(_tag(newId));
    await next;
    final sessions = await logger.readSessions();
    final cancelled = sessions.singleWhere((s) => s.id == oldId);
    final current = sessions.singleWhere((s) => s.id == newId);
    expect(cancelled.outcome, 'cancelled');
    expect(cancelled.events.any((e) => e.type == 'tag_discovered'), isFalse);
    expect(current.outcome, 'unsupported');
    expect(current.events.any((e) => e.type == 'scan_cancelled'), isFalse);
    for (final session in sessions) {
      expect(session.events.every((e) => e.sessionId == session.id), isTrue);
      expect(
        session.events.map((e) => e.sequence),
        List.generate(session.events.length, (i) => i),
      );
      expect(
        session.events.where((e) => e.type == 'close_result'),
        hasLength(1),
      );
    }
  });

  test('关闭持久化日志仍保留本次完整物理帧和文本过程', () async {
    final store = MemoryLogStore();
    final logger = AppLogger(store: store);
    addTearDown(logger.close);
    final channel = _Sessions();
    final scan = ScanController(
      channel: channel,
      felicaChannel: const MethodChannelFelicaChannel(),
      coordinator: CardReadCoordinator(MissingTestAssets()),
      logEvent: (_) {},
      diagnostics: logger,
    );
    addTearDown(scan.dispose);
    final pending = scan.scanOnce();
    final id = channel.discoveries.keys.single;
    channel.discoveries[id]!.complete(_tag(id));
    await pending;
    expect(scan.frames, hasLength(2));
    expect(scan.trace.first, contains('=='));
    expect(scan.trace.any((line) => line.contains('6A 82')), isTrue);
    expect(scan.trace.last, contains('!!'));
    expect(await logger.readSessions(), isEmpty);
  });
}

NfcScanResult _tag(String id) => NfcScanResult(
  sessionId: id,
  uid: '00112233',
  technologies: const ['IsoDep'],
  isoDepConnected: true,
  timestamp: DateTime.utc(2026),
);

class _Sessions implements SessionNfcChannel {
  final discoveries = <String, Completer<NfcScanResult?>>{};
  final commands = <List<int>>[];
  bool closeFails = false;
  @override
  Future<NfcScanResult?> scanSession(String sessionId) =>
      (discoveries[sessionId] = Completer<NfcScanResult?>()).future;
  @override
  Future<List<int>> exchangeSession(String sessionId, List<int> apdu) async {
    commands.add(List.of(apdu));
    if (commands.length == 1) return [0x6A, 0x82];
    throw PlatformException(
      code: 'TRANSCEIVE_FAILED',
      message: 'tag gone',
      details: {'exception': 'android.nfc.TagLostException'},
    );
  }

  @override
  Future<void> closeSession(String sessionId) async {
    if (closeFails) {
      throw PlatformException(
        code: 'NFC_CLOSE_FAILED',
        message: 'close failed',
      );
    }
  }

  @override
  Future<NfcScanResult?> scanOnce() => throw StateError('legacy');
  @override
  Future<List<int>> transceive(List<int> apdu) => throw StateError('legacy');
  @override
  Future<void> stopScan() => throw StateError('legacy');
}

class _NoIoCoordinator extends CardReadCoordinator {
  _NoIoCoordinator([this.result = const UnsupportedReadOutcome()])
    : super(MissingTestAssets());

  final CardReadOutcome result;

  @override
  Future<CardReadOutcome> read(
    NfcScanResult tag, {
    required Future<List<int>> Function(List<int>) apdu,
    required Future<List<int>> Function(List<int>) felica,
    required void Function(String) onStage,
    required void Function(int) onProgress,
  }) async => result;
}

class _DelayedSessions extends _Sessions {
  final entered = Completer<void>();
  final response = Completer<List<int>>();
  @override
  Future<List<int>> exchangeSession(String sessionId, List<int> apdu) {
    entered.complete();
    return response.future;
  }
}

class _OneExchangeCoordinator extends _NoIoCoordinator {
  int reads = 0;
  @override
  Future<CardReadOutcome> read(
    NfcScanResult tag, {
    required Future<List<int>> Function(List<int>) apdu,
    required Future<List<int>> Function(List<int>) felica,
    required void Function(String) onStage,
    required void Function(int) onProgress,
  }) async {
    if (reads++ == 0) await apdu([0, 0xA4, 0, 0]);
    return const UnsupportedReadOutcome();
  }
}
