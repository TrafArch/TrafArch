import 'dart:convert';

import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/features/scan/domain/scan_presentation.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/city_union_knowledge_base.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_models.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/cj_t331_public_info_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_identity.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_types.dart';
import 'package:transit_card_analyzer/features/archive/application/card_identification_service.dart';

void main() {
  group('CityUnionCardTable 解析与查表', () {
    final table = CityUnionCardTable.fromJson(jsonDecode(_catalogJson));

    test('按邮编前四位命中城市与卡名', () {
      final info = table.lookup('3500');
      expect(info, isNotNull);
      expect(info!.city, '福州');
      expect(info.province, '福建');
      expect(info.cardName, '榕城通');
      expect(info.hasCardName, isTrue);
      expect(info.isCardNameSupported, isFalse);
    });

    test('CU 城市项目代码同样可查表（上海 source_supported）', () {
      final info = table.lookup('2000');
      expect(info!.city, '上海');
      expect(info.cardName, '上海公共交通卡（紫色 CU 版）');
      expect(info.isCardNameSupported, isTrue);
    });

    test('未收录 / 空代码返回 null（不猜测）', () {
      expect(table.lookup('9999'), isNull);
      expect(table.lookup(null), isNull);
      expect(table.lookup('  '), isNull);
    });

    test('无代码条目（澳门）不计入查表键，但保留在条目列表', () {
      expect(table.lookup(null), isNull);
      expect(table.entries.any((e) => e.city == '澳门特别行政区'), isTrue);
    });
  });

  group('实际发行标识识别', () {
    final table = CityUnionCardTable.fromJson(jsonDecode(_catalogJson));

    test('同城市不同发行标识不按城市猜名', () {
      expect(
        table.resolveCard(cityCode: '3500', rawHex: _raw('544B3500'))!.cardName,
        '榕城通',
      );
      final unknown = table.resolveCard(
        cityCode: '3500',
        rawHex: _raw('12343500'),
      )!;
      expect(unknown.city, '福州');
      expect(unknown.province, '福建');
      expect(unknown.cardName, isNull);
      expect(unknown.isCardNameSupported, isFalse);
      expect(
        table.resolveCard(cityCode: '2000', rawHex: _raw('12342000'))!.cardName,
        isNull,
      );
    });

    test('完整八位标识保留前导零与 A-F，不依赖城市目录', () {
      expect(table.resolveCard(rawHex: _raw('00012230'))!.cardName, '淮安交通卡');
      final hex = table.resolveCard(rawHex: _raw('00abcdef'))!;
      expect(hex.cardName, '十六进制测试卡');
      expect(hex.city, isEmpty);
      expect(table.resolveCard(rawHex: _raw('544b3500'))!.cardName, '榕城通');
    });

    test('上海覆盖要求命中发行表、30 字节且索引28高半字节4', () {
      for (final marker in [0x40, 0x4f]) {
        expect(
          table.resolveCard(rawHex: _raw('86982000', marker: marker))!.cardName,
          '上海都市旅游卡',
        );
      }
      expect(
        table
            .resolveCard(rawHex: _raw('86982000', length: 29, marker: 0x40))!
            .cardName,
        '上海公共交通卡',
      );
      expect(
        table.resolveCard(rawHex: _raw('86982000', marker: 0x50))!.cardName,
        '上海公共交通卡',
      );
      expect(table.resolveCard(rawHex: _raw('12342000', marker: 0x40)), isNull);
    });

    test('未知、缺失、畸形原始数据不确认名称', () {
      for (final raw in [
        null,
        '',
        '544B',
        '544B350',
        '544B35000',
        '544B3500GG',
        ' 544B3500',
        '544B3500\n',
        _raw('FFFFFFFF'),
      ]) {
        expect(table.resolveCard(rawHex: raw), isNull);
        expect(
          table.resolveCard(cityCode: '3500', rawHex: raw)!.cardName,
          isNull,
        );
      }
    });
  });

  group('CardIdentificationService 城市一卡通识别', () {
    final kb = KnowledgeBase.fromJsonStrings(cityUnionCatalog: _catalogJson);

    test('字段视图的空格分隔原始字节可进入实际扫描和归档卡名识别', () {
      final compact = _raw('544B3500');
      final public = CjT331PublicInfoParser.parse([
        for (var index = 0; index < compact.length; index += 2)
          int.parse(compact.substring(index, index + 2), radix: 16),
      ]);
      expect(public.rawHex, contains(' '));
      final card = ParsedCard(
        parserId: CardParserIds.cityUnion,
        parserName: '城市一卡通',
        info: const TUnionCardInfo(),
        transactions: const [],
        cityUnionFiles: [public],
      );
      expect(
        ScanPresentation(TransitReadOutcome(card), kb).cityUnionCard!.cardName,
        '榕城通',
      );
      expect(
        CardIdentificationService(kb).identify(card)!.identity.officialName,
        '榕城通',
      );
    });

    test('命中 CU 识别库：正式卡名 + 城市 + 卡种目录来源', () {
      final identified = CardIdentificationService(kb)
          .identify(_cityUnionCard('3500'))!;
      expect(identified.identity.cardType, CardTypes.cityUnion);
      expect(identified.identity.officialName, '榕城通');
      expect(identified.identity.cityName, '福州');
      expect(
        identified.identity.identificationSource,
        CardIdentificationSources.cardCatalog,
      );
      expect(identified.cardNumber, 'AABBCCDD00112233');
    });

    test('扫描展示与归档使用相同实际名称，不提升候选名称', () {
      for (final issuer in ['544B3500', '12343500', '00012230']) {
        final card = _cityUnionCard('3500', rawHex: _raw(issuer));
        final scan = ScanPresentation(TransitReadOutcome(card), kb);
        final identified = CardIdentificationService(kb).identify(card)!;
        expect(scan.cityUnionCard!.cardName, identified.identity.officialName);
      }
    });

    test('名称升级不改变旧发行代码与序列号指纹，无城市时转 null', () {
      final card = _cityUnionCard('9999', rawHex: _raw('00012230'));
      final identified = CardIdentificationService(kb).identify(card)!;
      final before = CardIdentificationService(KnowledgeBase.empty())
          .identify(card)!;
      expect(identified.identity.officialName, '淮安交通卡');
      expect(identified.identity.cityName, isNull);
      expect(identified.fingerprint, before.fingerprint);
      expect(identified.fingerprint, 'city_union:0012:AABBCCDD00112233');
    });

    test('城市有记录但无卡名：仅城市，来源为城市代码', () {
      final identified = CardIdentificationService(kb)
          .identify(_cityUnionCard('2760'))!;
      expect(identified.identity.officialName, isNull);
      expect(identified.identity.cityName, '临沂');
      expect(
        identified.identity.identificationSource,
        CardIdentificationSources.cityCode,
      );
    });

    test('未收录城市代码：仅确认卡种，来源为解析器', () {
      final identified = CardIdentificationService(kb)
          .identify(_cityUnionCard('9999'))!;
      expect(identified.identity.officialName, isNull);
      expect(identified.identity.cityName, isNull);
      expect(
        identified.identity.identificationSource,
        CardIdentificationSources.parserOnly,
      );
    });
  });
}

ParsedCard _cityUnionCard(String cityCode, {String? rawHex}) => ParsedCard(
  parserId: CardParserIds.cityUnion,
  parserName: '城市一卡通',
  info: const TUnionCardInfo(),
  transactions: const [],
  cityUnionFiles: [
    CjT331PublicInfo(
      issuerCode: '0012',
      cityCode: cityCode,
      applicationSerialNumber: 'AABBCCDD00112233',
      fields: const [],
      rawHex: rawHex ?? _raw('544B$cityCode'),
    ),
  ],
);

String _raw(String issuer, {int length = 30, int marker = 0}) {
  final bytes = List.filled(length, '00');
  for (var i = 0; i < 4; i++) {
    bytes[i] = issuer.substring(i * 2, i * 2 + 2);
  }
  const serial = 'AABBCCDD00112233';
  for (var i = 0; i < 8 && i + 12 < length; i++) {
    bytes[i + 12] = serial.substring(i * 2, i * 2 + 2);
  }
  if (length > 28) bytes[28] = marker.toRadixString(16).padLeft(2, '0');
  return bytes.join();
}

const _catalogJson = '''
{
  "issuerNames": [
    {"issuer_code":"544B3500","name_zh_cn":"榕城通","name_en":"Green Payment Card"},
    {"issuer_code":"86982000","name_zh_cn":"上海公共交通卡"},
    {"issuer_code":"00012230","name_zh_cn":"淮安交通卡"},
    {"issuer_code":"00ABCDEF","name_zh_cn":"十六进制测试卡"}
  ],
  "nameOverrides": [
    {"rule_id":"shanghai_city_tour","issuer_code":"86982000","requires_map_match":1,"min_raw_length":30,"byte_index":28,"high_nibble":4,"name_zh_cn":"上海都市旅游卡"}
  ],
  "entries": [
    { "postalPrefix": "2000", "cuCityProjectCode": "2000", "city": "上海", "province": "上海", "type": "city", "cardName": "上海公共交通卡（紫色 CU 版）", "cardNameStatus": "source_supported", "codeStatus": "wiki_listed_code" },
    { "postalPrefix": "3500", "city": "福州", "province": "福建", "type": "city", "cardName": "榕城通", "cardNameStatus": "candidate_name", "codeStatus": "postal_prefix_reference_only" },
    { "postalPrefix": "2760", "city": "临沂", "province": "山东", "type": "city", "cardNameStatus": "not_found_or_unverified", "codeStatus": "postal_prefix_reference_only" },
    { "city": "澳门特别行政区", "province": "澳门", "type": "special_region", "cardNameStatus": "not_found_or_unverified", "codeStatus": "not_applicable_or_unverified" }
  ]
}
''';
