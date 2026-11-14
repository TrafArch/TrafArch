import 'dart:async';

import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../../platform/nfc/felica_channel.dart';
import '../../../platform/nfc/nfc_models.dart';
import '../../../platform/nfc/nfc_service.dart';
import '../../../platform/nfc/transport_failure_mapper.dart';
import '../../../protocols/bank/domain/models/bank_card_result.dart';
import '../../../protocols/transport/transport_failure.dart';
import '../domain/card_read_outcome.dart';
import '../domain/captured_frame.dart';
import 'card_read_coordinator.dart';
import '../../../shared/application/owned_notifier.dart';
import '../../../shared/diagnostics/diagnostic_event.dart';
import '../../../shared/diagnostics/raw_data_category.dart';
import 'card_diagnostic_capture.dart';
import 'parser_diagnostic_capture.dart';
import 'response_diagnostic_capture.dart';

enum ScanPhase {
  idle,
  waiting,
  reading,
  processing,
  complete,
  failed,
  cancelled,
}

/// Single owner of acquisition, generation checks and native session teardown.
class ScanController extends OwnedNotifier {
  ScanController({
    required this.channel,
    required this.felicaChannel,
    required this.coordinator,
    required this.logEvent,
    this.diagnostics,
  });
  final NfcChannel channel;
  final FelicaChannel felicaChannel;
  final CardReadCoordinator coordinator;
  final void Function(String) logEvent;
  final DiagnosticRecorder? diagnostics;
  final _recordings = <String, _ScanRecording>{};
  Future<void> Function(CardReadOutcome, String, DateTime, bool Function())?
  onCompleted;
  void Function()? onStarted;
  ScanPhase phase = ScanPhase.idle;
  String? _session;
  NfcScanResult? tag;
  CardReadOutcome? outcome;
  String? error;
  String? releaseError;
  String? _closing;
  TransportFailure? _terminalFailure;
  int? progress;
  bool autoScanConsumed = false;
  bool get scanning => phase == ScanPhase.waiting || parsing;
  bool get parsing =>
      phase == ScanPhase.reading || phase == ScanPhase.processing;
  final List<String> _trace = [];
  final List<CapturedFrame> _frames = [];
  List<CapturedFrame> get frames => List.unmodifiable(_frames);
  List<String> get trace => List.unmodifiable(_trace);

  bool _current(String id) => !disposed && _session == id;

  Future<void> scanOnce() async {
    if (disposed || scanning) return;
    final id = const Uuid().v4();
    final recording = _ScanRecording(diagnostics?.startSession(id));
    recording.started = recording.sink?.recording == true;
    _recordings[id] = recording;
    final attemptDone = Completer<void>();
    recording.done = attemptDone;
    recording.sink?.event('scan_waiting', phase: DiagnosticPhase.waiting);
    _session = id;
    phase = ScanPhase.waiting;
    error = null;
    releaseError = null;
    _terminalFailure = null;
    progress = null;
    tag = null;
    outcome = null;
    _trace.clear();
    _frames.clear();
    onStarted?.call();
    notifyListeners();
    try {
      final native = channel;
      final found = native is SessionNfcChannel
          ? await native.scanSession(id)
          : await native.scanOnce();
      if (!_current(id)) return;
      if (found?.sessionId != null && found!.sessionId != id) {
        throw const TransportFailure(
          kind: TransportFailureKind.staleSession,
          code: 'STALE_SESSION',
          message: '原生返回了不属于当前读取的标签',
        );
      }
      // Waiting for discovery does not yet consume any card data. A logging
      // switch enabled during that wait must apply to this first card too.
      refreshWaitingDiagnostics();
      tag = found;
      if (found == null) {
        recording.result = DiagnosticOutcome.noCard;
        phase = ScanPhase.complete;
        return;
      }
      recording.sink?.event(
        'tag_discovered',
        phase: DiagnosticPhase.reading,
        data: {
          'isoDepConnected': found.isoDepConnected,
          'felicaConnected': found.felicaConnected,
          'technologies': found.technologies,
        },
      );
      for (final issue in found.metadataIssues) {
        _log(
          'NFC metadata [${issue.stage}] ${issue.exception}: ${issue.message ?? ""}',
          persist: false,
        );
        recording.sink?.event(
          'metadata_issue',
          level: DiagnosticSeverity.warning,
          phase: DiagnosticPhase.reading,
          data: {
            'stage': issue.stage,
            'exception': issue.exception,
            'message': issue.message,
          },
        );
      }
      autoScanConsumed = true;
      phase = ScanPhase.reading;
      notifyListeners();
      final result = await coordinator.read(
        found,
        apdu: (bytes) => _exchange(id, bytes, false),
        felica: (bytes) => _exchange(id, bytes, true),
        onStage: (stage) {
          if (_current(id)) {
            recording.stage = stage;
            _log('== $stage ==', persist: false);
            recording.sink?.event(
              'protocol_stage',
              phase: DiagnosticPhase.reading,
              data: {'name': stage},
            );
          }
        },
        onProgress: (value) {
          if (!_current(id) || !parsing) return;
          if (progress != null && value <= progress!) return;
          progress = value.clamp(0, 100);
          notifyListeners();
        },
      );
      if (!_current(id)) return;
      outcome = result;
      for (final decoded in captureResponseFields(result, recording.frames)) {
        recording.sink?.event(
          'response_fields',
          phase: DiagnosticPhase.processing,
          data: decoded,
        );
      }
      recording.sink?.event(
        'card_info',
        phase: DiagnosticPhase.processing,
        data: captureCardInfo(result),
      );
      if (recording.sink?.recording == true) {
        try {
          for (final record in captureParserRecords(result)) {
            recording.sink?.event(
              'parser_record',
              phase: DiagnosticPhase.processing,
              data: record,
            );
          }
        } catch (_) {
          recording.sink?.event(
            'capture_gap',
            level: DiagnosticSeverity.warning,
            data: {'reason': 'parser_fields_unavailable'},
          );
        }
      }
      if (result case TransitReadOutcome(:final card)) {
        for (final record in captureProcessRecords(card)) {
          recording.sink?.event(
            'process_record',
            phase: DiagnosticPhase.processing,
            data: record,
          );
        }
      }
      recording.result = switch (result) {
        UnsupportedReadOutcome() => DiagnosticOutcome.unsupported,
        BankReadOutcome(
          card: BankCardResult(status: BankCardStatus.enumerationFailed),
        ) =>
          DiagnosticOutcome.partial,
        _ => DiagnosticOutcome.success,
      };
      recording.sink?.event(
        'read_result',
        phase: DiagnosticPhase.processing,
        data: {
          'family': switch (result) {
            TransitReadOutcome() => 'transit',
            BankReadOutcome() => 'bank',
            FelicaReadOutcome() => 'felica',
            UnsupportedReadOutcome() => 'unsupported',
          },
          'frames': recording.frameCount,
        },
      );
      if (_terminalFailure != null) error = _terminalFailure.toString();
      phase = ScanPhase.processing;
      notifyListeners();
      await onCompleted?.call(result, id, found.timestamp, () => _current(id));
      if (!_current(id)) return;
      phase = error == null ? ScanPhase.complete : ScanPhase.failed;
      progress = 100;
    } on PlatformException catch (e) {
      recording.failure(e.code, '$e', details: e.details);
      if (e.code == 'NFC_STOPPED') recording.cancelled = true;
      if (_current(id) && e.code != 'NFC_STOPPED') {
        error = e.message ?? e.code;
        phase = ScanPhase.failed;
      }
    } catch (e) {
      recording.failure(
        e is TransportFailure ? e.code ?? e.kind.name : 'SCAN_FAILED',
        '$e',
      );
      if (_current(id)) {
        error = '$e';
        phase = ScanPhase.failed;
      }
    } finally {
      // Even a stale attempt closes only its own native handle.
      await _close(id);
      recording.finish();
      _recordings.remove(id);
      attemptDone.complete();
      if (_current(id)) {
        if (scanning) {
          phase = error == null ? ScanPhase.complete : ScanPhase.failed;
        }
        notifyListeners();
      }
    }
  }

  Future<List<int>> _exchange(String id, List<int> bytes, bool isFelica) async {
    if (!_current(id)) {
      throw const TransportFailure(
        kind: TransportFailureKind.staleSession,
        code: 'STALE_SESSION',
        message: '读取会话已失效',
      );
    }
    final failure = _terminalFailure;
    if (failure != null && failure.stopsSession) throw failure;
    final at = DateTime.now();
    final clock = Stopwatch()..start();
    final recording = _recordings[id];
    final frameIndex = recording?.frameCount ?? _frames.length;
    final coordinates = classifyRawCommand(bytes, felica: isFelica);
    final context = <String, Object?>{
      'category': coordinates.category.name,
      'categoryLabel': coordinates.category.label,
      'sfi': coordinates.sfi,
      'recordNumber': coordinates.recordNumber,
      'protocolStage': recording?.stage,
      'selectedApplication': recording?.selectedApplication,
    };
    var recorded = false;
    recording?.sink?.event(
      'exchange_started',
      phase: DiagnosticPhase.reading,
      data: {
        'index': frameIndex,
        'transport': isFelica ? 'nfc-f' : 'iso-dep',
        'command': bytes,
        ...context,
      },
    );
    try {
      final nfc = channel;
      final nfcF = felicaChannel;
      final response = isFelica
          ? (nfcF is SessionFelicaChannel
                ? await nfcF.exchangeSession(id, bytes)
                : await nfcF.transceive(bytes))
          : (nfc is SessionNfcChannel
                ? await nfc.exchangeSession(id, bytes)
                : await nfc.transceive(bytes));
      // A delivered response is evidence for its captured attempt even if UI
      // publication was cancelled while the physical exchange was pending.
      recording?.frame(
        bytes,
        response,
        isFelica,
        frameIndex,
        at,
        clock.elapsedMicroseconds,
        context: context,
      );
      if (!isFelica &&
          bytes.length >= 5 &&
          bytes[1] == 0xA4 &&
          bytes[2] == 4 &&
          bytes[4] > 0 &&
          bytes.length >= 5 + bytes[4] &&
          response.length >= 2 &&
          response[response.length - 2] == 0x90 &&
          response.last == 0) {
        recording?.selectedApplication = _hex(bytes.sublist(5, 5 + bytes[4]));
      }
      if (!isFelica &&
          bytes.length >= 7 &&
          bytes[1] == 0xA4 &&
          bytes[2] == 0 &&
          bytes[4] == 2 &&
          bytes[5] == 0x3F &&
          bytes[6] == 0 &&
          response.length >= 2 &&
          response[response.length - 2] == 0x90 &&
          response.last == 0) {
        recording?.selectedApplication = null;
      }
      recorded = true;
      if (!_current(id)) {
        recording?.sink?.event(
          'late_response_ignored',
          data: {'index': frameIndex},
        );
        throw PlatformException(code: 'STALE_SESSION');
      }
      _frames.add(
        CapturedFrame(
          sessionId: id,
          index: _frames.length,
          transport: isFelica ? 'nfc-f' : 'iso-dep',
          capturedAt: at,
          command: bytes,
          response: response,
        ),
      );
      _log(
        '>> ${isFelica ? 'FeliCa ' : ''}${_hex(bytes)}\n<< ${_hex(response)}',
        persist: false,
      );
      return response;
    } catch (e, stack) {
      final failure = mapNfcFailure(e, stack);
      // Keep this attempt's failed command even after cancellation/replacement.
      if (!recorded) {
        recording?.frame(
          bytes,
          null,
          isFelica,
          frameIndex,
          at,
          clock.elapsedMicroseconds,
          failure: failure,
          context: context,
        );
      }
      if (_current(id)) {
        if (failure.stopsSession) _terminalFailure = failure;
        _frames.add(
          CapturedFrame(
            sessionId: id,
            index: _frames.length,
            transport: isFelica ? 'nfc-f' : 'iso-dep',
            capturedAt: at,
            command: bytes,
            error: '$e',
            errorCode: e is PlatformException ? e.code : null,
          ),
        );
        _log(
          '>> ${isFelica ? 'FeliCa ' : ''}${_hex(bytes)}\n!! $e',
          persist: false,
        );
      }
      throw failure; // Failure is never converted into an empty card response.
    }
  }

  void _log(String message, {bool persist = true}) {
    _trace.add(message);
    if (!persist && diagnostics == null) {
      logEvent(message);
    }
    // All frames remain available for the current read; persistent logging is
    // governed independently by SettingsController.
    if (persist) {
      final sink = _recordings[_session]?.sink;
      if (sink != null) {
        sink.event(
          'message',
          phase: DiagnosticPhase.processing,
          data: {'message': message},
        );
      } else {
        logEvent(message);
      }
    }
  }

  void addDiagnostic(String message) => _log(message);

  void refreshWaitingDiagnostics() {
    final id = _session;
    final recording = _recordings[id];
    if (disposed ||
        phase != ScanPhase.waiting ||
        id == null ||
        recording == null ||
        recording.started) {
      return;
    }
    final sink = diagnostics?.startSession(id);
    if (sink?.recording != true) return;
    recording.sink = sink;
    recording.started = true;
    sink!.event(
      'scan_waiting',
      phase: DiagnosticPhase.waiting,
      data: {'loggingEnabledWhileWaiting': true},
    );
  }

  void addStructuredDiagnostic(
    String id,
    String type,
    Map<String, Object?> data,
  ) {
    if (!_current(id)) return;
    _recordings[id]?.sink?.event(
      type,
      phase: DiagnosticPhase.processing,
      data: data,
    );
  }

  /// Shutdown joins accepted acquisition before closing its diagnostic writer.
  Future<void> finishPending() async {
    await Future.wait([
      for (final recording in _recordings.values)
        if (recording.done != null) recording.done!.future,
    ]);
  }

  Future<void> _close(String id) async {
    final recording = _recordings[id];
    recording?.closing();
    try {
      final native = channel;
      if (native is SessionNfcChannel) {
        await native.closeSession(id);
      } else if (_session == id) {
        await native.stopScan();
      }
      recording?.closed();
    } catch (e) {
      recording?.closed(error: e);
      if (!disposed &&
          (_session == id || (_session == null && _closing == id))) {
        releaseError = 'NFC 连接释放失败：$e';
        if (recording?.sink == null) logEvent(releaseError!);
        notifyListeners();
      }
    }
  }

  Future<void> stop() async {
    final id = _session;
    if (id != null) {
      _recordings[id]?.cancelled = true;
      _recordings[id]?.sink?.event(
        'scan_cancelled',
        phase: DiagnosticPhase.closing,
      );
    }
    _closing = id;
    _session = null;
    phase = ScanPhase.cancelled;
    progress = null;
    error = null;
    notifyListeners();
    if (id != null) {
      if (channel is SessionNfcChannel) {
        await _close(id);
      } else {
        try {
          await channel.stopScan();
        } catch (e) {
          if (!disposed && _session == null && _closing == id) {
            releaseError = 'NFC 连接释放失败：$e';
            logEvent(releaseError!);
            _recordings[id]?.closed(error: e);
            notifyListeners();
          }
        }
      }
    }
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }

  static String _hex(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');
}

class _ScanRecording {
  _ScanRecording(this.sink);
  DiagnosticSessionSink? sink;
  bool started = false;
  Completer<void>? done;
  DiagnosticOutcome result = DiagnosticOutcome.failed;
  int frameCount = 0;
  int successfulFrames = 0;
  bool cancelled = false;
  bool failed = false;
  bool closeFailed = false;
  bool _closing = false;
  bool _closed = false;
  String? stage;
  String? selectedApplication;
  final frames = <Map<String, Object?>>[];

  void frame(
    List<int> command,
    List<int>? response,
    bool felica,
    int index,
    DateTime at,
    int elapsedMicros, {
    TransportFailure? failure,
    Map<String, Object?> context = const {},
  }) {
    frameCount++;
    if (response != null) successfulFrames++;
    if (failure != null) failed = true;
    frames.add({
      'index': index,
      ...context,
      'command': List<int>.of(command),
      'response': response == null ? null : List<int>.of(response),
      'transport': felica ? 'nfc-f' : 'iso-dep',
    });
    sink?.event(
      'physical_frame',
      level: failure == null
          ? DiagnosticSeverity.info
          : DiagnosticSeverity.error,
      phase: DiagnosticPhase.reading,
      data: {
        'index': index,
        ...context,
        'transport': felica ? 'nfc-f' : 'iso-dep',
        'capturedAt': at.toUtc().toIso8601String(),
        'command': command,
        'response': response,
        'durationMicros': elapsedMicros,
        'commandLength': command.length,
        'responseLength': response?.length,
        if (!felica && response != null && response.length >= 2)
          'statusWord': (response[response.length - 2] << 8) | response.last,
        if (failure != null) ...{
          'errorCode': failure.code,
          'failureKind': failure.kind.name,
          'error': failure.message,
          if (failure.details != null) 'errorDetails': failure.details,
        },
      },
    );
  }

  void failure(String code, String error, {Object? details}) {
    failed = true;
    sink?.event(
      'scan_error',
      level: DiagnosticSeverity.error,
      data: {'errorCode': code, 'error': error, 'errorDetails': ?details},
    );
  }

  void closing() {
    if (_closing) return;
    _closing = true;
    sink?.event('close_started', phase: DiagnosticPhase.closing);
  }

  void closed({Object? error}) {
    if (_closed) return;
    _closed = true;
    closeFailed = error != null;
    sink?.event(
      'close_result',
      phase: DiagnosticPhase.closing,
      level: error == null ? DiagnosticSeverity.info : DiagnosticSeverity.error,
      data: {
        'success': error == null,
        if (error != null)
          'errorCode': error is PlatformException
              ? error.code
              : 'NFC_CLOSE_FAILED',
        if (error != null) 'error': '$error',
        if (error is PlatformException && error.details != null)
          'errorDetails': error.details,
      },
    );
  }

  void finish() {
    sink?.end(
      cancelled
          ? DiagnosticOutcome.cancelled
          : (failed || closeFailed)
          ? successfulFrames > 0
                ? DiagnosticOutcome.partial
                : DiagnosticOutcome.failed
          : result,
    );
  }
}
