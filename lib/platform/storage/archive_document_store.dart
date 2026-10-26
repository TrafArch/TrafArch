import 'dart:convert';

import 'package:flutter/services.dart';

/// A user-selected document. Its data is validated by the archive feature.
class PickedArchiveDocument {
  const PickedArchiveDocument({required this.name, required this.content});
  final String name;
  final String content;
}

abstract class ArchiveDocumentStore {
  static const maxBytes = 32 * 1024 * 1024;

  /// Cancellation is not a failure and returns null.
  Future<PickedArchiveDocument?> openJson();

  /// Ask the user where to save a JSON file. Returns its display name, or null
  /// when cancelled; a failed write must throw rather than return a name.
  Future<String?> saveJson(String fileName, String content);
}

class MethodChannelArchiveDocumentStore implements ArchiveDocumentStore {
  const MethodChannelArchiveDocumentStore();
  static const _channel = MethodChannel(
    'transit_card_analyzer/archive_documents',
  );

  @override
  Future<PickedArchiveDocument?> openJson() async {
    final result = await _channel.invokeMethod<Object?>('openJson');
    if (result == null) return null;
    if (result is! Map ||
        result['name'] is! String ||
        (result['name'] as String).trim().isEmpty ||
        result['content'] is! String) {
      throw PlatformException(
        code: 'DOCUMENT_READ_FAILED',
        message: '未能取得所选文件的内容，请重新选择。',
      );
    }
    final content = result['content'] as String;
    _checkSize(content);
    return PickedArchiveDocument(
      name: result['name'] as String,
      content: content,
    );
  }

  @override
  Future<String?> saveJson(String fileName, String content) async {
    if (fileName.trim().isEmpty ||
        fileName.length > 240 ||
        !fileName.toLowerCase().endsWith('.json') ||
        RegExp(r'[\x00-\x1f\\/:*?"<>|]').hasMatch(fileName)) {
      throw ArgumentError.value(fileName, 'fileName', '需要有效的 JSON 文件名');
    }
    _checkSize(content);
    final result = await _channel.invokeMethod<Object?>('saveJson', {
      'fileName': fileName,
      'content': content,
    });
    if (result == null) return null;
    if (result is! String || result.trim().isEmpty) {
      throw PlatformException(
        code: 'DOCUMENT_WRITE_FAILED',
        message: '未能确认文件已保存，请重试。',
      );
    }
    return result;
  }

  void _checkSize(String content) {
    if (content.length > ArchiveDocumentStore.maxBytes ||
        utf8.encode(content).length > ArchiveDocumentStore.maxBytes) {
      throw PlatformException(
        code: 'DOCUMENT_TOO_LARGE',
        message: 'JSON 文件不得大于 32 MiB，请分卡导出。',
      );
    }
  }
}
