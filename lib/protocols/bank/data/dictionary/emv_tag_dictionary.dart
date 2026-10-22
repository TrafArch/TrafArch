import 'dart:async';

import '../../domain/interfaces/tag_dictionary.dart';
import 'json_tag_dictionary.dart';

/// EMV 通用标签字典（依据 EMV 规范公共数据元，随版本演进维护数据文件）。
class EmvTagDictionary {
  EmvTagDictionary._();

  static const String assetPath = 'assets/dictionaries/emv_tags.json';

  /// 从 Flutter asset 加载（失败返回空字典，不阻断流程）。
  static Future<TagDictionary> load(
    Future<String> Function(String) loadString,
  ) async {
    try {
      return JsonTagDictionary.fromJson(await loadString(assetPath));
    } catch (_) {
      return _empty;
    }
  }

  static final TagDictionary _empty = JsonTagDictionary.fromJson(
    '{"schemaVersion":0,"dictionaryId":"emv",'
    '"entries":[]}',
  );
}
