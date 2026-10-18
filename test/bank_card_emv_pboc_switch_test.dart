import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/bank_card/data/pdol/pdol_data_builder.dart';
import 'package:transit_card_analyzer/features/bank_card/data/tlv/hex_codec.dart';
import 'package:transit_card_analyzer/features/bank_card/domain/models/bank_card_result.dart';
import 'package:transit_card_analyzer/features/bank_card/parsers/bank_card_analyzer.dart';
import 'package:transit_card_analyzer/features/bank_card/parsers/emv/emv_parser.dart';
import 'package:transit_card_analyzer/features/bank_card/parsers/pboc/pboc_parser.dart';
import 'package:transit_card_analyzer/features/bank_card/test_support/replay_card_transport.dart';

const String _emptyDict =
    '{"schemaVersion":1,"dictionaryId":"test","entries":[]}';

Future<BankCardAnalyzer> _buildAnalyzer() async {
  final pboc = await PbocParser.load((_) async => _emptyDict);
  final emv = await EmvParser.load((_) async => _emptyDict);
  return BankCardAnalyzer([pboc, emv]);
}

void main() {
  group('PdolDataBuilder 按 PDOL 自动组包', () {
    test('PBOC 四标签按声明长度填充（9F7A/9F02/5F2A/DF69）', () {
      final data =
          PdolDataBuilder.build(HexCodec.decode('9F7A019F02065F2A02DF6901'));
      expect(HexCodec.encode(data), '01000000000000015600');
    });

    test('日期与时间按 BCD 编码（注入时钟）', () {
      final data = PdolDataBuilder.build(
        HexCodec.decode('9A039F2103'),
        now: DateTime(2026, 10, 15, 8, 30, 5),
      );
      expect(HexCodec.encode(data), '261015083005');
    });

    test('未收录标签按声明长度补零', () {
      final data = PdolDataBuilder.build(HexCodec.decode('A1039F3704'));
      expect(data.length, 7);
      expect(data.sublist(0, 3), [0, 0, 0]);
    });

    test('9F37 按声明长度生成不可预知数', () {
      final data =
          PdolDataBuilder.build(HexCodec.decode('9F3704'), random: Random(42));
      expect(data.length, 4);
    });
  });

  group('PBOC 卡：PDOL 组包 + 77 模板读取', () {
    test('GPO 命令携带 PDOL 数据，AFL 按规范读取两条记录', () async {
      final transport = ReplayCardTransport([
        _ppsePboc,
        _selectPboc,
        _selectPboc, // 发现阶段 SELECT + 解析阶段各 SELECT 一次
        _gpoPboc,
        _recordPan,
        _recordAtc,
      ]);
      final result = await (await _buildAnalyzer()).analyze(transport);

      expect(result.protocolFamily, BankCardProtocolFamily.pboc);
      expect(result.status, BankCardStatus.success);
      final app = result.applications.single;
      expect(app.parserId, 'pboc');
      expect(app.records, hasLength(2));
      expect(app.records.first.parseError, isNull);

      expect(HexCodec.encode(transport.sent[3]),
          '80A800000C830A0100000000000001560000');
      expect(HexCodec.encode(transport.sent[4]), '00B2010C00');
      expect(HexCodec.encode(transport.sent[5]), '00B2020C00');
    });
  });

  group('EMV 卡：无 PDOL 自动切换 83 00 + 80 模板读取', () {
    test('GPO 发送 83 00，AIP+AFL 裸拼接响应正确提取 AFL', () async {
      final transport = ReplayCardTransport([
        _ppseEmv,
        _selectEmv,
        _selectEmv, // 发现阶段 SELECT + 解析阶段各 SELECT 一次
        _gpoEmv,
        _recordPan,
      ]);
      final result = await (await _buildAnalyzer()).analyze(transport);

      expect(result.protocolFamily, BankCardProtocolFamily.emv);
      expect(result.status, BankCardStatus.success);
      final app = result.applications.single;
      expect(app.parserId, 'emv');
      expect(app.records, hasLength(1));

      expect(HexCodec.encode(transport.sent[3]), '80A8000002830000');
      expect(HexCodec.encode(transport.sent[4]), '00B2010C00');
    });
  });

  group('GPO 形式自动切换重试', () {
    test('PDOL 组包被拒后自动切换 83 00 重试并记录切换轨迹', () async {
      final transport = ReplayCardTransport([
        _ppsePboc,
        _selectPboc,
        _selectPboc, // 发现阶段 SELECT + 解析阶段各 SELECT 一次
        '6985',
        _gpoPboc,
        _recordPan,
        _recordAtc,
      ]);
      final result = await (await _buildAnalyzer()).analyze(transport);

      final app = result.applications.single;
      expect(app.records, hasLength(2));
      expect(result.status, BankCardStatus.partial);
      expect(app.issues.any((i) => i.code == 'switch_empty_pdol'), isTrue);

      expect(HexCodec.encode(transport.sent[3]),
          '80A800000C830A0100000000000001560000');
      expect(HexCodec.encode(transport.sent[4]), '80A8000002830000');
      expect(HexCodec.encode(transport.sent[5]), '00B2010C00');
    });
  });
}

// ---- 回放样本（公开格式的最小构造数据，不含真实卡敏感信息） ----

/// PPSE 目录：银联 PBOC 借记应用（AID A000000333010101）。
const String _ppsePboc = '6F30840E325041592E5359532E4444463031A51EBF0C1B6119'
    '4F08A000000333010101500A50424F432044454249548701019000';

/// FCI：含 PDOL 9F38 = 9F7A01 9F0206 5F2A02 DF6901。
const String _selectPboc = '6F2A8408A000000333010101A51E500A50424F432044454249'
    '548701019F380C9F7A019F02065F2A02DF69019000';

/// GPO 响应：77 模板（AIP 3900，AFL 08 01 02 00 → SFI1 记录 1-2）。
const String _gpoPboc = '770A820239009404080102009000';

/// PPSE 目录：Visa 应用（AID A0000000031010）。
const String _ppseEmv = '6F2C840E325041592E5359532E4444463031A51ABF0C1761154F0A'
    'A00000000310105004564953418701019000';

/// FCI：无 PDOL。
const String _selectEmv =
    '6F148407A0000000031010A5095004564953418701019000';

/// GPO 响应：80 模板（Format 1：AIP 5C00 + AFL 08 01 01 00 → SFI1 记录 1）。
const String _gpoEmv = '80065C00080101009000';

/// 记录：70 模板（5A 卡号 + 5F24 有效期）。
const String _recordPan =
    '70105A0862220212345678905F24032712319000';

/// 记录：70 模板（9F36 应用交易计数器）。
const String _recordAtc = '70059F360200019000';