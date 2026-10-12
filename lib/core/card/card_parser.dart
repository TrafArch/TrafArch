import '../transit/tunion/tunion_models.dart';

/// APDU 收发函数签名：发送命令字节，返回响应字节（含 SW1SW2）。
typedef ApduTransceive = Future<List<int>> Function(List<int> apdu);

/// 统一卡片解析器接口。
/// v0.1 仅接入交通联合（JT/T 978.2）一种卡型；
/// 未来接入住建部卡/PBOC 金融卡时实现本接口并在 AppState 中注册。
abstract class CardParser {
  /// 解析器名称（用于界面展示）。
  String get parserName;

  /// 探测并解析：不是本解析器支持的卡片时返回 null。
  Future<ParsedCard?> parse();
}

/// 解析结果。
/// v0.1 暂以交通联合字段直接承载；接入多卡型后收敛为通用载荷 + 各卡型详情。
class ParsedCard {
  final String parserName;
  final TUnionCardInfo info;
  final List<TUnionTransaction> transactions;

  /// 公共交通过程信息记录（JT/T 978.2 附录 B.2.4 SFI 0x1A 变长记录 /
  /// B.2.5 SFI 0x1E 循环记录），供专家模式展示。
  final List<TUnionProcessRecord> transitProcessRecords;
  final String selectedAidHex;

  const ParsedCard({
    required this.parserName,
    required this.info,
    required this.transactions,
    this.transitProcessRecords = const [],
    this.selectedAidHex = '',
  });
}