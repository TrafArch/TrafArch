/// 标签语义信息（来自带版本号的 JSON 字典，而非页面硬编码）。
class TagInfo {
  final String tag;
  final String name;
  final String nameZh;
  final String format;
  final String decoder;
  final String sensitivity;

  /// 展示策略：normal / mask（mask 时值按脱敏规则处理）。
  final String displayPolicy;

  const TagInfo({
    required this.tag,
    required this.name,
    required this.nameZh,
    required this.format,
    required this.decoder,
    required this.sensitivity,
    required this.displayPolicy,
  });
}

/// 标签字典：负责"含义 / 格式 / 是否敏感 / 值解码"，不做流程控制。
abstract interface class TagDictionary {
  String get dictionaryId;
  int get schemaVersion;

  /// 查找标签；未收录返回 null（调用方仍应展示原始值）。
  TagInfo? lookup(String tagHex);

  /// 生成中文含义 + 格式说明文本。
  String describe(String tagHex);

  /// 按 decoder 解码原始值；无法解码时返回 null。
  String? decodeValue(String tagHex, List<int> raw);

  bool shouldMask(String tagHex);
}