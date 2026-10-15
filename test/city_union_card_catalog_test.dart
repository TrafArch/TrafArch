import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/core/card/card_parser.dart';
import 'package:transit_card_analyzer/core/data/city_union_knowledge_base.dart';
import 'package:transit_card_analyzer/core/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/core/transit/city_union/city_union_models.dart';
import 'package:transit_card_analyzer/core/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/features/card_archive/models/card_archive_identity.dart';
import 'package:transit_card_analyzer/features/card_archive/models/card_types.dart';
import 'package:transit_card_analyzer/features/card_archive/services/card_identification_service.dart';

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

  group('CardIdentificationService 城市一卡通识别', () {
    final kb = KnowledgeBase.fromJsonStrings(cityUnionCatalog: _catalogJson);

    test('命中 CU 识别库：正式卡名 + 城市 + 卡种目录来源', () {
      final identified =
          CardIdentificationService(kb).identify(_cityUnionCard('3500'))!;
      expect(identified.identity.cardType, CardTypes.cityUnion);
      expect(identified.identity.officialName, '榕城通');
      expect(identified.identity.cityName, '福州');
      expect(
        identified.identity.identificationSource,
        CardIdentificationSources.cardCatalog,
      );
      expect(identified.cardNumber, 'AABBCCDD00112233');
    });

    test('城市有记录但无卡名：仅城市，来源为城市代码', () {
      final identified =
          CardIdentificationService(kb).identify(_cityUnionCard('2760'))!;
      expect(identified.identity.officialName, isNull);
      expect(identified.identity.cityName, '临沂');
      expect(
        identified.identity.identificationSource,
        CardIdentificationSources.cityCode,
      );
    });

    test('未收录城市代码：仅确认卡种，来源为解析器', () {
      final identified =
          CardIdentificationService(kb).identify(_cityUnionCard('9999'))!;
      expect(identified.identity.officialName, isNull);
      expect(identified.identity.cityName, isNull);
      expect(
        identified.identity.identificationSource,
        CardIdentificationSources.parserOnly,
      );
    });
  });
}

ParsedCard _cityUnionCard(String cityCode) => ParsedCard(
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
          rawHex: '',
        ),
      ],
    );

const _catalogJson = '''
{
  "entries": [
    { "postalPrefix": "2000", "cuCityProjectCode": "2000", "city": "上海", "province": "上海", "type": "city", "cardName": "上海公共交通卡（紫色 CU 版）", "cardNameStatus": "source_supported", "codeStatus": "wiki_listed_code" },
    { "postalPrefix": "3500", "city": "福州", "province": "福建", "type": "city", "cardName": "榕城通", "cardNameStatus": "candidate_name", "codeStatus": "postal_prefix_reference_only" },
    { "postalPrefix": "2760", "city": "临沂", "province": "山东", "type": "city", "cardNameStatus": "not_found_or_unverified", "codeStatus": "postal_prefix_reference_only" },
    { "city": "澳门特别行政区", "province": "澳门", "type": "special_region", "cardNameStatus": "not_found_or_unverified", "codeStatus": "not_applicable_or_unverified" }
  ]
}
''';