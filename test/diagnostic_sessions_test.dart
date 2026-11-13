import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/settings/application/diagnostic_export.dart';
import 'package:transit_card_analyzer/features/settings/application/diagnostics_controller.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/log_exporter.dart';
import 'package:transit_card_analyzer/shared/diagnostics/diagnostic_event.dart';

void main() {
  test('command、response和raw数组单行写入，空响应和失败保持区分且不改原文', () async {
    final logger = AppLogger(store: MemoryLogStore())..enabled = true;
    addTearDown(logger.close);
    final sink = logger.startSession('inline');
    for (final response in [List<int>.generate(256, (i) => i), <int>[], null]) {
      sink.event(
        'physical_frame',
        data: {
          'command': [0, 0xB2, 1, 0xF4, 0],
          'response': response,
          'raw': List<int>.generate(48, (i) => i),
          'note': 'literal "command": [\nquoted text',
        },
      );
    }
    sink.end(DiagnosticOutcome.success);
    final session = (await logger.readSessions()).single;
    final text = buildFullDiagnostics([session], DateTime.utc(2026));
    expect(RegExp(r'"command":\s*\[\s*\n').hasMatch(text), isFalse);
    expect(RegExp(r'"response":\s*\[\s*\n').hasMatch(text), isFalse);
    expect(RegExp(r'"raw":\s*\[\s*\n').hasMatch(text), isFalse);
    expect(text, contains('"command": [0,178,1,244,0]'));
    final exported = (jsonDecode(text)['sessions'] as List).single;
    final frames = (exported['events'] as List)
        .where((e) => e['type'] == 'physical_frame')
        .toList();
    expect(frames[0]['data']['raw'], List<int>.generate(256, (i) => i));
    expect(frames[1]['data']['raw'], isEmpty);
    expect(frames[2]['data']['raw'], isNull);
    expect(frames[0]['data']['response']['state'], 'not_captured');
    expect(frames[2]['data']['response']['state'], 'no_response');
    expect(frames[0]['data']['note'], 'literal "command": [\nquoted text');
    expect(exported['rawJsonl'], session.raw);
  });

  test('停止应用日志采集，管理和导出排除旧应用会话但保留文件', () async {
    final store = MemoryLogStore();
    final logger = AppLogger(store: store)..enabled = true;
    addTearDown(logger.close);
    logger
        .startSession('application', kind: DiagnosticSessionKind.application)
        .event('message');
    expect(await logger.readSessions(), isEmpty);
    logger.startSession('old-application').end(DiagnosticOutcome.success);
    logger.startSession('scan').end(DiagnosticOutcome.success);
    await logger.flush();
    store.sessions['old-application'] = store.sessions['old-application']!
        .replaceFirst('"kind":"scan"', '"kind":"application"');
    final exporter = _Exporter();
    final controller = DiagnosticsController(logger, exporter);
    addTearDown(controller.dispose);
    expect((await controller.sessions()).map((s) => s.id), ['scan']);
    await controller.exportLog();
    expect(jsonDecode(exporter.content!)['kind'], 'full');
    expect(jsonDecode(exporter.content!)['sessions'][0]['sessionId'], 'scan');
    expect(store.sessions, contains('old-application'));
  });

  test('损坏结束字段标记不完整，不阻断其他会话读取', () async {
    final store = MemoryLogStore();
    final logger = AppLogger(store: store)..enabled = true;
    addTearDown(logger.close);
    logger.startSession('bad-end').end(DiagnosticOutcome.success);
    logger.startSession('good-end').end(DiagnosticOutcome.success);
    await logger.flush();
    store.sessions['bad-end'] = store.sessions['bad-end']!.replaceFirst(
      '"outcome":"success"',
      '"outcome":123',
    );
    final sessions = await logger.readSessions();
    expect(sessions.singleWhere((s) => s.id == 'bad-end').incomplete, isTrue);
    expect(sessions.singleWhere((s) => s.id == 'good-end').incomplete, isFalse);
    expect(
      buildFullDiagnostics(sessions, DateTime.utc(2026)),
      contains('日志未完整记录'),
    );
  });

  test('关闭后不续写旧会话，重新开启从新会话开始', () async {
    final logger = AppLogger(store: MemoryLogStore())..enabled = true;
    addTearDown(logger.close);
    final first = logger.startSession('first');
    first.event(
      'physical_frame',
      data: {
        'command': [0],
        'response': [0x90, 0],
      },
    );
    logger.enabled = false;
    first.event('hidden', data: {'message': 'private'});
    logger.enabled = true;
    first.event('hidden_again');
    logger.startSession('second').end(DiagnosticOutcome.success);
    final sessions = await logger.readSessions();
    final old = sessions.singleWhere((s) => s.id == 'first');
    expect(old.outcome, 'recordingStopped');
    expect(old.incomplete, isTrue);
    expect(old.raw, isNot(contains('hidden')));
    expect(sessions.singleWhere((s) => s.id == 'second').incomplete, isFalse);
  });

  test('文件分段不切事件，保留旧文本，整会话清理不截当前开头', () async {
    final dir = await Directory.systemTemp.createTemp('trafarch-diag-');
    // Test owns this exact newly-created temporary directory.
    addTearDown(() => dir.delete(recursive: true));
    final legacy = File('${dir.path}/app_log.txt');
    await legacy.writeAsString('original legacy\n');
    final store = FileLogStore(directory: () async => dir, segmentBytes: 400);
    final logger = AppLogger(store: store, maxSessions: 1)..enabled = true;
    addTearDown(logger.close);
    final current = logger.startSession('current');
    current.event(
      'beginning',
      data: {
        'command': [0, 0xA4],
      },
    );
    await logger.flush();
    for (var i = 0; i < 5; i++) {
      current.event(
        'physical_frame',
        data: {
          'index': i,
          'command': [0, i],
          'response': [0x90, 0],
        },
      );
      await logger.flush();
    }
    logger.startSession('old').end(DiagnosticOutcome.success);
    await logger.prune();
    final sessions = await logger.readSessions();
    expect(sessions.map((s) => s.id), containsAll(['current', 'legacy']));
    expect(sessions.any((s) => s.id == 'old'), isFalse);
    final active = sessions.singleWhere((s) => s.id == 'current');
    expect(active.events[1].type, 'beginning');
    expect(
      active.events.where((e) => e.type == 'physical_frame'),
      hasLength(5),
    );
    expect(active.running, isTrue);
    expect(active.damaged, isFalse);
    final files = Directory('${dir.path}/trafarch_diagnostics_v1')
        .listSync()
        .whereType<File>();
    expect(files.length, greaterThan(1));
    expect(await legacy.readAsString(), 'original legacy\n');
    current.end(DiagnosticOutcome.success);
  });

  test('重启识别异常中断，坏尾行不吞掉完整前缀及后续分段', () async {
    final store = MemoryLogStore();
    final logger = AppLogger(store: store)..enabled = true;
    addTearDown(logger.close);
    logger.startSession('interrupted').event('good');
    await logger.flush();
    store.sessions['interrupted'] = '${store.sessions['interrupted']}{"torn":';
    final reopened = AppLogger(store: store);
    addTearDown(reopened.close);
    final captured = (await reopened.readSessions()).single;
    expect(captured.events.map((e) => e.type), ['session_start', 'good']);
    expect(captured.running, isFalse);
    expect(captured.incomplete, isTrue);
    expect(captured.damaged, isTrue);
    final full =
        jsonDecode(buildFullDiagnostics([captured], DateTime.utc(2026))) as Map;
    final session = (full['sessions'] as List).single as Map;
    expect(session['incomplete'], isTrue);
    expect(session['damaged'], isTrue);
    expect(session['rawJsonl'], captured.raw);
    expect((session['events'] as List).map((e) => e['type']), [
      'session_start',
      'good',
    ]);
  });

  test('写入失败可见，恢复后继续，丢失序号持久标记不完整', () async {
    final store = _FailingStore();
    final logger = AppLogger(store: store)..enabled = true;
    addTearDown(logger.close);
    final session = logger.startSession('disk');
    await logger.flush();
    expect(logger.storageIssue, contains('写入失败'));
    expect((await logger.readSessions()).single.incomplete, isTrue);
    store.fail = false;
    session.event('recovered');
    session.end(DiagnosticOutcome.failed);
    final snapshot = (await logger.readSessions()).single;
    expect(snapshot.incomplete, isTrue);
    expect(snapshot.events.any((e) => e.type == 'capture_gap'), isTrue);
    final reopened = AppLogger(store: store);
    addTearDown(reopened.close);
    expect((await reopened.readSessions()).single.incomplete, isTrue);
  });

  test('读取失败明确抛出，不能导出为暂无日志或报告成功', () async {
    final logger = AppLogger(store: _FailingStore()..readFails = true);
    addTearDown(logger.close);
    final exporter = _Exporter();
    final controller = DiagnosticsController(logger, exporter);
    addTearDown(controller.dispose);
    await controller.exportLog();
    expect(controller.logExportFailed, isTrue);
    expect(exporter.content, isNull);
    expect(controller.storageIssue, contains('读取或清理失败'));
  });

  test('保留期限和总量独立生效，清理只删除完整旧会话', () async {
    final dir = await Directory.systemTemp.createTemp('trafarch-diag-retain-');
    addTearDown(() => dir.delete(recursive: true));
    final store = FileLogStore(directory: () async => dir);
    final logger = AppLogger(store: store)..enabled = true;
    logger.startSession('expired').end(DiagnosticOutcome.success);
    await logger.close();
    final files = Directory('${dir.path}/trafarch_diagnostics_v1')
        .listSync()
        .whereType<File>();
    for (final file in files) {
      await file.setLastModified(
        DateTime.now().subtract(const Duration(days: 8)),
      );
    }
    final reopened = AppLogger(store: store);
    await reopened.prune();
    expect(await reopened.readSessions(), isEmpty);
    await reopened.close();
    final budget = AppLogger(store: store, maxBytes: 100)..enabled = true;
    addTearDown(budget.close);
    budget.startSession('oversized').end(DiagnosticOutcome.success);
    await budget.prune();
    expect(await budget.readSessions(), isEmpty);
  });

  test('队列和单会话有界，超过上限仍落结束及缺失标记', () async {
    final logger = AppLogger(
      store: MemoryLogStore(),
      maxQueueBytes: 900,
      maxSessionBytes: 1100,
    )..enabled = true;
    addTearDown(logger.close);
    final sink = logger.startSession('bounded');
    for (var i = 0; i < 100; i++) {
      sink.event('bulk', data: {'value': 'x' * 200});
    }
    sink.end(DiagnosticOutcome.success);
    final session = (await logger.readSessions()).single;
    expect(session.incomplete, isTrue);
    expect(session.events.last.type, 'session_end');
    expect(session.events.any((e) => e.type == 'capture_gap'), isTrue);
    expect(session.bytes, lessThan(3000));
  });

  test('导出冻结前缀，新帧不会穿过读取屏障', () async {
    final store = _BlockedStore();
    final logger = AppLogger(store: store)..enabled = true;
    addTearDown(logger.close);
    final sink = logger.startSession('race');
    sink.event('first');
    final snapshotFuture = logger.readSessions();
    sink.event('second');
    final flushed = logger.flush();
    store.release.complete();
    final frozen = (await snapshotFuture).single;
    expect(frozen.events.last.type, 'first');
    expect(frozen.running, isTrue);
    await flushed;
    expect((await logger.readSessions()).single.events.last.type, 'second');
  });

  test('完整诊断保留原始证据和采集版本', () async {
    const private = 'CARD-123456789 /storage/private 线路站点 2026-10-01';
    final logger = AppLogger(
      store: MemoryLogStore(),
      appVersion: '1.2.3',
      buildNumber: '42',
    )..enabled = true;
    addTearDown(logger.close);
    final sink = logger.startSession('sensitive-id');
    sink.event(
      'protocol_stage',
      phase: DiagnosticPhase.reading,
      data: {'name': private},
    );
    sink.event(
      'physical_frame',
      level: DiagnosticSeverity.error,
      data: {
        'command': [1, 2, 3],
        'response': null,
        'error': private,
        'errorCode': private,
      },
    );
    sink.end(DiagnosticOutcome.partial);
    logger.enabled = false;
    final sessions = await logger.readSessions();
    final full = buildFullDiagnostics(sessions, DateTime.utc(2026));
    final document = jsonDecode(full) as Map;
    final session = (document['sessions'] as List).single as Map;
    expect(session['rawJsonl'], sessions.single.raw);
    final frame = (session['events'] as List).singleWhere(
      (e) => e['type'] == 'physical_frame',
    );
    expect(frame['data']['command'], [1, 2, 3]);
    expect(frame['data']['raw'], isNull);
    expect(frame['data']['response']['state'], 'no_response');
    expect(frame['data']['error'], private);
    final exporter = _Exporter();
    final controller = DiagnosticsController(logger, exporter);
    addTearDown(controller.dispose);
    await controller.exportLog(sessionIds: {'sensitive-id'});
    expect(exporter.name, endsWith('.json'));
    expect(exporter.content, contains(private));
    expect(controller.logExportFailed, isFalse);
  });

  test('多会话 JSON 保留旧文本、未知字段及原时区', () async {
    const legacy = 'old "card"\nline 2\\path\n';
    final store = MemoryLogStore()..legacy = legacy;
    final logger = AppLogger(store: store)..enabled = true;
    addTearDown(logger.close);
    logger.startSession('one').end(DiagnosticOutcome.success);
    logger.startSession('two').end(DiagnosticOutcome.failed);
    await logger.flush();
    final lines = store.sessions['one']!.split('\n');
    final first = jsonDecode(lines.first) as Map<String, dynamic>;
    first['utcOffsetMinutes'] = 480;
    first['extension'] = {'original': 'unknown field'};
    lines[0] = jsonEncode(first);
    store.sessions['one'] = lines.join('\n');
    final sessions = await logger.readSessions();
    final document =
        jsonDecode(buildFullDiagnostics(sessions, DateTime.utc(2026))) as Map;
    expect(document['version'], 4);
    expect(document['kind'], 'full');
    final exported = (document['sessions'] as List).cast<Map>();
    expect(exported, hasLength(3));
    final one = exported.singleWhere((s) => s['sessionId'] == 'one');
    expect(one['events'][0]['utcOffsetMinutes'], 480);
    expect(one['events'][0]['extension'], {'original': 'unknown field'});
    expect(one['rawJsonl'], store.sessions['one']);
    expect(
      exported.singleWhere((s) => s['legacy'] == true)['legacyText'],
      legacy,
    );
  });
}

class _FailingStore extends MemoryLogStore {
  bool fail = true;
  bool readFails = false;
  @override
  Future<void> append(String id, String jsonLines) async {
    if (fail) throw const FileSystemException('disk full');
    await super.append(id, jsonLines);
  }

  @override
  Future<List<LogStoreEntry>> entries() async {
    if (readFails) throw const FileSystemException('read failed');
    return super.entries();
  }
}

class _BlockedStore extends MemoryLogStore {
  final release = Completer<void>();
  @override
  Future<void> append(String id, String jsonLines) async {
    await release.future;
    await super.append(id, jsonLines);
  }
}

class _Exporter implements LogExporter {
  String? name;
  String? content;
  @override
  Future<String> saveToDownloads(String fileName, String content) async {
    name = fileName;
    this.content = content;
    return 'Download/$fileName';
  }
}
