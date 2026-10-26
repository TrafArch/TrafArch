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
  group('CU SELECT 兼容严格 APDU（合成状态字）', () {
    const commands = [
      '00A40000023F0000',
      '00A40000023F00',
      '00A4040009A0000000038698070100',
      '00A4040009A00000000386980701',
      '80A4040009A0000000038698070100',
      '80A4040009A00000000386980701',
    ];
    // 仅复现已知 SELECT 状态字，不含实卡卡号或交易数据。
    const rejected = [
      [0x6A, 0x86],
      [0x6A, 0x86],
      [0x6A, 0x82],
      [0x6A, 0x82],
      [0x6E, 0x00],
      [0x6E, 0x00],
    ];
    for (final successAt in [2, 3, 4, 5, -1]) {
      test('日志失败分支有界选择 successAt=$successAt', () async {
        await _selectExact([
          for (var i = 0; i < (successAt < 0 ? 6 : successAt + 1); i++)
            (commands[i], i == successAt ? [0x90, 0] : rejected[i]),
        ], succeeds: successAt >= 0);
      });
    }
    test('MF 无Le恢复后 CU 主策略成功', () async {
      await _selectExact([
        (commands[0], rejected[0]),
        (commands[1], [0x90, 0]),
        (commands[2], [0x90, 0]),
      ], succeeds: true);
    });
    test('原成功路径没有额外尝试', () async {
      await _selectExact([
        (commands[0], [0x90, 0]),
        (commands[2], [0x90, 0]),
      ], succeeds: true);
    });
    for (var failAt = 0; failAt < commands.length; failAt++) {
      test('SELECT 传输异常立即停止 step=$failAt', () async {
        await _selectExact([
          for (var i = 0; i <= failAt; i++)
            (
              commands[i],
              i == failAt ? StateError('disconnected') : rejected[i],
            ),
        ], transportFailure: true);
      });
    }
    for (final sw2 in [0x00, 0x10]) {
      test('无Le MF及两种CLA SELECT遇6C不改写FID/AID sw2=$sw2', () async {
        await _selectExact([
          for (var i = 0; i < commands.length; i++)
            (commands[i], i.isOdd ? [0x6C, sw2] : rejected[i]),
        ]);
      });
    }
    test('2120 补充及恢复共用 MF 无Le兼容并继续读余额', () async {
      final data = _publicFile()
        ..[2] = 0x21
        ..[3] = 0x20;
      final result = await _runExact([
        ('00B095001E', _sw9000(data)),
        (commands[0], rejected[0]),
        (commands[1], [0x90, 0]),
        (
          '00B085002C',
          _sw9000([...List.filled(32, 0), ...'000000000001'.codeUnits]),
        ),
        (commands[0], rejected[0]),
        (commands[1], [0x90, 0]),
        (commands[2], rejected[2]),
        (commands[3], [0x90, 0]),
        ('805C000204', _sw9000([0, 0, 0, 5])),
        ('00B201C417', [0x6A, 0x83]),
        ('00B2018417', [0x6A, 0x83]),
        ('00B201D417', [0x6A, 0x83]),
      ], balance: true);
      expect(result.$1.parsedCard!.info.balanceFen, 5);
      expect(
        (result.$1.parsedCard!.cityUnionFiles.first as CjT331PublicInfo)
            .cityDisplayNumber,
        '000000000001',
      );
    });
  });
  group('CU 读取修复严格 APDU', () {
    test('32 字节公共信息按前30解析并保留完整证据', () async {
      final data = [..._publicFile(), 0xAB, 0xCD];
      final result = await _strictCu(data);
      final public = result.$1.cityUnionFiles.first as CjT331PublicInfo;
      expect(public.applicationSerialNumber, '1122334455667788');
      expect(public.rawHex.replaceAll(' ', ''), _hex(data.sublist(0, 30)));
      final raw = result.$1.cityUnionFiles.last as CityUnionRawFileView;
      expect(raw.rawHex.replaceAll(' ', ''), _hex(data));
      expect(raw.errors.single, contains('前 30 字节'));
    });
    for (final sw in [0x67, 0x6C]) {
      for (final succeeds in [true, false]) {
        test('${sw.toRadixString(16)}00 记录校正一次 success=$succeeds', () async {
          final result = await _runExact([
            ('00B095001E', _sw9000(_publicFile())),
            ('00B201C417', [sw, 0]),
            ('00B201C400', succeeds ? _sw9000(_localRecord()) : [sw, 0]),
            if (succeeds) ('00B202C417', [0x6A, 0x83]),
            ('00B2018417', _sw9000(_rechargeRecord())),
            ('00B2028417', [0x6A, 0x83]),
            ('00B201D417', [0x6A, 0x83]),
          ]);
          expect(result.$2, hasLength(succeeds ? 2 : 1));
          expect(result.$2.last.fileSelector, 0x10);
        });
      }
    }
    test('公共信息与余额只读指令也支持长度校正', () async {
      final result = await _runExact([
        ('00B095001E', [0x67, 0]),
        ('00B0950000', _sw9000(_publicFile())),
        ('805C000204', [0x6C, 0]),
        ('805C000200', _sw9000([0, 0, 0, 5])),
        ('00B201C417', [0x6A, 0x83]),
        ('00B2018417', [0x6A, 0x83]),
        ('00B201D417', [0x6A, 0x83]),
      ], balance: true);
      expect(result.$1.parsedCard!.info.balanceFen, 5);
    });
    for (final balance in [0, 5]) {
      test('记录传输异常保留已读余额 $balance 并停止', () async {
        final result = await _runExact(
          [
            ('00B095001E', _sw9000(_publicFile())),
            ('805C000204', _sw9000([0, 0, 0, balance])),
            ('00B201C417', _sw9000(_localRecord())),
            ('00B202C417', StateError('disconnected')),
          ],
          balance: true,
          fails: true,
        );
        expect(result.$1.parsedCard!.info.balanceFen, balance);
        expect(result.$2, hasLength(1));
      });
    }
    test('余额状态字失败保留后续消费与充值', () async {
      final result = await _runExact([
        ('00B095001E', _sw9000(_publicFile())),
        ('805C000204', [0x6A, 0x81]),
        ('005C000204', [0x6A, 0x81]),
        ('00B201C417', _sw9000(_localRecord())),
        ('00B202C417', [0x6A, 0x83]),
        ('00B2018417', _sw9000(_rechargeRecord())),
        ('00B2028417', [0x6A, 0x83]),
        ('00B201D417', [0x6A, 0x83]),
      ], balance: true);
      expect(result.$1.parsedCard!.info.balanceFen, isNull);
      expect(result.$2.map((r) => r.fileSelector), [0x18, 0x10]);
    });
    test('2120 MF补充读取断连不再恢复SELECT', () async {
      final data = _publicFile()
        ..[2] = 0x21
        ..[3] = 0x20;
      final result = await _runExact(
        [
          ('00B095001E', _sw9000(data)),
          ('00A40000023F0000', [0x90, 0]),
          ('00B085002C', StateError('disconnected')),
        ],
        balance: true,
        fails: true,
      );
      expect(result.$1.parsedCard!.cityUnionFiles, hasLength(1));
      expect(result.$2, isEmpty);
    });
    test('余额传输异常不尝试另一CLA或记录', () async {
      final result = await _runExact(
        [
          ('00B095001E', _sw9000(_publicFile())),
          ('805C000204', StateError('disconnected')),
        ],
        balance: true,
        fails: true,
      );
      expect(result.$1.parsedCard!.info.balanceFen, isNull);
      expect(result.$1.parsedCard!.cityUnionFiles, hasLength(1));
      expect(result.$2, isEmpty);
    });
  });
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
        expect(
          public.withCityDisplayNumber('000000000001').toJson(),
          public.toJson(),
        );
        expect(public.toJson()['applicationSerialNumber'], '11223344499602D2');
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
    test('卡号末四字节按无符号大端处理，保留前导零', () async {
      for (final entry in [
        ([0, 0, 0, 0], '0000000000'),
        ([0, 0, 0, 1], '0000000001'),
        ([0, 0xFF, 0xFF, 0xFF], '0016777215'),
        ([0x80, 0, 0, 0], '2147483648'),
        ([0xFF, 0xFF, 0xFF, 0xFF], '4294967295'),
      ]) {
        final data = _publicFile()
          ..[2] = 0x71
          ..[3] = 0x00
          ..setRange(16, 20, entry.$1);
        expect((await _strictCu(data)).$2.cardNumber, entry.$2);
      }
    });
    test('默认 BCD 判断仅限末四字节，城市必须严格 BCD', () async {
      for (final city in [0x0000, 0x0099, 0x9999, 0x0A01, 0x1A60, 0xFFFF]) {
        final data = _publicFile(serial: [0, 0xAB, 0, 1, 0, 0, 0, 9])
          ..[2] = city >> 8
          ..[3] = city & 0xFF;
        final result = await _strictCu(data);
        final public = result.$1.cityUnionFiles.first as CjT331PublicInfo;
        expect(public.cityCardNumber, '00AB000100000009');
        expect(
          public.displayCityCode,
          city == 0x0A01 || city == 0x1A60 || city == 0xFFFF
              ? isNull
              : int.parse(city.toRadixString(16)),
        );
      }
    });
    test('短数据与非法原始 HEX 的展示回退不抛异常', () async {
      for (final raw in ['', '00' * 19, '00' * 16 + 'GG000001']) {
        final public = CjT331PublicInfo(
          cityCode: '2000',
          applicationSerialNumber: '00123',
          fields: const [],
          rawHex: raw,
        );
        expect(public.cityCardNumber, '0000000000000123');
      }
      for (final data in [
        <int>[],
        List.filled(19, 1),
        List.filled(29, 1),
        List.filled(30, 0),
        List.filled(30, 0xFF),
      ]) {
        final result = await _strictCu(data);
        if (data.length < 30) {
          final raw = result.$1.cityUnionFiles.single;
          expect(raw, isA<CityUnionRawFileView>());
          expect(raw.rawHex.replaceAll(' ', ''), _hex(data));
          expect(raw.errors.single, contains('实际 ${data.length} 字节'));
        } else {
          expect(result.$1.cityUnionFiles, isEmpty);
        }
        expect(result.$2.cardNumber, isEmpty);
      }
    });
    test('上海成对反转及右起加倍校验，含非全零的零校验位', () async {
      for (final entry in [
        ([0, 0, 0, 1], '80100000000'),
        ([0, 0, 0, 0x13], '01900000000'),
        ([0xFF, 0xFF, 0xFF, 0xFF], '29572969442'),
      ]) {
        final data = _publicFile()
          ..[2] = 0x20
          ..[3] = 0
          ..setRange(16, 20, entry.$1);
        expect((await _strictCu(data)).$2.cardNumber, entry.$2);
      }
    });
    test('2120 额外读取失败、短数据及非法 ASCII 回退并恢复 CU', () async {
      for (final response in [
        [0x6A, 0x82],
        _sw9000(List.filled(43, 1)),
        _sw9000([...List.filled(32, 1), ...List.filled(12, 0xFF)]),
      ]) {
        for (final restore in [true, false]) {
          final data = _publicFile()
            ..[2] = 0x21
            ..[3] = 0x20;
          final result = await _strictCu(
            data,
            restore: restore,
            extraResponse: response,
            balance: [0, 0, 0, 1],
          );
          final public = result.$1.cityUnionFiles.first as CjT331PublicInfo;
          expect(result.$2.cardNumber, '1122334455667788');
          expect(public.cityDisplayNumber, isNull);
          expect(result.$2.observedBalance, restore ? 1 : isNull);
          expect(public.applicationSerialNumberRawHex, '1122334455667788');
        }
      }
    });
    test('2120 MF 失败仍恢复，恢复 CLA 80 成功继续读取', () async {
      final data = _publicFile()
        ..[2] = 0x21
        ..[3] = 0x20;
      final result = await _strictCu(
        data,
        restore: true,
        mfFailure: true,
        restoreFallback: true,
        rows: [_localRecord()],
        balance: [0, 0, 0, 1],
      );
      expect(result.$2.cardNumber, '1122334455667788');
      expect(result.$3, hasLength(1));
      expect(result.$2.observedBalance, 1);
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
    test('完整读取：0x15 公共信息 + 0x18 本地消费 + 0x10 充值', () async {
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
      link.enqueue(0xB2, const [0x6A, 0x83]); // 0x10 未找到

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
      link.enqueue(0xA4, const [0x6A, 0x82]); // AID CLA 00 带 Le 失败
      link.enqueue(0xA4, const [0x6A, 0x82]); // AID CLA 00 无 Le 失败
      link.enqueue(0xA4, _sw9000(const [])); // AID CLA 80 成功
      link.enqueue(0xB0, _sw9000(_publicFile()));
      link.enqueue(0xB2, const [0x6A, 0x83]); // 0x18 记录未找到
      link.enqueue(0xB2, const [0x6A, 0x83]); // 0x10 记录未找到

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
      link.enqueue(0xB2, _sw9000(_rechargeRecord())); // 0x10 记录 1 命中
      link.enqueue(0xB2, const [0x6A, 0x83]); // 0x10 记录 2 未找到

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
      link.enqueue(0xB2, const [0x6A, 0x83]); // 0x10 未找到

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
      link.enqueue(0xB2, const [0x6A, 0x83]); // 0x10 未找到

      final parsed = await _parseCu(link.call);

      final local = parsed!.cityUnionFiles.where((f) => f.sfi == 0x18).toList();
      expect(local, hasLength(1)); // 重复内容停止，不产出重复条目
      expect(local.single, isA<CjT331WalletLocalConsumption>());
    });
  });
}

Future<void> _selectExact(
  List<(String, Object)> script, {
  bool succeeds = false,
  bool transportFailure = false,
}) async {
  var index = 0;
  final cu = CommonUnitCu(
    ApduExchange(
      transceive: (command) async {
        expect(index, lessThan(script.length));
        final step = script[index++];
        expect(_hex(command), step.$1);
        if (step.$2 is! List<int>) throw step.$2;
        return step.$2 as List<int>;
      },
    ),
  );
  final info = CardInfo();
  final records = <ApduRecord>[];
  final selection = cu.select(info, records);
  if (transportFailure) {
    await expectLater(selection, throwsA(isA<ApduTransportException>()));
  } else {
    expect(await selection, succeeds);
  }
  expect(cu.selectedAid, succeeds ? CommonUnitCu.walletAid : isNull);
  if (!succeeds) {
    expect(await cu.read(info, records, readBalance: true), isNull);
  }
  expect(index, script.length);
}

Future<(CommonUnitCu, List<ApduRecord>)> _runExact(
  List<(String, Object)> reads, {
  bool balance = false,
  bool fails = false,
}) async {
  final script = <(String, Object)>[
    ('00A40000023F0000', [0x90, 0]),
    ('00A4040009A0000000038698070100', [0x90, 0]),
    ...reads,
  ];
  var index = 0;
  final cu = CommonUnitCu(
    ApduExchange(
      transceive: (command) async {
        expect(index, lessThan(script.length));
        final step = script[index++];
        expect(_hex(command), step.$1);
        if (step.$2 is! List<int>) throw step.$2;
        return step.$2 as List<int>;
      },
    ),
  );
  final info = CardInfo();
  final records = <ApduRecord>[];
  expect(await cu.select(info, records), isTrue);
  final read = cu.read(info, records, readBalance: balance);
  if (fails) {
    await expectLater(read, throwsA(isA<ApduTransportException>()));
  } else {
    await read;
  }
  expect(index, script.length);
  expect(info.observedBalance, cu.parsedCard!.info.balanceFen);
  return (cu, records);
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

Future<(ParsedCard, CardInfo, List<ApduRecord>)> _strictCu(
  List<int> data, {
  List<int>? balance,
  List<List<int>> rows = const [],
  bool? restore,
  List<int>? extraResponse,
  bool mfFailure = false,
  bool restoreFallback = false,
  bool balanceFallback = false,
  bool balanceFailure = false,
}) async {
  final script = <(String, List<int>)>[
    ('00A40000023F0000', [0x90, 0]),
    ('00A4040009A0000000038698070100', [0x90, 0]),
    ('00B095001E', _sw9000(data)),
    if (restore != null) ...[
      ('00A40000023F0000', mfFailure ? [0x6A, 0x82] : [0x90, 0]),
      if (mfFailure) ('00A40000023F00', [0x6A, 0x82]),
      if (!mfFailure)
        (
          '00B085002C',
          extraResponse ??
              _sw9000([...List.filled(32, 0), ...'123456789012'.codeUnits]),
        ),
      ('00A40000023F0000', [0x90, 0]),
      (
        '00A4040009A0000000038698070100',
        restore && !restoreFallback ? [0x90, 0] : [0x6A, 0x82],
      ),
      if (!restore || restoreFallback) ...[
        ('00A4040009A00000000386980701', [0x6A, 0x82]),
        ('80A4040009A0000000038698070100', restore ? [0x90, 0] : [0x6A, 0x82]),
        if (!restore) ('80A4040009A00000000386980701', [0x6A, 0x82]),
      ],
    ],
    if (restore != false) ...[
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
      ('00B2018417', [0x6A, 0x83]),
      (
        data.length >= 30 &&
                ((data[2] == 0x20 && data[3] == 0) ||
                    (data[2] == 0x21 && data[3] == 0x53))
            ? '00B2013417'
            : '00B201D417',
        [0x6A, 0x83],
      ),
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

/// 完整读取脚本：MF → AID → 0x15 → 0x18 (1 条) → 0x10 (1 条)。
_ScriptedLink _baseLink() {
  final link = _ScriptedLink();
  link.enqueue(0xA4, const [0x90, 0x00]); // 选择主文件 MF
  link.enqueue(0xA4, _sw9000(const [])); // 选择城市一卡通 AID
  link.enqueue(0xB0, _sw9000(_publicFile())); // 0x15 整体读取
  link.enqueue(0xB2, _sw9000(_localRecord())); // 0x18 记录 1
  link.enqueue(0xB2, const [0x6A, 0x83]); // 0x18 记录 2 未找到
  link.enqueue(0xB2, _sw9000(_rechargeRecord())); // 0x10 记录 1
  link.enqueue(0xB2, const [0x6A, 0x83]); // 0x10 记录 2 未找到
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
