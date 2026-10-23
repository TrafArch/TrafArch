/// 交通联合（T-Union）电子钱包卡片信息模型。
///
/// 字段布局对应 JT/T 978.2 附录 B 标准文件：
/// 公共应用信息文件（0x15）、持卡人基本信息文件（0x16）、
/// 管理信息文件（0x17）；余额与交易为动态读取。
class TUnionCardInfo {
  // 公共应用信息文件（SFI 0x15）
  final String? issuerId; // 发卡机构标识（8 字节 HEX）
  final String? appTypeId; // 应用类型标识（1 字节 HEX）
  final String? appVersion; // 发卡机构应用版本（1 字节 HEX）
  final String? applicationSerial; // 应用序列号（10 字节 HEX）
  final DateTime? effectiveDate; // 应用生效日期
  final DateTime? expireDate; // 应用失效日期
  final String? issuerFci; // 发卡机构自定义 FCI 数据（2 字节 HEX）

  // 持卡人基本信息文件（SFI 0x16）
  final String? cardTypeId; // 卡类型标识
  final String? employeeFlag; // 本行职工标识
  final String? holderName; // 持卡人姓名（HEX）
  final String? idNumber; // 持卡人证件号码（HEX）
  final String? idType; // 持卡人证件类型

  // 管理信息文件（SFI 0x17）
  final String? countryCode; // 国际代码
  final String? provinceCode; // 省级代码
  final String? cityCode; // 城市代码
  final String? interopCardType; // 互通卡种
  final String? cardKind; // 卡种类型

  // GET BALANCE 动态读取
  final int? balanceFen; // 电子钱包余额（分）

  const TUnionCardInfo({
    this.issuerId,
    this.appTypeId,
    this.appVersion,
    this.applicationSerial,
    this.effectiveDate,
    this.expireDate,
    this.issuerFci,
    this.cardTypeId,
    this.employeeFlag,
    this.holderName,
    this.idNumber,
    this.idType,
    this.countryCode,
    this.provinceCode,
    this.cityCode,
    this.interopCardType,
    this.cardKind,
    this.balanceFen,
  });

  /// 逻辑卡号，即应用序列号。
  String? get logicalCardNumber => applicationSerial;

  /// 展示用卡号：应用序列号按 10 字节 BCD 定长写入（20 位），有效卡面
  /// 卡号为 19 位（IIN 以 31 开头），首位为写卡时补齐的 0，展示时去除
  /// 前导 0；原始值仍保留在 [applicationSerial]，供专家模式核对原始数据。
  String? get displayCardNumber {
    final s = applicationSerial;
    if (s == null || s.isEmpty) return null;
    final trimmed = s.replaceFirst(RegExp(r'^0+'), '');
    return trimmed.isEmpty ? s : trimmed;
  }

  /// 发卡日期，即应用生效日期。
  DateTime? get issueDate => effectiveDate;

  /// 全国互联互通启用状态（依据管理信息文件 SFI 0x17「互通卡种」字段
  /// [interopCardType]，JT/T 978.2 部标口径）：
  /// - 0x01 互通卡：已开启全国互联互通（true）；
  /// - 0x00 非互通卡：未开启全国互联互通（false）；
  /// - 管理信息文件未读到 / 字段缺失 / 部标未定义取值：null（未知，不猜测）。
  bool? get isNationalInteropEnabled {
    final raw = interopCardType?.trim();
    if (raw == null || raw.isEmpty) return null;
    final value = int.tryParse(raw, radix: 16);
    return switch (value) {
      0x01 => true, // 互通卡
      0x00 => false, // 非互通卡
      _ => null, // 部标未定义取值 / HEX 非法：未知
    };
  }

  /// 替换余额字段（余额为动态读取，不随文件解析）。
  TUnionCardInfo withBalance(int? balanceFen) => TUnionCardInfo(
    issuerId: issuerId,
    appTypeId: appTypeId,
    appVersion: appVersion,
    applicationSerial: applicationSerial,
    effectiveDate: effectiveDate,
    expireDate: expireDate,
    issuerFci: issuerFci,
    cardTypeId: cardTypeId,
    employeeFlag: employeeFlag,
    holderName: holderName,
    idNumber: idNumber,
    idType: idType,
    countryCode: countryCode,
    provinceCode: provinceCode,
    cityCode: cityCode,
    interopCardType: interopCardType,
    cardKind: cardKind,
    balanceFen: balanceFen,
  );
}

class TUnionTransaction {
  final int sequence; // 电子钱包消费交易序号
  final int overdraftLimitFen; // 透支限额（分）
  final int amountFen; // 交易金额（分）
  final int rawType; // 交易类型原始值（0x02 充值 / 0x06 消费 / 0x09 复合消费）
  final String terminalId; // 交易终端编号（BCD 字符串）
  final DateTime time; // 交易时间

  /// 记录体原始字节 HEX（详情页原始数据展示 / 重解析依据）；未保留时为 null。
  final String? rawHex;
  // 线路/站点等位置信息不在原始记录中直接给出，
  // 由分析层通过终端编号(TAC)规则库二次解码（见 analysis/tunion_analysis_engine.dart）。

  const TUnionTransaction({
    required this.sequence,
    required this.overdraftLimitFen,
    required this.amountFen,
    required this.rawType,
    required this.terminalId,
    required this.time,
    this.rawHex,
  });

  /// 是否为消费类交易（0x06 消费 / 0x09 复合消费）。
  bool get isConsume => rawType == 0x06 || rawType == 0x09;

  /// 是否为充值交易（0x02）。取值来自社区读卡实现实测（T-Union 系列：
  /// 0x02 充值 / 0x06 消费 / 0x09 复合消费）；其余取值保持"其他"未知（不猜测）。
  bool get isRecharge => rawType == 0x02;

  /// 是否为复合消费交易（0x09，如轨道交通进出站行程的一次性结算）。
  bool get isCompositeConsume => rawType == 0x09;

  /// 兼容旧语义：0 消费，1 其他（充值等）。
  int get type => isConsume ? 0 : 1;

  String get typeName {
    switch (rawType) {
      case 0x02:
        return '充值';
      case 0x06:
        return '消费';
      case 0x09:
        return '复合消费';
      default:
        return '其他(0x${rawType.toRadixString(16).toUpperCase()})';
    }
  }
}

/// 公共交通过程信息记录（JT/T 978.2 附录 B.2.4 / B.2.5）。
///
/// - sfi = 0x1A：公共交通过程信息变长记录文件（记录 1 城市轨道应用信息记录、
///   记录 2 公共汽电车应用信息记录、…、记录 13 优惠信息记录，最多 18 条）；
/// - sfi = 0x1E：公共交通过程信息循环记录文件（定长循环记录，保存最近若干次
///   跨区域乘车过程信息，供换乘优惠判定与乘车记录展示）。
class TUnionProcessRecord {
  final int sfi; // 0x1A 变长记录文件 / 0x1E 循环记录文件
  final int recordNumber; // 记录号（从 1 开始；整体读取兜底时为 0）
  final String recordName; // 记录名称（0x1A 按记录号对照表，0x1E 为“循环记录 N”）
  final List<int> raw; // 原始记录字节

  /// 0x1E 循环记录的行程解码结果；记录未写入、长度不足或布局无法识别时为 null
  /// （保持未知，不猜测；原始数据仍完整保留在 [raw]）。
  final TUnionTripRecord? trip;

  /// 0x1A 记录 1（城市轨道应用信息记录）解码结果；记录过短或布局不符时
  /// 为 null（不猜测；原始数据仍完整保留在 [raw]）。
  final TransitRecord? railTransit;

  /// 0x1A 记录 2（公共汽电车应用信息记录）解码结果；记录过短或布局不符时
  /// 为 null（不猜测；原始数据仍完整保留在 [raw]）。
  final BusTransitRecord? busTransit;

  const TUnionProcessRecord({
    required this.sfi,
    required this.recordNumber,
    required this.recordName,
    required this.raw,
    this.trip,
    this.railTransit,
    this.busTransit,
  });

  /// 原始记录字节（空格分隔 HEX，便于逐字节核对）。
  String get rawHex => raw
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');

  /// 是否已成功解码为结构化字段（0x1E 行程或 0x1A 记录任一）。
  bool get isDecoded =>
      trip != null || railTransit != null || busTransit != null;

  /// 记录内容是否为全 0x00 / 0xFF（未写入 / 擦除态初始值）。
  bool get isBlank =>
      raw.isNotEmpty && raw.every((b) => b == 0x00 || b == 0xFF);
}

/// 0x1E 公共交通过程信息循环记录（48 字节）解码结果。
///
/// 字段布局按 JT/T 978.2 公共交通过程信息交易记录逐字节排定
/// （经社区开源读卡实现 T-Union Master / NekoCardReader 实测交叉验证）：
/// - [0x00] 交易类型（0x01~0x0A：EC/EP 入站 / 出站 / 单次消费 / 补票 / 充值）；
/// - [0x01-0x08] 交易终端编号（BCD，16 位）；
/// - [0x09] 应用分类码（0x01 城市轨道交通 / 0x02 公共汽电车 / …）；
/// - [0x0A-0x0B] 线路代码（BCD，4 位）　[0x0C-0x0D] 站点代码（BCD，4 位）
///   [0x0E-0x0F] 运营代码（BCD，4 位）　[0x10] 预留字段；
/// - [0x11-0x14] 交易金额（大端无符号，单位：分）；
/// - [0x15-0x18] 记录余额（大端无符号，单位：分）；
/// - [0x19-0x1F] 交易日期时间（BCD YYYYMMDDhhmmss）；
/// - [0x20-0x21] 受理方城市代码（HEX）；
/// - [0x22-0x29] 受理方机构标识（HEX）；
/// - [0x2A-0x2F] 预留字段。
///
/// 个别发卡方若存在写入差异，以原始数据为准（见 [TUnionProcessRecord.rawHex]）。
class TUnionTripRecord {
  final int typeCode; // [0x00] 交易类型原始值
  final String terminalId; // [0x01-0x08] 终端编号（BCD 或 HEX 回退）
  final int appTypeCode; // [0x09] 应用分类码原始值
  final String lineStationCode; // [0x0A-0x10] 线路和站点代码（BCD）
  final int amountFen; // [0x11-0x14] 交易金额（分）
  final int balanceFen; // [0x15-0x18] 记录余额（分）
  final DateTime time; // [0x19-0x1F] 交易日期时间
  final String? cityCode; // [0x20-0x21] 受理方城市代码（HEX）
  final String? acquirerId; // [0x22-0x29] 受理方机构标识（HEX）

  /// 记录原始字节 HEX（历史批次按值关联 / 原始数据展示）；未保留时为 null。
  final String? rawHex;

  const TUnionTripRecord({
    required this.typeCode,
    required this.terminalId,
    required this.appTypeCode,
    required this.lineStationCode,
    required this.amountFen,
    required this.balanceFen,
    required this.time,
    this.cityCode,
    this.acquirerId,
    this.rawHex,
  });

  /// 交易类型名称（标准类型表 0x01~0x0A；其余显式标注未知）。
  String get typeName =>
      _typeNames[typeCode] ??
      '未知(0x${typeCode.toRadixString(16).padLeft(2, '0').toUpperCase()})';

  /// 应用分类码名称（标准表未收录时显式标注未知）。
  String get appTypeName =>
      _appTypeNames[appTypeCode] ??
      '未知(0x${appTypeCode.toRadixString(16).padLeft(2, '0').toUpperCase()})';

  /// 已识别的应用分类名称；标准表未收录时为 null（展示层只消费已知值）。
  String? get appTypeLabel => _appTypeNames[appTypeCode];

  /// 是否城市轨道交通行业记录（[0x09] 应用分类码标准值 0x01）。
  bool get isCityRail => appTypeCode == 0x01;

  /// 是否公共汽电车行业记录（[0x09] 应用分类码标准值 0x02）。
  bool get isBus => appTypeCode == 0x02;

  /// 仅适用于 0x1E 的消费与充值类型，不复用 0x18 的类型码。
  bool get isConsume =>
      const {0x02, 0x04, 0x05, 0x06, 0x07, 0x08}.contains(typeCode);
  bool get isRecharge => typeCode == 0x09 || typeCode == 0x0A;

  /// 按用户实测将记录余额解释为交易前余额；尚待多卡验证，非规范结论。
  /// 不改原始 balanceFen/rawHex；未知类型及非零金额进站不推断。
  int? get balanceAfterFen {
    if (isConsume) return balanceFen - amountFen;
    if (isRecharge) return balanceFen + amountFen;
    if (isEntry && amountFen == 0) return balanceFen;
    return null;
  }

  /// 是否入站/上车/进场类记录（EC 0x01 / EP 0x03）：不承载扣费金额，
  /// 不参与与交易明细（0x18）的行程配对。
  bool get isEntry => typeCode == 0x01 || typeCode == 0x03;

  /// 行程状态短名（行程卡标题展示用）：进/出站类按应用分类码区分
  /// 轨道交通"进站/出站"与公共汽电车"上车/下车"；单次消费 / 补票 /
  /// 充值取短名；类型未收录时返回 null（展示层不替换，不猜测）。
  String? get statusShortName => switch (typeCode) {
    0x01 || 0x03 => isBus ? '上车' : '进站',
    0x02 || 0x04 => isBus ? '下车' : '出站',
    0x05 || 0x06 => '单次消费',
    0x07 || 0x08 => '补票',
    0x09 || 0x0A => '充值',
    _ => null,
  };

  /// [0x0A-0x0B] 线路代码（BCD，4 位）。
  String? get lineCode =>
      lineStationCode.length >= 12 ? lineStationCode.substring(0, 4) : null;

  /// [0x0C-0x0D] 站点代码（BCD，4 位）。
  String? get stationCode =>
      lineStationCode.length >= 12 ? lineStationCode.substring(4, 8) : null;

  /// [0x0E-0x0F] 运营代码（BCD，4 位）。
  String? get operatorCode =>
      lineStationCode.length >= 12 ? lineStationCode.substring(8, 12) : null;

  String get amountText => '${(amountFen / 100).toStringAsFixed(2)} 元';

  String get balanceText => '${(balanceFen / 100).toStringAsFixed(2)} 元';

  static const _typeNames = <int, String>{
    0x01: 'EC 入站/上车/进场等',
    0x02: 'EC 出站/下车/出场等',
    0x03: 'EP 入站/上车/进场等',
    0x04: 'EP 出站/下车/出场等',
    0x05: 'EC 单次消费',
    0x06: 'EP 单次消费',
    0x07: 'EC 补票',
    0x08: 'EP 补票',
    0x09: 'EC 充值',
    0x0A: 'EP 充值',
  };

  static const _appTypeNames = <int, String>{
    0x01: '城市轨道交通',
    0x02: '公共汽电车',
    0x03: '城市水上客运',
    0x04: '出租汽车',
    0x05: '租赁汽车',
    0x06: '公共自行车',
    0x07: '公共停车',
    0x08: '长途客运',
    0x09: '轮渡',
    0x0A: '城际铁路',
    0x0B: '民航',
    0x0C: '高速公路',
    0x0D: '优惠',
    0x0E: '市郊铁路',
    0x0F: '公共充电桩',
    0x12: '行业巡检',
  };
}

/// 0x1A 记录 1（城市轨道应用信息记录，85 字节）解码结果。
///
/// 字段顺序与项目需求给定的目标输出格式一致，字节偏移按其逐字段排定：
/// [00] 交易状态　[01-02] 进闸城市代码　[03-04] 出闸城市代码
/// [05-0C] 进闸机构标识　[0D-14] 出闸机构标识　[15-1C] 进闸站点
/// [1D-24] 出闸站点　[25-2C] 进闸终端编号　[2D-34] 出闸终端编号
/// [35-3B] 进站时间（BCD YYYYMMDDhhmmss）　[3C-42] 出站时间（BCD）
/// [43-46] 标注金额　[47] 入站线路号　[48] 出站线路号
/// [49-4C] 进站交易金额　[4D-50] 进站钱包余额　[51-54] 出站交易金额。
///
/// 真机存在 128 字节完整格式：27 记录头（14 字节：记录号 / 记录长度 7D /
/// 应用有效标识 / 互联互通交易标识 / 应用锁定标志 / 交易流水号）+
/// 上述字段体（85 字节）+ 发卡机构自定义（29 字节）。解析层自动识别记录头
/// 并按字段体偏移解析（记录头仅用于偏移定位，不产出头部字段）。
/// [43-46] 标注金额在部分规范文本中记为“不完整交易补扣金额”（同一字节段）。
///
/// 站点/线路名称字段预留给动态线路数据库接入：解析层只产出原始编码
/// （stationId / lineCode），由线路库按城市码 + 线路号 + 站点号查表
/// 补全名称，展示层直接消费。
class TransitRecord {
  final int statusCode; // [00] 交易状态（0x00 初始值 / 0x01 进闸 / 0x02 出闸）

  /// [63-7F] 发卡机构自定义（HEX）；仅完整格式且自定义区有有效内容时产出；
  /// 未写入 / 擦除态（全 0x00 / 0xFF）或裸 85 字节字段体实现时为 null。
  final String? issuerCustom;

  final String? entryCityCode; // [01-02] 进闸城市代码（HEX）
  final String? exitCityCode; // [03-04] 出闸城市代码（HEX）
  final String? entryAgencyId; // [05-0C] 进闸机构标识（HEX）
  final String? exitAgencyId; // [0D-14] 出闸机构标识（HEX）
  final String? entryStationId; // [15-1C] 进闸站点（原始编码）
  final String? exitStationId; // [1D-24] 出闸站点（原始编码）
  final String? entryTerminalId; // [25-2C] 进闸终端编号（HEX）
  final String? exitTerminalId; // [2D-34] 出闸终端编号（HEX）
  final DateTime? entryTime; // [35-3B] 进站时间（BCD 合法时）
  final String? entryTimeBcd; // [35-3B] 进站时间 BCD 原始 14 位数字串
  final DateTime? exitTime; // [3C-42] 出站时间（BCD 合法时）
  final String? exitTimeBcd; // [3C-42] 出站时间 BCD 原始 14 位数字串
  final int? annotateAmountFen; // [43-46] 标注金额（分）
  final int? entryLineCode; // [47] 入站线路号
  final int? exitLineCode; // [48] 出站线路号
  final int? entryAmountFen; // [49-4C] 进站交易金额（分）
  final int? entryBalanceFen; // [4D-50] 进站钱包余额（分）
  final int? exitAmountFen; // [51-54] 出站交易金额（分）

  /// 交易金额（分）：当前布局无独立字段，解析时保持 null（兼容保留）。
  final int? transactionAmountFen;

  /// 字段体原始字节 HEX（详情页原始数据展示 / 重解析依据）。
  final String? rawHex;

  // 动态线路数据库预留：解析层不填充，由线路库二次解码后展示。
  final String? entryStationName; // 进闸站点名称
  final String? exitStationName; // 出闸站点名称
  final String? lineName; // 线路名称

  const TransitRecord({
    required this.statusCode,
    this.issuerCustom,
    this.entryCityCode,
    this.exitCityCode,
    this.entryAgencyId,
    this.exitAgencyId,
    this.entryStationId,
    this.exitStationId,
    this.entryTerminalId,
    this.exitTerminalId,
    this.entryTime,
    this.entryTimeBcd,
    this.exitTime,
    this.exitTimeBcd,
    this.annotateAmountFen,
    this.entryLineCode,
    this.exitLineCode,
    this.entryAmountFen,
    this.entryBalanceFen,
    this.exitAmountFen,
    this.transactionAmountFen,
    this.rawHex,
    this.entryStationName,
    this.exitStationName,
    this.lineName,
  });

  /// 交易状态名称（仅收录实测取值，其余显式标注未知）。
  String get statusName =>
      _statusNames[statusCode] ??
      '未知(0x${statusCode.toRadixString(16).padLeft(2, '0').toUpperCase()})';

  String? get entryAmountText => _fenText(entryAmountFen);

  String? get exitAmountText => _fenText(exitAmountFen);

  String? get transactionAmountText => _fenText(transactionAmountFen);

  static String? _fenText(int? fen) =>
      fen == null ? null : '${(fen / 100).toStringAsFixed(2)} 元';

  static const _statusNames = <int, String>{
    0x00: '初始值',
    0x01: '进闸',
    0x02: '出闸',
  };
}

/// 0x1A 记录 2（公共汽电车应用信息记录，88 字节）解码结果。
///
/// 字段顺序与项目需求给定的目标输出格式一致，字节偏移按其逐字段排定：
/// [00] 交易状态　[01-02] 上车城市代码　[03-0A] 上车机构标识
/// [0B-0C] 上车运营商代码　[0D-0E] 上车线路号　[0F] 上车站点
/// [10-17] 上车车辆号　[18-1F] 上车终端编号
/// [20-26] 上车时间（BCD YYYYMMDDhhmmss）　[27-2A] 标注金额
/// [2B] 方向标识　[2C-2D] 下车城市代码　[2E-35] 下车机构标识
/// [36-37] 下车运营商代码　[38-39] 下车线路号　[3A] 下车站点
/// [3B-42] 下车车辆号　[43-4A] 下车终端编号
/// [4B-51] 下车时间（BCD）　[52-55] 交易金额　[56-57] 乘车里程。
class BusTransitRecord {
  final int statusCode; // [00] 交易状态（0x00 初始值）

  /// 是否携带 14 字节记录头（完整格式 27 02，专家模式结构核对用）。
  final bool hasRecordHeader;

  /// 记录体标准长度之外的发卡机构自定义数据（HEX）；未写入时为 null。
  final String? issuerCustomHex;

  final String? entryCityCode; // [01-02] 上车城市代码（HEX）
  final String? entryAgencyId; // [03-0A] 上车机构标识（HEX）
  final String? entryOperatorCode; // [0B-0C] 上车运营商代码（HEX）
  final String? entryLineCode; // [0D-0E] 上车线路号（HEX）
  final String? entryStationCode; // [0F] 上车站点（HEX）
  final String? entryVehicleId; // [10-17] 上车车辆号（HEX）
  final String? entryTerminalId; // [18-1F] 上车终端编号（HEX）
  final DateTime? entryTime; // [20-26] 上车时间（BCD 合法时）
  final String? entryTimeBcd; // [20-26] 上车时间 BCD 原始 14 位数字串
  final int? annotateAmountFen; // [27-2A] 标注金额（分）
  final int? directionCode; // [2B] 方向标识
  final String? exitCityCode; // [2C-2D] 下车城市代码（HEX）
  final String? exitAgencyId; // [2E-35] 下车机构标识（HEX）
  final String? exitOperatorCode; // [36-37] 下车运营商代码（HEX）
  final String? exitLineCode; // [38-39] 下车线路号（HEX）
  final String? exitStationCode; // [3A] 下车站点（HEX）
  final String? exitVehicleId; // [3B-42] 下车车辆号（HEX）
  final String? exitTerminalId; // [43-4A] 下车终端编号（HEX）
  final DateTime? exitTime; // [4B-51] 下车时间（BCD 合法时）
  final String? exitTimeBcd; // [4B-51] 下车时间 BCD 原始 14 位数字串
  final int? transactionAmountFen; // [52-55] 交易金额（分）
  final int? mileage; // [56-57] 乘车里程

  /// 记录体原始字节 HEX（详情页原始数据展示 / 重解析依据）。
  final String? rawHex;
  const BusTransitRecord({
    required this.statusCode,
    this.hasRecordHeader = false,
    this.issuerCustomHex,
    this.rawHex,
    this.entryCityCode,
    this.entryAgencyId,
    this.entryOperatorCode,
    this.entryLineCode,
    this.entryStationCode,
    this.entryVehicleId,
    this.entryTerminalId,
    this.entryTime,
    this.entryTimeBcd,
    this.annotateAmountFen,
    this.directionCode,
    this.exitCityCode,
    this.exitAgencyId,
    this.exitOperatorCode,
    this.exitLineCode,
    this.exitStationCode,
    this.exitVehicleId,
    this.exitTerminalId,
    this.exitTime,
    this.exitTimeBcd,
    this.transactionAmountFen,
    this.mileage,
  });

  /// 交易状态名称（公交记录仅收录实测确认的初始值，其余显式标注未知，
  /// 不套用轨道记录的"进闸 / 出闸"取值表——避免猜测）。
  String get statusName =>
      _statusNames[statusCode] ??
      '未知(0x${statusCode.toRadixString(16).padLeft(2, '0').toUpperCase()})';

  /// 方向标识名称（标准表未收录取值时显式"未知方向"）。
  String get directionName => _directionNames[directionCode] ?? '未知方向';

  /// 是否读取到有效的发卡机构自定义数据（标准记录体之后的尾部字节）：
  /// 未写入（null / 空）或整段为 0x00 / 0xFF（擦除态）时视为未读取到
  /// 有效信息，展示层据此隐藏该字段（与轨道记录口径一致）。
  bool get hasIssuerCustomData {
    final hex = issuerCustomHex?.replaceAll(RegExp(r'\s'), '');
    if (hex == null || hex.length < 2) return false;
    for (var i = 0; i + 1 < hex.length; i += 2) {
      final byte = hex.substring(i, i + 2).toUpperCase();
      if (byte != '00' && byte != 'FF') return true;
    }
    return false;
  }

  static const _statusNames = <int, String>{0x00: '初始值'};

  static const _directionNames = <int, String>{0x01: '上行', 0x02: '下行'};
}
