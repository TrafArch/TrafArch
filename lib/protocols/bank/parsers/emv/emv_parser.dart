import '../../data/dictionary/emv_tag_dictionary.dart';
import '../../domain/interfaces/tag_dictionary.dart';
import '../../domain/models/card_application.dart';
import '../contactless_read_parser.dart';

/// EMV（国际规范）非接触借记/贷记应用只读解析器。
///
/// 作为兜底解析器：PBOC 未命中的应用由本解析器处理，
/// 使用 EMV 标签字典解释语义，仅读取允许公开访问的数据。
class EmvParser extends ContactlessReadParser {
  final TagDictionary _dictionary;

  EmvParser(this._dictionary);

  static Future<EmvParser> load(
    Future<String> Function(String) loadString,
  ) async => EmvParser(await EmvTagDictionary.load(loadString));

  @override
  String get parserId => 'emv';

  /// 兜底解析器：接受任何已进入枚举列表的应用。
  @override
  bool supports(CardApplication application) => application.aidHex.isNotEmpty;

  @override
  TagDictionary get dictionary => _dictionary;
}
