import 'dart:convert';

import 'city_union_codec.dart';
import 'city_union_models.dart';

/// CJ/T 331-2016 表 8：电子钱包异地消费交易明细记录文件解析器
/// （SFI 0x10，循环记录文件，单条记录长度 0x17=23 字节，
/// 标准要求至少容纳 10 条记录）。
///
/// 单条记录结构（字节编号按标准表格 1 起计数）：
/// - 01-02 电子钱包消费交易序号（HEX 大端）；03-05 预留（HEX 原样保留）；
/// - 06-09 交易金额（HEX 大端）；10 交易类型（06 消费 / 09 复合消费）；
/// - 11-16 交易终端编号（BCD 12 位数字）；17-20 交易日期（BCD YYYYMMDD）；
/// - 21-23 交易时间（BCD HHMMSS）。
///
/// 责任边界与读取约定：
/// - 本解析器只接受单条完整 23 字节记录（READ RECORD 单条读取）；
///   0x17 为单条记录长度而非文件长度，不按 23 字节对整文件切片；
///   循环记录的选取（最新记录 / 覆盖顺序）由读取层按 COS/NFC 接口与
///   完整标准规则确认后逐条传入，不假定记录 1 是最新交易；
/// - 金额字段是 HEX 而非 BCD，且表 8 未定义金额单位与小数位，
///   本解析器只保留原始十六进制与十进制大端值，不擅自换算为元；
/// - 终端编号是 BCD，保留 12 位数字前导零（不转整数）；
/// - 记录长度、字节值范围等结构性错误抛 [FormatException]；
///   单字段 BCD / 日期 / 时间异常只标记该字段（[CjField]），
///   其他字段照常解析，不丢弃整条记录。
class CjT331WalletOfflineTransactionParser {
  CjT331WalletOfflineTransactionParser._();

  /// 文件 SFI（0x10）。
  static const int sfi = CityUnionFileIds.walletOfflineTransaction;

  /// 单条记录长度 0x17（十进制 23 字节；该文件为循环记录文件，
  /// 标准要求至少容纳 10 条记录，读取层按记录边界逐条传入）。
  static const int recordLength = 0x17;

  /// 解析一条完整的 23 字节异地消费交易记录。
  ///
  /// [input] 为单条记录内容（23 字节，0 起 Dart 数组下标）。
  /// 长度不符或字节值越界（读取层错误）时抛 [FormatException]；
  /// 字段级编码 / 日期 / 时间异常不抛异常，记录在对应 [CjField] 上。
  static CjT331WalletOfflineTransaction parseRecord(List<int> input) {
    if (input.length != recordLength) {
      throw FormatException(
        '异地消费交易记录长度错误：期望单条记录 $recordLength 字节，'
        '实际 ${input.length} 字节。'
        'SFI ${CityUnionCodec.sfiLabel(sfi)} 为循环记录文件，'
        '单条记录长度 0x17（$recordLength 字节）而非文件长度；'
        '请先确认读取接口返回的是单条记录还是整个文件，'
        '由读取层按记录边界逐条传入，'
        '不要把整文件当作连续交易数组切分。',
      );
    }
    final data = _validate(input);

    // 01-02：电子钱包消费交易序号（HEX 大端；计数规则表 8 未说明）。
    final sequenceHex = CityUnionCodec.hex(data.sublist(0, 2));
    final sequence = (data[0] << 8) | data[1];

    // 03-05：预留（HEX 原样保留）。
    final reservedHex = CityUnionCodec.hex(data.sublist(2, 5));

    // 06-09：交易金额（HEX 大端；单位表 8 未定义，不擅自换算）。
    final amountHex = CityUnionCodec.hex(data.sublist(5, 9));
    final amountRaw =
        (data[5] << 24) | (data[6] << 16) | (data[7] << 8) | data[8];

    // 10：交易类型（06 消费 / 09 复合消费）。
    final transactionType = data[9];
    final typeName =
        CjT331WalletOfflineTransaction.transactionTypeLabel(transactionType);

    // 11-16：交易终端编号（BCD 12 位数字，保留前导零）。
    final terminal = _bcdField(data, 10, 6, 'terminalNumber', '交易终端编号');

    // 17-20：交易日期（BCD YYYYMMDD）。
    final date = _bcdDateField(data, 16, 'transactionDate', '交易日期');

    // 21-23：交易时间（BCD HHMMSS）。
    final time = _bcdTimeField(data, 20, 'transactionTime', '交易时间');

    final fields = <CjField>[
      _hexField(
        data,
        0,
        2,
        'sequence',
        '电子钱包消费交易序号',
        note: '十进制值 $sequence',
      ),
      _hexField(data, 2, 3, 'reserved', '预留'),
      _hexField(
        data,
        5,
        4,
        'amount',
        '交易金额',
        note: '十进制值 $amountRaw（金额单位表 8 未定义，不换算）',
      ),
      _hexField(data, 9, 1, 'transactionType', '交易类型', note: typeName),
      terminal,
      date,
      time,
    ];

    return CjT331WalletOfflineTransaction(
      sequence: sequence,
      sequenceHex: sequenceHex,
      reservedHex: reservedHex,
      amountRaw: amountRaw,
      amountHex: amountHex,
      transactionType: transactionType,
      terminalNumber: terminal.decoded,
      transactionDate: date.decoded,
      transactionTime: time.decoded,
      fields: fields,
      rawHex: CityUnionCodec.hexSpaced(data),
    );
  }

  /// 调试输出：解析结果格式化 JSON（含字段明细与原始值）。
  static String toPrettyJson(CjT331WalletOfflineTransaction record) =>
      const JsonEncoder.withIndent('  ').convert(record.toJson());

  /// 校验字节值范围（0~255），防止调用方传入越界整数。
  static List<int> _validate(List<int> input) {
    for (var i = 0; i < input.length; i++) {
      if (input[i] < 0 || input[i] > 255) {
        throw FormatException(
          '第${i + 1}字节超出有效范围：${input[i]}（应为 0-255）',
        );
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

  /// 时间字段（3 字节 BCD HHMMSS）：
  /// - BCD 非法：decoded 为 null，标记 "BCD 编码非法"；
  /// - 时刻非法（时 > 23 / 分秒 > 59）：decoded 保留 BCD 数字串，
  ///   标记 "时间非法"（不猜测修正，原始字节保留在 rawHex）。
  static CjField _bcdTimeField(
    List<int> data,
    int offset,
    String key,
    String name,
  ) {
    final segment = data.sublist(offset, offset + 3);
    final digits = CityUnionCodec.bcdString(segment);
    if (digits == null) {
      return CjField(
        key: key,
        name: name,
        offset: offset,
        length: 3,
        format: CjFieldFormat.bcd,
        rawHex: CityUnionCodec.hexSpaced(segment),
        error: 'BCD 编码非法',
      );
    }
    final valid = CityUnionCodec.isValidTimeDigits(digits);
    return CjField(
      key: key,
      name: name,
      offset: offset,
      length: 3,
      format: CjFieldFormat.bcd,
      rawHex: CityUnionCodec.hexSpaced(segment),
      decoded: valid ? CityUnionCodec.formatTimeDigits(digits) : digits,
      error: valid ? null : '时间非法',
    );
  }
}