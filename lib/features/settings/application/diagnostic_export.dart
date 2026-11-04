import 'dart:convert';

import '../../../shared/diagnostics/diagnostic_event.dart';
import '../../../shared/diagnostics/raw_data_category.dart';

/// A standard JSON document contains both event objects and untouched source.
/// Torn JSONL is escaped as a string so it cannot invalidate the export itself.
String buildFullDiagnostics(
  List<DiagnosticSession> sessions,
  DateTime exportedAt,
) {
  return _encodeExport('full', [
    for (final session in sessions)
      {
        'sessionId': session.id,
        'throughSequence': session.last?.sequence,
        'running': session.running,
        'incomplete': session.incomplete || session.legacy,
        'damaged': session.damaged,
        'legacy': session.legacy,
        'status': session.statusText,
        if (session.legacy)
          'legacyText': session.raw
        else ...{
          'cardInfo': session.cardInfo,
          'apduGroups': [
            for (final category in RawDataCategory.values)
              {
                'category': category.name,
                'label': category.label,
                'frames': [
                  for (final event in session.events)
                    if (event.type == 'physical_frame' &&
                        _frameCategory(event) == category)
                      _exportFrame(session, event),
                ],
              },
          ],
          'processRecords': [
            for (final category in ProcessDataCategory.values)
              {
                'category': category.name,
                'label': category.label,
                'records': [
                  for (final event in session.events)
                    if (event.type == 'process_record' &&
                        event.data['category'] == category.name)
                      {'eventSequence': event.sequence, ...event.data},
                ],
              },
          ],
          'events': _eventObjects(session).toList(),
          'rawJsonl': session.raw,
        },
      },
  ], exportedAt);
}

Map<String, Object?> _exportFrame(
  DiagnosticSession session,
  DiagnosticEvent frame,
) {
  final matches = session.events
      .where(
        (event) =>
            event.type == 'response_fields' &&
            event.data['index'] == frame.data['index'] &&
            jsonEncode(event.data['command']) ==
                jsonEncode(frame.data['command']) &&
            jsonEncode(event.data['raw']) == jsonEncode(frame.data['response']),
      )
      .toList();
  final frozen = matches.length == 1 ? matches.single.data : null;
  final raw = frame.data['response'];
  return {
    'eventSequence': frame.sequence,
    ...frame.data,
    'raw': raw,
    'response': frozen == null
        ? {
            'state': raw == null ? 'no_response' : 'not_captured',
            'parserId': null,
            'fields': null,
          }
        : {
            'state': frozen['state'],
            'parserId': frozen['parserId'],
            if (frozen.containsKey('statusWord'))
              'statusWord': frozen['statusWord'],
            'fields': frozen['fields'],
          },
  };
}

RawDataCategory _frameCategory(DiagnosticEvent event) {
  final name = event.data['category'];
  for (final category in RawDataCategory.values) {
    if (name == category.name) return category;
  }
  // Old diagnostic captures have no classification field. Derive only the
  // command coordinate at export; the original events and raw text stay intact.
  final bytes = event.data['command'];
  if (bytes is List && bytes.every((b) => b is int && b >= 0 && b <= 255)) {
    return classifyRawCommand(
      bytes.cast<int>(),
      felica: event.data['transport'] == 'nfc-f',
    ).category;
  }
  return RawDataCategory.other;
}

Iterable<Map<String, dynamic>> _eventObjects(DiagnosticSession session) sync* {
  for (final line in const LineSplitter().convert(session.raw)) {
    if (line.isEmpty) continue;
    try {
      if (DiagnosticEvent.decode(line).sessionId == session.id) {
        // Preserve original UTC offsets and unknown fields in valid events.
        final original = jsonDecode(line) as Map<String, dynamic>;
        if (original['type'] == 'physical_frame') {
          final event = DiagnosticEvent.decode(line);
          original['data'] = _exportFrame(session, event)
            ..remove('eventSequence');
        }
        yield original;
      }
    } catch (_) {
      // The complete original, including malformed lines, remains in rawJsonl.
    }
  }
}

String _encodeExport(
  String kind,
  List<Map<String, Object?>> sessions,
  DateTime exportedAt,
) =>
    '${_encodeReadableJson({'format': 'trafarch.diagnostic_export', 'version': 3, 'appName': 'TrafArch', 'kind': kind, 'exportedAt': exportedAt.toUtc().toIso8601String(), 'sessions': sessions})}\n';

/// Preserve byte arrays as JSON arrays, but keep command/response/raw on one
/// physical line. Encoding values directly avoids rewriting text inside strings.
String _encodeReadableJson(Object? value, [int depth = 0, String? key]) {
  if ((key == 'command' || key == 'response' || key == 'raw') ||
      value is! Map && value is! List) {
    return jsonEncode(value);
  }
  final indent = '  ' * depth;
  final next = '  ' * (depth + 1);
  if (value is Map) {
    if (value.isEmpty) return '{}';
    return '{\n${value.entries.map((entry) => '$next${jsonEncode(entry.key)}: ${_encodeReadableJson(entry.value, depth + 1, entry.key as String)}').join(',\n')}\n$indent}';
  }
  final list = value as List;
  if (list.isEmpty) return '[]';
  return '[\n${list.map((item) => '$next${_encodeReadableJson(item, depth + 1)}').join(',\n')}\n$indent]';
}
