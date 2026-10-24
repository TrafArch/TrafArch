import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_models.dart';
import 'package:transit_card_analyzer/protocols/transit/local/apdu_exchange.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_reader.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';

/// 驱动新模块 CU 单元完成一次识读（等价原 CityUnionParser.parse()，
/// APDU 序列完全一致；老模块已移除，测试改为直接调用单元）。
Future<ParsedCard?> _parseCu(LocalTransceive link) async {
  final apdu = ApduExchange(transceive: link);
  final info = CardInfo();
  final records = <ApduRecord>[];
  final cu = CommonUnitCu(apdu);
  if (!await cu.select(info, records)) return null;
  return cu.read(info, records);
}

void main() {
  group('TripReader CU 完整 APDU 回归', () {
    test('部分记录失败保留证据、无效时间不猜测、余额 CLA 回退', () async {
      for (final fail in [false, true]) {
        final row = _localRecord()..[22] = 0xFF;
        final result = await _strictCu(
          _publicFile(),
          rows: [row, List.filled(20, 0x5A)],
          balance: [0, 0, 0, 0],
          balanceFallback: true,
          balanceFailure: fail,
        );
        expect(result.$1.cityUnionFiles.last, isA<CityUnionRawFileView>());
        expect(result.$3, hasLength(1));
        expect(
          result.$3.single.timestamp,
          DateTime.fromMillisecondsSinceEpoch(0),
        );
        expect(result.$2.observedBalance, fail ? isNull : 0);
      }
    });
    for (final city in [
      1160,
      2253,
      2000,
      2140,
      2153,
      3000,
      3100,
      3120,
      3150,
      3500,
      2300,
      5240,
      3250,
      4500,
      7100,
      9999,
    ]) {
      test('城市 $city 派生显示且标准字段不变', () async {
        final data = _publicFile();
        final code = city.toString();
        data[2] = int.parse(code.substring(0, 2), radix: 16);
        data[3] = int.parse(code.substring(2), radix: 16);
        // 1234567890 -> 90 78 56 34 12；右侧起加倍得到前缀 3。
        data.setRange(16, 20, [0x49, 0x96, 0x02, 0xD2]);
        final expected = switch (city) {
          1160 || 2253 => '441234567890',
          2000 || 2140 => '39078563412',
          2300 || 5240 => '499602D2',
          3250 => '0A0111223344499602D2',
          4500 => '3344499602D2',
          7100 || 9999 => '1234567890',
          _ => '11223344499602D2',
        };
        final result = await _strictCu(data);
        final public = result.$1.cityUnionFiles.first as CjT331PublicInfo;
        expect(result.$2.cardNumber, expected);
        expect(public.cityCardNumber, expected);
        expect(public.applicationSerialNumber, '11223344499602D2');
        expect(public.applicationSerialNumberRawHex, '11223344499602D2');
        expect(public.issuerCode, '0123');
        expect(public.rawHex.replaceAll(' ', ''), _hex(data));
      });
    }
    test('默认纯数字 HEX、无效城市与零校验位', () async {
      for (final entry in [
        (0x99, 0x99, '1122334455667788'),
        (0x0A, 0x01, '1122334455667788'),
        (0x20, 0x00, '00000000000'),
      ]) {
        final data = _publicFile()
          ..[2] = entry.$1
          ..[3] = entry.$2;
        if (entry.$1 == 0x20) data.setRange(16, 20, [0, 0, 0, 0]);
        expect((await _strictCu(data)).$2.cardNumber, entry.$3);
      }
    });
    for (final value in [
      ([0, 0, 0, 0], 0),
      ([0xFF, 0xFF, 0xFF, 0x9C], -100),
      ([0x00, 0xFF, 0xFF, 0x9C], -100),
      ([0xFF, 0xFE, 0x79, 0x61], 16677217),
      ([0xFF, 0xFE, 0x79, 0x60], 16677216),
      ([1, 0, 0, 5], 5),
    ]) {
      test('2150 余额 ${value.$2}', () async {
        final data = _publicFile()
          ..[2] = 0x21
          ..[3] = 0x50;
        final result = await _strictCu(data, balance: value.$1);
        expect(result.$2.observedBalance, value.$2);
      });
    }
    test('31条边界、HEX终端、秒与标准金额保留', () async {
      final rows = [
        for (var i = 1; i <= 31; i++)
          _localRecord()
            ..[1] = i
            ..[5] = 1
            ..[10] = 0xAB
            ..[22] = 0x59,
      ];
      final result = await _strictCu(_publicFile(), rows: rows);
      expect(result.$3, hasLength(31));
      expect(result.$3.last.recordNumber, 31);
      expect(result.$3.first.terminalHex, 'AB3456789012');
      expect(result.$3.first.timestamp.second, 59);
      expect(result.$3.first.posType, 6);
      expect(result.$3.first.response, _sw9000(rows.first));
      expect(result.$3.first.balanceDelta, 0);
      expect(
        (result.$1.cityUnionFiles[1] as CjT331WalletLocalConsumption).amountHex,
        '010003E8',
      );
    });
    test('2120 ASCII 及恢复失败停止后续读取', () async {
      for (final restore in [true, false]) {
        final data = _publicFile()
          ..[2] = 0x21
          ..[3] = 0x20;
        final result = await _strictCu(data, restore: restore);
        expect(result.$2.cardNumber, '123456789012');
        expect(result.$1.cityUnionFiles, hasLength(1));
        expect(result.$2.observedBalance, isNull);
      }
    });
  });
  group('城市一卡通（CU）解析管道', () {
    test('完整读取：0x15 公共信息 + 0x18 本地消费 + 0x1A 充值', () async {
      final parsed = await _parseCu(_baseLink().call);

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

    test('非 BCD 应用序列号：卡号按原始 HEX 展示而非读取失败', () async {
      final link = _ScriptedLink();
      link.enqueue(0xA4, const [0x90, 0x00]);
      link.enqueue(0xA4, _sw9000(const []));
      link.enqueue(
        0xB0,
        _sw9000(
          _publicFile(
            serial: const [0xB9, 0x21, 0xDC, 0xAD, 0x7E, 0x32, 0xED, 0xA7],
          ),
        ),
      );
      link.enqueue(0xB2, const [0x6A, 0x83]); // 0x18 未找到
      link.enqueue(0xB2, const [0x6A, 0x83]); // 0x1A 未找到

      final apdu = ApduExchange(transceive: link.call);
      final info = CardInfo();
      final cu = CommonUnitCu(apdu);
      expect(await cu.select(info, <ApduRecord>[]), isTrue);
      final parsed = await cu.read(info, <ApduRecord>[]);

      expect(parsed, isNotNull);
      // 新架构卡汇总使用 CU 卡号（原始 HEX），不因非 BCD 而留空。
      expect(info.cardNumber, 'B921DCAD7E32EDA7');
      final public = parsed!.cityUnionFiles
          .whereType<CjT331PublicInfo>()
          .single;
      expect(public.applicationSerialNumber, 'B921DCAD7E32EDA7');
      expect(public.displayApplicationSerialNumber, 'B921DCAD7E32EDA7');
    });

    test('非城市一卡通卡：CLA 00 / 80 应用选择均失败返回 null', () async {
      final link = _ScriptedLink();
      link.enqueue(0xA4, const [0x90, 0x00]); // 选择主文件 MF
      link.enqueue(0xA4, const [0x6A, 0x82]); // AID CLA 00 失败
      link.enqueue(0xA4, const [0x6A, 0x82]); // AID CLA 80 失败

      final parsed = await _parseCu(link.call);
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

      final parsed = await _parseCu(link.call);
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

      final parsed = await _parseCu(link.call);
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

      final parsed = await _parseCu(link.call);

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

      final parsed = await _parseCu(link.call);

      final local = parsed!.cityUnionFiles.where((f) => f.sfi == 0x18).toList();
      expect(local, hasLength(1)); // 重复内容停止，不产出重复条目
      expect(local.single, isA<CjT331WalletLocalConsumption>());
    });
  });
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

Future<(ParsedCard, CardInfo, List<ApduRecord>)> _strictCu(
  List<int> data, {
  List<int>? balance,
  List<List<int>> rows = const [],
  bool? restore,
  bool balanceFallback = false,
  bool balanceFailure = false,
}) async {
  final script = <(String, List<int>)>[
    ('00A40000023F0000', [0x90, 0]),
    ('00A4040009A0000000038698070100', [0x90, 0]),
    ('00B095001E', _sw9000(data)),
    if (restore != null) ...[
      ('00A40000023F0000', [0x90, 0]),
      (
        '00B085002C',
        _sw9000([...List.filled(32, 0), ...'123456789012'.codeUnits]),
      ),
      ('00A40000023F0000', [0x90, 0]),
      ('00A4040009A0000000038698070100', restore ? [0x90, 0] : [0x6A, 0x82]),
      if (!restore) ('80A4040009A0000000038698070100', [0x6A, 0x82]),
    ],
    if (restore != false) ...[
      for (var i = 0; i < rows.length; i++)
        (
          '00B2${(i + 1).toRadixString(16).padLeft(2, '0').toUpperCase()}C417',
          _sw9000(rows[i]),
        ),
      if (rows.length < 31)
        (
          '00B2${(rows.length + 1).toRadixString(16).padLeft(2, '0').toUpperCase()}C417',
          [0x6A, 0x83],
        ),
      ('00B201D417', [0x6A, 0x83]),
      if (balance != null) ...[
        (
          '805C00${data[2] == 0x21 && data[3] == 0x50 ? '01' : '02'}04',
          balanceFallback ? [0x6A, 0x82] : _sw9000(balance),
        ),
        if (balanceFallback)
          (
            '005C00${data[2] == 0x21 && data[3] == 0x50 ? '01' : '02'}04',
            balanceFailure ? [0x6A, 0x82] : _sw9000(balance),
          ),
      ],
    ],
  ];
  final info = CardInfo();
  final records = <ApduRecord>[];
  var index = 0;
  final cu = CommonUnitCu(
    ApduExchange(
      transceive: (command) async {
        expect(index, lessThan(script.length));
        final step = script[index++];
        expect(_hex(command), step.$1);
        return step.$2;
      },
    ),
  );
  expect(await cu.select(info, records), isTrue);
  final parsed = await cu.read(
    info,
    records,
    readBalance: balance != null || restore == false,
  );
  expect(index, script.length);
  return (parsed!, info, records);
}

/// 历史 INS 脚本；上方新兼容规则使用严格全命令脚本验证。
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
List<int> _publicFile({List<int> serial = _defaultSerial}) => [
  0x01, 0x23, // 01-02 发卡方代码（BCD）
  0x0A, 0x01, // 03-04 城市代码（HEX）
  0x01, // 05 多算法支持
  0x26, // 06 行业代码
  0x00, 0x00, // 07-08 预留
  0x01, // 09 互联互通启用标识
  0x02, // 10 应用版本
  0x0A, 0x01, // 11-12 互联互通标识
  ...serial, // 13-20 应用序列号
  0x20, 0x24, 0x01, 0x01, // 21-24 应用启动日期 2024-01-01
  0x20, 0x30, 0x12, 0x31, // 25-28 应用有效日期 2030-12-31
  0x00, 0x00, // 29-30 预留
];

const _defaultSerial = [0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88];

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
