import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/core/transit/city_union/city_union_file_parser.dart';
import 'package:transit_card_analyzer/core/transit/city_union/city_union_models.dart';
import 'package:transit_card_analyzer/core/transit/city_union/cj_t331_composite_transaction_parser.dart';
import 'package:transit_card_analyzer/core/transit/city_union/cj_t331_public_info_parser.dart';
import 'package:transit_card_analyzer/core/transit/city_union/cj_t331_wallet_offline_transaction_parser.dart';
import 'package:transit_card_analyzer/core/transit/city_union/cj_t331_wallet_recharge_parser.dart';

void main() {
  group('CjT331PublicInfoParser 表5 公共应用基本信息文件', () {
    test('合法 30 字节文件完整解析：BCD/HEX 分别处理', () {
      final info = CjT331PublicInfoParser.parse(_sampleFile());

      expect(info.sfi, 0x15);
      expect(info.fileLabel, '公共应用基本信息文件');
      expect(info.issuerCode, '0123');
      expect(info.cityCode, '0A01');
      expect(info.multiAlgorithmSupport, '01');
      expect(info.industryCode, '26');
      expect(info.reserved1, '0000');
      expect(info.interconnectionEnabled, '01');
      expect(info.isInterconnectionEnabled, isTrue);
      expect(info.applicationVersion, '02');
      expect(info.interconnectionId, '0A01');
      expect(info.applicationSerialNumber, '1122334455667788');
      expect(info.applicationStartDate, '2024-01-01');
      expect(info.applicationExpiryDate, '2030-12-31');
      expect(info.reserved2, '0000');

      expect(info.fields, hasLength(12));
      expect(info.errors, isEmpty);
      expect(info.rawHex.split(' '), hasLength(30)); // 0x1E 字节
    });

    test('字段明细：原始值、解码值、说明与字节范围', () {
      final info = CjT331PublicInfoParser.parse(_sampleFile());

      final issuer = info.fields.first;
      expect(issuer.key, 'issuerCode');
      expect(issuer.name, '发卡方代码');
      expect(issuer.byteRange, '01-02');
      expect(issuer.format, CjFieldFormat.bcd);
      expect(issuer.rawHex, '01 23');
      expect(issuer.decoded, '0123');
      expect(issuer.hasError, isFalse);

      final city = info.fields[1];
      expect(city.byteRange, '03-04');
      expect(city.format, CjFieldFormat.hex);
      expect(city.note, '十进制值 2561');

      final enabled = info.fields[5];
      expect(enabled.byteRange, '09');
      expect(enabled.note, '已启用');

      final start = info.fields[9];
      expect(start.byteRange, '21-24');
      expect(start.decoded, '2024-01-01');
    });

    test('BCD 解码保留前导零（不转整数）', () {
      final info = CjT331PublicInfoParser.parse(
        _sampleFile(issuer: const [0x00, 0x12]),
      );
      expect(info.issuerCode, '0012');
    });

    test('互联互通启用标识：00 未启用，非 00 已启用', () {
      final off = CjT331PublicInfoParser.parse(_sampleFile(enabled: 0x00));
      expect(off.interconnectionEnabled, '00');
      expect(off.isInterconnectionEnabled, isFalse);
      expect(off.fields[5].note, '未启用');

      final on = CjT331PublicInfoParser.parse(_sampleFile(enabled: 0xFF));
      expect(on.interconnectionEnabled, 'FF');
      expect(on.isInterconnectionEnabled, isTrue);
      expect(on.fields[5].note, '已启用');
    });

    test('互联互通标识与城市代码分别展示，不一致时给出提示', () {
      final same = CjT331PublicInfoParser.parse(_sampleFile());
      expect(same.interconnectionId, same.cityCode);
      expect(same.fields[7].note, '与城市代码一致');

      final diff = CjT331PublicInfoParser.parse(
        _sampleFile(interop: const [0x0B, 0x02]),
      );
      expect(diff.interconnectionId, '0B02');
      expect(diff.cityCode, '0A01'); // 不擅自修改卡片数据
      expect(diff.fields[7].note, '与城市代码不一致（城市代码 0A01）');
    });

    test('长度错误（非 30 字节）抛 FormatException', () {
      expect(
        () => CjT331PublicInfoParser.parse(List.filled(29, 0x00)),
        throwsFormatException,
      );
      expect(
        () => CjT331PublicInfoParser.parse(List.filled(31, 0x00)),
        throwsFormatException,
      );
    });

    test('越界字节值抛 FormatException', () {
      final data = _sampleFile();
      data[2] = 0x1FF;
      expect(
        () => CjT331PublicInfoParser.parse(data),
        throwsFormatException,
      );
    });

    test('BCD 非法只标记该字段，其他字段照常解析', () {
      final info = CjT331PublicInfoParser.parse(
        _sampleFile(issuer: const [0x1A, 0x23]),
      );

      expect(info.issuerCode, isNull);
      expect(info.fields.first.decoded, isNull);
      expect(info.fields.first.error, 'BCD 编码非法');
      expect(info.fields.first.rawHex, '1A 23'); // 原始值保留
      expect(info.errors, contains('发卡方代码：BCD 编码非法'));

      // 其他字段不受影响
      expect(info.cityCode, '0A01');
      expect(info.applicationStartDate, '2024-01-01');
      expect(info.errors, hasLength(1));
    });

    test('日期非法（13 月）标记异常并保留 BCD 解码数字串', () {
      final info = CjT331PublicInfoParser.parse(
        _sampleFile(start: const [0x20, 0x24, 0x13, 0x01]),
      );

      final start = info.fields[9];
      expect(start.decoded, '20241301');
      expect(start.error, '日期非法');
      expect(info.applicationStartDate, '20241301');
      expect(info.errors, contains('应用启动日期：日期非法'));
      expect(info.applicationExpiryDate, '2030-12-31'); // 其他字段正常
    });

    test('日期字段 BCD 非法（0xAB）标记异常', () {
      final info = CjT331PublicInfoParser.parse(
        _sampleFile(expiry: const [0x20, 0x30, 0xAB, 0x31]),
      );

      final expiry = info.fields[10];
      expect(expiry.decoded, isNull);
      expect(expiry.error, 'BCD 编码非法');
      expect(info.applicationExpiryDate, isNull);
      expect(info.errors, contains('应用有效日期：BCD 编码非法'));
    });

    test('闰年校验：2024-02-29 合法，2023-02-29 非法', () {
      final leap = CjT331PublicInfoParser.parse(
        _sampleFile(expiry: const [0x20, 0x24, 0x02, 0x29]),
      );
      expect(leap.applicationExpiryDate, '2024-02-29');
      expect(leap.errors, isEmpty);

      final invalid = CjT331PublicInfoParser.parse(
        _sampleFile(expiry: const [0x20, 0x23, 0x02, 0x29]),
      );
      expect(invalid.applicationExpiryDate, '20230229');
      expect(invalid.errors, contains('应用有效日期：日期非法'));
    });
  });

  group('CjT331WalletOfflineTransactionParser 表8 电子钱包异地消费交易明细记录', () {
    test('合法 23 字节单条记录完整解析：HEX 与 BCD 分别处理', () {
      final record =
          CjT331WalletOfflineTransactionParser.parseRecord(_sampleOffline());

      expect(record.sfi, 0x10);
      expect(record.fileLabel, '电子钱包异地消费交易明细记录文件');
      expect(record.sequence, 1);
      expect(record.sequenceHex, '0001');
      expect(record.reservedHex, '000000');
      expect(record.amountRaw, 1000);
      expect(record.amountHex, '000003E8');
      expect(record.transactionType, 0x06);
      expect(record.transactionTypeHex, '06');
      expect(record.transactionTypeName, '消费');
      expect(record.terminalNumber, '123456789012');
      expect(record.transactionDate, '2024-05-01');
      expect(record.transactionTime, '08:30:00');

      expect(record.fields, hasLength(7));
      expect(record.errors, isEmpty);
      expect(record.rawHex.split(' '), hasLength(23)); // 0x17 字节
    });

    test('字段明细：字节范围、编码格式与说明', () {
      final record =
          CjT331WalletOfflineTransactionParser.parseRecord(_sampleOffline());

      final sequence = record.fields[0];
      expect(sequence.key, 'sequence');
      expect(sequence.byteRange, '01-02');
      expect(sequence.format, CjFieldFormat.hex);
      expect(sequence.rawHex, '00 01');
      expect(sequence.decoded, '0001');
      expect(sequence.note, '十进制值 1');

      expect(record.fields[1].byteRange, '03-05');
      expect(record.fields[1].decoded, '000000');

      final amount = record.fields[2];
      expect(amount.byteRange, '06-09');
      expect(amount.format, CjFieldFormat.hex); // 金额是 HEX 不是 BCD
      expect(amount.decoded, '000003E8');

      final type = record.fields[3];
      expect(type.byteRange, '10');
      expect(type.note, '消费');

      final terminal = record.fields[4];
      expect(terminal.byteRange, '11-16');
      expect(terminal.format, CjFieldFormat.bcd);
      expect(terminal.decoded, '123456789012');

      expect(record.fields[5].byteRange, '17-20');
      expect(record.fields[5].decoded, '2024-05-01');
      expect(record.fields[6].byteRange, '21-23');
      expect(record.fields[6].decoded, '08:30:00');
    });

    test('金额按 HEX 大端解码（不是 BCD 十进制）', () {
      // 0x03E8 作为 HEX 是十进制 1000；若误按 BCD 会解成 "000003E8" 数字串。
      final record = CjT331WalletOfflineTransactionParser.parseRecord(
        _sampleOffline(amount: const [0x00, 0x00, 0x03, 0xE8]),
      );
      expect(record.amountRaw, 1000);
      expect(record.amountHex, '000003E8');
      expect(record.fields[2].format, CjFieldFormat.hex);
    });

    test('终端编号 BCD 保留 12 位前导零', () {
      final record = CjT331WalletOfflineTransactionParser.parseRecord(
        _sampleOffline(terminal: const [0x00, 0x12, 0x34, 0x56, 0x78, 0x90]),
      );
      expect(record.terminalNumber, '001234567890');
      expect(record.terminalNumber, hasLength(12));
    });

    test('交易类型：06 消费、09 复合消费、其他未知', () {
      final consume = CjT331WalletOfflineTransactionParser.parseRecord(
        _sampleOffline(type: 0x06),
      );
      expect(consume.transactionTypeName, '消费');
      expect(consume.fields[3].note, '消费');

      final composite = CjT331WalletOfflineTransactionParser.parseRecord(
        _sampleOffline(type: 0x09),
      );
      expect(composite.transactionTypeName, '复合消费');
      expect(composite.fields[3].note, '复合消费');

      final unknown = CjT331WalletOfflineTransactionParser.parseRecord(
        _sampleOffline(type: 0x0A),
      );
      expect(unknown.transactionTypeName, '未知类型');
      expect(unknown.fields[3].note, '未知类型');
    });

    test('长度错误（非 23 字节）抛 FormatException', () {
      expect(
        () => CjT331WalletOfflineTransactionParser.parseRecord(
          List.filled(22, 0x00),
        ),
        throwsFormatException,
      );
      expect(
        () => CjT331WalletOfflineTransactionParser.parseRecord(
          List.filled(24, 0x00),
        ),
        throwsFormatException,
      );
    });

    test('越界字节值抛 FormatException', () {
      final data = _sampleOffline();
      data[10] = 0x1FF;
      expect(
        () => CjT331WalletOfflineTransactionParser.parseRecord(data),
        throwsFormatException,
      );
    });

    test('终端编号 BCD 非法只标记该字段，其他字段照常解析', () {
      final record = CjT331WalletOfflineTransactionParser.parseRecord(
        _sampleOffline(terminal: const [0x1A, 0x34, 0x56, 0x78, 0x90, 0x12]),
      );

      expect(record.terminalNumber, isNull);
      expect(record.fields[4].decoded, isNull);
      expect(record.fields[4].error, 'BCD 编码非法');
      expect(record.fields[4].rawHex, '1A 34 56 78 90 12'); // 原始值保留
      expect(record.errors, contains('交易终端编号：BCD 编码非法'));

      // 其他字段不受影响
      expect(record.amountRaw, 1000);
      expect(record.transactionDate, '2024-05-01');
      expect(record.errors, hasLength(1));
    });

    test('日期非法（13 月）标记异常并保留 BCD 数字串', () {
      final record = CjT331WalletOfflineTransactionParser.parseRecord(
        _sampleOffline(date: const [0x20, 0x24, 0x13, 0x01]),
      );

      expect(record.transactionDate, '20241301');
      expect(record.fields[5].error, '日期非法');
      expect(record.errors, contains('交易日期：日期非法'));
      expect(record.transactionTime, '08:30:00'); // 其他字段正常
    });

    test('时间非法（25 时）标记异常并保留 BCD 数字串', () {
      final record = CjT331WalletOfflineTransactionParser.parseRecord(
        _sampleOffline(time: const [0x25, 0x30, 0x00]),
      );

      expect(record.transactionTime, '253000');
      expect(record.fields[6].error, '时间非法');
      expect(record.errors, contains('交易时间：时间非法'));
      expect(record.transactionDate, '2024-05-01'); // 其他字段正常
    });

    test('日期字段 BCD 非法（0xAB）标记异常', () {
      final record = CjT331WalletOfflineTransactionParser.parseRecord(
        _sampleOffline(date: const [0x20, 0x24, 0xAB, 0x01]),
      );

      expect(record.transactionDate, isNull);
      expect(record.fields[5].decoded, isNull);
      expect(record.fields[5].error, 'BCD 编码非法');
      expect(record.errors, contains('交易日期：BCD 编码非法'));
    });
  });

  group('CjT331WalletRechargeParser 表9 电子钱包充值交易明细记录', () {
    test('合法 23 字节单条记录完整解析：HEX 与 BCD 分别处理', () {
      final record = CjT331WalletRechargeParser.parseRecord(_sampleRecharge());

      expect(record.sfi, 0x1A);
      expect(record.fileLabel, '电子钱包充值交易明细记录文件');
      expect(record.sequence, 1);
      expect(record.sequenceHex, '0001');
      expect(record.reservedHex, '000000');
      expect(record.amountRaw, 1000);
      expect(record.amountHex, '000003E8');
      expect(record.transactionType, 0x02);
      expect(record.transactionTypeHex, '02');
      expect(record.transactionTypeName, '充值');
      expect(record.isRecharge, isTrue);
      expect(record.terminalNumber, '123456789012');
      expect(record.transactionDate, '2026-01-01');
      expect(record.transactionTime, '12:30:45');

      expect(record.fields, hasLength(7));
      expect(record.errors, isEmpty);
      expect(record.rawHex.split(' '), hasLength(23)); // 0x17 字节
    });

    test('字段明细：字节范围、编码格式与说明', () {
      final record = CjT331WalletRechargeParser.parseRecord(_sampleRecharge());

      final sequence = record.fields[0];
      expect(sequence.key, 'sequence');
      expect(sequence.name, '电子钱包充值交易序号');
      expect(sequence.byteRange, '01-02');
      expect(sequence.format, CjFieldFormat.hex);
      expect(sequence.rawHex, '00 01');
      expect(sequence.decoded, '0001');
      expect(sequence.note, '十进制值 1');

      expect(record.fields[1].byteRange, '03-05');
      expect(record.fields[1].decoded, '000000');

      final amount = record.fields[2];
      expect(amount.byteRange, '06-09');
      expect(amount.format, CjFieldFormat.hex); // 金额是 HEX 不是 BCD
      expect(amount.decoded, '000003E8');

      final type = record.fields[3];
      expect(type.byteRange, '10');
      expect(type.note, '充值');

      final terminal = record.fields[4];
      expect(terminal.byteRange, '11-16');
      expect(terminal.format, CjFieldFormat.bcd);
      expect(terminal.decoded, '123456789012');

      expect(record.fields[5].byteRange, '17-20');
      expect(record.fields[5].decoded, '2026-01-01');
      expect(record.fields[6].byteRange, '21-23');
      expect(record.fields[6].decoded, '12:30:45');
    });

    test('金额按 HEX 大端解码（不是 BCD 十进制）', () {
      // 0x03E8 作为 HEX 是十进制 1000；若误按 BCD 会解成 "000003E8" 数字串。
      final record = CjT331WalletRechargeParser.parseRecord(
        _sampleRecharge(amount: const [0x00, 0x00, 0x03, 0xE8]),
      );
      expect(record.amountRaw, 1000);
      expect(record.amountHex, '000003E8');
      expect(record.fields[2].format, CjFieldFormat.hex);
    });

    test('终端编号 BCD 保留 12 位前导零', () {
      final record = CjT331WalletRechargeParser.parseRecord(
        _sampleRecharge(terminal: const [0x00, 0x12, 0x34, 0x56, 0x78, 0x90]),
      );
      expect(record.terminalNumber, '001234567890');
      expect(record.terminalNumber, hasLength(12));
    });

    test('交易类型：02 充值、其他未知类型仍解析保留', () {
      final recharge = CjT331WalletRechargeParser.parseRecord(
        _sampleRecharge(type: 0x02),
      );
      expect(recharge.transactionTypeName, '充值');
      expect(recharge.isRecharge, isTrue);
      expect(recharge.fields[3].note, '充值');

      final unknown = CjT331WalletRechargeParser.parseRecord(
        _sampleRecharge(type: 0x06),
      );
      expect(unknown.transactionTypeName, '未知类型');
      expect(unknown.isRecharge, isFalse);
      expect(unknown.fields[3].note, '未知类型');
    });

    test('长度错误（非 23 字节）抛 FormatException', () {
      expect(
        () => CjT331WalletRechargeParser.parseRecord(List.filled(22, 0x00)),
        throwsFormatException,
      );
      expect(
        () => CjT331WalletRechargeParser.parseRecord(List.filled(24, 0x00)),
        throwsFormatException,
      );
    });

    test('越界字节值抛 FormatException', () {
      final data = _sampleRecharge();
      data[10] = 0x1FF;
      expect(
        () => CjT331WalletRechargeParser.parseRecord(data),
        throwsFormatException,
      );
    });

    test('终端编号 BCD 非法只标记该字段，其他字段照常解析', () {
      final record = CjT331WalletRechargeParser.parseRecord(
        _sampleRecharge(terminal: const [0x1A, 0x34, 0x56, 0x78, 0x90, 0x12]),
      );

      expect(record.terminalNumber, isNull);
      expect(record.fields[4].decoded, isNull);
      expect(record.fields[4].error, 'BCD 编码非法');
      expect(record.fields[4].rawHex, '1A 34 56 78 90 12'); // 原始值保留
      expect(record.errors, contains('交易终端编号：BCD 编码非法'));

      // 其他字段不受影响
      expect(record.amountRaw, 1000);
      expect(record.transactionDate, '2026-01-01');
      expect(record.errors, hasLength(1));
    });

    test('日期非法（13 月）标记异常并保留 BCD 数字串', () {
      final record = CjT331WalletRechargeParser.parseRecord(
        _sampleRecharge(date: const [0x20, 0x26, 0x13, 0x01]),
      );

      expect(record.transactionDate, '20261301');
      expect(record.fields[5].error, '日期非法');
      expect(record.errors, contains('交易日期：日期非法'));
      expect(record.transactionTime, '12:30:45'); // 其他字段正常
    });

    test('时间非法（25 时）标记异常并保留 BCD 数字串', () {
      final record = CjT331WalletRechargeParser.parseRecord(
        _sampleRecharge(time: const [0x25, 0x30, 0x00]),
      );

      expect(record.transactionTime, '253000');
      expect(record.fields[6].error, '时间非法');
      expect(record.errors, contains('交易时间：时间非法'));
      expect(record.transactionDate, '2026-01-01'); // 其他字段正常
    });
  });

  group('CityUnionFileParser 按 SFI 分发', () {
    test('SFI 0x10 分发到表 8 异地消费交易记录解析器（单条记录输入）', () {
      final view = CityUnionFileParser.parse(0x10, _sampleOffline());
      expect(view, isA<CjT331WalletOfflineTransaction>());
      expect(view.fileLabel, '电子钱包异地消费交易明细记录文件');
      expect(view.fields, hasLength(7));
    });

    test('SFI 0x15 分发到表 5 解析器', () {
      final view = CityUnionFileParser.parse(0x15, _sampleFile());
      expect(view, isA<CjT331PublicInfo>());
      expect(view.fileLabel, '公共应用基本信息文件');
      expect(view.fields, hasLength(12));
    });

    test('SFI 0x17 分发到表 6 复合交易记录解析器（单条记录输入）', () {
      final view = CityUnionFileParser.parse(0x17, _sampleRecord());
      expect(view, isA<CjT331CompositeTransaction>());
      expect(view.fileLabel, '复合交易记录文件');
      expect(view.fields, hasLength(4));
    });

    test('SFI 0x1A 分发到表 9 充值交易记录解析器（单条记录输入）', () {
      final view = CityUnionFileParser.parse(0x1A, _sampleRecharge());
      expect(view, isA<CjT331WalletRecharge>());
      expect(view.fileLabel, '电子钱包充值交易明细记录文件');
      expect(view.fields, hasLength(7));
    });

    test('未接入 SFI 返回原始占位视图（保留原始字节，不猜测）', () {
      final view = CityUnionFileParser.parse(0x16, const [0x01, 0x02, 0x03]);
      expect(view, isA<CityUnionRawFileView>());
      expect(view.sfi, 0x16);
      expect(view.rawHex, '01 02 03');
      expect(view.fields, isEmpty);
      expect(view.errors, isNotEmpty);
    });
  });

  group('JSON 输出', () {
    test('包含类型化字段、字段明细、异常与原始值', () {
      final info = CjT331PublicInfoParser.parse(_sampleFile());
      final json = jsonDecode(CjT331PublicInfoParser.toPrettyJson(info))
          as Map<String, dynamic>;

      expect(json['sfi'], '0x15');
      expect(json['issuerCode'], '0123');
      expect(json['applicationSerialNumber'], '1122334455667788');
      expect(json['isInterconnectionEnabled'], isTrue);
      expect(json['errors'], isEmpty);
      expect(json['fields'], hasLength(12));
      expect(json['rawHex'], isA<String>());
    });

    test('异常字段在 JSON 中带 error 与原始值', () {
      final info = CjT331PublicInfoParser.parse(
        _sampleFile(issuer: const [0x1A, 0x23]),
      );
      final json = jsonDecode(CjT331PublicInfoParser.toPrettyJson(info))
          as Map<String, dynamic>;

      expect(json['issuerCode'], isNull);
      expect(json['errors'], contains('发卡方代码：BCD 编码非法'));
      final issuer = (json['fields'] as List).first as Map<String, dynamic>;
      expect(issuer['rawHex'], '1A 23');
      expect(issuer['error'], 'BCD 编码非法');
    });

    test('表 8 记录 JSON 包含原始值与解码值', () {
      final record =
          CjT331WalletOfflineTransactionParser.parseRecord(_sampleOffline());
      final json = jsonDecode(
        CjT331WalletOfflineTransactionParser.toPrettyJson(record),
      ) as Map<String, dynamic>;

      expect(json['sfi'], '0x10');
      expect(json['sequence'], 1);
      expect(json['sequenceHex'], '0001');
      expect(json['amountRaw'], 1000);
      expect(json['amountHex'], '000003E8');
      expect(json['transactionType'], '06');
      expect(json['transactionTypeName'], '消费');
      expect(json['terminalNumber'], '123456789012');
      expect(json['transactionDate'], '2024-05-01');
      expect(json['transactionTime'], '08:30:00');
      expect(json['errors'], isEmpty);
      expect(json['fields'], hasLength(7));
    });

    test('表 9 记录 JSON 包含原始值与解码值', () {
      final record = CjT331WalletRechargeParser.parseRecord(_sampleRecharge());
      final json = jsonDecode(
        CjT331WalletRechargeParser.toPrettyJson(record),
      ) as Map<String, dynamic>;

      expect(json['sfi'], '0x1A');
      expect(json['sequence'], 1);
      expect(json['sequenceHex'], '0001');
      expect(json['amountRaw'], 1000);
      expect(json['amountHex'], '000003E8');
      expect(json['transactionType'], '02');
      expect(json['transactionTypeName'], '充值');
      expect(json['isRecharge'], isTrue);
      expect(json['terminalNumber'], '123456789012');
      expect(json['transactionDate'], '2026-01-01');
      expect(json['transactionTime'], '12:30:45');
      expect(json['errors'], isEmpty);
      expect(json['fields'], hasLength(7));
    });
  });
}

/// 构造表 5 示例文件（默认全字段合法；按需覆盖单个字段）。
List<int> _sampleFile({
  List<int> issuer = const [0x01, 0x23],
  List<int> city = const [0x0A, 0x01],
  int enabled = 0x01,
  List<int> interop = const [0x0A, 0x01],
  List<int> serial = const [0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88],
  List<int> start = const [0x20, 0x24, 0x01, 0x01],
  List<int> expiry = const [0x20, 0x30, 0x12, 0x31],
}) =>
    [
      ...issuer, // 01-02 发卡方代码（BCD）
      ...city, // 03-04 城市代码（HEX）
      0x01, // 05 多算法支持
      0x26, // 06 行业代码
      0x00, 0x00, // 07-08 预留
      enabled, // 09 互联互通启用标识
      0x02, // 10 应用版本
      ...interop, // 11-12 互联互通标识
      ...serial, // 13-20 用户卡应用序列号
      ...start, // 21-24 应用启动日期
      ...expiry, // 25-28 应用有效日期
      0x00, 0x00, // 29-30 预留
    ];

/// 构造表 6 示例记录（默认外层字段合法；应用方自定义区填充递增字节 00~2C）。
List<int> _sampleRecord({
  int identifier = 0x09,
  int dataLength = 0x2D,
  int lockFlag = 0x00,
  List<int>? applicationData,
}) =>
    [
      identifier, // 01 记录标识
      dataLength, // 02 复合消费数据长度（0x2D=45，与自定义区等长）
      lockFlag, // 03 复合消费锁定标识
      ...(applicationData ?? List<int>.generate(45, (i) => i)), // 04-48
    ];

/// 构造表 8 示例记录（默认全字段合法，单条 23 字节）。
List<int> _sampleOffline({
  List<int> sequence = const [0x00, 0x01],
  List<int> amount = const [0x00, 0x00, 0x03, 0xE8],
  int type = 0x06,
  List<int> terminal = const [0x12, 0x34, 0x56, 0x78, 0x90, 0x12],
  List<int> date = const [0x20, 0x24, 0x05, 0x01],
  List<int> time = const [0x08, 0x30, 0x00],
}) =>
    [
      ...sequence, // 01-02 电子钱包消费交易序号（HEX）
      0x00, 0x00, 0x00, // 03-05 预留
      ...amount, // 06-09 交易金额（HEX 大端）
      type, // 10 交易类型
      ...terminal, // 11-16 交易终端编号（BCD）
      ...date, // 17-20 交易日期（BCD）
      ...time, // 21-23 交易时间（BCD）
    ];

/// 构造表 9 示例记录（默认全字段合法，单条 23 字节；
/// 金额原始值 0x000003E8 十进制 1000，单位未定义不换算）。
List<int> _sampleRecharge({
  List<int> sequence = const [0x00, 0x01],
  List<int> amount = const [0x00, 0x00, 0x03, 0xE8],
  int type = 0x02,
  List<int> terminal = const [0x12, 0x34, 0x56, 0x78, 0x90, 0x12],
  List<int> date = const [0x20, 0x26, 0x01, 0x01],
  List<int> time = const [0x12, 0x30, 0x45],
}) =>
    [
      ...sequence, // 01-02 电子钱包充值交易序号（HEX）
      0x00, 0x00, 0x00, // 03-05 预留
      ...amount, // 06-09 交易金额（HEX 大端）
      type, // 10 交易类型（02 充值）
      ...terminal, // 11-16 交易终端编号（BCD）
      ...date, // 17-20 交易日期（BCD）
      ...time, // 21-23 交易时间（BCD）
    ];
