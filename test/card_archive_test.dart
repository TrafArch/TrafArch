import 'dart:convert';

import 'package:drift/drift.dart' show DatabaseConnection, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_identity.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_fingerprint.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_name_extension.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_types.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/application/card_identification_service.dart';

/// 卡片档案链路测试：识别（不猜测）→ 指纹（稳定、可复现）→ 仓库
/// （不重复建档、不覆盖自定义名称）→ 名称展示规则。
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('CardIdentificationService.resolve 统一结果构建器', () {
    final service = CardIdentificationService(KnowledgeBase.empty());

    test('字段去空白；空串 / 空白视为未知', () {
      final identity = service.resolve(
        cardType: CardTypes.chinaTunion,
        officialName: '  福路通 ',
        issuerName: '',
        cityName: '  ',
        source: CardIdentificationSources.cardCatalog,
        confidence: 0.8,
      );
      expect(identity.officialName, '福路通');
      expect(identity.issuerName, isNull);
      expect(identity.cityName, isNull);
      expect(
        identity.identificationSource,
        CardIdentificationSources.cardCatalog,
      );
      expect(identity.confidence, 0.8);
    });

    test('无名称证据时保持未知（部分识别）', () {
      final identity = service.resolve(cardType: CardTypes.chinaTunion);
      expect(identity.officialName, isNull);
      expect(identity.status, CardIdentificationStatus.partial);
    });

    test('有正式卡名或发行方证据视为已确认', () {
      expect(
        service
            .resolve(cardType: CardTypes.chinaTunion, officialName: '福路通')
            .status,
        CardIdentificationStatus.confirmed,
      );
      expect(
        service
            .resolve(cardType: CardTypes.chinaTunion, issuerName: '示例运营方')
            .status,
        CardIdentificationStatus.confirmed,
      );
    });
  });

  group('交通联合卡识别', () {
    final service = CardIdentificationService(_knowledge());

    test('卡种目录命中：正式卡名 / 发卡地 / 指纹 / 卡号', () {
      final identified = service.identify(
        _tunionCard(_tunionInfo()),
        analysisIdentity: const CardIdentity(
          cityName: '福州市',
          operatorName: '示例运营方',
          confidence: 0.85,
        ),
      )!;
      final identity = identified.identity;
      expect(identity.cardType, CardTypes.chinaTunion);
      expect(identity.officialName, '福路通·榕城通');
      expect(identity.issuerName, '示例运营方');
      expect(identity.cityName, '福州市');
      expect(
        identity.identificationSource,
        CardIdentificationSources.cardCatalog,
      );
      expect(identity.confidence, 0.85);
      expect(
        identified.fingerprint,
        'tunion:1122334455667788:3105060012345678900',
      );
      expect(identified.cardNumber, '3105060012345678900');
    });

    test('卡种目录细化：八达通-全国通卡', () {
      final identified = service.identify(
        _tunionCard(
          _tunionInfo(
            serial: '03104850000000123456',
            issuerId: 'AABBCCDDEEFF0011',
          ),
        ),
      )!;
      expect(identified.identity.cardType, CardTypes.octopusTunion);
      expect(identified.identity.officialName, '八达通-全国通卡');
      expect(identified.identity.cityName, '香港');
      expect(identified.cardNumber, '3104850000000123456');
    });

    test('无目录 / 指纹命中：回退城市码表，保持不猜测', () {
      final identified = service.identify(
        _tunionCard(
          _tunionInfo(
            serial: '03999990000000123456',
            issuerId: 'AABBCCDDEEFF0011',
          ),
        ),
        analysisIdentity: const CardIdentity(confidence: 0),
      )!;
      expect(identified.identity.officialName, isNull);
      expect(identified.identity.issuerName, isNull);
      expect(identified.identity.cityName, '福州市'); // 城市代码 3910 查表
      expect(
        identified.identity.identificationSource,
        CardIdentificationSources.cityCode,
      );
      expect(identified.identity.confidence, isNull); // 无证据不记录置信度
    });

    test('应用序列号缺失或全 0（未写入）：无法生成指纹，跳过建档', () {
      expect(service.identify(_tunionCard(_tunionInfo(serial: null))), isNull);
      expect(
        service.identify(
          _tunionCard(_tunionInfo(serial: '00000000000000000000')),
        ),
        isNull,
      );
    });
  });

  group('城市一卡通卡识别', () {
    final service = CardIdentificationService(_knowledge());

    test('0x15 公共应用基本信息：城市查表，正式卡名保持未知', () {
      final identified = service.identify(_cityUnionCard())!;
      expect(identified.identity.cardType, CardTypes.cityUnion);
      expect(identified.identity.officialName, isNull);
      expect(identified.identity.cityName, '福州市');
      expect(
        identified.identity.identificationSource,
        CardIdentificationSources.cityCode,
      );
      expect(identified.fingerprint, 'city_union:0012:AABBCCDD00112233');
      expect(identified.cardNumber, 'AABBCCDD00112233');
    });

    test('未读到 0x15：无法生成指纹，跳过建档', () {
      final card = ParsedCard(
        parserId: CardParserIds.cityUnion,
        parserName: '城市一卡通',
        info: const TUnionCardInfo(),
        transactions: const [],
      );
      expect(service.identify(card), isNull);
    });
  });

  group('CardFingerprint 指纹构建', () {
    test('规范化分隔符与大小写', () {
      expect(
        CardFingerprint.build(
          system: 'tu',
          issuerId: '11 22:33',
          cardNumber: '3105 0600-1234',
        ),
        'tu:112233:310506001234',
      );
    });

    test('卡号缺失 / 全 0 无法构建；发卡方全 0 视为未写入', () {
      expect(CardFingerprint.build(system: 'tu', cardNumber: null), isNull);
      expect(CardFingerprint.build(system: 'tu', cardNumber: '0000'), isNull);
      expect(
        CardFingerprint.build(
          system: 'tu',
          issuerId: '0000000000000000',
          cardNumber: '310506001234',
        ),
        'tu::310506001234',
      );
    });
  });

  group('SavedCardDisplayName 名称展示规则', () {
    test('无自定义名称：展示正式卡名；副标题为发行方 · 城市', () {
      final card = _savedCard();
      expect(card.displayName, '福路通·榕城通');
      expect(card.subtitle, '示例运营方 · 福州市');
    });

    test('有自定义名称：主名称用自定义名称，副标题保留正式卡名', () {
      final card = _savedCard(customName: '上学用的卡');
      expect(card.displayName, '上学用的卡');
      expect(card.subtitle, '福路通·榕城通 · 示例运营方 · 福州市');
    });

    test('无正式卡名与发行方城市：回退卡型兜底名称（不猜测）', () {
      final card = _savedCard(
        officialName: null,
        issuerName: null,
        cityName: null,
      );
      expect(card.displayName, '交通联合卡');
      expect(card.subtitle, '交通联合卡');
    });

    test('未知卡型：展示未识别交通卡', () {
      final card = _savedCard(
        cardType: 'mystery',
        officialName: null,
        issuerName: null,
        cityName: null,
      );
      expect(card.displayName, '未识别交通卡');
    });

    test('卡号 / 余额 / 交易条数 / 最近读取时间展示文本', () {
      final card = _savedCard(
        balanceFen: 200,
        currencyCode: 'CNY',
        transactionCount: 41,
        lastReadAt: DateTime(2026, 10, 14, 21, 40).millisecondsSinceEpoch,
      );
      expect(card.cardNumberText, '3105060012345678900');
      expect(card.balanceText, '¥ 2.00');
      expect(card.transactionCountText, '41条');
      expect(card.lastReadShortText, '10月14日 21:40');
      expect(card.lastReadFullText, '2026-10-14 21:40:00');
    });

    test('余额货币按存储的货币代码展示（如 HKD）', () {
      final card = _savedCard(balanceFen: 200, currencyCode: 'HKD');
      expect(card.balanceText, 'HK\$ 2.00');
    });

    test('未记录快照：卡号兜底文案，余额 / 条数 / 时间为 null', () {
      final card = _savedCard(
        cardNumber: null,
        balanceFen: null,
        transactionCount: null,
        lastReadAt: null,
      );
      expect(card.cardNumberText, '卡号未提供');
      expect(card.balanceText, isNull);
      expect(card.transactionCountText, isNull);
      expect(card.lastReadShortText, isNull);
      expect(card.lastReadFullText, isNull);
    });
  });

  group('CardSessionSnapshot 行程记录快照', () {
    test('编解码往返：行程 / 进出站 / 上下车记录', () {
      final snapshot = CardSessionSnapshot(
        cardCityCode: '3910',
        trips: [
          TransitTrip(
            time: DateTime(2024, 5, 1, 8, 30),
            amountFen: 4660,
            overdraftLimitFen: 0,
            isConsume: true,
            typeName: '复合消费',
            sequence: 1,
            terminalId: '123456789012',
            cityName: '福州市',
            cityCode: '3910',
            lineLabel: '2号线',
            stationLabel: '苏洋',
            appTypeName: '城市轨道交通',
            balanceAfterFen: 5340,
            rideStatusName: '出站',
          ),
        ],
        rails: [
          TransitRecord(
            statusCode: 0x02,
            entryCityCode: '3910',
            exitCityCode: '3501',
            entryStationId: '0800190030000123',
            exitStationId: '0800190030000456',
            entryTime: DateTime(2026, 8, 8, 9, 6, 2),
            exitTime: DateTime(2026, 8, 8, 9, 12, 31),
            entryBalanceFen: 2500,
            exitAmountFen: 300,
          ),
        ],
        buses: [
          BusTransitRecord(
            statusCode: 0x02,
            exitCityCode: '3501',
            entryTime: DateTime(2026, 8, 8, 9, 6, 2),
            exitTime: DateTime(2026, 8, 8, 9, 12, 31),
            transactionAmountFen: 300,
            mileage: 5,
          ),
        ],
      );

      final decoded = CardSessionSnapshot.decode(snapshot.encode())!;
      expect(decoded.cardCityCode, '3910');
      final trip = decoded.trips.single;
      expect(trip.timeText, '2024-05-01 08:30:00');
      expect(trip.amountText, '-¥46.60');
      expect(trip.rideStatusName, '出站');
      expect(trip.stationLabel, '苏洋');
      expect(trip.balanceAfterFen, 5340);
      expect(decoded.railRecord!.statusName, '出闸');
      expect(decoded.railRecord!.exitAmountFen, 300);
      expect(decoded.railRecord!.entryBalanceFen, 2500);
      expect(decoded.busRecord!.mileage, 5);
      expect(decoded.busRecord!.transactionAmountFen, 300);
    });

    test('异地用卡判定与 AppDependencies 同口径：未写入 / 不可判定不猜测', () {
      const snapshot = CardSessionSnapshot(cardCityCode: '3910');
      expect(snapshot.isRemoteUse('3501'), isTrue);
      expect(snapshot.isRemoteUse('3910'), isFalse);
      expect(snapshot.isRemoteUse(null), isFalse);
      expect(snapshot.isRemoteUse('0000'), isFalse);
      expect(const CardSessionSnapshot().isRemoteUse('3501'), isFalse);
    });

    test('空快照与损坏数据：不写入 / 解码失败返回 null', () {
      expect(const CardSessionSnapshot().isEmpty, isTrue);
      expect(const CardSessionSnapshot(cardCityCode: '3910').isEmpty, isTrue);
      expect(CardSessionSnapshot.decode('not-json'), isNull);
      expect(CardSessionSnapshot.decode('[]'), isNull);
    });

    test('sessionSnapshot：解码档案中保存的行程记录快照', () {
      expect(_savedCard().sessionSnapshot, isNull);
      expect(_savedCard(sessionDataJson: 'not-json').sessionSnapshot, isNull);
      final card = _savedCard(
        sessionDataJson: const CardSessionSnapshot(cardCityCode: '3910')
            .encode(),
      );
      expect(card.sessionSnapshot, isNotNull);
      expect(card.sessionSnapshot!.cardCityCode, '3910');
    });
  });

  group('CardRepository 卡片档案仓库', () {
    late AppDatabase db;
    late CardRepository repository;

    setUp(() {
      db = AppDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      repository = CardRepository(db);
    });

    tearDown(() => db.close());

    test('首次保存新建档案并记录最近读取时间', () async {
      await repository.saveIdentity(
        fingerprint: 'tunion:1:2',
        identity: const CardArchiveIdentity(
          cardType: CardTypes.chinaTunion,
          officialName: '福路通',
          issuerName: '示例运营方',
          cityName: '福州市',
          identificationSource: CardIdentificationSources.cardCatalog,
          confidence: 0.8,
        ),
        cardNumber: '3105060012345678900',
        readAt: DateTime(2026, 1, 1, 8, 0),
      );

      final rows = await db.select(db.savedCards).get();
      expect(rows.length, 1);
      final row = rows.single;
      expect(row.customName, isNull);
      expect(row.officialName, '福路通');
      expect(row.cardNumber, '3105060012345678900');
      expect(row.lastReadAt, DateTime(2026, 1, 1, 8, 0).millisecondsSinceEpoch);
    });

    test('重复保存：更新识别结果与读取时间，不覆盖自定义名称', () async {
      await repository.saveIdentity(
        fingerprint: 'tunion:1:2',
        identity: const CardArchiveIdentity(
          cardType: CardTypes.chinaTunion,
          officialName: '福路通',
          identificationSource: CardIdentificationSources.cardCatalog,
        ),
        readAt: DateTime(2026, 1, 1),
      );
      final first = (await db.select(db.savedCards).get()).single;
      await repository.renameCard(first.id, '上学用的卡');

      // 重新读取：识别规则升级后的正式卡名与读取时间
      await repository.saveIdentity(
        fingerprint: 'tunion:1:2',
        identity: const CardArchiveIdentity(
          cardType: CardTypes.chinaTunion,
          officialName: '福路通·榕城通',
          cityName: '福州市',
          identificationSource: CardIdentificationSources.cardCatalog,
        ),
        readAt: DateTime(2026, 1, 2),
      );

      final rows = await db.select(db.savedCards).get();
      expect(rows.length, 1); // 同一指纹不重复建档
      expect(rows.single.officialName, '福路通·榕城通'); // 识别结果可更新
      expect(rows.single.customName, '上学用的卡'); // 自定义名称不被覆盖
      expect(
        rows.single.lastReadAt,
        DateTime(2026, 1, 2).millisecondsSinceEpoch,
      );
    });

    test('renameCard：trim 后为空视为清除（恢复正式卡名）', () async {
      await repository.saveIdentity(
        fingerprint: 'tunion:1:2',
        identity: const CardArchiveIdentity(
          cardType: CardTypes.chinaTunion,
          officialName: '福路通',
          identificationSource: CardIdentificationSources.cardCatalog,
        ),
      );
      final id = (await db.select(db.savedCards).get()).single.id;

      await repository.renameCard(id, '  通勤卡  ');
      expect((await db.select(db.savedCards).get()).single.customName, '通勤卡');

      await repository.renameCard(id, '   ');
      expect((await db.select(db.savedCards).get()).single.customName, isNull);

      await repository.renameCard(id, null);
      expect((await db.select(db.savedCards).get()).single.customName, isNull);
    });

    test('保存读取快照：余额 / 货币 / 交易条数随重复读取更新', () async {
      await repository.saveIdentity(
        fingerprint: 'tunion:1:2',
        identity: const CardArchiveIdentity(cardType: CardTypes.chinaTunion),
        balanceFen: 200,
        currencyCode: 'CNY',
        transactionCount: 41,
        readAt: DateTime(2026, 1, 1),
      );
      var row = (await db.select(db.savedCards).get()).single;
      expect(row.balanceFen, 200);
      expect(row.currencyCode, 'CNY');
      expect(row.transactionCount, 41);

      await repository.saveIdentity(
        fingerprint: 'tunion:1:2',
        identity: const CardArchiveIdentity(cardType: CardTypes.chinaTunion),
        balanceFen: 350,
        currencyCode: 'CNY',
        transactionCount: 42,
        readAt: DateTime(2026, 1, 2),
      );
      row = (await db.select(db.savedCards).get()).single;
      expect(row.balanceFen, 350);
      expect(row.transactionCount, 42);
    });

    test('行程记录快照：新捕获单独保存，旧原文保留在历史批次', () async {
      await repository.saveIdentity(
        fingerprint: 'tunion:1:2',
        identity: const CardArchiveIdentity(cardType: CardTypes.chinaTunion),
        sessionDataJson: '{"trips":[{"sequence":1}]}',
        readAt: DateTime(2026, 1, 1),
      );
      var row = (await db.select(db.savedCards).get()).single;
      expect(row.sessionDataJson, '{"trips":[{"sequence":1}]}');

      // 再次读取未解析到行程：保留本次空捕获，旧内容仍在独立历史批次。
      await repository.saveIdentity(
        fingerprint: 'tunion:1:2',
        identity: const CardArchiveIdentity(cardType: CardTypes.chinaTunion),
        readAt: DateTime(2026, 1, 2),
      );
      row = (await db.select(db.savedCards).get()).single;
      final latest = CardSessionSnapshot.decodeResult(row.sessionDataJson!);
      expect(latest.formatVersion, 3);
      expect(latest.snapshot!.trips, isEmpty);
      final retained = await repository.watchBatches(row.id).first;
      expect(
        retained.map((b) => b.payloadJson),
        contains('{"trips":[{"sequence":1}]}'),
      );

      // 重新解析到行程：更新为新快照
      await repository.saveIdentity(
        fingerprint: 'tunion:1:2',
        identity: const CardArchiveIdentity(cardType: CardTypes.chinaTunion),
        sessionDataJson: '{"trips":[{"sequence":1},{"sequence":2}]}',
        readAt: DateTime(2026, 1, 3),
      );
      row = (await db.select(db.savedCards).get()).single;
      expect(row.sessionDataJson, '{"trips":[{"sequence":1},{"sequence":2}]}');
    });

    test('watchCards：最近读取的卡片在前', () async {
      await repository.saveIdentity(
        fingerprint: 'tunion:1:1',
        identity: const CardArchiveIdentity(cardType: CardTypes.chinaTunion),
        readAt: DateTime(2026, 1, 1),
      );
      await repository.saveIdentity(
        fingerprint: 'tunion:1:2',
        identity: const CardArchiveIdentity(cardType: CardTypes.chinaTunion),
        readAt: DateTime(2026, 1, 2),
      );

      final cards = await repository.watchCards().first;
      expect(cards.map((c) => c.cardFingerprint).toList(), [
        'tunion:1:2',
        'tunion:1:1',
      ]);
    });

    test('deleteCard：删除档案并清理其读取批次，其他卡片不受影响', () async {
      await repository.saveIdentity(
        fingerprint: 'tunion:1:1',
        identity: const CardArchiveIdentity(cardType: CardTypes.chinaTunion),
        sessionDataJson: '{"trips":[{"sequence":1}]}',
      );
      await repository.saveIdentity(
        fingerprint: 'tunion:1:2',
        identity: const CardArchiveIdentity(cardType: CardTypes.chinaTunion),
        sessionDataJson: '{"trips":[{"sequence":2}]}',
      );
      final cards = await repository.watchCards().first;
      final target = cards.firstWhere((c) => c.cardFingerprint == 'tunion:1:2');
      final survivor = cards.firstWhere(
        (c) => c.cardFingerprint == 'tunion:1:1',
      );

      expect(await repository.deleteCard(target.id), isTrue);

      final remaining = await repository.watchCards().first;
      expect(remaining.map((c) => c.cardFingerprint).toList(), ['tunion:1:1']);
      final batches = await db.select(db.cardReadBatches).get();
      expect(batches.map((b) => b.cardId).toSet(), {survivor.id});

      // 重复删除：档案已不存在时返回 false
      expect(await repository.deleteCard(target.id), isFalse);
    });
  });
}

/// 最小知识库：卡种目录（福路通 + 八达通条目）、发卡机构指纹。
KnowledgeBase _knowledge() => KnowledgeBase.fromJsonStrings(
  cityUnionCatalog: jsonEncode({
    'entries': [
      {'cuCityProjectCode': '3910', 'city': '福州市'},
    ],
  }),
  cardPrefixes: jsonEncode({
    'entries': [
      {
        'prefix': '31050600',
        'issuer': '01283910',
        'cardName': '福路通·榕城通',
        'city': '福州市',
      },
      {'prefix': '31048500', 'cardName': '八达通-全国通卡', 'city': '香港'},
    ],
  }),
  issuerFingerprints: jsonEncode({
    'entries': [
      {
        'issuerId': '1122334455667788',
        'cityCode': '3910',
        'cityName': '福州市',
        'operator': '示例运营方',
      },
    ],
  }),
);

TUnionCardInfo _tunionInfo({
  String? serial = '03105060012345678900',
  String? issuerId = '1122334455667788',
  String? cityCode = '3910',
}) => TUnionCardInfo(
  applicationSerial: serial,
  issuerId: issuerId,
  cityCode: cityCode,
);

ParsedCard _tunionCard(TUnionCardInfo info) => ParsedCard(
  parserId: CardParserIds.tunion,
  parserName: '交通联合',
  info: info,
  transactions: const [],
);

ParsedCard _cityUnionCard() => ParsedCard(
  parserId: CardParserIds.cityUnion,
  parserName: '城市一卡通',
  info: const TUnionCardInfo(),
  transactions: const [],
  cityUnionFiles: [
    const CjT331PublicInfo(
      issuerCode: '0012',
      cityCode: '3910',
      applicationSerialNumber: 'AABBCCDD00112233',
      fields: [],
      rawHex: '',
    ),
  ],
);

SavedCard _savedCard({
  String cardType = CardTypes.chinaTunion,
  String? officialName = '福路通·榕城通',
  String? customName,
  String? issuerName = '示例运营方',
  String? cityName = '福州市',
  String? cardNumber = '3105060012345678900',
  int? balanceFen,
  String? currencyCode,
  int? transactionCount,
  String? sessionDataJson,
  int? lastReadAt = 1000,
}) => SavedCard(
  id: 'card-1',
  cardFingerprint: 'tunion:1:2',
  cardType: cardType,
  officialName: officialName,
  customName: customName,
  issuerName: issuerName,
  cityName: cityName,
  identificationSource: CardIdentificationSources.cardCatalog,
  identificationConfidence: 0.85,
  cardNumber: cardNumber,
  balanceFen: balanceFen,
  currencyCode: currencyCode,
  transactionCount: transactionCount,
  sessionDataJson: sessionDataJson,
  cardImagePath: null,
  lastReadAt: lastReadAt,
  createdAt: 900,
  updatedAt: 1000,
);
