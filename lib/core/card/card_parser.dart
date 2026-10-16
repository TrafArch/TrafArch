import '../transit/city_union/city_union_models.dart';
import '../transit/local_card/local_card_models.dart';
import '../transit/tunion/tunion_models.dart';

/// APDU 收发函数签名：发送命令字节，返回响应字节（含 SW1SW2）。
typedef ApduTransceive = Future<List<int>> Function(List<int> apdu);

/// 解析器稳定标识（界面按解析器分派展示用；新增卡型解析器时在此登记，
/// 如未来住建部一卡通）。
abstract final class CardParserIds {
  /// 交通联合电子钱包（JT/T 978.2）。
  static const String tunion = 'tunion';

  /// 城市一卡通（住建部 City Union，CJ/T 331-2016）。
  static const String cityUnion = 'city_union';

  /// 地方交通卡（北京 / 羊城通 / 深圳通 / 苏州 / 天府通等城市探测卡种）。
  static const String localCard = 'local_card';
}

/// 统一卡片解析器接口。
/// v0.1 仅接入交通联合（JT/T 978.2）一种卡型；
/// 未来接入住建部卡/PBOC 金融卡时实现本接口并在 AppState 中注册。
abstract class CardParser {
  /// 解析器稳定标识（[CardParserIds] 常量，不随展示名与本地化变化）。
  String get parserId;

  /// 解析器名称（用于界面展示）。
  String get parserName;

  /// 探测并解析：不是本解析器支持的卡片时返回 null。
  Future<ParsedCard?> parse();
}

/// 解析结果。
/// v0.1 暂以交通联合字段直接承载；接入多卡型后收敛为通用载荷 + 各卡型详情。
class ParsedCard {
  /// 产出该结果的解析器标识（[CardParserIds] 常量；空串表示未声明）。
  /// 专家页据此分派卡型专属字段与页签的展示。
  final String parserId;
  final String parserName;
  final TUnionCardInfo info;
  final List<TUnionTransaction> transactions;

  /// 公共交通过程信息记录（JT/T 978.2 附录 B.2.4 SFI 0x1A 变长记录 /
  /// B.2.5 SFI 0x1E 循环记录），供专家模式展示。
  final List<TUnionProcessRecord> transitProcessRecords;

  /// City Union（CJ/T 331-2016）标准文件解析视图（SFI 0x15 公共应用
  /// 基本信息 / 0x17 复合交易记录 / 0x10 异地消费交易明细 / 0x1A 充值
  /// 交易明细）；由城市一卡通解析器产出，交通联合解析器产出时为空。
  final List<CityUnionFileView> cityUnionFiles;

  /// 地方交通卡识读结果（卡信息 + 乘车流水 + 扩展槽位）；
  /// 由 [LocalCardParser]（parserId [CardParserIds.localCard]）产出，
  /// 其它解析器产出时为 null。
  final ReadResult? localCard;

  final String selectedAidHex;

  const ParsedCard({
    this.parserId = '',
    required this.parserName,
    required this.info,
    required this.transactions,
    this.transitProcessRecords = const [],
    this.cityUnionFiles = const [],
    this.localCard,
    this.selectedAidHex = '',
  });
}