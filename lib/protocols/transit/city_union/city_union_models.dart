import 'city_union_codec.dart';

/// City Union（CJ/T 331-2016）文件 SFI 登记。
///
/// 已接入解析器的文件在此登记；后续实现发行基本信息、城市轨道交通
/// 应用信息等文件时追加常量并挂接 CityUnionFileParser。
abstract final class CityUnionFileIds {
  /// 公共应用基本信息文件（表 5，二进制 0x1E=30 字节，读自由）。
  static const int publicBasicInfo = 0x15;

  /// 复合交易记录文件（表 6，循环记录文件；单条记录 48 字节，
  /// 由记录标识 0x09 + 数据长度 + 锁定标识 + 45 字节应用方自定义区组成）。
  static const int compositeTransaction = 0x17;

  /// 电子钱包本地消费交易明细记录文件（表 7，循环记录文件；
  /// 单条记录 0x17=23 字节，解析单元为单条记录而非整文件）。
  static const int walletLocalConsumption = 0x18;

  /// 电子钱包异地消费交易明细记录文件（表 8，循环记录文件；
  /// 单条记录 0x17=23 字节，字段布局与表 7 一致）。
  static const int walletOfflineTransaction = 0x19;

  /// 电子钱包充值交易明细记录文件（表 9，循环记录文件；
  /// 单条记录 0x17=23 字节，解析单元为单条记录而非整文件）。
  static const int walletRecharge = 0x1A;
}

/// 字段编码格式：BCD 按十进制半字节解码，HEX 按字节原样保留，
/// AUTO 为卡号类字段的自适应解码（BCD 优先，非 BCD 回退原始 HEX）。
enum CjFieldFormat { bcd, hex, auto }

/// 单个字段的解析结果：原始值、标准解码值与可读说明一起保留，
/// 字段级异常只标记本字段（原始字节始终保留在 [rawHex]）。
class CjField {
  /// 稳定标识（如 issuerCode），供 JSON 输出与按字段查询使用。
  final String key;

  /// 字段名（标准表格字段名，如 "发卡方代码"）。
  final String name;

  /// 文件内起始偏移（0 起，Dart 数组下标）。
  final int offset;

  /// 字节长度。
  final int length;

  /// 编码格式。
  final CjFieldFormat format;

  /// 原始值（空格分隔大写 HEX，逐字节核对）。
  final String rawHex;

  /// 标准解码值：BCD 为数字字符串（保留前导零，如 "0012"），
  /// HEX 为连续大写 HEX（如 "0A01"）；BCD 非法时为 null。
  final String? decoded;

  /// 可读说明（如 "已启用" / "与城市代码一致"）；无附加说明时为 null。
  final String? note;

  /// 字段级解析异常（"BCD 编码非法" / "日期非法"）；正常时为 null。
  final String? error;

  const CjField({
    required this.key,
    required this.name,
    required this.offset,
    required this.length,
    required this.format,
    required this.rawHex,
    this.decoded,
    this.note,
    this.error,
  });

  /// 是否存在解析异常。
  bool get hasError => error != null;

  /// 标准表格字节编号（1 起两位补零；多字节为 "01-02"，单字节为 "09"）。
  String get byteRange {
    final start = (offset + 1).toString().padLeft(2, '0');
    if (length == 1) return start;
    final end = (offset + length).toString().padLeft(2, '0');
    return '$start-$end';
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'name': name,
    'byteRange': byteRange,
    'format': switch (format) {
      CjFieldFormat.bcd => 'BCD',
      CjFieldFormat.hex => 'HEX',
      CjFieldFormat.auto => 'AUTO（BCD 优先，非 BCD 回退 HEX）',
    },
    'rawHex': rawHex,
    'decoded': decoded,
    'note': note,
    'error': error,
  };
}

/// City Union 文件解析结果的统一视图：[CityUnionFileParser] 按 SFI 分发后
/// 返回本接口，展示层只依赖本接口渲染原始值、解码值与异常信息。
abstract interface class CityUnionFileView {
  /// 来源文件 SFI。
  int get sfi;

  /// 文件名称（展示用）。
  String get fileLabel;

  /// 整文件原始字节（空格分隔大写 HEX）。
  String get rawHex;

  /// 字段级解析结果（原始值 / 解码值 / 说明 / 异常）。
  List<CjField> get fields;

  /// 解析异常汇总（逐字段汇总，正常时为空）。
  List<String> get errors;

  Map<String, dynamic> toJson();
}

/// CJ/T 331-2016 表 5：公共应用基本信息文件（SFI 0x15）解析结果。
///
/// 字段布局（字节编号按标准表格 1 起计数）：
/// - 01-02 发卡方代码（BCD）；03-04 城市代码（HEX）；05 多算法支持（BCD）；
/// - 06 行业代码（BCD）；07-08 预留；09 互联互通启用标识（00 未启用，
///   非 00 启用）；10 应用版本；11-12 互联互通标识；13-20 用户卡应用
///   序列号（8 字节原样保留）；
/// - 21-24 应用启动日期（BCD YYYYMMDD）；25-28 应用有效日期（BCD）；
/// - 29-30 预留。
///
/// 类型化字段为 null 表示该字段未解码出值（BCD 非法），此时原始数据与
/// 异常信息仍完整保留在 [fields] 对应条目中；日期非法时保留 BCD 解码
/// 数字串并标记异常（不猜测修正）。预留字段同样保留在 [fields] 与
/// [rawHex] 中，供原始数据与调试页面核对。
class CjT331PublicInfo implements CityUnionFileView {
  final String? issuerCode;
  final String? cityCode;
  final String? multiAlgorithmSupport;
  final String? industryCode;
  final String? reserved1;
  final String? interconnectionEnabled;
  final String? applicationVersion;
  final String? interconnectionId;

  /// 用户卡应用序列号（0x15 第 13-20 字节）解码结果：
  /// BCD 编码为纯数字串；非 BCD 编码为原始字节大写 HEX
  /// （如 "B921DCAD7E32EDA7"）；空 / 未写入时为 null。
  final String? applicationSerialNumber;

  final String? applicationStartDate;
  final String? applicationExpiryDate;
  final String? reserved2;

  @override
  final List<CjField> fields;

  @override
  final String rawHex;

  const CjT331PublicInfo({
    this.issuerCode,
    this.cityCode,
    this.multiAlgorithmSupport,
    this.industryCode,
    this.reserved1,
    this.interconnectionEnabled,
    this.applicationVersion,
    this.interconnectionId,
    this.applicationSerialNumber,
    this.applicationStartDate,
    this.applicationExpiryDate,
    this.reserved2,
    required this.fields,
    required this.rawHex,
  });

  @override
  int get sfi => CityUnionFileIds.publicBasicInfo;

  @override
  String get fileLabel => '公共应用基本信息文件';

  /// 互联互通启用标识：00 未启用，非 00 启用；字段缺失视为未启用。
  bool get isInterconnectionEnabled =>
      interconnectionEnabled != null && interconnectionEnabled != '00';

  /// 用户卡应用序列号原始字节（连续大写 HEX，无分隔符）。
  ///
  /// 指纹与历史档案比对必须使用本值：字段解码口径升级时指纹保持不变，
  /// 避免同一张卡产生重复档案。
  String? get applicationSerialNumberRawHex {
    for (final f in fields) {
      if (f.key == 'applicationSerialNumber') {
        return f.rawHex.replaceAll(' ', '');
      }
    }
    return applicationSerialNumber;
  }

  /// 展示用卡号：BCD 数字串不做前导 0 裁剪；填充位解码导致有效位不足
  /// 16 位时左补 0 恢复定长。非 BCD 的原始 HEX（固定 8 字节 = 16 字符）
  /// 原样返回，不按数字补零。
  String? get displayApplicationSerialNumber {
    final s = applicationSerialNumber;
    if (s == null || s.isEmpty) return null;
    if (!RegExp(r'^\d+$').hasMatch(s)) return s;
    return s.length < 16 ? s.padLeft(16, '0') : s;
  }

  @override
  List<String> get errors => [
    for (final f in fields)
      if (f.error != null) '${f.name}：${f.error}',
  ];

  @override
  Map<String, dynamic> toJson() => {
    'sfi': CityUnionCodec.sfiLabel(sfi),
    'fileLabel': fileLabel,
    'issuerCode': issuerCode,
    'cityCode': cityCode,
    'multiAlgorithmSupport': multiAlgorithmSupport,
    'industryCode': industryCode,
    'reserved1': reserved1,
    'interconnectionEnabled': interconnectionEnabled,
    'isInterconnectionEnabled': isInterconnectionEnabled,
    'applicationVersion': applicationVersion,
    'interconnectionId': interconnectionId,
    'applicationSerialNumber': applicationSerialNumber,
    'applicationStartDate': applicationStartDate,
    'applicationExpiryDate': applicationExpiryDate,
    'reserved2': reserved2,
    'rawHex': rawHex,
    'errors': errors,
    'fields': [for (final f in fields) f.toJson()],
  };
}

/// CJ/T 331-2016 表 6：复合交易记录文件（SFI 0x17）单条记录解析结果。
///
/// 本类型代表单条记录视图（非整文件）。记录外层结构（字节编号按标准
/// 表格 1 起计数）：
/// - 01 记录标识（标准值 0x09，解析时已校验）；
/// - 02 复合消费数据长度（HEX 原值；计数规则表 6 未说明）；
/// - 03 复合消费锁定标识（HEX，0x00 允许 / 非 0x00 禁止）；
/// - 04-48 应用方自定义（45 字节）。
///
/// 表 6 未定义 45 字节应用方自定义区的内部结构，[applicationData] 与
/// [rawData] 原样保留（不猜测金额、时间、终端编号等字段）。锁定标识
/// 非 00 属于有效状态（禁止）而非解析异常；外层字段均为 HEX 编码，
/// [errors] 正常时为空。
class CjT331CompositeTransaction implements CityUnionFileView {
  /// 字节01：记录标识（标准值 0x09）。
  final int recordIdentifier;

  /// 字节02：复合消费数据长度（HEX 原值）。
  final int dataLength;

  /// 字节03：复合消费锁定标识（0x00 允许，非 0x00 禁止）。
  final int lockFlag;

  /// 字节04-48：应用方自定义数据（45 字节，内部结构未在表 6 定义）。
  final List<int> applicationData;

  /// 完整 48 字节原始记录（含记录标识、长度与锁定标识字节）。
  final List<int> rawData;

  @override
  final List<CjField> fields;

  const CjT331CompositeTransaction({
    required this.recordIdentifier,
    required this.dataLength,
    required this.lockFlag,
    required this.applicationData,
    required this.rawData,
    required this.fields,
  });

  @override
  int get sfi => CityUnionFileIds.compositeTransaction;

  @override
  String get fileLabel => '复合交易记录文件';

  /// 复合消费锁定标识：00 允许；非 00 禁止。
  bool get isConsumptionAllowed => lockFlag == 0x00;

  /// 锁定状态描述（"允许" / "禁止"）。
  String get lockStatus => isConsumptionAllowed ? '允许' : '禁止';

  /// 记录标识 HEX（记录标识非法时解析器已抛异常，此处固定为 "09"）。
  String get recordIdentifierHex => CityUnionCodec.hexByte(recordIdentifier);

  /// 复合消费数据长度 HEX（如 "2D"）。
  String get dataLengthHex => CityUnionCodec.hexByte(dataLength);

  /// 复合消费锁定标识 HEX（如 "00"）。
  String get lockFlagHex => CityUnionCodec.hexByte(lockFlag);

  /// 应用方自定义数据 HEX（45 字节连续大写）。
  String get applicationDataHex => CityUnionCodec.hex(applicationData);

  @override
  String get rawHex => CityUnionCodec.hexSpaced(rawData);

  /// 数据长度字段的容量检查：不超过应用方自定义区（45 字节）时为 true。
  /// 表 6 未说明该长度的计数规则（是否含自身 / 锁定标识等），
  /// 仅对照自定义区容量核对，不据此解释或修正数据长度含义。
  bool get dataLengthWithinCustomArea => dataLength <= applicationData.length;

  @override
  List<String> get errors => [
    for (final f in fields)
      if (f.error != null) '${f.name}：${f.error}',
  ];

  @override
  Map<String, dynamic> toJson() => {
    'sfi': CityUnionCodec.sfiLabel(sfi),
    'fileLabel': fileLabel,
    'recordIdentifier': recordIdentifierHex,
    'dataLength': dataLength,
    'dataLengthHex': dataLengthHex,
    'lockFlag': lockFlagHex,
    'lockStatus': lockStatus,
    'isConsumptionAllowed': isConsumptionAllowed,
    'applicationDataLength': applicationData.length,
    'applicationDataHex': applicationDataHex,
    'dataLengthWithinCustomArea': dataLengthWithinCustomArea,
    'rawHex': rawHex,
    'errors': errors,
    'fields': [for (final f in fields) f.toJson()],
  };
}

/// CJ/T 331-2016 表 8：电子钱包异地消费交易明细记录文件（SFI 0x19）
/// 单条记录解析结果。
///
/// 本类型代表单条记录视图（非整文件）。该文件为循环记录文件，单条记录
/// 长度 0x17（23 字节），标准要求至少容纳 10 条异地消费交易记录；读取
/// 层必须按记录逐条获取（READ RECORD），不能把文件当作连续交易数组
/// 切分，也不假定记录 1 是最新交易。
///
/// 字段布局（字节编号按标准表格 1 起计数）：
/// - 01-02 电子钱包消费交易序号（HEX 大端无符号整数）；
/// - 03-05 预留（HEX 原样保留）；
/// - 06-09 交易金额（HEX 大端原始值；表 8 未定义金额单位与小数位，
///   只保留原始值与十进制大端值，不擅自换算为元）；
/// - 10 交易类型（HEX：06 消费 / 09 复合消费）；
/// - 11-16 交易终端编号（BCD 12 位数字，保留前导零）；
/// - 17-20 交易日期（BCD YYYYMMDD）；21-23 交易时间（BCD HHMMSS）。
///
/// 金额字段是 HEX 而非 BCD（不能按半字节十进制解码）；终端编号是 BCD
/// 而非 HEX（必须保留 12 位数字前导零）。BCD / 日期 / 时间非法时类型化
/// 字段为 null（日期 / 时间非法保留 BCD 数字串），异常标记在 [fields]
/// 对应条目上，其他字段照常解析。
class CjT331WalletOfflineTransaction implements CityUnionFileView {
  /// 字节01-02：电子钱包消费交易序号（HEX 大端解码值）。
  final int sequence;

  /// 字节01-02：交易序号 HEX 原始值（4 位大写，如 "0001"）。
  final String sequenceHex;

  /// 字节03-05：预留字段（连续大写 HEX；表 8 未定义内容，原样保留）。
  final String reservedHex;

  /// 字节06-09：交易金额 HEX 大端解码值（金额单位未定义，不换算）。
  final int amountRaw;

  /// 字节06-09：交易金额 HEX 原始值（8 位大写，如 "000003E8"）。
  final String amountHex;

  /// 字节10：交易类型原始值（0x06 消费 / 0x09 复合消费）。
  final int transactionType;

  /// 字节11-16：交易终端编号（BCD 12 位数字，保留前导零）；
  /// BCD 非法时为 null。
  final String? terminalNumber;

  /// 字节17-20：交易日期（BCD）；合法时为 "YYYY-MM-DD"，日期非法时
  /// 保留 BCD 数字串并标记异常（不猜测修正），BCD 非法时为 null。
  final String? transactionDate;

  /// 字节21-23：交易时间（BCD）；合法时为 "HH:MM:SS"，时刻非法时
  /// 保留 BCD 数字串并标记异常（不猜测修正），BCD 非法时为 null。
  final String? transactionTime;

  @override
  final List<CjField> fields;

  @override
  final String rawHex;

  const CjT331WalletOfflineTransaction({
    required this.sequence,
    required this.sequenceHex,
    required this.reservedHex,
    required this.amountRaw,
    required this.amountHex,
    required this.transactionType,
    this.terminalNumber,
    this.transactionDate,
    this.transactionTime,
    required this.fields,
    required this.rawHex,
  });

  @override
  int get sfi => CityUnionFileIds.walletOfflineTransaction;

  @override
  String get fileLabel => '电子钱包异地消费交易明细记录文件';

  /// 交易类型 HEX 原始值（如 "06"）。
  String get transactionTypeHex => CityUnionCodec.hexByte(transactionType);

  /// 交易类型名称：06 消费 / 09 复合消费 / 其他未知类型。
  String get transactionTypeName => transactionTypeLabel(transactionType);

  /// 交易类型取值 → 名称映射（解析层字段说明共用，保持单一来源）。
  static String transactionTypeLabel(int type) => switch (type) {
    0x06 => '消费',
    0x09 => '复合消费',
    _ => '未知类型',
  };

  @override
  List<String> get errors => [
    for (final f in fields)
      if (f.error != null) '${f.name}：${f.error}',
  ];

  @override
  Map<String, dynamic> toJson() => {
    'sfi': CityUnionCodec.sfiLabel(sfi),
    'fileLabel': fileLabel,
    'sequence': sequence,
    'sequenceHex': sequenceHex,
    'reservedHex': reservedHex,
    'amountRaw': amountRaw,
    'amountHex': amountHex,
    'transactionType': transactionTypeHex,
    'transactionTypeName': transactionTypeName,
    'terminalNumber': terminalNumber,
    'transactionDate': transactionDate,
    'transactionTime': transactionTime,
    'rawHex': rawHex,
    'errors': errors,
    'fields': [for (final f in fields) f.toJson()],
  };
}

/// CJ/T 331-2016 表 7：电子钱包本地消费交易明细记录文件（SFI 0x18）
/// 单条记录解析结果。
///
/// 本类型代表单条记录视图（非整文件）。该文件为循环记录文件，单条记录
/// 长度 0x17（23 字节）；读取层必须按记录逐条获取（READ RECORD），
/// 不能把文件当作连续交易数组切分，也不假定记录 1 是最新交易。
///
/// 字段布局（字节编号按标准表格 1 起计数）：
/// - 01-02 电子钱包消费交易序号（HEX 大端无符号整数）；
/// - 03-05 预留（HEX 原样保留）；
/// - 06-09 交易金额（HEX 大端原始值；表 7 未定义金额单位与小数位，
///   只保留原始值与十进制大端值，不擅自换算为元）；
/// - 10 交易类型（HEX：06 消费 / 09 复合消费）；
/// - 11-16 交易终端编号（BCD 12 位数字，保留前导零）；
/// - 17-20 交易日期（BCD YYYYMMDD）；21-23 交易时间（BCD HHMMSS）。
///
/// 金额字段是 HEX 而非 BCD（不能按半字节十进制解码）；终端编号是 BCD
/// 而非 HEX（必须保留 12 位数字前导零）。BCD / 日期 / 时间非法时类型化
/// 字段为 null（日期 / 时间非法保留 BCD 数字串），异常标记在 [fields]
/// 对应条目上，其他字段照常解析。
class CjT331WalletLocalConsumption implements CityUnionFileView {
  /// 字节01-02：电子钱包消费交易序号（HEX 大端解码值）。
  final int sequence;

  /// 字节01-02：交易序号 HEX 原始值（4 位大写，如 "0001"）。
  final String sequenceHex;

  /// 字节03-05：预留字段（连续大写 HEX；表 7 未定义内容，原样保留）。
  final String reservedHex;

  /// 字节06-09：交易金额 HEX 大端解码值（金额单位未定义，不换算）。
  final int amountRaw;

  /// 字节06-09：交易金额 HEX 原始值（8 位大写，如 "000003E8"）。
  final String amountHex;

  /// 字节10：交易类型原始值（0x06 消费 / 0x09 复合消费）。
  final int transactionType;

  /// 字节11-16：交易终端编号（BCD 12 位数字，保留前导零）；
  /// BCD 非法时为 null。
  final String? terminalNumber;

  /// 字节17-20：交易日期（BCD）；合法时为 "YYYY-MM-DD"，日期非法时
  /// 保留 BCD 数字串并标记异常（不猜测修正），BCD 非法时为 null。
  final String? transactionDate;

  /// 字节21-23：交易时间（BCD）；合法时为 "HH:MM:SS"，时刻非法时
  /// 保留 BCD 数字串并标记异常（不猜测修正），BCD 非法时为 null。
  final String? transactionTime;

  @override
  final List<CjField> fields;

  @override
  final String rawHex;

  const CjT331WalletLocalConsumption({
    required this.sequence,
    required this.sequenceHex,
    required this.reservedHex,
    required this.amountRaw,
    required this.amountHex,
    required this.transactionType,
    this.terminalNumber,
    this.transactionDate,
    this.transactionTime,
    required this.fields,
    required this.rawHex,
  });

  @override
  int get sfi => CityUnionFileIds.walletLocalConsumption;

  @override
  String get fileLabel => '电子钱包本地消费交易明细记录文件';

  /// 交易类型 HEX 原始值（如 "06"）。
  String get transactionTypeHex => CityUnionCodec.hexByte(transactionType);

  /// 交易类型名称：06 消费 / 09 复合消费 / 其他未知类型。
  String get transactionTypeName => transactionTypeLabel(transactionType);

  /// 交易类型取值 → 名称映射（解析层字段说明共用，保持单一来源）。
  static String transactionTypeLabel(int type) => switch (type) {
    0x06 => '消费',
    0x09 => '复合消费',
    _ => '未知类型',
  };

  @override
  List<String> get errors => [
    for (final f in fields)
      if (f.error != null) '${f.name}：${f.error}',
  ];

  @override
  Map<String, dynamic> toJson() => {
    'sfi': CityUnionCodec.sfiLabel(sfi),
    'fileLabel': fileLabel,
    'sequence': sequence,
    'sequenceHex': sequenceHex,
    'reservedHex': reservedHex,
    'amountRaw': amountRaw,
    'amountHex': amountHex,
    'transactionType': transactionTypeHex,
    'transactionTypeName': transactionTypeName,
    'terminalNumber': terminalNumber,
    'transactionDate': transactionDate,
    'transactionTime': transactionTime,
    'rawHex': rawHex,
    'errors': errors,
    'fields': [for (final f in fields) f.toJson()],
  };
}

/// CJ/T 331-2016 表 9：电子钱包充值交易明细记录文件（SFI 0x1A）
/// 单条记录解析结果。
///
/// 本类型代表单条记录视图（非整文件）。该文件为循环记录文件，单条记录
/// 长度 0x17（23 字节）；读取层必须按记录逐条获取（READ RECORD），
/// 不能把文件当作连续交易数组切分，也不假定记录 1 是最新交易。
///
/// 字段布局（字节编号按标准表格 1 起计数）：
/// - 01-02 电子钱包充值交易序号（HEX 大端无符号整数）；
/// - 03-05 预留（HEX 原样保留）；
/// - 06-09 交易金额（HEX 大端原始值；表 9 未定义金额单位与小数位，
///   只保留原始值与十进制大端值，不擅自换算为元）；
/// - 10 交易类型（HEX：02 充值）；
/// - 11-16 交易终端编号（BCD 12 位数字，保留前导零）；
/// - 17-20 交易日期（BCD YYYYMMDD）；21-23 交易时间（BCD HHMMSS）。
///
/// 金额字段是 HEX 而非 BCD（不能按半字节十进制解码）；终端编号是 BCD
/// 而非 HEX（必须保留 12 位数字前导零）。BCD / 日期 / 时间非法时类型化
/// 字段为 null（日期 / 时间非法保留 BCD 数字串），异常标记在 [fields]
/// 对应条目上，其他字段照常解析。
class CjT331WalletRecharge implements CityUnionFileView {
  /// 字节01-02：电子钱包充值交易序号（HEX 大端解码值）。
  final int sequence;

  /// 字节01-02：充值交易序号 HEX 原始值（4 位大写，如 "0001"）。
  final String sequenceHex;

  /// 字节03-05：预留字段（连续大写 HEX；表 9 未定义内容，原样保留）。
  final String reservedHex;

  /// 字节06-09：交易金额 HEX 大端解码值（金额单位未定义，不换算）。
  final int amountRaw;

  /// 字节06-09：交易金额 HEX 原始值（8 位大写，如 "000003E8"）。
  final String amountHex;

  /// 字节10：交易类型原始值（0x02 充值）。
  final int transactionType;

  /// 字节11-16：交易终端编号（BCD 12 位数字，保留前导零）；
  /// BCD 非法时为 null。
  final String? terminalNumber;

  /// 字节17-20：交易日期（BCD）；合法时为 "YYYY-MM-DD"，日期非法时
  /// 保留 BCD 数字串并标记异常（不猜测修正），BCD 非法时为 null。
  final String? transactionDate;

  /// 字节21-23：交易时间（BCD）；合法时为 "HH:MM:SS"，时刻非法时
  /// 保留 BCD 数字串并标记异常（不猜测修正），BCD 非法时为 null。
  final String? transactionTime;

  @override
  final List<CjField> fields;

  @override
  final String rawHex;

  const CjT331WalletRecharge({
    required this.sequence,
    required this.sequenceHex,
    required this.reservedHex,
    required this.amountRaw,
    required this.amountHex,
    required this.transactionType,
    this.terminalNumber,
    this.transactionDate,
    this.transactionTime,
    required this.fields,
    required this.rawHex,
  });

  @override
  int get sfi => CityUnionFileIds.walletRecharge;

  @override
  String get fileLabel => '电子钱包充值交易明细记录文件';

  /// 是否为充值交易（表 9 规定 0x02 为充值）。
  bool get isRecharge => transactionType == 0x02;

  /// 交易类型 HEX 原始值（如 "02"）。
  String get transactionTypeHex => CityUnionCodec.hexByte(transactionType);

  /// 交易类型名称：02 充值 / 其他未知类型（保留原始记录便于排查）。
  String get transactionTypeName => transactionTypeLabel(transactionType);

  /// 交易类型取值 → 名称映射（解析层字段说明共用，保持单一来源）。
  static String transactionTypeLabel(int type) => switch (type) {
    0x02 => '充值',
    _ => '未知类型',
  };

  @override
  List<String> get errors => [
    for (final f in fields)
      if (f.error != null) '${f.name}：${f.error}',
  ];

  @override
  Map<String, dynamic> toJson() => {
    'sfi': CityUnionCodec.sfiLabel(sfi),
    'fileLabel': fileLabel,
    'sequence': sequence,
    'sequenceHex': sequenceHex,
    'reservedHex': reservedHex,
    'amountRaw': amountRaw,
    'amountHex': amountHex,
    'transactionType': transactionTypeHex,
    'transactionTypeName': transactionTypeName,
    'isRecharge': isRecharge,
    'terminalNumber': terminalNumber,
    'transactionDate': transactionDate,
    'transactionTime': transactionTime,
    'rawHex': rawHex,
    'errors': errors,
    'fields': [for (final f in fields) f.toJson()],
  };
}

/// 未接入解析器的 SFI 原始视图：仅保留原始字节与提示，不猜测字段布局。
class CityUnionRawFileView implements CityUnionFileView {
  @override
  final int sfi;

  @override
  final String rawHex;

  @override
  final List<CjField> fields = const [];

  @override
  final List<String> errors;

  CityUnionRawFileView({
    required this.sfi,
    required List<int> raw,
    String? reason,
  }) : rawHex = CityUnionCodec.hexSpaced(raw),
       errors = [reason ?? '${CityUnionCodec.sfiLabel(sfi)} 尚未接入解析器，仅保留原始数据'];

  @override
  String get fileLabel => '未接入文件（${CityUnionCodec.sfiLabel(sfi)}）';

  @override
  Map<String, dynamic> toJson() => {
    'sfi': CityUnionCodec.sfiLabel(sfi),
    'fileLabel': fileLabel,
    'rawHex': rawHex,
    'errors': errors,
    'fields': const <Map<String, dynamic>>[],
  };
}
