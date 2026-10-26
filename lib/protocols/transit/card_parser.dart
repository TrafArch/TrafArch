import 'city_union/city_union_models.dart';
import 'local/local_card_models.dart';
import 'tunion/tunion_models.dart';

/// APDU 收发函数签名：发送命令字节，返回响应字节（含 SW1SW2）。
typedef ApduTransceive = Future<List<int>> Function(List<int> apdu);

/// 解析器稳定标识（界面按解析器分派展示用；新增卡型解析器时在此登记，
/// 如未来住建部一卡通）。
abstract final class CardParserIds {
  /// 交通联合电子钱包（JT/T 978.2）。
  static const String tunion = 'tunion';

  /// 上海交通卡（交通联合版）：TU + CU 双标卡独立卡种。
  /// 由 [ShanghaiTransitUnionCardParser] 以「辅助前缀 + 应用结构」双重确认，
  /// 不归入普通交通联合解析器（[tunion]）。
  static const String shanghaiTunion = 'shanghai_tunion';

  /// 城市一卡通（住建部 City Union，CJ/T 331-2016）。
  static const String cityUnion = 'city_union';

  /// 地方交通卡（北京 / 羊城通 / 深圳通 / 苏州 / 天府通等城市探测卡种）。
  static const String localCard = 'local_card';

  /// 是否属于交通联合（JT/T 978.2）家族：普通交通联合卡或上海交通卡
  /// （交通联合版）。分析链路与展示层按族级分派时使用。
  static bool isTUnionFamily(String? parserId) =>
      parserId == tunion || parserId == shanghaiTunion;
}

/// 统一卡片解析器接口。
/// v0.1 仅接入交通联合（JT/T 978.2）一种卡型；
/// 未来接入住建部卡/PBOC 金融卡时实现本接口并在 AppDependencies 中注册。
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

  /// A successful, structurally valid TU transaction-file response was read.
  /// An empty list alone cannot distinguish an empty file from an unread file.
  final bool transactionFileObserved;

  /// 公共交通过程信息记录（JT/T 978.2 附录 B.2.4 SFI 0x1A 变长记录 /
  /// B.2.5 SFI 0x1E 循环记录），供专家模式展示。
  final List<TUnionProcessRecord> transitProcessRecords;

  /// City Union 文件解析视图，保留实际 SFI 与运行时读取角色。
  /// 标准表格默认 SFI 与 Trip Reader 应用读取 profile 分别定义，
  /// 不单凭 SFI 推测充值或异地消费；上海双应用也可携带此视图。
  final List<CityUnionFileView> cityUnionFiles;

  /// 地方交通卡识读结果（卡信息 + 乘车流水 + 扩展槽位）；
  /// 由 [LocalCardParser]（parserId [CardParserIds.localCard]）产出，
  /// 其它解析器产出时为 null。
  final ReadResult? localCard;

  final String selectedAidHex;

  /// 双应用卡标记：同一张物理卡上同时读取到交通联合（TU，JT/T 978.2）与
  /// 城市一卡通（CU，CJ/T 331-2016）两个应用。为 true 时，[info] /
  /// [transactions] / [transitProcessRecords] 承载交通部互联互通应用数据，
  /// [cityUnionFiles] 与 [cityUnionBalanceFen] 承载住建部城市一卡通应用数据；
  /// [parserId] 为 [CardParserIds.tunion] 或 [CardParserIds.shanghaiTunion]
  /// （以互联互通应用驱动分析链路）。
  final bool dualApplication;

  /// 双应用卡上城市一卡通（CU）应用的电子钱包余额（分）；非双应用或未读到
  /// 余额时为 null。与 [info]（交通联合钱包余额）分属两套独立钱包。
  final int? cityUnionBalanceFen;

  const ParsedCard({
    this.parserId = '',
    required this.parserName,
    required this.info,
    required this.transactions,
    this.transactionFileObserved = false,
    this.transitProcessRecords = const [],
    this.cityUnionFiles = const [],
    this.localCard,
    this.selectedAidHex = '',
    this.dualApplication = false,
    this.cityUnionBalanceFen,
  });
}
