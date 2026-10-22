import '../../data/dictionary/pboc_tag_dictionary.dart';
import '../../domain/interfaces/tag_dictionary.dart';
import '../../domain/models/card_application.dart';
import '../contactless_read_parser.dart';
import 'pboc_version_rules.dart';

/// PBOC 非接触借记/贷记应用只读解析器。
///
/// 与 EMV 共用协议工具（APDU / BER-TLV），但使用 PBOC 专属标签字典
/// 与版本规则；不因某个标签相同就套用整套流程解释。
class PbocParser extends ContactlessReadParser {
  final TagDictionary _dictionary;

  PbocParser(this._dictionary);

  static Future<PbocParser> load(
    Future<String> Function(String) loadString,
  ) async => PbocParser(await PbocTagDictionary.load(loadString));

  @override
  String get parserId => 'pboc';

  @override
  bool supports(CardApplication application) =>
      PbocVersionRules.matches(application.aidHex);

  @override
  TagDictionary get dictionary => _dictionary;
}
