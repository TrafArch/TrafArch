import 'dart:async';
import 'dart:convert';

import '../../shared/application/owned_notifier.dart';
import '../../shared/diagnostics/diagnostic_event.dart';
import 'diagnostic_log_store.dart';

export 'diagnostic_log_store.dart';

/// Bounded, serial, batched local diagnostics. Logging never fails card I/O.
class AppLogger extends OwnedNotifier implements DiagnosticRecorder {
  AppLogger({
    LogStore? store,
    this.appVersion = 'unknown',
    this.buildNumber = 'unknown',
    this.maxBytes = 20 * 1024 * 1024,
    this.maxSessions = 30,
    this.maxAge = const Duration(days: 7),
    this.maxQueueBytes = 1024 * 1024,
    this.maxSessionBytes = 8 * 1024 * 1024,
    DateTime Function()? now,
  }) : _store = store ?? FileLogStore(),
       _now = now ?? DateTime.now;
  final LogStore _store;
  final String appVersion;
  final String buildNumber;
  final int maxBytes;
  final int maxSessions;
  final Duration maxAge;
  final int maxQueueBytes;
  final int maxSessionBytes;
  final DateTime Function() _now;
  final _active = <String, _SessionSink>{};
  final _incomplete = <String>{};
  final _pending = <(String, String, int)>[];
  final _writesBySession = <String, int>{};
  int _queuedBytes = 0;
  int _bufferBytes = 0;
  Timer? _timer;
  Future<void> _chain = Future.value();
  bool _enabled = false;
  bool _accepting = true;
  String? _storageIssue;
  String? get storageIssue => _storageIssue;
  bool get enabled => _enabled;
  set enabled(bool value) {
    if (_enabled == value || !_accepting) return;
    if (!value) {
      for (final sink in _active.values.toList()) {
        sink.end(DiagnosticOutcome.recordingStopped);
      }
      unawaited(flush());
    }
    _enabled = value;
  }

  @override
  DiagnosticSessionSink startSession(
    String id, {
    DiagnosticSessionKind kind = DiagnosticSessionKind.scan,
  }) {
    if (!enabled || !_accepting || kind == DiagnosticSessionKind.application) {
      return const _SilentSink();
    }
    final existing = _active[id];
    if (existing != null) return existing;
    final sink = _SessionSink(this, id);
    _active[id] = sink;
    sink.event(
      'session_start',
      data: {
        'kind': kind.name,
        'appVersion': appVersion,
        'buildNumber': buildNumber,
      },
    );
    return sink;
  }

  void _issue(String message, [String? id]) {
    if (id != null) _incomplete.add(id);
    if (_storageIssue == message) return;
    _storageIssue = message;
    notifyListeners();
  }

  void _append(
    _SessionSink sink,
    DiagnosticEvent event, {
    bool control = false,
  }) {
    try {
      final line = '${jsonEncode(event.toJson())}\n';
      final bytes = utf8.encode(line).length;
      if ((!control && _queuedBytes + bytes > maxQueueBytes) ||
          (!control && sink.bytes + bytes > maxSessionBytes) ||
          (control && _queuedBytes + bytes > maxQueueBytes + 16384)) {
        sink.dropped++;
        _issue('日志未完整保存：记录量超过上限。', sink.id);
        return;
      }
      sink.bytes += bytes;
      _queuedBytes += bytes;
      _bufferBytes += bytes;
      _pending.add((sink.id, line, bytes));
      _writesBySession.update(sink.id, (count) => count + 1, ifAbsent: () => 1);
      if (_bufferBytes >= 32 * 1024 ||
          control ||
          event.level == DiagnosticSeverity.error) {
        _drain();
      } else {
        _timer ??= Timer(const Duration(milliseconds: 200), _drain);
      }
    } catch (_) {
      sink.dropped++;
      _issue('日志未完整保存：记录无法编码。', sink.id);
    }
  }

  void _drain() {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) return;
    final batch = List.of(_pending);
    _pending.clear();
    _bufferBytes = 0;
    _chain = _chain.then((_) async {
      final grouped = <String, StringBuffer>{};
      for (final (id, line, _) in batch) {
        (grouped[id] ??= StringBuffer()).write(line);
      }
      try {
        for (final entry in grouped.entries) {
          try {
            await _store.append(entry.key, entry.value.toString());
          } catch (_) {
            _issue('日志未完整保存：文件写入失败，请检查可用空间。', entry.key);
          }
        }
      } finally {
        for (final (id, _, bytes) in batch) {
          _queuedBytes -= bytes;
          final remaining = _writesBySession[id]! - 1;
          if (remaining == 0) {
            _writesBySession.remove(id);
          } else {
            _writesBySession[id] = remaining;
          }
        }
      }
    });
  }

  Future<void> flush() {
    _drain();
    return _chain;
  }

  /// Reads follow the accepted prefix and precede subsequently queued writes.
  Future<T> _readBarrier<T>(Future<T> Function() read) {
    _drain();
    final result = _chain.then((_) => read());
    _chain = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {
        _issue('日志读取或清理失败，请稍后重试。');
      },
    );
    return result;
  }

  Future<List<DiagnosticSession>> readSessions({Set<String>? ids}) {
    final active = _active.keys.toSet();
    final selectedIds = ids == null ? null : Set<String>.of(ids);
    return _readBarrier(() async {
      final sessions = <DiagnosticSession>[];
      for (final entry in await _store.entries()) {
        if (selectedIds != null && !selectedIds.contains(entry.id)) continue;
        sessions.add(
          DiagnosticSession.parse(
            entry.id,
            await _store.read(entry.id),
            running: active.contains(entry.id),
            storageIncomplete: _incomplete.contains(entry.id),
          ),
        );
      }
      // A failed first write may leave no file at all. Keep that loss visible
      // during this process instead of presenting it as an empty log history.
      for (final id in _incomplete) {
        if ((selectedIds == null || selectedIds.contains(id)) &&
            !sessions.any((session) => session.id == id)) {
          sessions.add(
            DiagnosticSession.parse(
              id,
              '',
              running: active.contains(id),
              storageIncomplete: true,
            ),
          );
        }
      }
      if (selectedIds == null || selectedIds.contains('legacy')) {
        final legacy = await _store.readLegacy();
        if (legacy != null && legacy.isNotEmpty) {
          sessions.add(
            DiagnosticSession(
              id: 'legacy',
              raw: legacy,
              events: const [],
              bytes: utf8.encode(legacy).length,
              legacy: true,
            ),
          );
        }
      }
      sessions.sort(
        (a, b) => (b.startedAt ?? DateTime(1970)).compareTo(
          a.startedAt ?? DateTime(1970),
        ),
      );
      return List.unmodifiable(sessions);
    });
  }

  Future<void> prune() => _readBarrier(() async {
    final entries = await _store.entries();
    entries.sort((a, b) => a.modifiedAt.compareTo(b.modifiedAt));
    var bytes = entries.fold<int>(0, (sum, e) => sum + e.bytes);
    var count = entries.length;
    for (final entry in entries) {
      if (_active.containsKey(entry.id) ||
          _writesBySession.containsKey(entry.id)) {
        continue;
      }
      if (bytes <= maxBytes &&
          count <= maxSessions &&
          _now().difference(entry.modifiedAt) <= maxAge) {
        continue;
      }
      await _store.delete(entry.id);
      _incomplete.remove(entry.id);
      bytes -= entry.bytes;
      count--;
    }
  });

  Future<void> deleteSessions(Set<String> ids) {
    final selected = Set<String>.of(ids);
    return _readBarrier(() async {
      if (selected.any(
        (id) => _active.containsKey(id) || _writesBySession.containsKey(id),
      )) {
        throw StateError('Session is still recording');
      }
      for (final id in selected) {
        if (id == 'legacy') {
          await _store.deleteLegacy();
        } else {
          await _store.delete(id);
        }
        _incomplete.remove(id);
      }
    });
  }

  Future<String> readAll() async =>
      (await readSessions()).map((session) => session.raw).join();
  Future<void> close() async {
    enabled = false;
    _accepting = false;
    await flush();
    super.dispose();
  }

  /// 时间戳格式：yyyy-MM-dd HH:mm:ss.SSS。
  static String formatTimestamp(DateTime t) {
    String pad2(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${pad2(t.month)}-${pad2(t.day)} '
        '${pad2(t.hour)}:${pad2(t.minute)}:${pad2(t.second)}'
        '.${t.millisecond.toString().padLeft(3, '0')}';
  }
}

class _SessionSink implements DiagnosticSessionSink {
  _SessionSink(this.owner, this.id);
  final AppLogger owner;
  final String id;
  final _clock = Stopwatch()..start();
  int sequence = 0;
  int bytes = 0;
  int dropped = 0;
  bool ended = false;
  @override
  bool get recording => !ended && owner.enabled;
  @override
  void event(
    String type, {
    DiagnosticSeverity level = DiagnosticSeverity.info,
    DiagnosticPhase? phase,
    Map<String, Object?> data = const {},
  }) {
    if (ended || !owner.enabled) return;
    owner._append(
      this,
      DiagnosticEvent(
        sessionId: id,
        sequence: sequence++,
        at: owner._now(),
        elapsedMicros: _clock.elapsedMicroseconds,
        type: type,
        level: level,
        phase: phase,
        data: data,
      ),
      control: type == 'session_end' || type == 'capture_gap',
    );
  }

  @override
  void end(DiagnosticOutcome outcome) {
    if (ended) return;
    if (dropped > 0 || owner._incomplete.contains(id)) {
      event(
        'capture_gap',
        level: DiagnosticSeverity.warning,
        data: {'droppedEvents': dropped},
      );
    }
    event('session_end', data: {'outcome': outcome.name});
    ended = true;
    _clock.stop();
    owner._active.remove(id);
    unawaited(owner.prune().catchError((Object _) {}));
  }
}

class _SilentSink implements DiagnosticSessionSink {
  const _SilentSink();
  @override
  bool get recording => false;
  @override
  void event(
    String type, {
    DiagnosticSeverity level = DiagnosticSeverity.info,
    DiagnosticPhase? phase,
    Map<String, Object?> data = const {},
  }) {}
  @override
  void end(DiagnosticOutcome outcome) {}
}
