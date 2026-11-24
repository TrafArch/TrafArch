import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/octopus/octopus_balance_controller.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/platform/nfc/octopus_channel.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/protocols/octopus/octopus_balance.dart';
import 'package:transit_card_analyzer/protocols/octopus/octopus_balance_reader.dart';
import 'package:transit_card_analyzer/shared/diagnostics/diagnostic_event.dart';

const _idm = '0102030405060708';
const _idmBytes = [1, 2, 3, 4, 5, 6, 7, 8];
const _poll = [6, 0, 0x80, 8, 1, 0];

OctopusBalanceResult _result([String idm = _idm]) => OctopusBalanceResult(
  balanceMinor: 5000,
  idmHex: idm,
  readAt: DateTime.utc(2026, 11, 17),
);

class _Nfc implements OctopusNfcChannel {
  final scanned = <String>[];
  final closed = <String>[];
  final frames = <List<int>>[];
  Completer<NfcScanResult?>? discovery;
  Completer<void>? closeGate;
  final closeStarted = Completer<void>();
  bool connected = true;
  bool staleDiscovery = false;
  Object? scanFailure;
  Object? closeFailure;
  Object? exchangeFailure;
  List<int> response = const [2, 1];
  final responses = <List<int>>[];

  NfcScanResult tag(String id) => NfcScanResult(
    sessionId: staleDiscovery ? 'stale-session' : id,
    uid: 'native-uid-must-not-be-trusted',
    technologies: const ['android.nfc.tech.NfcF'],
    isoDepConnected: false,
    felicaConnected: connected,
    timestamp: DateTime.utc(2026),
  );

  @override
  Future<NfcScanResult?> scanSession(String sessionId) async {
    scanned.add(sessionId);
    if (scanFailure case final failure?) throw failure;
    return discovery == null ? tag(sessionId) : discovery!.future;
  }

  @override
  Future<List<int>> exchangeSession(String sessionId, List<int> frame) async {
    expect(sessionId, scanned.last);
    frames.add(List.of(frame));
    if (exchangeFailure case final failure?) throw failure;
    return responses.isEmpty ? response : responses.removeAt(0);
  }

  @override
  Future<void> closeSession(String sessionId) async {
    closed.add(sessionId);
    if (!closeStarted.isCompleted) closeStarted.complete();
    await closeGate?.future;
    if (closeFailure case final failure?) throw failure;
  }
}

class _BrokenRecorder implements DiagnosticRecorder, DiagnosticSessionSink {
  _BrokenRecorder({this.failStart = false});
  final bool failStart;

  @override
  bool get recording => true;

  @override
  DiagnosticSessionSink startSession(
    String id, {
    DiagnosticSessionKind kind = DiagnosticSessionKind.scan,
  }) {
    if (failStart) throw StateError('private-logging-failure');
    return this;
  }

  @override
  void event(
    String type, {
    DiagnosticSeverity level = DiagnosticSeverity.info,
    DiagnosticPhase? phase,
    Map<String, Object?> data = const {},
  }) => throw StateError('private-logging-failure');

  @override
  void end(DiagnosticOutcome outcome) =>
      throw StateError('private-logging-failure');
}

OctopusBalanceController _controller(
  _Nfc nfc, {
  OctopusBalanceExecute? execute,
  DiagnosticRecorder? diagnostics,
  Duration discoveryTimeout = const Duration(seconds: 60),
  Duration operationTimeout = const Duration(seconds: 20),
}) => OctopusBalanceController(
  channel: nfc,
  diagnostics: diagnostics,
  discoveryTimeout: discoveryTimeout,
  operationTimeout: operationTimeout,
  execute:
      execute ??
      ({
        required transceiveFelica,
        required isCancelled,
        expectedCardIdm,
      }) async => _result(),
);

void main() {
  test('余额只在本次 NFC 会话关闭成功后发布', () async {
    final nfc = _Nfc()..closeGate = Completer<void>();
    final controller = _controller(nfc);
    addTearDown(controller.dispose);
    final reading = controller.read(expectedCardIdm: _idm);
    await nfc.closeStarted.future;
    expect(controller.busy, isTrue);
    expect(controller.result, isNull);
    expect(controller.lastAttemptSucceeded, isFalse);
    nfc.closeGate!.complete();
    await reading;
    expect(controller.result?.balanceMinor, 5000);
    expect(controller.result?.idmHex, _idm);
    expect(controller.lastAttemptSucceeded, isTrue);
    expect(controller.phase, OctopusBalancePhase.complete);
    expect(controller.busy, isFalse);
    expect(nfc.closed, nfc.scanned);
  });

  test('发现 NFC-F 前不执行读取，卡片身份交由执行器核验', () async {
    final nfc = _Nfc()..discovery = Completer<NfcScanResult?>();
    var executions = 0;
    String? suppliedIdm;
    final controller = _controller(
      nfc,
      execute:
          ({
            required transceiveFelica,
            required isCancelled,
            expectedCardIdm,
          }) async {
            executions++;
            suppliedIdm = expectedCardIdm;
            return _result();
          },
    );
    addTearDown(controller.dispose);
    final reading = controller.read(expectedCardIdm: '  $_idm  ');
    expect(controller.phase, OctopusBalancePhase.waiting);
    expect(controller.progressMessage, isNotNull);
    expect(executions, 0);
    nfc.discovery!.complete(nfc.tag(nfc.scanned.single));
    await reading;
    expect(executions, 1);
    expect(suppliedIdm, _idm);
    expect(controller.lastAttemptSucceeded, isTrue);
  });

  for (final issue in ['stale', 'disconnected', 'missing']) {
    test('拒绝 $issue 发现结果且始终关闭原会话', () async {
      final nfc = _Nfc()
        ..staleDiscovery = issue == 'stale'
        ..connected = issue != 'disconnected';
      if (issue == 'missing') {
        nfc.discovery = Completer<NfcScanResult?>()..complete(null);
      }
      var executions = 0;
      final controller = _controller(
        nfc,
        execute:
            ({
              required transceiveFelica,
              required isCancelled,
              expectedCardIdm,
            }) async {
              executions++;
              return _result();
            },
      );
      addTearDown(controller.dispose);
      await controller.read();
      expect(executions, 0);
      expect(controller.phase, OctopusBalancePhase.failed);
      expect(controller.result, isNull);
      expect(controller.error, isNotNull);
      final error = controller.error;
      controller.adapterEnabled();
      expect(controller.error, error);
      expect(controller.phase, OctopusBalancePhase.failed);
      expect(nfc.closed, nfc.scanned);
    });
  }

  for (final idm in ['0000000000000000', '010203', 'private-identifier']) {
    test('无效预期卡片标识 $idm 不开启 NFC', () async {
      final nfc = _Nfc();
      final controller = _controller(nfc);
      addTearDown(controller.dispose);
      await controller.read(expectedCardIdm: idm);
      expect(nfc.scanned, isEmpty);
      expect(controller.lastAttemptSucceeded, isFalse);
      expect(controller.error, isNotNull);
      expect(controller.error, isNot(contains(idm)));
    });
  }

  for (final idm in ['0000000000000000', '010203', '0102030405060709']) {
    test('执行器返回无效或不匹配标识 $idm 不发布余额', () async {
      final controller = _controller(
        _Nfc(),
        execute: ({
          required transceiveFelica,
          required isCancelled,
          expectedCardIdm,
        }) async => _result(idm),
      );
      addTearDown(controller.dispose);
      await controller.read(expectedCardIdm: _idm);
      expect(controller.result, isNull);
      expect(controller.lastAttemptSucceeded, isFalse);
      expect(controller.phase, OctopusBalancePhase.failed);
    });
  }

  final allowedFrames = <String, List<int>>{
    'Polling': _poll,
    'Request Service': [13, 2, ..._idmBytes, 1, 0x17, 1],
    'Request Response': [10, 4, ..._idmBytes],
    'Read Without Encryption': [16, 6, ..._idmBytes, 1, 0x17, 1, 1, 0x80, 0],
    'Request System Code': [10, 12, ..._idmBytes],
  };
  for (final entry in allowedFrames.entries) {
    test('只读传输允许 ${entry.key}', () async {
      final nfc = _Nfc();
      final controller = _controller(
        nfc,
        execute:
            ({
              required transceiveFelica,
              required isCancelled,
              expectedCardIdm,
            }) async {
              expect(await transceiveFelica(entry.value), [2, 1]);
              return _result();
            },
      );
      addTearDown(controller.dispose);
      await controller.read();
      expect(nfc.frames, [entry.value]);
      expect(controller.lastAttemptSucceeded, isTrue);
    });
  }

  final rejectedFrames = <String, List<int>>{
    '写入': [10, 8, ..._idmBytes],
    '认证': [10, 0x10, ..._idmBytes],
    '加密写入': [10, 0x16, ..._idmBytes],
    '未知命令': [2, 0xff],
    '空帧': [],
    '无命令': [1],
    '长度字段错误': [5, 0, 0x80, 8, 1, 0],
    '负数字节': [6, 0, 0x80, 8, -1, 0],
    '溢出字节': [6, 0, 0x80, 8, 256, 0],
    'Polling 其他系统': [6, 0, 0xff, 0xff, 1, 0],
    'Polling 附加字节': [7, 0, 0x80, 8, 1, 0, 0],
    'Request Service 缺少节点': [11, 2, ..._idmBytes, 1],
    'Request Response 附加数据': [11, 4, ..._idmBytes, 0],
    'Read Without Encryption 缺少块描述': [14, 6, ..._idmBytes, 1, 0x17, 1, 1],
    'Request System Code 缺少标识': [2, 12],
  };
  for (final entry in rejectedFrames.entries) {
    test('只读传输在原生调用前拒绝${entry.key}', () async {
      final nfc = _Nfc();
      final controller = _controller(
        nfc,
        execute:
            ({
              required transceiveFelica,
              required isCancelled,
              expectedCardIdm,
            }) async {
              await transceiveFelica(entry.value);
              return _result();
            },
      );
      addTearDown(controller.dispose);
      await controller.read();
      expect(nfc.frames, isEmpty);
      expect(controller.lastAttemptSucceeded, isFalse);
      expect(controller.phase, OctopusBalancePhase.failed);
    });
  }

  test('取消发现立即作废会话，迟到标签不进入读取', () async {
    final nfc = _Nfc()..discovery = Completer<NfcScanResult?>();
    var executions = 0;
    final controller = _controller(
      nfc,
      execute:
          ({
            required transceiveFelica,
            required isCancelled,
            expectedCardIdm,
          }) async {
            executions++;
            return _result();
          },
    );
    addTearDown(controller.dispose);
    final reading = controller.read();
    final before = controller.cancellationRevision;
    await controller.cancel();
    expect(controller.cancellationRevision, before + 1);
    expect(controller.phase, OctopusBalancePhase.cancelled);
    nfc.discovery!.complete(nfc.tag(nfc.scanned.single));
    await reading;
    expect(executions, 0);
    expect(controller.result, isNull);
    expect(nfc.closed, hasLength(1));
  });

  test('取消执行立即阻断后续 NFC 交换且丢弃迟到余额', () async {
    final nfc = _Nfc();
    final started = Completer<void>();
    final response = Completer<OctopusBalanceResult>();
    late bool Function() cancelled;
    late Future<List<int>> Function(List<int>) exchange;
    final controller = _controller(
      nfc,
      execute:
          ({required transceiveFelica, required isCancelled, expectedCardIdm}) {
            cancelled = isCancelled;
            exchange = transceiveFelica;
            started.complete();
            return response.future;
          },
    );
    addTearDown(controller.dispose);
    final reading = controller.read();
    await started.future;
    final closing = controller.cancel();
    expect(cancelled(), isTrue);
    await expectLater(exchange(_poll), throwsA(isA<OctopusBalanceException>()));
    response.complete(_result());
    await closing;
    await reading;
    expect(nfc.frames, isEmpty);
    expect(controller.result, isNull);
    expect(controller.lastAttemptSucceeded, isFalse);
    expect(controller.phase, OctopusBalancePhase.cancelled);
  });

  test('完成过程中取消也不发布已返回但未关闭的余额', () async {
    final nfc = _Nfc()..closeGate = Completer<void>();
    final controller = _controller(nfc);
    addTearDown(controller.dispose);
    final reading = controller.read();
    await nfc.closeStarted.future;
    final cancelling = controller.cancel();
    nfc.closeGate!.complete();
    await Future.wait([reading, cancelling]);
    expect(controller.result, isNull);
    expect(controller.phase, OctopusBalancePhase.cancelled);
    expect(controller.lastAttemptSucceeded, isFalse);
    expect(nfc.closed, hasLength(1));
  });

  test('关闭失败保持 busy 并阻止新读取，取消可重试释放', () async {
    final nfc = _Nfc()..closeFailure = StateError('private-close-failure');
    final controller = _controller(nfc);
    addTearDown(controller.dispose);
    await controller.read();
    expect(controller.busy, isTrue);
    expect(controller.releaseError, isNotNull);
    expect(controller.lastAttemptSucceeded, isFalse);
    expect(controller.result, isNull);
    await controller.read();
    expect(nfc.scanned, hasLength(1));
    expect(nfc.closed, hasLength(1));
    nfc.closeFailure = null;
    await controller.cancel();
    expect(nfc.closed, hasLength(2));
    expect(controller.busy, isFalse);
    expect(controller.releaseError, isNull);
    await controller.read();
    expect(nfc.scanned.toSet(), hasLength(2));
    expect(controller.result?.balanceMinor, 5000);
  });

  test('并行取消和 finishPending 共同等待同一次物理关闭', () async {
    final nfc = _Nfc()..closeGate = Completer<void>();
    final controller = _controller(nfc);
    addTearDown(controller.dispose);
    final reading = controller.read();
    await nfc.closeStarted.future;
    final first = controller.cancel();
    final second = controller.cancel();
    var finished = false;
    final finishing = controller.finishPending().then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    expect(nfc.closed, hasLength(1));
    nfc.closeGate!.complete();
    await Future.wait([reading, first, second, finishing]);
    expect(finished, isTrue);
    expect(controller.busy, isFalse);
    expect(controller.result, isNull);
  });

  test('监听器在 waiting 即取消仍能关闭已注册会话', () async {
    final nfc = _Nfc()..discovery = Completer<NfcScanResult?>();
    final controller = _controller(nfc);
    addTearDown(controller.dispose);
    controller.addListener(() {
      if (controller.phase == OctopusBalancePhase.waiting) {
        unawaited(controller.cancel());
      }
    });
    final reading = controller.read();
    await nfc.closeStarted.future;
    expect(nfc.closed, nfc.scanned);
    nfc.discovery!.complete(nfc.tag(nfc.scanned.single));
    await reading;
    expect(controller.result, isNull);
  });

  for (final action in ['clear', 'dispose']) {
    test('$action 作废在途读取且迟到结果不通知', () async {
      final nfc = _Nfc();
      final started = Completer<void>();
      final response = Completer<OctopusBalanceResult>();
      final controller = _controller(
        nfc,
        execute:
            ({
              required transceiveFelica,
              required isCancelled,
              expectedCardIdm,
            }) {
              started.complete();
              return response.future;
            },
      );
      var notifications = 0;
      controller.addListener(() => notifications++);
      final reading = controller.read();
      await started.future;
      if (action == 'clear') {
        controller.clearResult();
      } else {
        controller.dispose();
      }
      await nfc.closeStarted.future;
      final previous = notifications;
      response.complete(_result());
      await reading;
      await controller.finishPending();
      expect(controller.result, isNull);
      expect(controller.lastAttemptSucceeded, isFalse);
      if (action == 'dispose') expect(notifications, previous);
      expect(nfc.closed, hasLength(1));
      if (action == 'clear') controller.dispose();
    });
  }

  test('clearResult 清除已完成结果并恢复 idle', () async {
    final controller = _controller(_Nfc());
    addTearDown(controller.dispose);
    await controller.read();
    controller.clearResult();
    expect(controller.result, isNull);
    expect(controller.error, isNull);
    expect(controller.lastAttemptSucceeded, isFalse);
    expect(controller.phase, OctopusBalancePhase.idle);
  });

  test('发现超时不会执行协议且会关闭会话', () async {
    final nfc = _Nfc()..discovery = Completer<NfcScanResult?>();
    var executed = false;
    final controller = _controller(
      nfc,
      discoveryTimeout: const Duration(milliseconds: 1),
      execute:
          ({
            required transceiveFelica,
            required isCancelled,
            expectedCardIdm,
          }) async {
            executed = true;
            return _result();
          },
    );
    addTearDown(controller.dispose);
    await controller.read();
    nfc.discovery!.complete(nfc.tag(nfc.scanned.single));
    expect(executed, isFalse);
    expect(controller.error, contains('重新贴卡'));
    expect(controller.error, isNot(contains('网络')));
    expect(nfc.closed, hasLength(1));
  });

  test('协议超时后迟到返回不得恢复成功', () async {
    final response = Completer<OctopusBalanceResult>();
    final nfc = _Nfc();
    final controller = _controller(
      nfc,
      operationTimeout: const Duration(milliseconds: 1),
      execute: ({
        required transceiveFelica,
        required isCancelled,
        expectedCardIdm,
      }) => response.future,
    );
    addTearDown(controller.dispose);
    await controller.read();
    response.complete(_result());
    await Future<void>.delayed(Duration.zero);
    expect(controller.phase, OctopusBalancePhase.failed);
    expect(controller.result, isNull);
    expect(controller.error, isNot(contains('网络')));
    expect(nfc.closed, hasLength(1));
  });

  for (final code in ['NFC_DISABLED', 'NFC_UNAVAILABLE']) {
    test('$code 拒绝注册后重新开启 NFC 会清除提示并保留上次实读余额', () async {
      final nfc = _Nfc();
      final controller = _controller(nfc);
      addTearDown(controller.dispose);
      await controller.read();
      final previous = controller.result!;
      nfc.scanFailure = PlatformException(code: code);
      nfc.closeFailure = PlatformException(code: 'STALE_SESSION');
      await controller.read();
      expect(controller.busy, isFalse);
      expect(controller.releaseError, isNull);
      expect(controller.error, contains('NFC'));
      expect(controller.phase, OctopusBalancePhase.failed);
      controller.adapterEnabled();
      expect(controller.error, isNull);
      expect(controller.phase, OctopusBalancePhase.idle);
      expect(controller.result, same(previous));
      expect(controller.lastAttemptSucceeded, isFalse);
    });
  }

  test('开启 NFC 不会覆盖被中断的八达通会话的真实释放失败', () async {
    final nfc = _Nfc()
      ..discovery = Completer<NfcScanResult?>()
      ..closeFailure = PlatformException(code: 'NFC_CLOSE_FAILED');
    final controller = _controller(nfc);
    addTearDown(controller.dispose);
    final read = controller.read();
    nfc.discovery!.completeError(
      PlatformException(
        code: 'NFC_DISABLED',
        details: {'sessionId': nfc.scanned.single},
      ),
    );
    await read;
    controller.adapterEnabled();
    expect(controller.error, isNull);
    expect(controller.phase, OctopusBalancePhase.failed);
    expect(controller.busy, isTrue);
    expect(controller.releaseError, isNotNull);
    nfc.closeFailure = null;
    await controller.cancel();
    expect(controller.busy, isFalse);
    expect(controller.releaseError, isNull);
  });

  test('日志默认关闭，由注入 recorder 决定是否存储', () async {
    final logger = AppLogger(store: MemoryLogStore());
    addTearDown(logger.close);
    final controller = _controller(_Nfc(), diagnostics: logger);
    addTearDown(controller.dispose);
    await controller.read();
    expect(await logger.readSessions(), isEmpty);
    expect(controller.lastAttemptSucceeded, isTrue);
  });

  test('余额诊断只保留固定标识和标量，不包含卡片标识及帧', () async {
    final logger = AppLogger(store: MemoryLogStore())..enabled = true;
    addTearDown(logger.close);
    final controller = _controller(
      _Nfc(),
      diagnostics: logger,
      execute:
          ({
            required transceiveFelica,
            required isCancelled,
            expectedCardIdm,
          }) async {
            await transceiveFelica(_poll);
            return _result();
          },
    );
    addTearDown(controller.dispose);
    await controller.read(expectedCardIdm: _idm);
    final session = (await logger.readSessions()).single;
    expect(session.cardInfo?['cardName'], '八达通余额读取');
    expect(
      session.events.any((e) => e.data['protocol'] == 'octopus_balance'),
      isTrue,
    );
    expect(session.outcome, 'success');
    expect(session.raw, isNot(contains(_idm)));
    expect(session.raw, isNot(contains('native-uid')));
    expect(session.raw, isNot(contains('5000')));
    for (final event in session.events) {
      expect(
        event.data.values.every(
          (v) => v == null || v is String || v is num || v is bool,
        ),
        isTrue,
      );
      expect(event.data.keys, isNot(contains('frame')));
      expect(event.data.keys, isNot(contains('payload')));
    }
  });

  for (final failure in <Object>[
    StateError('private-message-$_idm'),
    const OctopusBalanceException(
      'private-message-$_idm',
      code: 'private-code-$_idm',
    ),
    const OctopusBalanceException('private-message-$_idm', code: 'identity'),
    PlatformException(
      code: 'private-code-$_idm',
      message: 'private-message-$_idm',
      details: {'raw': _idm},
    ),
  ]) {
    test('未知失败与已知异常都不显示或记录原始详情 ${failure.runtimeType}', () async {
      final logger = AppLogger(store: MemoryLogStore())..enabled = true;
      addTearDown(logger.close);
      final controller = _controller(
        _Nfc(),
        diagnostics: logger,
        execute: ({
          required transceiveFelica,
          required isCancelled,
          expectedCardIdm,
        }) async => throw failure,
      );
      addTearDown(controller.dispose);
      await controller.read();
      final session = (await logger.readSessions()).single;
      final details = jsonEncode({
        'error': controller.error,
        'raw': session.raw,
      });
      expect(details, isNot(contains('private-')));
      expect(details, isNot(contains(_idm)));
      expect(session.outcome, 'failed');
      expect(controller.phase, OctopusBalancePhase.failed);
    });
  }

  for (final failStart in [false, true]) {
    test('日志 ${failStart ? '启动' : '写入和结束'} 异常不改变余额和关闭次数', () async {
      final nfc = _Nfc();
      final controller = _controller(
        nfc,
        diagnostics: _BrokenRecorder(failStart: failStart),
      );
      addTearDown(controller.dispose);
      await controller.read();
      expect(controller.result?.balanceMinor, 5000);
      expect(controller.lastAttemptSucceeded, isTrue);
      expect(nfc.closed, hasLength(1));
    });
  }

  test('默认读取器通过控制器完成实卡帧余额读取', () async {
    final nfc = _Nfc()
      ..responses.addAll(const [
        [
          0x14, 0x01, //
          0x01, 0x01, 0x13, 0x01, 0xE2, 0x22, 0x3F, 0x08,
          0x04, 0x3B, 0x46, 0x85, 0x84, 0x82, 0xCC, 0xFF, 0x80, 0x08,
        ],
        [
          0x1D, 0x07, //
          0x01, 0x01, 0x13, 0x01, 0xE2, 0x22, 0x3F, 0x08,
          0x00, 0x00, 0x01, //
          0x00, 0x00, 0x03, 0x52, 0x00, 0x00, 0x00, 0x00,
          0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05,
        ],
      ]);
    const realIdm = '01011301E2223F08';
    final controller = _controller(
      nfc,
      execute: const OctopusBalanceReader().execute,
    );
    addTearDown(controller.dispose);
    await controller.read(expectedCardIdm: realIdm);

    expect(controller.phase, OctopusBalancePhase.complete);
    expect(controller.result?.idmHex, realIdm);
    expect(controller.result?.balanceMinor, 5000);
    expect(nfc.frames.first, OctopusBalanceReader.pollingFrame);
    expect(nfc.frames.last, [
      0x10, 0x06, //
      0x01, 0x01, 0x13, 0x01, 0xE2, 0x22, 0x3F, 0x08,
      0x01, 0x17, 0x01, //
      0x01, 0x80, 0x00,
    ]);
  });
}
