import 'dart:async';

import '../../domain/interfaces/tag_dictionary.dart';
import 'json_tag_dictionary.dart';

/// PBOC（JR/T 0025 系列）标签字典：与 EMV 分离维护，仅复用协议工具。
class PbocTagDictionary {
  PbocTagDictionary._();

  static const String assetPath = 'assets/dictionaries/pboc_tags.json';

  static Future<TagDictionary> load(
    Future<String> Function(String) loadString,
  ) async {
    try {
      return JsonTagDictionary.fromJson(await loadString(assetPath));
    } catch (_) {
      return _empty;
    }
  }

  static final TagDictionary _empty =
      JsonTagDictionary.fromJson('{"schemaVersion":0,"dictionaryId":"pboc",'
          '"entries":[]}');
}