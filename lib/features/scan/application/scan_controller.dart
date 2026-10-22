import 'dart:async';

import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../../platform/nfc/felica_channel.dart';
import '../../../platform/nfc/nfc_models.dart';
import '../../../platform/nfc/nfc_service.dart';
import '../../../platform/nfc/transport_failure_mapper.dart';
import '../../../protocols/transport/transport_failure.dart';
import '../domain/card_read_outcome.dart';
import '../domain/captured_frame.dart';
import 'card_read_coordinator.dart';
import '../../../shared/application/owned_notifier.dart';

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
  });
  final NfcChannel channel;
  final FelicaChannel felicaChannel;
  final CardReadCoordinator coordinator;
  final void Function(String) logEvent;
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
      tag = found;
      if (found == null) {
        phase = ScanPhase.complete;
        return;
      }
      for (final issue in found.metadataIssues) {
        _log(
          'NFC metadata [${issue.stage}] ${issue.exception}: ${issue.message ?? ""}',
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
          if (_current(id)) _log('== $stage ==');
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
      if (_terminalFailure != null) error = _terminalFailure.toString();
      phase = ScanPhase.processing;
      notifyListeners();
      await onCompleted?.call(result, id, found.timestamp, () => _current(id));
      if (!_current(id)) return;
      phase = error == null ? ScanPhase.complete : ScanPhase.failed;
      progress = 100;
    } on PlatformException catch (e) {
      if (_current(id) && e.code != 'NFC_STOPPED') {
        error = e.message ?? e.code;
        phase = ScanPhase.failed;
      }
    } catch (e) {
      if (_current(id)) {
        error = '$e';
        phase = ScanPhase.failed;
      }
    } finally {
      // Even a stale attempt closes only its own native handle.
      await _close(id);
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
      if (!_current(id)) throw PlatformException(code: 'STALE_SESSION');
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
      );
      return response;
    } catch (e, stack) {
      final failure = mapNfcFailure(e, stack);
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
        _log('!! $e');
      }
      throw failure; // Failure is never converted into an empty card response.
    }
  }

  void _log(String message) {
    _trace.add(message);
    // All frames remain available for the current read; persistent logging is
    // governed independently by SettingsController.
    logEvent(message);
  }

  void addDiagnostic(String message) => _log(message);

  Future<void> _close(String id) async {
    try {
      final native = channel;
      if (native is SessionNfcChannel) {
        await native.closeSession(id);
      } else if (_session == id) {
        await native.stopScan();
      }
    } catch (e) {
      if (!disposed &&
          (_session == id || (_session == null && _closing == id))) {
        releaseError = 'NFC 连接释放失败：$e';
        logEvent(releaseError!);
        notifyListeners();
      }
    }
  }

  Future<void> stop() async {
    final id = _session;
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
