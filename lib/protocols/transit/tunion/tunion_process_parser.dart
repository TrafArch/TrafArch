import 'tunion_codec.dart';
import 'tunion_models.dart';

/// 公共交通过程信息记录解析器（解析层）。
///
/// 与读取流程（TUnionParser）解耦：只接收原始记录字节、产出结构化模型，
/// 不感知 APDU 交互；字节编解码统一走 [TUnionCodec]。
///
/// 覆盖两类文件：
/// - SFI 0x1E 公共交通过程信息循环记录（48 字节定长，[parseCycleTrip]）；
/// - SFI 0x1A 公共交通过程信息变长记录（记录 1 [parseRailTransit] /
///   记录 2 [parseBusTransit]）。
///
/// 真机兼容（对齐 0x18 交易明细的实测行为）：
/// - 记录内容被 70 记录模板（TLV）包裹时，先剥离模板再解析（支持多层嵌套）；
/// - 0x1A 记录 1 存在 128 字节完整格式（27 记录号 7D 记录头 + 85 字节
///   字段体 + 29 字节发卡机构自定义），自动识别记录头并按字段体偏移解析；
///   发卡机构自定义全 0x00 / 0xFF（未读取到有效信息）时不产出；
/// - 记录短于标准布局（85 / 88 字节）时，按实际可用字节解析，
///   越界字段保持 null（不截断取值、不猜测）。
///
/// 设计原则：字段布局必须有实测数据依据；无依据时返回 null，
/// 原始数据由调用方完整保留（不猜测字段值）。
class TUnionProcessParser {
  const TUnionProcessParser();

  /// 剥离 70 模板后仍短于该长度的记录视为无效，返回 null（不猜测）。
  static const _minRecordLength = 0x10;

  /// 0x1A 记录 1（城市轨道应用信息记录）字段体标准长度：85 字节。
  static const _railBodyLength = 0x55;

  /// 完整格式记录头长度：记录 ID（27）+ 记录号 + 记录长度 + 应用有效
  /// 标识 + 互联互通交易标识 + 应用锁定标志 + 交易流水号（8 字节）。
  static const _railHeaderLength = 0x0E;

  /// 完整格式记录长度字段值：0x7D = 记录总长 128 − 3（记录 ID / 记录号 /
  /// 长度字段自身）。
  static const _railRecordLengthField = 0x7D;

  /// 完整格式记录尾部发卡机构自定义数据长度：29 字节。
  static const _railIssuerCustomLength = 0x1D;

  /// 0x1A 记录 2（公共汽电车应用信息记录）标准长度：88 字节。
  static const _busRecordLength = 88;

  /// 0x1A 记录 2 记录头长度：14 字节。
  /// [0-1] 记录标识 27 02　[2] 记录长度（自 [3] 起计数，标准值 0x7D）
  /// [3] 应用有效标识　[4] 互联互通交易标识　[5] 应用锁定标志
  /// [6-13] 交易流水号（BCD）。记录体布局不因记录头而改变。
  static const _busRecordHeaderLength = 14;

  /// 解码 0x1E 公共交通过程信息循环记录（48 字节）。
  ///
  /// 字段布局按 JT/T 978.2 公共交通过程信息交易记录排定，并经社区开源
  /// 读卡实现（T-Union Master / NekoCardReader）实测交叉验证：
  /// [00] 交易类型（标准表 0x01~0x0A）　[01-08] 终端编号（BCD 16 位）
  /// [09] 应用分类码　[0A-0B] 线路代码　[0C-0D] 站点代码　[0E-0F] 运营代码
  /// [10] 预留字段　[11-14] 交易金额（大端，分）　[15-18] 记录余额（大端，分）
  /// [19-1F] 交易日期时间（BCD YYYYMMDDhhmmss）　[20-21] 受理方城市代码（HEX）
  /// [22-29] 受理方机构标识（HEX）　[2A-2F] 预留字段。
  ///
  /// 记录过短（< 32 字节）、未写入（首字节 0x00 / 0xFF）或时间非法时
  /// 返回 null（保持未知，不猜测）。
  TUnionTripRecord? parseCycleTrip(List<int> data) {
    data = _unwrapRecordTemplate(data) ?? data;
    if (data.length < 0x20) return null;
    final typeCode = data[0];
    if (typeCode == 0x00 || typeCode == 0xFF) return null;
    final time = TUnionCodec.parseBcdDateTime(data.sublist(0x19, 0x20));
    if (time == null) return null;
    return TUnionTripRecord(
      typeCode: typeCode,
      terminalId:
          TUnionCodec.bcdString(data.sublist(0x01, 0x09)) ??
          TUnionCodec.hexBytes(data.sublist(0x01, 0x09)) ??
          '',
      appTypeCode: data[0x09],
      lineStationCode:
          TUnionCodec.bcdString(data.sublist(0x0A, 0x11)) ??
          TUnionCodec.hexBytes(data.sublist(0x0A, 0x11)) ??
          '',
      amountFen: TUnionCodec.beInt(data, 0x11, 4),
      balanceFen: TUnionCodec.beInt(data, 0x15, 4),
      time: time,
      cityCode: data.length >= 0x22
          ? TUnionCodec.hexBytes(data.sublist(0x20, 0x22))
          : null,
      acquirerId: data.length >= 0x2A
          ? TUnionCodec.hexBytes(data.sublist(0x22, 0x2A))
          : null,
      rawHex: TUnionCodec.hexBytes(data),
    );
  }

  /// 解码 0x1A 记录 1（城市轨道应用信息记录）。
  ///
  /// 支持裸字段体（85 字节）与 128 字节完整格式两种真机写入形态，字段体
  /// 布局一致。字段布局按项目需求给定的目标输出格式逐字段排定（按样例
  /// 数据逐字段核对；真机如有字节差异以原始数据为准，仅需调整偏移常量）：
  /// [00] 交易状态　[01-02] 进闸城市代码　[03-04] 出闸城市代码
  /// [05-0C] 进闸机构标识　[0D-14] 出闸机构标识　[15-1C] 进闸站点
  /// [1D-24] 出闸站点　[25-2C] 进闸终端编号　[2D-34] 出闸终端编号
  /// [35-3B] 进站时间（BCD）　[3C-42] 出站时间（BCD）　[43-46] 标注金额
  /// （部分规范文本记为“不完整交易补扣金额”，同一字节段）
  /// [47] 入站线路号　[48] 出站线路号　[49-4C] 进站交易金额
  /// [4D-50] 进站钱包余额　[51-54] 出站交易金额。
  ///
  /// 128 字节完整格式：27 记录头（[00] 记录 ID 27　[01] 记录号
  /// [02] 记录长度 7D　[03] 应用有效标识　[04] 互联互通交易标识
  /// [05] 应用锁定标志　[06-0D] 交易流水号）+ 字段体（[0E-62]，偏移同
  /// 裸字段体）+ 发卡机构自定义（[63-7F]）；记录头仅用于识别完整格式并
  /// 后移字段体偏移（不产出头部字段）。金额口径与 0x18 / 0x1E / 余额
  /// 一致（分），展示层 ÷100 后为人民币元；发卡机构自定义全 0x00 / 0xFF
  /// （未读取到有效信息）时不产出。
  ///
  /// 真机兼容：记录被 70 记录模板包裹时先剥离；首字节为 0x27 但记录头
  /// 不合法（长度字段非 7D / 记录号不匹配）时返回 null（不按错位偏移
  /// 猜测字段值，原始数据由调用方保留）；不足标准长度时按可用字节解析，
  /// 越界字段保持 null（不猜测；原始数据由调用方保留）。
  TransitRecord? parseRailTransit(int recordNumber, List<int> data) {
    // 仅记录 1 承载城市轨道进出站配对信息；其余记录不产出 TransitRecord。
    if (recordNumber != 1) return null;
    final payload = _unwrapRecordTemplate(data) ?? data;
    if (payload.length < _minRecordLength) return null;

    // 完整格式记录头：27 <记录号> 7D，仅用于识别完整格式并后移字段体偏移。
    var base = 0;
    if (payload[0] == 0x27) {
      if (payload[1] != recordNumber || payload[2] != _railRecordLengthField) {
        return null;
      }
      base = _railHeaderLength;
    }

    final entryTimeBytes = _slice(payload, base + 0x35, base + 0x3C);
    final exitTimeBytes = _slice(payload, base + 0x3C, base + 0x43);
    return TransitRecord(
      statusCode: payload[base],
      issuerCustom: _issuerCustomAt(payload, base),
      entryCityCode: _hexAt(payload, base + 0x01, 2),
      exitCityCode: _hexAt(payload, base + 0x03, 2),
      entryAgencyId: _hexAt(payload, base + 0x05, 8),
      exitAgencyId: _hexAt(payload, base + 0x0D, 8),
      entryStationId: _hexAt(payload, base + 0x15, 8),
      exitStationId: _hexAt(payload, base + 0x1D, 8),
      entryTerminalId: _hexAt(payload, base + 0x25, 8),
      exitTerminalId: _hexAt(payload, base + 0x2D, 8),
      entryTime: entryTimeBytes == null
          ? null
          : TUnionCodec.parseBcdDateTime(entryTimeBytes),
      entryTimeBcd: entryTimeBytes == null
          ? null
          : TUnionCodec.bcdString(entryTimeBytes),
      exitTime: exitTimeBytes == null
          ? null
          : TUnionCodec.parseBcdDateTime(exitTimeBytes),
      exitTimeBcd: exitTimeBytes == null
          ? null
          : TUnionCodec.bcdString(exitTimeBytes),
      annotateAmountFen: _beIntAt(payload, base + 0x43, 4),
      entryLineCode: _byteAt(payload, base + 0x47),
      exitLineCode: _byteAt(payload, base + 0x48),
      entryAmountFen: _beIntAt(payload, base + 0x49, 4),
      entryBalanceFen: _beIntAt(payload, base + 0x4D, 4),
      exitAmountFen: _beIntAt(payload, base + 0x51, 4),
      rawHex: TUnionCodec.hexBytes(payload),
    );
  }

  /// 完整格式记录尾部发卡机构自定义数据（字段体后固定 29 字节）；
  /// 仅完整格式（base 非 0，字段体外的字节可按记录头归属本记录）且写满
  /// 29 字节时产出，否则返回 null（不截断、不越界读取下一条记录）；
  /// 全 0x00 / 0xFF（未写入 / 擦除态）视为未读取到有效信息，返回 null。
  static String? _issuerCustomAt(List<int> d, int base) {
    if (base == 0) return null;
    final start = base + _railBodyLength;
    final end = start + _railIssuerCustomLength;
    if (d.length < end) return null;
    return _customHexOrNull(d.sublist(start, end));
  }

  /// 自定义区字节转 HEX；全 0x00 / 0xFF（未读取到有效信息）返回 null，
  /// 展示层据此不展示该字段。
  static String? _customHexOrNull(List<int> bytes) =>
      bytes.every((b) => b == 0x00 || b == 0xFF)
      ? null
      : TUnionCodec.hexBytes(bytes);

  /// 解码 0x1A 记录 2（公共汽电车应用信息记录，标准 88 字节）。
  ///
  /// 字段布局按项目需求给定的目标输出格式逐字段排定：
  /// [00] 交易状态　[01-02] 上车城市代码　[03-0A] 上车机构标识
  /// [0B-0C] 上车运营商代码　[0D-0E] 上车线路号　[0F] 上车站点
  /// [10-17] 上车车辆号　[18-1F] 上车终端编号　[20-26] 上车时间（BCD）
  /// [27-2A] 标注金额　[2B] 方向标识　[2C-2D] 下车城市代码
  /// [2E-35] 下车机构标识　[36-37] 下车运营商代码　[38-39] 下车线路号
  /// [3A] 下车站点　[3B-42] 下车车辆号　[43-4A] 下车终端编号
  /// [4B-51] 下车时间（BCD）　[52-55] 交易金额　[56-57] 乘车里程。
  ///
  /// 真机兼容：记录以 27 02 记录标识开头（完整格式）时自动探测并按
  /// 14 字节偏移解析记录体；记录被 70 记录模板包裹时先剥离；不足
  /// 88 字节时按可用字节解析，越界字段保持 null（不猜测；原始数据由
  /// 调用方保留）。
  BusTransitRecord? parseBusTransit(int recordNumber, List<int> data) {
    // 仅记录 2 承载公共汽电车上下车配对信息；其余记录不产出结果。
    if (recordNumber != 2) return null;
    final raw = _unwrapRecordTemplate(data) ?? data;
    // 真机存在两种形态：携带 14 字节记录头（记录标识 27 02）的完整记录，
    // 与不带头的 88 字节记录体；按记录标识探测，命中则记录体偏移后移。
    // 记录头内的应用有效标识～交易流水号字段不产出（仅用于结构探测）。
    final hasHeader = _isBusRecordWithHeader(raw);
    final payload = hasHeader ? raw.sublist(_busRecordHeaderLength) : raw;
    if (payload.length < _minRecordLength) return null;

    final entryTimeBytes = _slice(payload, 0x20, 0x27);
    final exitTimeBytes = _slice(payload, 0x4B, 0x52);
    return BusTransitRecord(
      hasRecordHeader: hasHeader,
      issuerCustomHex: payload.length > _busRecordLength
          ? TUnionCodec.hexBytes(payload.sublist(_busRecordLength))
          : null,
      statusCode: payload[0x00],
      entryCityCode: _hexAt(payload, 0x01, 2),
      entryAgencyId: _hexAt(payload, 0x03, 8),
      entryOperatorCode: _hexAt(payload, 0x0B, 2),
      entryLineCode: _hexAt(payload, 0x0D, 2),
      entryStationCode: _hexAt(payload, 0x0F, 1),
      entryVehicleId: _hexAt(payload, 0x10, 8),
      entryTerminalId: _hexAt(payload, 0x18, 8),
      entryTime: entryTimeBytes == null
          ? null
          : TUnionCodec.parseBcdDateTime(entryTimeBytes),
      entryTimeBcd: entryTimeBytes == null
          ? null
          : TUnionCodec.bcdString(entryTimeBytes),
      annotateAmountFen: _beIntAt(payload, 0x27, 4),
      directionCode: _byteAt(payload, 0x2B),
      exitCityCode: _hexAt(payload, 0x2C, 2),
      exitAgencyId: _hexAt(payload, 0x2E, 8),
      exitOperatorCode: _hexAt(payload, 0x36, 2),
      exitLineCode: _hexAt(payload, 0x38, 2),
      exitStationCode: _hexAt(payload, 0x3A, 1),
      exitVehicleId: _hexAt(payload, 0x3B, 8),
      exitTerminalId: _hexAt(payload, 0x43, 8),
      exitTime: exitTimeBytes == null
          ? null
          : TUnionCodec.parseBcdDateTime(exitTimeBytes),
      exitTimeBcd: exitTimeBytes == null
          ? null
          : TUnionCodec.bcdString(exitTimeBytes),
      transactionAmountFen: _beIntAt(payload, 0x52, 4),
      mileage: _beIntAt(payload, 0x56, 2),
      rawHex: TUnionCodec.hexBytes(payload),
    );
  }

  /// 探测 0x1A 记录 2 是否携带 14 字节记录头：以记录标识 27 02 开头
  /// （0x27 不是合法交易状态取值，误判概率极低），且记录长度字节自洽
  /// （等于剩余长度）或等于标准值 0x7D；不满足时按 88 字节裸记录体解析。
  static bool _isBusRecordWithHeader(List<int> raw) {
    if (raw.length <= _busRecordHeaderLength) return false;
    if (raw[0] != 0x27 || raw[1] != 0x02) return false;
    final declared = raw[2];
    return declared == raw.length - 3 || declared == 0x7D;
  }

  /// 剥离 70 记录模板（TLV）返回内容；非模板或长度头不合法时返回 null。
  ///
  /// 支持多层嵌套模板（真机存在“70 模板内再套 70 模板”的实现）：
  /// 最多剥离 3 层，遇长度头不合法即停止并返回已剥出的最内层内容。
  /// 模板声明长度超出实际数据（记录被截断）时，取剩余全部可用字节。
  static List<int>? _unwrapRecordTemplate(List<int> data) {
    List<int>? result;
    var current = data;
    for (var depth = 0; depth < 3; depth++) {
      final next = _unwrapOneTemplate(current);
      if (next == null) break;
      result = next;
      current = next;
    }
    return result;
  }

  /// 剥离单层 70 记录模板（TLV）返回内容；非模板或长度头不合法时返回 null。
  /// 0x80 不定长与 0x83~0xFF 超过两字节的长度头在记录场景不合法，按不剥离处理。
  static List<int>? _unwrapOneTemplate(List<int> data) {
    if (data.length < 3 || data[0] != 0x70) return null;
    var pos = 1;
    var len = data[pos++];
    if (len == 0x81) {
      if (pos >= data.length) return null;
      len = data[pos++];
    } else if (len == 0x82) {
      if (pos + 1 >= data.length) return null;
      len = (data[pos] << 8) | data[pos + 1];
      pos += 2;
    } else if (len >= 0x80) {
      return null;
    }
    if (len == 0) return null;
    final end = pos + len;
    return end <= data.length ? data.sublist(pos, end) : data.sublist(pos);
  }

  /// 按 [start, end) 切分；越界返回 null（不截断取值）。
  static List<int>? _slice(List<int> d, int start, int end) =>
      d.length >= end ? d.sublist(start, end) : null;

  /// 偏移处 HEX 字符串；越界返回 null。
  static String? _hexAt(List<int> d, int off, int len) {
    final bytes = _slice(d, off, off + len);
    return bytes == null ? null : TUnionCodec.hexBytes(bytes);
  }

  /// 偏移处大端整数；越界返回 null（避免截断出错误值）。
  static int? _beIntAt(List<int> d, int off, int len) {
    final bytes = _slice(d, off, off + len);
    return bytes == null ? null : TUnionCodec.beInt(d, off, len);
  }

  /// 偏移处单字节；越界返回 null。
  static int? _byteAt(List<int> d, int off) => d.length > off ? d[off] : null;
}
