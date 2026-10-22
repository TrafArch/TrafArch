import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/bank_card/presentation/application_detail_page.dart';
import 'package:transit_card_analyzer/protocols/bank/data/dictionary/json_tag_dictionary.dart';
import 'package:transit_card_analyzer/protocols/bank/data/tlv/hex_codec.dart';
import 'package:transit_card_analyzer/protocols/bank/domain/models/card_application.dart';
import 'package:transit_card_analyzer/protocols/bank/domain/models/card_field_summary.dart';
import 'package:transit_card_analyzer/protocols/bank/domain/models/emv_date_codec.dart';
import 'package:transit_card_analyzer/protocols/bank/parsers/emv/emv_parser.dart';

import 'support/replay_card_transport.dart';

const _emptyDictionary =
    '{"schemaVersion":1,"dictionaryId":"test","entries":[]}';
const _visa = 'A0000000031010';
const _oneRecordGpo = '80060000080101009000';

void main() {
  group('EMV 日期解码', () {
    test('3 字节 BCD YYMMDD', () {
      expect(EmvDateCodec.decodeHex('271231'), '2027-12-31');
    });

    test('4 字节 BCD YYYYMMDD', () {
      expect(EmvDateCodec.decodeHex('20271231'), '2027-12-31');
    });

    test('ASCII 6 位与 8 位数字', () {
      expect(
        EmvDateCodec.decodeHex(HexCodec.encode('271231'.codeUnits)),
        '2027-12-31',
      );
      expect(
        EmvDateCodec.decodeHex(HexCodec.encode('20271231'.codeUnits)),
        '2027-12-31',
      );
    });

    test('仅 YYMM 时输出年月，不虚构日', () {
      expect(EmvDateCodec.decodeHex('2912'), '2029-12');
      expect(EmvDateCodec.normalize('2029-12'), '2029-12');
    });

    test('非法日期不会被猜测修复', () {
      expect(EmvDateCodec.normalize('271331'), isNull);
      expect(EmvDateCodec.normalize('270230'), isNull);
      expect(EmvDateCodec.normalize('2027-13-01'), isNull);
      expect(EmvDateCodec.decodeHex('2A1231'), isNull);
    });

    test('标签字典解码 4 字节 BCD 有效期', () {
      final dictionary = JsonTagDictionary.fromJson(
        '{"entries":[{"tag":"5F24","decoder":"date_yymmdd"}]}',
      );
      expect(
        dictionary.decodeValue('5F24', [0x20, 0x27, 0x12, 0x31]),
        '2027-12-31',
      );
    });
  });

  group('CardFieldSummary 有效期证据', () {
    test('5F24 为 4 字节 BCD 时正常提取', () {
      const summary = CardFieldSummary([
        CardField(
          tag: '5F24',
          label: '应用有效期',
          value: '20271231',
          rawValueHex: '20271231',
        ),
      ]);
      expect(summary.expiry, '2027-12-31');
      expect(summary.expirySourceTag, '5F24');
    });

    test('缺少 5F24 时从二磁道 YYMM 提取', () {
      const summary = CardFieldSummary([
        CardField(
          tag: '57',
          label: '二磁道等效数据',
          value: '4111111111111111D291220100000F',
          rawValueHex: '4111111111111111D291220100000F',
          sensitive: true,
        ),
      ]);
      expect(summary.expiry, '2029-12');
      expect(summary.expirySourceTag, '57');
      expect(summary.serviceCode, '201');
    });
  });

  group('读取流程中的有效期', () {
    test('记录内 4 字节 BCD 5F24 被读到', () async {
      final replay = ReplayCardTransport([
        _fci(_visa),
        _oneRecordGpo,
        '${_tlv('70', _tlv('5A', '4111111111111111') + _tlv('5F24', '20271231'))}9000',
      ]);
      final app = await (await EmvParser.load((_) async => _emptyDictionary))
          .parse(const CardApplication(aidHex: _visa), replay);
      expect(app.summary.expiry, '2027-12-31');
      expect(app.summary.expirySourceTag, '5F24');
    });

    test('无 5F24 时使用记录内二磁道', () async {
      final replay = ReplayCardTransport([
        _fci(_visa),
        _oneRecordGpo,
        '${_tlv('70', _tlv('57', '4111111111111111D291220100000F'))}9000',
      ]);
      final app = await (await EmvParser.load((_) async => _emptyDictionary))
          .parse(const CardApplication(aidHex: _visa), replay);
      expect(app.summary.expiry, '2029-12');
      expect(app.summary.expirySourceTag, '57');
    });
  });

  testWidgets('应用详情页醒目展示有效期与来源', (tester) async {
    final replay = ReplayCardTransport([
      _fci(_visa),
      _oneRecordGpo,
      '${_tlv('70', _tlv('5A', '4111111111111111') + _tlv('5F24', '20271231'))}9000',
    ]);
    final app = await (await EmvParser.load((_) async => _emptyDictionary))
        .parse(const CardApplication(aidHex: _visa), replay);
    await tester.pumpWidget(
      MaterialApp(home: ApplicationDetailPage(application: app)),
    );
    expect(find.text('有效期'), findsOneWidget);
    expect(find.textContaining('2027-12-31'), findsWidgets);
    expect(find.textContaining('来源 5F24'), findsOneWidget);
  });
}

String _tlv(String tag, String value) {
  final length = value.length ~/ 2;
  assert(value.length.isEven);
  final encoded = length.toRadixString(16).padLeft(2, '0');
  return '$tag${length < 128 ? encoded : '81$encoded'}$value'.toUpperCase();
}

String _fci(String aid) => '${_tlv('6F', _tlv('84', aid))}9000';
