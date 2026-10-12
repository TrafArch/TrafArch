import 'dart:convert';

import 'city_union_codec.dart';
import 'city_union_models.dart';

/// CJ/T 331-2016 表 6：复合交易记录文件解析器
/// （SFI 0x17，变长记录文件，文件大小 0x00A0=160 字节，单条标准记录 48 字节）。
///
/// 记录外层结构（字节编号按标准表格 1 起计数）：
/// - 01 记录标识（必须为 0x09）；02 复合消费数据长度（HEX）；
/// - 03 复合消费锁定标识（HEX，00 允许 / 非 00 禁止）；
/// - 04-48 应用方自定义（45 字节）。
///
/// 责任边界与读取约定：
/// - 本解析器只接受单条完整 48 字节记录（READ RECORD 单条读取）；
///   0x00A0 为文件大小而非单条记录长度，不按 48 字节对整文件切片；
/// - 表 6 未定义 45 字节应用方自定义区的内部结构，本解析器只解析
///   外层结构并原样保留自定义区（不猜测金额、时间、终端编号等字段）；
/// - 记录长度、字节值范围与记录标识等结构性错误抛 [FormatException]，
///   由调用方分类处理（如空白 / 未写入记录），不做静默容错。
class CjT331CompositeTransactionParser {
  CjT331CompositeTransactionParser._();

  /// 文件 SFI（0x17）。
  static const int sfi = CityUnionFileIds.compositeTransaction;

  /// 标准文件大小 0x00A0（十进制 160 字节；非单条记录长度）。
  static const int fileSize = 0x00A0;

  /// 单条标准记录长度（48 字节）。
  static const int recordLength = 48;

  /// 记录标识期望值（复合交易记录 = 0x09）。
  static const int expectedRecordIdentifier = 0x09;

  /// 应用方自定义区长度（字节 04-48，共 45 字节）。
  static const int applicationDataLength = 45;

  /// 解析一条完整的 48 字节复合交易记录。
  ///
  /// [input] 为单条记录内容（48 字节，0 起 Dart 数组下标）。
  /// 长度不符、字节值越界或记录标识非 0x09 时抛 [FormatException]；
  /// 通过结构性校验后，外层字段与 45 字节自定义区全部保留。
  static CjT331CompositeTransaction parseRecord(List<int> input) {
    if (input.length != recordLength) {
      throw FormatException(
        '复合交易记录长度错误：期望单条记录 $recordLength 字节，'
        '实际 ${input.length} 字节。'
        'SFI ${CityUnionCodec.sfiLabel(sfi)} 为变长记录文件，'
        '文件大小 0x00A0（$fileSize 字节）不是单条记录长度；'
        '请先确认读取接口返回的是单条记录还是整个文件，'
        '不要按 $recordLength 字节对整文件直接切片。',
      );
    }
    final data = _validate(input);

    // 字节01：记录标识（必须为 09）。
    final recordIdentifier = data[0];
    if (recordIdentifier != expectedRecordIdentifier) {
      throw FormatException(
        '记录标识错误：期望 '
        '${CityUnionCodec.hexByte(expectedRecordIdentifier)}，'
        '实际 ${CityUnionCodec.hexByte(recordIdentifier)}',
      );
    }

    // 字节02：复合消费数据长度（HEX；计数规则表 6 未说明，仅容量核对）。
    final dataLength = data[1];

    // 字节03：复合消费锁定标识（00 允许，非 00 禁止）。
    final lockFlag = data[2];

    // 字节04-48：应用方自定义数据（45 字节，内部结构未在表 6 定义）。
    final applicationData =
        List<int>.unmodifiable(data.sublist(3, recordLength));

    final fields = <CjField>[
      _hexField(data, 0, 1, 'recordIdentifier', '记录标识'),
      _hexField(
        data,
        1,
        1,
        'compositeConsumptionDataLength',
        '复合消费数据长度',
        note: dataLength <= applicationDataLength
            ? '十进制值 $dataLength'
            : '十进制值 $dataLength（超出应用方自定义区 $applicationDataLength 字节）',
      ),
      _hexField(
        data,
        2,
        1,
        'compositeConsumptionLockFlag',
        '复合消费锁定标识',
        note: lockFlag == 0x00 ? '允许' : '禁止',
      ),
      _hexField(
        data,
        3,
        applicationDataLength,
        'applicationDefinedData',
        '应用方自定义数据',
        note: '表 6 未定义内部结构，原始保留',
      ),
    ];

    return CjT331CompositeTransaction(
      recordIdentifier: recordIdentifier,
      dataLength: dataLength,
      lockFlag: lockFlag,
      applicationData: applicationData,
      rawData: data,
      fields: fields,
    );
  }

  /// 调试输出：解析结果格式化 JSON（含字段明细与原始值）。
  static String toPrettyJson(CjT331CompositeTransaction record) =>
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
}