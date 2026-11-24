import 'dart:async';

import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../platform/nfc/octopus_channel.dart';
import '../../protocols/octopus/octopus_balance.dart';
import '../../shared/application/owned_notifier.dart';
import '../../shared/diagnostics/diagnostic_event.dart';

enum OctopusBalancePhase { idle, waiting, reading, complete, failed, cancelled }

/// Owns one read-only NFC-F attempt, including its physical close barrier.
/// A result becomes visible only after that same attempt closes successfully.
class OctopusBalanceController extends OwnedNotifier {
  OctopusBalanceController({
    required this.channel,
    required this.execute,
    this.diagnostics,
    this.discoveryTimeout = const Duration(seconds: 60),
    this.operationTimeout = const Duration(seconds: 20),
  });

  final OctopusNfcChannel channel;
  final OctopusBalanceExecute execute;
  final DiagnosticRecorder? diagnostics;
  final Duration discoveryTimeout;
  final Duration operationTimeout;

  OctopusBalancePhase phase = OctopusBalancePhase.idle;
  OctopusBalanceResult? result;
  String? error;
  bool _adapterFailure = false;
  String? releaseError;
  bool lastAttemptSucceeded = false;
  _BalanceAttempt? _attempt;
  int _cancelRevision = 0;
  final Set<Future<void>> _pending = {};

  bool get busy => _attempt != null;
  int get cancellationRevision => _cancelRevision;
  String? get progressMessage => !busy
      ? null
      : switch (phase) {
          OctopusBalancePhase.waiting => '正在寻找八达通 NFC-F 接口，请保持同一张卡片贴近手机。',
          OctopusBalancePhase.reading => '正在读取八达通余额，请保持同一张卡片贴近手机。',
          _ => null,
        };

  bool _current(_BalanceAttempt attempt) =>
      !disposed &&
      identical(_attempt, attempt) &&
      !attempt.cancelled &&
      attempt.closeFuture == null;

  void adapterEnabled() {
    if (disposed || !_adapterFailure) return;
    _adapterFailure = false;
    error = null;
    if (phase == OctopusBalancePhase.failed && releaseError == null) {
      phase = OctopusBalancePhase.idle;
    }
    notifyListeners();
  }

  Future<void> read({String? expectedCardIdm}) async {
    if (disposed || busy) return;
    _adapterFailure = false;
    final expectedIdm = expectedCardIdm?.trim().toUpperCase();
    if (expectedIdm != null && !_validIdm(expectedIdm)) {
      error = '本次卡片标识无效，请重新读卡。';
      phase = OctopusBalancePhase.failed;
      lastAttemptSucceeded = false;
      notifyListeners();
      return;
    }

    final attempt = _BalanceAttempt();
    _attempt = attempt;
    try {
      attempt.sink = diagnostics?.startSession(attempt.id);
    } catch (_) {
      // Optional diagnostics must never change or repeat a card operation.
    }
    _record(
      attempt,
      'protocol_stage',
      data: {'protocol': 'octopus_balance', 'stage': 'start'},
    );
    _record(
      attempt,
      'card_info',
      data: {'cardName': '八达通余额读取', 'cardTypeLabel': '八达通 NFC-F'},
    );
    phase = OctopusBalancePhase.waiting;
    error = null;
    releaseError = null;
    lastAttemptSucceeded = false;
    // Register the scan before notifying: a waiting listener may cancel now.
    final pending = _track(_run(attempt, expectedIdm));
    notifyListeners();
    await pending;
  }

  Future<void> _run(_BalanceAttempt attempt, String? expectedIdm) async {
    try {
      final tag = await channel
          .scanSession(attempt.id)
          .timeout(
            discoveryTimeout,
            onTimeout: () => throw const OctopusBalanceException(
              _discoveryTimedOut,
              code: 'NFC_DISCOVERY_TIMEOUT',
            ),
          );
      if (!_current(attempt)) return;
      if (tag == null) {
        throw const OctopusBalanceException('未检测到卡片。', code: 'no_card');
      }
      if (tag.sessionId != attempt.id) {
        throw const OctopusBalanceException(
          '读卡会话已失效。',
          code: 'NFC_SESSION_CLOSED',
        );
      }
      if (!tag.felicaConnected) {
        throw const OctopusBalanceException(
          '未连接 NFC-F 接口。',
          code: 'NFC_NOT_CONNECTED',
        );
      }
      attempt.stage = 'reading';
      phase = OctopusBalancePhase.reading;
      _record(attempt, 'protocol_stage', data: {'stage': 'reading'});
      notifyListeners();
      if (!_current(attempt)) return;
      final response = await execute(
        transceiveFelica: (frame) => _exchange(attempt, frame),
        isCancelled: () => !_current(attempt),
        expectedCardIdm: expectedIdm,
      ).timeout(operationTimeout);
      if (!_current(attempt)) return;
      final idm = response.idmHex.toUpperCase();
      if (!_validIdm(idm) || (expectedIdm != null && idm != expectedIdm)) {
        throw const OctopusBalanceException(
          '返回余额与本次卡片身份不一致。',
          code: 'identity',
        );
      }
      attempt.pendingResult = OctopusBalanceResult(
        balanceMinor: response.balanceMinor,
        idmHex: idm,
        readAt: response.readAt,
      );
      attempt.outcome = DiagnosticOutcome.success;
      _record(attempt, 'protocol_stage', data: {'stage': 'complete'});
    } catch (failure) {
      if (!_current(attempt)) return;
      phase = OctopusBalancePhase.failed;
      attempt.outcome = DiagnosticOutcome.failed;
      final code = _failureCode(failure);
      _adapterFailure = code == 'NFC_DISABLED' || code == 'NFC_UNAVAILABLE';
      error = _failureMessage(failure, code);
      _record(
        attempt,
        'octopus_failure',
        level: DiagnosticSeverity.error,
        data: {'stage': attempt.stage, ..._safeFailure(failure)},
      );
    } finally {
      await _close(attempt);
    }
  }

  Future<List<int>> _exchange(_BalanceAttempt attempt, List<int> frame) async {
    if (!_current(attempt)) throw _cancelled;
    // Freeze before validation so a caller cannot later change an approved
    // command into a write while the native exchange is queued.
    final request = List<int>.unmodifiable(frame);
    if (!_validReadOnlyFrame(request)) {
      throw const OctopusBalanceException(
        '不允许发送非只读或无效的 NFC 请求。',
        code: 'command_policy',
      );
    }
    final elapsed = Stopwatch()..start();
    _record(
      attempt,
      'octopus_nfc_exchange',
      data: {
        'stage': attempt.stage,
        'state': 'start',
        'command': request[1],
        'requestLength': request.length,
      },
    );
    try {
      final response = await channel.exchangeSession(attempt.id, request);
      if (!_current(attempt)) throw _cancelled;
      if (!_validEnvelope(response)) {
        throw const OctopusBalanceException(
          'NFC 响应帧无效。',
          code: 'invalid_response',
        );
      }
      _record(
        attempt,
        'octopus_nfc_exchange',
        data: {
          'stage': attempt.stage,
          'state': 'complete',
          'command': request[1],
          'responseLength': response.length,
          'durationMs': elapsed.elapsedMilliseconds,
        },
      );
      return List<int>.unmodifiable(response);
    } catch (failure) {
      if (_current(attempt)) {
        _record(
          attempt,
          'octopus_nfc_exchange',
          level: DiagnosticSeverity.error,
          data: {
            'stage': attempt.stage,
            'state': 'failed',
            'command': request[1],
            'durationMs': elapsed.elapsedMilliseconds,
            ..._safeFailure(failure),
          },
        );
      }
      rethrow;
    }
  }

  Future<void> _close(_BalanceAttempt attempt, {bool retryFailure = false}) {
    final previous = attempt.closeFuture;
    if (previous != null &&
        !(retryFailure && attempt.closeFinished && attempt.closeFailed)) {
      return previous;
    }
    attempt.closeFinished = false;
    attempt.closeFailed = false;
    // Reserve the same future before close begins; all callers join it and no
    // further frame can pass _current while physical release is pending.
    final closing = _track(Future<void>.microtask(() => _finishClose(attempt)));
    return attempt.closeFuture = closing;
  }

  Future<void> _finishClose(_BalanceAttempt attempt) async {
    _record(attempt, 'protocol_stage', data: {'stage': 'closing'});
    try {
      await channel.closeSession(attempt.id);
    } on PlatformException catch (failure) {
      // Native has no connection for a rejected or already retired session.
      attempt.closeFailed = failure.code != 'STALE_SESSION';
    } catch (_) {
      attempt.closeFailed = true;
    }
    attempt.closeFinished = true;
    _record(
      attempt,
      'protocol_stage',
      data: {'stage': attempt.closeFailed ? 'close_failed' : 'closed'},
    );
    _endRecording(attempt);
    if (disposed || !identical(_attempt, attempt)) return;
    if (attempt.closeFailed) {
      attempt.pendingResult = null;
      if (!attempt.cancelled) phase = OctopusBalancePhase.failed;
      releaseError = 'NFC 连接尚未确认关闭，请先停止操作再重试。';
      lastAttemptSucceeded = false;
    } else {
      _attempt = null;
      releaseError = null;
      if (attempt.pendingResult case final response? when !attempt.cancelled) {
        result = response;
        lastAttemptSucceeded = true;
        phase = OctopusBalancePhase.complete;
      }
    }
    notifyListeners();
  }

  Future<void> cancel() async {
    _cancelRevision++;
    final attempt = _attempt;
    if (attempt == null) return;
    // Cancellation also invalidates a candidate result during the close barrier.
    attempt.cancelled = true;
    attempt.pendingResult = null;
    attempt.outcome = DiagnosticOutcome.cancelled;
    phase = OctopusBalancePhase.cancelled;
    lastAttemptSucceeded = false;
    _record(attempt, 'protocol_stage', data: {'stage': 'cancelled'});
    final closing = _close(attempt, retryFailure: true);
    notifyListeners();
    await closing;
  }

  void clearResult() {
    result = null;
    error = null;
    _adapterFailure = false;
    lastAttemptSucceeded = false;
    if (busy) {
      unawaited(cancel());
    } else {
      phase = OctopusBalancePhase.idle;
      notifyListeners();
    }
  }

  void _record(
    _BalanceAttempt attempt,
    String type, {
    DiagnosticSeverity level = DiagnosticSeverity.info,
    Map<String, Object?> data = const {},
  }) {
    if (attempt.recordingEnded) return;
    try {
      attempt.sink?.event(
        type,
        level: level,
        data: {...data, 'elapsedMs': attempt.elapsed.elapsedMilliseconds},
      );
    } catch (_) {
      // Recording is best effort and never owns the NFC lifecycle.
    }
  }

  void _endRecording(_BalanceAttempt attempt) {
    if (attempt.recordingEnded) return;
    attempt.recordingEnded = true;
    attempt.elapsed.stop();
    try {
      attempt.sink?.end(
        attempt.closeFailed ? DiagnosticOutcome.failed : attempt.outcome,
      );
    } catch (_) {
      // Logging completion cannot substitute for physical close confirmation.
    }
  }

  Future<void> _track(Future<void> future) {
    _pending.add(future);
    return future.whenComplete(() => _pending.remove(future));
  }

  Future<void> finishPending() async {
    while (_pending.isNotEmpty) {
      await Future.wait(_pending.toList());
    }
  }

  @override
  void dispose() {
    _cancelRevision++;
    final attempt = _attempt;
    if (attempt != null) {
      attempt.cancelled = true;
      attempt.pendingResult = null;
      attempt.outcome = DiagnosticOutcome.cancelled;
      _record(attempt, 'protocol_stage', data: {'stage': 'disposed'});
    }
    _attempt = null;
    super.dispose();
    if (attempt != null) unawaited(_close(attempt, retryFailure: true));
  }
}

class _BalanceAttempt {
  final String id = const Uuid().v4();
  final elapsed = Stopwatch()..start();
  DiagnosticSessionSink? sink;
  DiagnosticOutcome outcome = DiagnosticOutcome.failed;
  String stage = 'discovery';
  bool recordingEnded = false;
  bool cancelled = false;
  OctopusBalanceResult? pendingResult;
  Future<void>? closeFuture;
  bool closeFinished = false;
  bool closeFailed = false;
}

bool _validIdm(String idm) =>
    RegExp(r'^[0-9A-F]{16}$').hasMatch(idm) && idm != '0000000000000000';

bool _validEnvelope(List<int> frame) =>
    frame.length >= 2 &&
    frame.length <= 255 &&
    frame.first == frame.length &&
    frame.every((value) => value >= 0 && value <= 255);

bool _validReadOnlyFrame(List<int> frame) {
  if (!_validEnvelope(frame)) return false;
  switch (frame[1]) {
    case 0:
      return frame.length == 6 && frame[2] == 0x80 && frame[3] == 8;
    case 2:
      return frame.length >= 13 &&
          frame[10] >= 1 &&
          frame[10] <= 32 &&
          frame.length == 11 + frame[10] * 2;
    case 4:
    case 12:
      return frame.length == 10;
    case 6:
      if (frame.length < 16) return false;
      final services = frame[10];
      if (services < 1 || services > 16) return false;
      var offset = 11 + services * 2;
      if (offset >= frame.length) return false;
      final blocks = frame[offset++];
      if (blocks == 0) return false;
      for (var i = 0; i < blocks; i++) {
        if (offset >= frame.length || (frame[offset] & 0x0f) >= services) {
          return false;
        }
        offset += (frame[offset] & 0x80) == 0 ? 3 : 2;
      }
      return offset == frame.length;
    default:
      return false;
  }
}

const _cancelled = OctopusBalanceException('本次操作已取消。', code: 'cancelled');
const _discoveryTimedOut = '未检测到八达通 NFC-F 接口，请移开卡片后重新贴卡。';
const _nativeCodes = {
  'TRANSCEIVE_FAILED',
  'FELICA_NOT_CONNECTED',
  'STALE_SESSION',
  'NFC_STOPPED',
  'NFC_DISABLED',
  'NFC_UNAVAILABLE',
  'NFC_BUSY',
  'NFC_SCAN_FAILED',
  'NFC_DISCOVERY_TIMEOUT',
  'NFC_CLOSE_FAILED',
  'BAD_ARGUMENT',
};
const _protocolCodes = {
  'balance',
  'protocol',
  'invalid_response',
  'identity',
  'tag_mismatch',
  'command_policy',
  'unsupported',
  'cancelled',
  'CANCELLED',
  'timeout',
  'transport',
  'no_card',
  'NFC_TAG_LOST',
  'NFC_NOT_CONNECTED',
  'NFC_SESSION_CLOSED',
  'NFC_BUSY',
  'NFC_EXCHANGE_FAILED',
  'NFC_DISABLED',
  'NFC_UNAVAILABLE',
  'NFC_DISCOVERY_TIMEOUT',
};
const _nativeClasses = {
  'android.nfc.TagLostException',
  'java.io.IOException',
  'java.lang.IllegalStateException',
  'java.lang.IllegalArgumentException',
  'java.lang.SecurityException',
};

String? _nativeClass(PlatformException failure) {
  final details = failure.details;
  final value = details is Map ? details['exception'] : null;
  return value is String && _nativeClasses.contains(value) ? value : null;
}

String? _discoveryPhase(PlatformException failure) {
  if (failure.code != 'NFC_DISCOVERY_TIMEOUT') return null;
  final details = failure.details;
  final value = details is Map ? details['discoveryPhase'] : null;
  return value is String &&
          const {'waiting_for_tag', 'connecting'}.contains(value)
      ? value
      : null;
}

Map<String, Object?> _safeFailure(Object failure) => switch (failure) {
  PlatformException() => {
    'code': _nativeCodes.contains(failure.code) ? failure.code : 'NFC_OTHER',
    'exceptionClass': ?_nativeClass(failure),
    'discoveryPhase': ?_discoveryPhase(failure),
  },
  OctopusBalanceException() => {
    'code': _protocolCodes.contains(failure.code)
        ? failure.code
        : 'OCTOPUS_OTHER',
  },
  TimeoutException() => {'code': 'TIMEOUT'},
  _ => {'code': 'UNEXPECTED'},
};

String _failureCode(Object failure) => switch (failure) {
  PlatformException() => failure.code,
  OctopusBalanceException() => failure.code,
  TimeoutException() => 'timeout',
  _ => '',
};

String _failureMessage(Object failure, String code) {
  if (failure is PlatformException &&
      _nativeClass(failure) == 'android.nfc.TagLostException') {
    return '手机与八达通的 NFC 连接已丢失，请重新贴卡。';
  }
  if (failure is PlatformException &&
      _discoveryPhase(failure) == 'connecting') {
    return '连接八达通 NFC-F 接口超时，请移开卡片后重新贴卡。';
  }
  return switch (code) {
    'identity' || 'tag_mismatch' => '请贴上与本次读取相同的同一张八达通卡。',
    'protocol' || 'invalid_response' => '八达通返回的数据无效，请重新贴卡。',
    'unsupported' => '暂不支持读取这张八达通的余额。',
    'command_policy' => '已拦截非只读或无效的 NFC 请求，请停止后重新读取。',
    'cancelled' || 'CANCELLED' || 'NFC_STOPPED' => '本次操作已取消。',
    'timeout' => '读取超时，请保持卡片贴近手机后重试。',
    'NFC_DISCOVERY_TIMEOUT' => _discoveryTimedOut,
    'no_card' => '未检测到卡片，请重新贴卡。',
    'NFC_DISABLED' => '请先打开系统 NFC。',
    'NFC_UNAVAILABLE' => '当前设备不支持 NFC。',
    'STALE_SESSION' || 'NFC_SESSION_CLOSED' => '八达通 NFC 会话已结束，请重新开始读取。',
    'FELICA_NOT_CONNECTED' || 'NFC_NOT_CONNECTED' => '八达通 NFC-F 连接已断开，请重新贴卡。',
    'NFC_TAG_LOST' => '手机与八达通的 NFC 连接已丢失，请重新贴卡。',
    'NFC_BUSY' => '八达通 NFC 通信忙，请停止后重新读取。',
    'transport' ||
    'TRANSCEIVE_FAILED' ||
    'NFC_EXCHANGE_FAILED' => '八达通 NFC-F 通信失败，请重新贴卡。',
    _ => '八达通余额读取未完成，请重新贴卡后重试。',
  };
}
