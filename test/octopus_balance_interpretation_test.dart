import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/transit_analysis/balance_interpretation.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

void main() {
  group('八达通全国通余额解释', () {
    test('4225 保留 TU 人民币观察，不伪造港币余额或汇率', () {
      final result = BalanceInterpretation.fromParsedCard(_card(4225));
      expect(result.product, BalanceProduct.octopusTunion);
      expect(result.semantics, BalanceSemantics.tuObservation);
      expect(result.matchedPrefix, '31048500');
      expect(result.rawApplicationSerial, '03104850000000123456');
      expect(result.parserId, 'tunion');
      expect(result.selectedAidHex, 'A000000632010105');
      expect(result.observedAmountMinor, 4225);
      expect(result.observedCurrency, 'CNY');
      expect(result.accountCurrency, 'HKD');
      expect(result.accountBalanceMinor, isNull);
      expect(result.exchangeRate, isNull);
      expect(result.accountBalanceText, '港币余额未读取');
      expect(result.observedBalanceText, '¥42.25');
      expect(result.observationLabel, 'TU侧金额');
      expect(result.safeDisplayText, contains('港币余额未读取'));
      expect(result.safeDisplayText, contains('TU侧金额：¥42.25'));
      expect(result.safeDisplayText, isNot(contains('HK\$42.25')));
    });

    test('TU 零值是有效观察，但不是已验证的 HKD 零余额', () {
      final result = BalanceInterpretation.fromParsedCard(_card(0));
      expect(result.observedAmountMinor, 0);
      expect(result.observedBalanceText, '¥0.00');
      expect(result.accountBalanceMinor, isNull);
      expect(result.accountBalanceText, '港币余额未读取');
    });

    test('未读到余额不能补零或生成任何金额', () {
      final result = BalanceInterpretation.fromParsedCard(_card(null));
      expect(result.observedAmountMinor, isNull);
      expect(result.observedBalanceText, isNull);
      expect(result.accountBalanceMinor, isNull);
      expect(result.safeDisplayText, isNot(contains('0.00')));
    });

    test('普通 TU 使用直接 CNY 余额语义', () {
      final result = BalanceInterpretation.fromParsedCard(
        _card(4225, serial: '03101000000000123456'),
      );
      expect(result.product, BalanceProduct.tunion);
      expect(result.semantics, BalanceSemantics.direct);
      expect(result.matchedPrefix, isNull);
      expect(result.accountCurrency, 'CNY');
      expect(result.accountBalanceMinor, 4225);
      expect(result.accountBalanceText, '¥42.25');
      expect(result.safeDisplayText, '¥42.25');
    });

    test('普通 TU 的零余额与未知余额保持区别', () {
      for (final amount in <int?>[0, null]) {
        final result = BalanceInterpretation.fromParsedCard(
          _card(amount, serial: '03101000000000123456'),
        );
        expect(result.accountBalanceMinor, amount);
        expect(result.accountBalanceText, amount == null ? '余额未读取' : '¥0.00');
      }
    });

    test('前缀 HKD 元数据不能把 TU 金额变为港币读数', () {
      for (final serial in ['03104850000000123456', '03101000000000123456']) {
        final result = BalanceInterpretation.fromParsedCard(
          _card(4225, serial: serial),
          metadataCurrency: 'HKD',
        );
        expect(result.observedCurrency, 'CNY');
        expect(result.observedAmountMinor, 4225);
        expect(result.safeDisplayText, isNot(contains('HK\$42.25')));
        expect(result.toJson()['metadataCurrency'], 'HKD');
      }
    });

    test('不匹配的 parser 不套用全国通身份和余额语义', () {
      final result = BalanceInterpretation.fromParsedCard(
        _card(4225, parser: CardParserIds.cityUnion),
      );
      expect(result.product, BalanceProduct.unknown);
      expect(result.semantics, BalanceSemantics.unknown);
      expect(result.observedAmountMinor, 4225);
      expect(result.observedCurrency, isNull);
      expect(result.accountBalanceMinor, isNull);
      expect(result.accountCurrency, isNull);
      expect(result.safeDisplayText, isNot(contains('HK\$')));
    });

    test('矛盾 AID 或仅有前缀不能当作真实全国通身份', () {
      final wrongAid = BalanceInterpretation.fromParsedCard(
        _card(4225, aid: 'A00000000386980701'),
      );
      expect(wrongAid.semantics, BalanceSemantics.unknown);
      expect(wrongAid.accountBalanceMinor, isNull);
      final prefixOnly = BalanceInterpretation.fromParsedCard(
        _card(4225, serial: '31048500'),
      );
      expect(prefixOnly.product, isNot(BalanceProduct.octopusTunion));
      expect(prefixOnly.semantics, BalanceSemantics.unknown);
      expect(prefixOnly.accountBalanceMinor, isNull);
    });

    test('10 字节序列号兼容多个补零及未补零，原始值无损保留', () {
      for (final serial in [
        '00310485000000000001',
        '03104850000000123456',
        '31048500000000123456',
      ]) {
        final result = BalanceInterpretation.fromParsedCard(
          _card(4225, serial: serial),
        );
        expect(result.isOctopusTunion, isTrue, reason: serial);
        expect(result.rawApplicationSerial, serial);
        expect(result.accountBalanceMinor, isNull);
        expect(result.accountBalanceText, '港币余额未读取');
      }
    });

    test('截断或非法的全国通序列号不升级为普通 TU 直接余额', () {
      for (final serial in [
        '3104850000000123456',
        '0310485000000012345',
        '0310485000000012345A',
        '003104850000000000001',
      ]) {
        final result = BalanceInterpretation.fromParsedCard(
          _card(4225, serial: serial),
        );
        expect(result.product, BalanceProduct.unknown, reason: serial);
        expect(result.accountBalanceMinor, isNull);
        expect(result.observedAmountMinor, 4225);
        expect(result.rawApplicationSerial, serial);
      }
    });

    test('显式已验证的独立 HKD 读数可展示，TU 原数及未知汇率不变', () {
      final result = BalanceInterpretation.fromParsedCard(
        _card(4225),
        verifiedAccountBalance: VerifiedAccountBalance(
          amountMinor: 5000,
          currency: 'HKD',
          evidenceSource: 'test:independently-verified-account-read',
        ),
      );
      expect(result.accountBalanceMinor, 5000);
      expect(result.accountBalanceText, 'HK\$50.00');
      expect(result.safeDisplayText, 'HK\$50.00');
      expect(result.observedAmountMinor, 4225);
      expect(result.observedBalanceText, '¥42.25');
      expect(result.exchangeRate, isNull);
      final restored = BalanceInterpretation.fromJson(
        _roundTrip(result.toJson()),
      );
      expect(restored.accountBalanceText, 'HK\$50.00');
      expect(
        restored.verifiedAccountBalance!.evidenceSource,
        'test:independently-verified-account-read',
      );
      expect(restored.observedAmountMinor, 4225);
    });

    test('已验证 HKD 读数可以独立于缺失的 TU 金额，且零值有效', () {
      final result = BalanceInterpretation.fromParsedCard(
        _card(null),
        verifiedAccountBalance: VerifiedAccountBalance(
          amountMinor: 0,
          currency: 'HKD',
          evidenceSource: 'test:verified-zero',
        ),
      );
      expect(result.accountBalanceText, 'HK\$0.00');
      expect(result.observedAmountMinor, isNull);
      expect(result.exchangeRate, isNull);
    });

    test('不同币种或缺少证据来源的显式读数被拒绝', () {
      expect(
        () => BalanceInterpretation.fromParsedCard(
          _card(4225),
          verifiedAccountBalance: VerifiedAccountBalance(
            amountMinor: 5000,
            currency: 'CNY',
            evidenceSource: 'test:wrong-currency',
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => VerifiedAccountBalance(
          amountMinor: 5000,
          currency: 'HKD',
          evidenceSource: ' ',
        ),
        throwsArgumentError,
      );
    });

    test('fromCardInfo 保留原始序列号及调用方历史证据', () {
      final result = BalanceInterpretation.fromCardInfo(
        const TUnionCardInfo(
          applicationSerial: '03104850000000123456',
          balanceFen: 4225,
        ),
        parserId: 'tunion',
        selectedAidHex: 'A000000632010105',
        extensions: {
          'readBatchId': 'batch-001',
          'rawEvidence': {'verified': false, 'apduRef': null},
        },
      );
      expect(result.toJson()['rawApplicationSerial'], '03104850000000123456');
      expect(result.toJson()['readBatchId'], 'batch-001');
      expect(result.toJson()['rawEvidence'], {
        'verified': false,
        'apduRef': null,
      });
    });

    test('JSON 往返无损保留未知嵌套字段，外部修改不污染历史', () {
      final json = BalanceInterpretation.fromParsedCard(_card(4225)).toJson();
      json['future'] = {
        'items': [
          1,
          null,
          '0012',
          {'x': true},
        ],
      };
      final expected = _roundTrip(json);
      final decoded = BalanceInterpretation.fromJson(json);
      (json['future'] as Map<String, dynamic>)['items'] = ['changed'];
      expect(decoded.toJson(), expected);
      final exported = decoded.toJson();
      (exported['future'] as Map<String, dynamic>)['items'] = ['changed-again'];
      expect(decoded.toJson(), expected);
      expect(decoded.accountBalanceMinor, isNull);
    });

    test('没有独立验证证据的归档港币数字和汇率不能变成已读余额', () {
      final json = BalanceInterpretation.fromParsedCard(_card(4225)).toJson();
      json['accountBalanceMinor'] = 4225;
      json['exchangeRate'] = {'futureUnverifiedRate': 123};
      final result = BalanceInterpretation.fromJson(json);
      expect(result.accountBalanceMinor, isNull);
      expect(result.semantics, BalanceSemantics.unknown);
      expect(result.accountBalanceText, '余额未读取');
      expect(result.exchangeRate, isNull);
      expect(result.toJson(), json);
    });

    test('归档账户金额与独立验证证据矛盾时保留原文并停止解释', () {
      final json = BalanceInterpretation.fromParsedCard(
        _card(4225),
        verifiedAccountBalance: VerifiedAccountBalance(
          amountMinor: 5000,
          currency: 'HKD',
          evidenceSource: 'test:verified-account',
        ),
      ).toJson();
      for (final contradictory in <Object?>[4225, 5000.0, null, '5000']) {
        final changed = _roundTrip(json)
          ..['accountBalanceMinor'] = contradictory;
        final result = BalanceInterpretation.fromJson(changed);
        expect(result.semantics, BalanceSemantics.unknown);
        expect(result.accountBalanceMinor, isNull);
        expect(result.safeDisplayText, isNot(contains('HK\$50.00')));
        expect(result.toJson(), changed);
      }
    });

    test('新采集的扩展不能覆盖受保护金额字段或伪造验证证据', () {
      final result = BalanceInterpretation.fromParsedCard(
        _card(4225),
        extensions: {
          'accountBalanceMinor': 5000,
          'observedCurrency': 'HKD',
          'semantics': 'direct',
          'exchangeRate': 123,
          'verifiedAccountBalance': {'verification': 'verified'},
          'futureEvidence': {'id': '001'},
        },
      );
      final json = result.toJson();
      expect(json['accountBalanceMinor'], isNull);
      expect(json['observedCurrency'], 'CNY');
      expect(json['semantics'], 'tuObservation');
      expect(json['exchangeRate'], isNull);
      expect(json['verifiedAccountBalance'], isNull);
      expect(json['futureEvidence'], {'id': '001'});
      expect(BalanceInterpretation.fromJson(json).isOctopusTunion, isTrue);
    });

    test('非整数版本号不按当前版本读取，但完整保留', () {
      final json = BalanceInterpretation.fromParsedCard(_card(4225)).toJson();
      json['version'] = 1.0;
      final result = BalanceInterpretation.fromJson(json);
      expect(result.semantics, BalanceSemantics.unknown);
      expect(result.toJson(), json);
    });

    test('未知未来版本保持原文，禁止按当前语义解释金额', () {
      final json = BalanceInterpretation.fromParsedCard(_card(4225)).toJson();
      json['version'] = 99;
      json['semantics'] = 'futureSemantics';
      json['accountBalanceMinor'] = 5000;
      final result = BalanceInterpretation.fromJson(json);
      expect(result.semantics, BalanceSemantics.unknown);
      expect(result.accountBalanceText, '余额未读取');
      expect(result.toJson(), json);
    });

    test('整数格式化保留负金额和分位，不经过浮点换算', () {
      final result = BalanceInterpretation.fromParsedCard(_card(-5));
      expect(result.observedBalanceText, '¥-0.05');
      expect(result.accountBalanceText, '港币余额未读取');
    });
  });
}

Map<String, dynamic> _roundTrip(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

ParsedCard _card(
  int? amount, {
  String serial = '03104850000000123456',
  String parser = CardParserIds.tunion,
  String aid = 'A000000632010105',
}) => ParsedCard(
  parserId: parser,
  parserName: 'test',
  info: TUnionCardInfo(applicationSerial: serial, balanceFen: amount),
  transactions: const [],
  selectedAidHex: aid,
);
