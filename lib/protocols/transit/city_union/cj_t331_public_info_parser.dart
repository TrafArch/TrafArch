import 'dart:convert';

import 'city_union_codec.dart';
import 'city_union_models.dart';

/// CJ/T 331-2016 表 5：公共应用基本信息文件解析器
/// （SFI 0x15，0x1E=30 字节）。
///
/// 读取层（NFC）负责选卡、选应用并读取 SFI 0x15 的完整 30 字节内容；
/// 本解析器只做数据解释，不含写卡或密钥操作：
/// - 按标准表格固定字节偏移逐字段解析，BCD 与 HEX 分别处理；
/// - BCD 字段保留前导零（不转整数），日期字段做真实日历校验；
/// - 字段级异常（BCD / 日期非法）只标记该字段并保留原始字节，
///   其他字段照常解析，不丢弃整张卡的其他解析结果。
class CjT331PublicInfoParser {
  CjT331PublicInfoParser._();

  /// 文件 SFI。
  static const int sfi = CityUnionFileIds.publicBasicInfo;

  /// 标准文件长度 0x1E（十进制 30 字节，非 30 个字符）。
  static const int expectedLength = 0x1E;

  /// 解析表 5。
  ///
  /// [input] 为 SFI 0x15 完整文件内容（30 字节，0 起 Dart 数组下标）。
  /// 长度不符或存在越界字节值（读取层错误）时抛 [FormatException]；
  /// 单字段编码/日期异常不抛异常，记录在对应 [CjField] 上。
  static CjT331PublicInfo parse(List<int> input) {
    if (input.length != expectedLength) {
      throw FormatException(
        '公共应用基本信息文件长度错误：'
        '期望 0x1E（30 字节），实际 ${input.length} 字节',
      );
    }
    final data = _validate(input);

    // 01-02 发卡方代码（BCD，保留前导零）
    final issuer = _bcdField(data, 0, 2, 'issuerCode', '发卡方代码');

    // 03-04 城市代码（HEX；附十进制值便于核对）
    final cityDecoded = CityUnionCodec.hex(data.sublist(2, 4));
    final city = _hexField(
      data,
      2,
      2,
      'cityCode',
      '城市代码',
      note: '十进制值 ${int.parse(cityDecoded, radix: 16)}',
    );

    // 05 多算法支持（BCD；具体含义待核对标准注释，不做推断）
    final multiAlgorithm = _bcdField(
      data,
      4,
      1,
      'multiAlgorithmSupport',
      '多算法支持',
    );

    // 06 行业代码（BCD）
    final industry = _bcdField(data, 5, 1, 'industryCode', '行业代码');

    // 07-08 预留（原样保留）
    final reserved1 = _hexField(data, 6, 2, 'reserved1', '预留');

    // 09 互联互通启用标识：00 未启用，非 00 启用
    final enabled = _hexField(
      data,
      8,
      1,
      'interconnectionEnabled',
      '互联互通启用标识',
      note: data[8] == 0x00 ? '未启用' : '已启用',
    );

    // 10 应用版本（HEX）
    final appVersion = _hexField(data, 9, 1, 'applicationVersion', '应用版本');

    // 11-12 互联互通标识（标准资料说明与城市/项目代码相同；
    // 仅对不一致给出提示，两个字段仍分别展示，不擅自修改卡片数据）
    final interopDecoded = CityUnionCodec.hex(data.sublist(10, 12));
    final interopId = _hexField(
      data,
      10,
      2,
      'interconnectionId',
      '互联互通标识',
      note: interopDecoded == cityDecoded
          ? '与城市代码一致'
          : '与城市代码不一致（城市代码 $cityDecoded）',
    );

    // 13-20 用户卡应用序列号（8 字节，按发卡方实际编码自适应解码为纯数字）
    final serial = _cardNumberField(
      data,
      12,
      8,
      'applicationSerialNumber',
      '用户卡应用序列号',
    );

    // 21-24 应用启动日期（BCD YYYYMMDD）
    final startDate = _bcdDateField(data, 20, 'applicationStartDate', '应用启动日期');

    // 25-28 应用有效日期（BCD YYYYMMDD）
    final expiryDate = _bcdDateField(
      data,
      24,
      'applicationExpiryDate',
      '应用有效日期',
    );

    // 29-30 预留（原样保留）
    final reserved2 = _hexField(data, 28, 2, 'reserved2', '预留');

    final fields = <CjField>[
      issuer,
      city,
      multiAlgorithm,
      industry,
      reserved1,
      enabled,
      appVersion,
      interopId,
      serial,
      startDate,
      expiryDate,
      reserved2,
    ];

    return CjT331PublicInfo(
      issuerCode: issuer.decoded,
      cityCode: city.decoded,
      multiAlgorithmSupport: multiAlgorithm.decoded,
      industryCode: industry.decoded,
      reserved1: reserved1.decoded,
      interconnectionEnabled: enabled.decoded,
      applicationVersion: appVersion.decoded,
      interconnectionId: interopId.decoded,
      applicationSerialNumber: serial.decoded,
      applicationStartDate: startDate.decoded,
      applicationExpiryDate: expiryDate.decoded,
      reserved2: reserved2.decoded,
      fields: fields,
      rawHex: CityUnionCodec.hexSpaced(data),
    );
  }

  /// 调试输出：解析结果格式化 JSON（含字段明细、异常与原始值）。
  static String toPrettyJson(CjT331PublicInfo info) =>
      const JsonEncoder.withIndent('  ').convert(info.toJson());

  /// 校验字节值范围（0~255），防止调用方传入越界整数。
  static List<int> _validate(List<int> input) {
    for (final b in input) {
      if (b < 0 || b > 255) {
        throw FormatException('发现非法字节值：$b');
      }
    }
    return List<int>.unmodifiable(input);
  }

  /// HEX 字段：原始字节转连续大写 HEX，可选附加可读说明。
  static CjField _hexField(
    List<int> data,
    int offset,
    int length,
    String key,
    String name, {
    String? note,
  }) {
    final segment = data.sublist(offset, offset + length);
    return CjField(
      key: key,
      name: name,
      offset: offset,
      length: length,
      format: CjFieldFormat.hex,
      rawHex: CityUnionCodec.hexSpaced(segment),
      decoded: CityUnionCodec.hex(segment),
      note: note,
    );
  }

  /// BCD 字段：数字字符串解码（保留前导零），非法半字节标记异常。
  static CjField _bcdField(
    List<int> data,
    int offset,
    int length,
    String key,
    String name,
  ) {
    final segment = data.sublist(offset, offset + length);
    final digits = CityUnionCodec.bcdString(segment);
    return CjField(
      key: key,
      name: name,
      offset: offset,
      length: length,
      format: CjFieldFormat.bcd,
      rawHex: CityUnionCodec.hexSpaced(segment),
      decoded: digits,
      error: digits == null ? 'BCD 编码非法' : null,
    );
  }

  /// 日期字段（4 字节 BCD YYYYMMDD）：
  /// - BCD 非法：decoded 为 null，标记 "BCD 编码非法"；
  /// - 日期非法（如 13 月 / 非闰年 2-29）：decoded 保留 BCD 数字串，
  ///   标记 "日期非法"（不猜测修正，原始字节保留在 rawHex）。
  static CjField _bcdDateField(
    List<int> data,
    int offset,
    String key,
    String name,
  ) {
    final segment = data.sublist(offset, offset + 4);
    final digits = CityUnionCodec.bcdString(segment);
    if (digits == null) {
      return CjField(
        key: key,
        name: name,
        offset: offset,
        length: 4,
        format: CjFieldFormat.bcd,
        rawHex: CityUnionCodec.hexSpaced(segment),
        error: 'BCD 编码非法',
      );
    }
    final valid = CityUnionCodec.isValidDateDigits(digits);
    return CjField(
      key: key,
      name: name,
      offset: offset,
      length: 4,
      format: CjFieldFormat.bcd,
      rawHex: CityUnionCodec.hexSpaced(segment),
      decoded: valid ? CityUnionCodec.formatDateDigits(digits) : digits,
      error: valid ? null : '日期非法',
    );
  }

  /// 卡号类字段：BCD 优先解码为纯数字；非 BCD 时按原始字节大写 HEX
  /// 展示（如上海 CU 单标卡），原始字节始终保留在 rawHex。
  static CjField _cardNumberField(
    List<int> data,
    int offset,
    int length,
    String key,
    String name,
  ) {
    final segment = data.sublist(offset, offset + length);
    final result = CityUnionCodec.decodeCardNumber(segment);
    return CjField(
      key: key,
      name: name,
      offset: offset,
      length: length,
      format: CjFieldFormat.auto,
      rawHex: CityUnionCodec.hexSpaced(segment),
      decoded: result.displayValue,
      note: result.note,
      error: result.error,
    );
  }
}
