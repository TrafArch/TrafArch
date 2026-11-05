import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class LogStoreEntry {
  const LogStoreEntry(this.id, this.bytes, this.modifiedAt);
  final String id;
  final int bytes;
  final DateTime modifiedAt;
}

abstract interface class LogStore {
  Future<void> append(String id, String jsonLines);
  Future<List<LogStoreEntry>> entries();
  Future<String> read(String id);
  Future<void> delete(String id);
  Future<String?> readLegacy();
  Future<void> deleteLegacy();
}

/// Private JSONL segments; no database or rewriting of captured lines.
class FileLogStore implements LogStore {
  FileLogStore({
    Future<Directory> Function()? directory,
    this.segmentBytes = 1024 * 1024,
  }) : _directory = directory ?? getApplicationDocumentsDirectory;
  static const fileName = 'app_log.txt';
  final Future<Directory> Function() _directory;
  final int segmentBytes;
  final _tails = <String, (File, int, int)>{};
  static final _segmentName = RegExp(
    r'^([a-zA-Z0-9_-]{1,80})\.(\d{6})\.jsonl$',
  );

  Future<Directory> _root() async =>
      Directory('${(await _directory()).path}/trafarch_diagnostics_v1');
  void _validate(String id) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(id)) {
      throw ArgumentError('Invalid diagnostic session ID');
    }
  }

  Future<List<File>> _files(String id) async {
    _validate(id);
    final root = await _root();
    if (!await root.exists()) return [];
    final files = <File>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is File &&
          _segmentName.firstMatch(entity.uri.pathSegments.last)?.group(1) ==
              id) {
        files.add(entity);
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  @override
  Future<void> append(String id, String jsonLines) async {
    _validate(id);
    var tail = _tails[id];
    if (tail == null) {
      final root = await _root();
      await root.create(recursive: true);
      final files = await _files(id);
      final part = files.isEmpty
          ? 0
          : int.parse(
              _segmentName
                  .firstMatch(files.last.uri.pathSegments.last)!
                  .group(2)!,
            );
      final file = files.isEmpty
          ? File('${root.path}/$id.000000.jsonl')
          : files.last;
      tail = (file, part, files.isEmpty ? 0 : await file.length());
    }
    final size = utf8.encode(jsonLines).length;
    var (file, part, length) = tail;
    if (length > 0 && length + size > segmentBytes) {
      part++;
      file = File(
        '${file.parent.path}/$id.${part.toString().padLeft(6, '0')}.jsonl',
      );
      length = 0;
    }
    try {
      await file.writeAsString(jsonLines, mode: FileMode.append, flush: true);
      _tails[id] = (file, part, length + size);
    } catch (_) {
      // A partial write must not consume the next intact JSON line.
      _tails[id] = (
        File(
          '${file.parent.path}/$id.${(part + 1).toString().padLeft(6, '0')}.jsonl',
        ),
        part + 1,
        0,
      );
      rethrow;
    }
  }

  @override
  Future<List<LogStoreEntry>> entries() async {
    final root = await _root();
    if (!await root.exists()) return [];
    final grouped = <String, LogStoreEntry>{};
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File) continue;
      final match = _segmentName.firstMatch(entity.uri.pathSegments.last);
      if (match == null) continue;
      final id = match.group(1)!;
      final stat = await entity.stat();
      final old = grouped[id];
      grouped[id] = LogStoreEntry(
        id,
        stat.size + (old?.bytes ?? 0),
        old != null && old.modifiedAt.isAfter(stat.modified)
            ? old.modifiedAt
            : stat.modified,
      );
    }
    return grouped.values.toList();
  }

  @override
  Future<String> read(String id) async {
    final text = StringBuffer();
    final files = await _files(id);
    for (var i = 0; i < files.length; i++) {
      // A power loss may tear a UTF-8 character as well as the final JSON line.
      final part = utf8.decode(
        await files[i].readAsBytes(),
        allowMalformed: true,
      );
      text.write(part);
      if (i < files.length - 1 && part.isNotEmpty && !part.endsWith('\n')) {
        text.write('\n');
      }
    }
    return text.toString();
  }

  @override
  Future<void> delete(String id) async {
    for (final file in await _files(id)) {
      await file.delete();
    }
    _tails.remove(id);
  }

  @override
  Future<String?> readLegacy() async {
    final file = File('${(await _directory()).path}/$fileName');
    return await file.exists() ? file.readAsString() : null;
  }

  @override
  Future<void> deleteLegacy() async {
    final file = File('${(await _directory()).path}/$fileName');
    if (await file.exists()) await file.delete();
  }
}

class MemoryLogStore implements LogStore {
  final sessions = <String, String>{};
  String? legacy;
  @override
  Future<void> append(String id, String jsonLines) async =>
      sessions.update(id, (old) => old + jsonLines, ifAbsent: () => jsonLines);
  @override
  Future<List<LogStoreEntry>> entries() async => [
    for (final entry in sessions.entries)
      LogStoreEntry(entry.key, utf8.encode(entry.value).length, DateTime.now()),
  ];
  @override
  Future<String> read(String id) async => sessions[id] ?? '';
  @override
  Future<void> delete(String id) async {
    sessions.remove(id);
  }

  @override
  Future<String?> readLegacy() async => legacy;
  @override
  Future<void> deleteLegacy() async {
    legacy = null;
  }

  Future<String> readAll() async => sessions.values.join();
}
