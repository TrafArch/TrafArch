import 'dart:convert';

enum DiagnosticSessionKind { scan, application, qr }

enum DiagnosticSeverity { info, warning, error }

enum DiagnosticPhase { waiting, reading, processing, closing, application }

enum DiagnosticOutcome {
  success,
  partial,
  failed,
  cancelled,
  unsupported,
  noCard,
  recordingStopped,
}

/// Acquisition supplies events; only the injected implementation owns storage.
abstract interface class DiagnosticRecorder {
  DiagnosticSessionSink startSession(
    String id, {
    DiagnosticSessionKind kind = DiagnosticSessionKind.scan,
  });
}

abstract interface class DiagnosticSessionSink {
  bool get recording;
  void event(
    String type, {
    DiagnosticSeverity level = DiagnosticSeverity.info,
    DiagnosticPhase? phase,
    Map<String, Object?> data = const {},
  });
  void end(DiagnosticOutcome outcome);
}

class DiagnosticEvent {
  const DiagnosticEvent({
    required this.sessionId,
    required this.sequence,
    required this.at,
    required this.elapsedMicros,
    required this.type,
    required this.level,
    this.phase,
    this.data = const {},
  });
  final String sessionId;
  final int sequence;
  final DateTime at;
  final int elapsedMicros;
  final String type;
  final DiagnosticSeverity level;
  final DiagnosticPhase? phase;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => {
    'format': 'trafarch.diagnostics',
    'version': 1,
    'sessionId': sessionId,
    'sequence': sequence,
    'at': at.toUtc().toIso8601String(),
    'utcOffsetMinutes': at.timeZoneOffset.inMinutes,
    'elapsedMicros': elapsedMicros,
    'type': type,
    'level': level.name,
    if (phase != null) 'phase': phase!.name,
    'data': data,
  };

  static DiagnosticEvent decode(String line) {
    final value = jsonDecode(line);
    if (value is! Map<String, dynamic> ||
        value['format'] != 'trafarch.diagnostics' ||
        value['version'] != 1 ||
        value['sessionId'] is! String ||
        value['sequence'] is! int ||
        (value['sequence'] as int) < 0 ||
        value['elapsedMicros'] is! int ||
        value['at'] is! String ||
        value['type'] is! String ||
        value['data'] is! Map<String, dynamic>) {
      throw const FormatException('Invalid diagnostic event');
    }
    return DiagnosticEvent(
      sessionId: value['sessionId'] as String,
      sequence: value['sequence'] as int,
      at: DateTime.parse(value['at'] as String),
      elapsedMicros: value['elapsedMicros'] as int,
      type: value['type'] as String,
      level: DiagnosticSeverity.values.byName(value['level'] as String),
      phase: value['phase'] == null
          ? null
          : DiagnosticPhase.values.byName(value['phase'] as String),
      data: Map.unmodifiable(value['data'] as Map<String, dynamic>),
    );
  }
}

/// A frozen export boundary. Raw lines are retained separately from projections.
class DiagnosticSession {
  DiagnosticSession({
    required this.id,
    required this.raw,
    required this.events,
    required this.bytes,
    this.running = false,
    this.damaged = false,
    this.legacy = false,
    this.storageIncomplete = false,
  });
  final String id;
  final String raw;
  final List<DiagnosticEvent> events;
  final int bytes;
  final bool running;
  final bool damaged;
  final bool legacy;
  final bool storageIncomplete;
  DiagnosticEvent? get first => events.isEmpty ? null : events.first;
  DiagnosticEvent? get last => events.isEmpty ? null : events.last;
  DateTime? get startedAt => first?.at;
  bool get isScan => first?.data['kind'] == 'scan';
  bool get isQr => first?.data['kind'] == 'qr';
  Map<String, Object?>? get cardInfo {
    for (final event in events.reversed) {
      if (event.type == 'card_info') return event.data;
    }
    return null;
  }

  String? get outcome {
    final value = last?.type == 'session_end' ? last?.data['outcome'] : null;
    return value is String &&
            DiagnosticOutcome.values.any((o) => o.name == value)
        ? value
        : null;
  }

  bool get incomplete =>
      damaged ||
      storageIncomplete ||
      first?.type != 'session_start' ||
      (outcome == null && !running) ||
      outcome == 'recordingStopped' ||
      events.any((e) => e.type == 'capture_gap');

  String get statusText {
    if (legacy) return '旧版文本；无法核实会话完整性';
    if (incomplete) return running ? '记录中，部分日志未完整保存' : '日志未完整记录';
    if (running) return '记录中，尚未结束';
    if (isQr) return outcome == 'success' ? '二维码解析完成' : '二维码解析失败';
    if (!isScan && outcome == 'success') return '应用记录已结束';
    return switch (outcome) {
      'success' => '读取完成',
      'partial' => '部分读取',
      'failed' => '读取失败',
      'cancelled' => '已取消',
      'unsupported' => '暂不支持此卡',
      'noCard' => '未发现卡片',
      _ => '未正常结束',
    };
  }

  static DiagnosticSession parse(
    String id,
    String raw, {
    bool running = false,
    bool storageIncomplete = false,
  }) {
    final events = <DiagnosticEvent>[];
    var damaged = raw.isNotEmpty && !raw.endsWith('\n');
    var expected = 0;
    // A torn last line never discards its intact prefix.
    for (final line in const LineSplitter().convert(raw)) {
      if (line.isEmpty) continue;
      try {
        final event = DiagnosticEvent.decode(line);
        if (event.sessionId != id) {
          damaged = true;
          continue;
        }
        if (event.sequence != expected) damaged = true;
        expected = event.sequence + 1;
        events.add(event);
      } catch (_) {
        damaged = true;
      }
    }
    return DiagnosticSession(
      id: id,
      raw: raw,
      events: List.unmodifiable(events),
      bytes: utf8.encode(raw).length,
      running: running,
      damaged: damaged,
      storageIncomplete: storageIncomplete,
    );
  }
}
