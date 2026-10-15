import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/core/card/card_parser.dart';
import 'package:transit_card_analyzer/core/transit/city_union/city_union_models.dart';
import 'package:transit_card_analyzer/core/transit/city_union/city_union_parser.dart';

void main() {
  group('CityUnionParser 解析管道', () {
    test('完整读取：0x15 公共信息 + 0x18 本地消费 + 0x1A 充值', () async {
      final parsed = await CityUnionParser(_baseLink().call).parse();

      expect(parsed, isNotNull);
      expect(parsed!.parserId, CardParserIds.cityUnion);
      expect(parsed.parserName, '城市一卡通（CJ/T 331-2016）');
      expect(parsed.selectedAidHex, 'A00000000386980701');
      expect(parsed.info.issuerId, isNull); // 交通联合载荷保持为空
      expect(parsed.transactions, isEmpty);

      final files = parsed.cityUnionFiles;
      expect(files, hasLength(3));

      final info = files[0];
      expect(info, isA<CjT331PublicInfo>());
      expect((info as CjT331PublicInfo).issuerCode, '0123');
      expect(info.applicationSerialNumber, '1122334455667788');

      final local = files[1];
      expect(local, isA<CjT331WalletLocalConsumption>());
      expect((local as CjT331WalletLocalConsumption).amountHex, '000003E8');
      expect(local.transactionTypeName, '消费');

      final recharge = files[2];
      expect(recharge, isA<CjT331WalletRecharge>());
      expect((recharge as CjT331WalletRecharge).isRecharge, isTrue);
    });

    test('非城市一卡通卡：CLA 00 / 80 应用选择均失败返回 null', () async {
      final link = _ScriptedLink();
      link.enqueue(0xA4, const [0x90, 0x00]); // 选择主文件 MF
      link.enqueue(0xA4, const [0x6A, 0x82]); // AID CLA 00 失败
      link.enqueue(0xA4, const [0x6A, 0x82]); // AID CLA 80 失败

      final parsed = await CityUnionParser(link.call).parse();
      expect(parsed, isNull);
    });

    test('CLA 0x00 选择失败后回退 CLA 0x80 选择成功', () async {
      final link = _ScriptedLink();
      link.enqueue(0xA4, const [0x90, 0x00]); // 选择主文件 MF
      link.enqueue(0xA4, const [0x6A, 0x82]); // AID CLA 00 失败
      link.enqueue(0xA4, _sw9000(const [])); // AID CLA 80 成功
      link.enqueue(0xB0, _sw9000(_publicFile()));
      link.enqueue(0xB2, const [0x6A, 0x83]); // 0x18 记录未找到
      link.enqueue(0xB2, const [0x6A, 0x83]); // 0x1A 记录未找到

      final parsed = await CityUnionParser(link.call).parse();
      expect(parsed, isNotNull);
      expect(parsed!.cityUnionFiles, hasLength(1)); // 仅 0x15 公共信息
    });

    test('文件缺失时跳过：仅命中部分文件仍产出解析结果', () async {
      final link = _ScriptedLink();
      link.enqueue(0xA4, const [0x90, 0x00]); // 选择主文件 MF
      link.enqueue(0xA4, _sw9000(const [])); // 选择城市一卡通 AID
      link.enqueue(0xB0, const [0x6A, 0x82]); // 0x15 整体读取失败
      link.enqueue(0xB0, const [0x6A, 0x82]); // 0x15 按偏移补读同样失败
      link.enqueue(0xB2, const [0x6A, 0x83]); // 0x18 记录未找到
      link.enqueue(0xB2, _sw9000(_rechargeRecord())); // 0x1A 记录 1 命中
      link.enqueue(0xB2, const [0x6A, 0x83]); // 0x1A 记录 2 未找到

      final parsed = await CityUnionParser(link.call).parse();
      expect(parsed, isNotNull);
      expect(parsed!.cityUnionFiles, hasLength(1));
      expect(parsed.cityUnionFiles.single, isA<CjT331WalletRecharge>());
    });

    test('记录不符合标准布局时保留原始字节（CityUnionRawFileView）', () async {
      final link = _ScriptedLink();
      link.enqueue(0xA4, const [0x90, 0x00]);
      link.enqueue(0xA4, _sw9000(const []));
      link.enqueue(0xB0, _sw9000(_publicFile()));
      link.enqueue(0xB2, _sw9000(List.filled(20, 0x5A))); // 0x18 记录 20 字节（非 23）
      link.enqueue(0xB2, const [0x6A, 0x83]); // 0x18 记录 2 未找到
      link.enqueue(0xB2, const [0x6A, 0x83]); // 0x1A 未找到

      final parsed = await CityUnionParser(link.call).parse();

      final files = parsed!.cityUnionFiles;
      expect(files, hasLength(2)); // 0x15 正常 + 0x18 原始占位
      final raw = files[1];
      expect(raw, isA<CityUnionRawFileView>());
      expect(raw.sfi, 0x18);
      expect(raw.fields, isEmpty);
      expect(raw.errors, isNotEmpty); // 保留解析器给出的长度错误说明
      expect(raw.rawHex, contains('5A'));
    });

    test('空白记录跳过、忽略记录号的重复内容终止读取', () async {
      final link = _ScriptedLink();
      link.enqueue(0xA4, const [0x90, 0x00]);
      link.enqueue(0xA4, _sw9000(const []));
      link.enqueue(0xB0, const [0x6A, 0x82]); // 0x15 整体失败
      link.enqueue(0xB0, const [0x6A, 0x82]); // 0x15 补读失败
      link.enqueue(0xB2, _sw9000(List.filled(23, 0x00))); // 0x18 记录 1 空白
      link.enqueue(0xB2, _sw9000(_localRecord())); // 0x18 记录 2 有效
      link.enqueue(0xB2, _sw9000(_localRecord())); // 0x18 记录 3 与记录 2 相同
      link.enqueue(0xB2, const [0x6A, 0x83]); // 0x1A 未找到

      final parsed = await CityUnionParser(link.call).parse();

      final local =
          parsed!.cityUnionFiles.where((f) => f.sfi == 0x18).toList();
      expect(local, hasLength(1)); // 重复内容停止，不产出重复条目
      expect(local.single, isA<CjT331WalletLocalConsumption>());
    });
  });
}

/// 按 INS 字节匹配的脚本化 APDU 链路（无需真机）。
class _ScriptedLink {
  final Map<int, List<List<int>>> _queues = {};

  void enqueue(int ins, List<int> resp) =>
      _queues.putIfAbsent(ins, () => []).add(resp);

  Future<List<int>> call(List<int> apdu) async {
    final ins = apdu.length > 1 ? apdu[1] : -1;
    final queue = _queues[ins];
    if (queue == null || queue.isEmpty) return const [0x6A, 0x82];
    return queue.removeAt(0);
  }
}

/// 完整读取脚本：MF → AID → 0x15 → 0x18 (1 条) → 0x1A (1 条)。
_ScriptedLink _baseLink() {
  final link = _ScriptedLink();
  link.enqueue(0xA4, const [0x90, 0x00]); // 选择主文件 MF
  link.enqueue(0xA4, _sw9000(const [])); // 选择城市一卡通 AID
  link.enqueue(0xB0, _sw9000(_publicFile())); // 0x15 整体读取
  link.enqueue(0xB2, _sw9000(_localRecord())); // 0x18 记录 1
  link.enqueue(0xB2, const [0x6A, 0x83]); // 0x18 记录 2 未找到
  link.enqueue(0xB2, _sw9000(_rechargeRecord())); // 0x1A 记录 1
  link.enqueue(0xB2, const [0x6A, 0x83]); // 0x1A 记录 2 未找到
  return link;
}

List<int> _sw9000(List<int> data) => [...data, 0x90, 0x00];

/// 表 5 示例文件（30 字节，全字段合法）。
List<int> _publicFile() => [
      0x01, 0x23, // 01-02 发卡方代码（BCD）
      0x0A, 0x01, // 03-04 城市代码（HEX）
      0x01, // 05 多算法支持
      0x26, // 06 行业代码
      0x00, 0x00, // 07-08 预留
      0x01, // 09 互联互通启用标识
      0x02, // 10 应用版本
      0x0A, 0x01, // 11-12 互联互通标识
      0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, // 13-20 应用序列号
      0x20, 0x24, 0x01, 0x01, // 21-24 应用启动日期 2024-01-01
      0x20, 0x30, 0x12, 0x31, // 25-28 应用有效日期 2030-12-31
      0x00, 0x00, // 29-30 预留
    ];

/// 表 7 示例记录（23 字节，本地消费 1000，终端 123456789012）。
List<int> _localRecord() => [
      0x00, 0x01, // 01-02 交易序号
      0x00, 0x00, 0x00, // 03-05 预留
      0x00, 0x00, 0x03, 0xE8, // 06-09 交易金额
      0x06, // 10 交易类型：消费
      0x12, 0x34, 0x56, 0x78, 0x90, 0x12, // 11-16 交易终端编号（BCD）
      0x20, 0x24, 0x05, 0x01, // 17-20 交易日期 2024-05-01
      0x08, 0x30, 0x00, // 21-23 交易时间 08:30:00
    ];

/// 表 9 示例记录（23 字节，充值 1000）。
List<int> _rechargeRecord() => [
      0x00, 0x01, // 01-02 交易序号
      0x00, 0x00, 0x00, // 03-05 预留
      0x00, 0x00, 0x03, 0xE8, // 06-09 交易金额
      0x02, // 10 交易类型：充值
      0x12, 0x34, 0x56, 0x78, 0x90, 0x12, // 11-16 交易终端编号（BCD）
      0x20, 0x26, 0x01, 0x01, // 17-20 交易日期 2026-01-01
      0x12, 0x30, 0x45, // 21-23 交易时间 12:30:45
    ];