/// 卡片档案卡型取值（写入数据库的稳定标识，已启用取值勿修改；
/// 新增卡型在此登记，并由 CardIdentificationService 负责识别产出）。
abstract final class CardTypes {
  /// User-imported selected JSON fields, with no implied NFC capture evidence.
  static const String importedJson = 'imported_json';

  /// 交通联合电子钱包（JT/T 978.2）。
  static const String chinaTunion = 'china_tunion';

  /// 城市一卡通（住建部 City Union，CJ/T 331-2016）。
  static const String cityUnion = 'city_union';

  /// 八达通-全国通卡（交通联合版，由卡种目录细化识别）。
  static const String octopusTunion = 'octopus_tunion';

  /// 地区产品名仅供识别与展示，TU、CU 仍是独立读取的应用。
  static const String shanghaiTransitUnion = 'shanghai_transit_union';
  static const String harbinTransitUnion = 'harbin_transit_union';

  /// Only a serial acquired from the TU wallet may identify these products.
  static String? regionalTunionType(String? rawSerial) {
    if (rawSerial == null || !RegExp(r'^[0-9]{20}$').hasMatch(rawSerial)) {
      return null;
    }
    final number = rawSerial.replaceFirst(RegExp(r'^0+'), '');
    if (number.startsWith('31047700')) return shanghaiTransitUnion;
    if (number.startsWith('31049702')) return harbinTransitUnion;
    return null;
  }

  static const String lingnanTong = 'lingnan_tong';
  static const String lingnanTunion = 'lingnan_tunion';
  static const String shenzhenTunion = 'shenzhen_tunion';
  static const String beijingBmac = 'beijing_bmac';
  static const String macauPass = 'macau_pass';

  /// 通用地方交通卡（武汉通 / 北京互通卡 / 深圳通本地 / 苏州苏薪·计次 /
  /// 天府通等 parserId=localCard 的城市卡种）；正式卡名由解析结果提供。
  static const String localCard = 'local_card';

  /// Suica（FeliCa，只读历史与日元钱包）。
  static const String suica = 'suica';

  /// Amusement IC 游戏身份卡，无交通钱包。
  static const String amusementIc = 'amusement_ic';
}

/// 卡型 → 兜底展示名称（无正式卡名与自定义名称时使用）。
///
/// 兜底名称仅在对应卡型经可靠识别确认后使用；未识别卡型显示
/// 「未识别交通卡」，不猜测具体卡名。
String cardTypeLabel(String cardType) => switch (cardType) {
  CardTypes.importedJson => 'JSON 导入记录',
  CardTypes.chinaTunion => '交通联合卡',
  CardTypes.cityUnion => '城市一卡通',
  CardTypes.octopusTunion => '八达通全国通卡',
  CardTypes.shanghaiTransitUnion => '上海交通卡（交通联合版）',
  CardTypes.harbinTransitUnion => '哈尔滨城市通（交通联合版）',
  CardTypes.lingnanTong => '岭南通',
  CardTypes.lingnanTunion => '岭南通（交通联合版）',
  CardTypes.shenzhenTunion => '深圳通（交通联合版）',
  CardTypes.beijingBmac => '北京市政交通一卡通（BMAC）',
  CardTypes.macauPass => '澳门通',
  CardTypes.localCard => '地方交通卡',
  CardTypes.suica => 'Suica',
  CardTypes.amusementIc => 'Amusement IC',
  _ => '未识别交通卡',
};
