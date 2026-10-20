// 新建文件：lib/features/card_archive/models/card_types.dart
/// 卡片档案卡型取值（写入数据库的稳定标识，已启用取值勿修改；
/// 新增卡型在此登记，并由 CardIdentificationService 负责识别产出）。
abstract final class CardTypes {
  /// 交通联合电子钱包（JT/T 978.2）。
  static const String chinaTunion = 'china_tunion';

  /// 城市一卡通（住建部 City Union，CJ/T 331-2016）。
  static const String cityUnion = 'city_union';

  /// 八达通-全国通卡（交通联合版，由卡种目录细化识别）。
  static const String octopusTunion = 'octopus_tunion';

  /// 上海交通卡（交通联合版）：TU + CU 双标卡独立卡种（由专用识别器以
  /// 卡号前缀 + 应用结构双重确认，不归入普通交通联合卡）。
  static const String shanghaiTransitUnion = 'shanghai_transit_union';

  /// Suica（预留：FeliCa 解析器接入后启用）。
  static const String suica = 'suica';
}

/// 卡型 → 兜底展示名称（无正式卡名与自定义名称时使用）。
///
/// 兜底名称仅在对应卡型经可靠识别确认后使用；未识别卡型显示
/// 「未识别交通卡」，不猜测具体卡名。
String cardTypeLabel(String cardType) => switch (cardType) {
      CardTypes.chinaTunion => '交通联合卡',
      CardTypes.cityUnion => '城市一卡通',
      CardTypes.octopusTunion => '八达通全国通卡',
      CardTypes.shanghaiTransitUnion => '上海交通卡（交通联合版）',
      CardTypes.suica => 'Suica',
      _ => '未识别交通卡',
    };