// test/shanghai_transit_union_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/core/card/card_parser.dart';
import 'package:transit_card_analyzer/core/transit/city_union/city_union_models.dart';
import 'package:transit_card_analyzer/core/transit/local_card/cards/shanghai_transit_union_card.dart';
import 'package:transit_card_analyzer/core/transit/local_card/cards/shanghai_transit_union_models.dart';
import 'package:transit_card_analyzer/core/transit/local_card/local_card_models.dart';
import 'package:transit_card_analyzer/core/transit/tunion/tunion_models.dart';

const _shanghaiSerial = '3104770000000000001';

CjT331PublicInfo _publicInfo({
  String serial = _shanghaiSerial,
  String? cityCode = '3100',
}) =>
    CjT331PublicInfo(
      issuerCode: '0200',
      cityCode: cityCode,
      applicationSerialNumber: serial,
      fields: const [],
      rawHex: '',
    );

ParsedCard _tuCard({
  String serial = _shanghaiSerial,
  int? balanceFen = 1000,
  List<TUnionTransaction> transactions = const [],
}) =>
    ParsedCard(
      parserId: CardParserIds.tunion,
      parserName: '交通联合',
      info: TUnionCardInfo(
        issuerId: '0200290012345678',
        applicationSerial: serial,
        balanceFen: balanceFen,
      ),
      transactions: transactions,
      selectedAidHex: 'A000000632010105',
    );

ParsedCard _cuCard({
  CjT331PublicInfo? public,
  int? balanceFen = 500,
}) =>
    ParsedCard(
      parserId: CardParserIds.cityUnion,
      parserName: '城市一卡通',
      info: const TUnionCardInfo().withBalance(balanceFen),
      transactions: const [],
      cityUnionFiles: [if (public != null) public],
      selectedAidHex: 'A00000000386980701',
    );

ShanghaiTransitApplication _application({
  required String system,
  bool confirmed = false,
  bool readSucceeded = false,
  bool dataComplete = false,
  ParsedCard? card,
  TUnionCardInfo? identity,
  List<ApduRecord> records = const [],
}) =>
    ShanghaiTransitApplication(
      system: system,
      confirmed: confirmed,
      readSucceeded: readSucceeded,
      dataComplete: dataComplete,
      card: card,
      identity: identity,
      cardInfo: CardInfo(),
      records: List<ApduRecord>.of(records),
    );

void main() {
  group('ShanghaiTransitUnionResult', () {
    test('TU + CU 均可用 → bothAvailable，两套数据同时保留', () {
      final tu = _application(
        system: ShanghaiTransitUnionIds.tuSystem,
        confirmed: true,
        readSucceeded: true,
        dataComplete: true,
        card: _tuCard(),
      );
      final cu = _application(
        system: ShanghaiTransitUnionIds.cuSystem,
        confirmed: true,
        readSucceeded: true,
        dataComplete: true,
        card: _cuCard(public: _publicInfo()),
      );

      final result = ShanghaiTransitUnionResult.build(tu: tu, cu: cu);

      expect(result.status, ShanghaiTransitUnionStatus.bothAvailable);
      expect(result.isShanghaiTransitUnion, isTrue);
      expect(result.matchedPrefix, ShanghaiTransitUnionIds.cardNumberPrefix);
      expect(result.mergedCard, isNotNull);
      expect(result.mergedCard!.parserId, CardParserIds.shanghaiTunion);
      expect(result.mergedCard!.dualApplication, isTrue);
      expect(result.mergedCard!.info.balanceFen, 1000);
      expect(result.mergedCard!.cityUnionBalanceFen, 500);
      expect(result.mergedCard!.cityUnionFiles, hasLength(1));
      expect(result.readResult.info.cardNumber, _shanghaiSerial);
    });

    test('仅 TU 可用 → tuOnlyAvailable，仍成立为上海卡', () {
      final tu = _application(
        system: ShanghaiTransitUnionIds.tuSystem,
        confirmed: true,
        readSucceeded: true,
        dataComplete: true,
        card: _tuCard(),
      );
      final cu = _application(
        system: ShanghaiTransitUnionIds.cuSystem,
        confirmed: false,
        identity: const TUnionCardInfo(),
      );

      final result = ShanghaiTransitUnionResult.build(tu: tu, cu: cu);

      expect(result.status, ShanghaiTransitUnionStatus.tuOnlyAvailable);
      expect(result.isShanghaiTransitUnion, isTrue);
      expect(result.mergedCard!.dualApplication, isFalse);
      expect(result.mergedCard!.cityUnionFiles, isEmpty);
      expect(result.mergedCard!.cityUnionBalanceFen, isNull);
    });

    test('仅 CU 可用 → cuOnlyAvailable，统一卡信息回退 CU 0x15', () {
      final tu = _application(
        system: ShanghaiTransitUnionIds.tuSystem,
        confirmed: false,
      );
      final cu = _application(
        system: ShanghaiTransitUnionIds.cuSystem,
        confirmed: true,
        readSucceeded: true,
        dataComplete: true,
        card: _cuCard(public: _publicInfo()),
      );

      final result = ShanghaiTransitUnionResult.build(tu: tu, cu: cu);

      expect(result.status, ShanghaiTransitUnionStatus.cuOnlyAvailable);
      expect(result.isShanghaiTransitUnion, isTrue);
      expect(result.mergedCard!.info.displayCardNumber, _shanghaiSerial);
      expect(result.mergedCard!.info.balanceFen, 500);
      expect(result.mergedCard!.selectedAidHex, 'A00000000386980701');
    });

    test('应用已确认但数据不可读 → recognizedButUnreadable', () {
      final tu = _application(
        system: ShanghaiTransitUnionIds.tuSystem,
        confirmed: true,
        readSucceeded: false,
        identity: const TUnionCardInfo(
          applicationSerial: _shanghaiSerial,
          issuerId: '0200290012345678',
        ),
      );
      final cu = _application(
        system: ShanghaiTransitUnionIds.cuSystem,
        confirmed: false,
      );

      final result = ShanghaiTransitUnionResult.build(tu: tu, cu: cu);

      expect(result.status, ShanghaiTransitUnionStatus.recognizedButUnreadable);
      expect(result.structureConfirmed, isTrue);
      expect(result.isShanghaiTransitUnion, isTrue);
      expect(result.mergedCard, isNull);
    });

    test('仅前缀命中、无应用结构 → 不认定为上海卡', () {
      final tu = _application(
        system: ShanghaiTransitUnionIds.tuSystem,
        confirmed: false,
        identity: const TUnionCardInfo(applicationSerial: _shanghaiSerial),
      );
      final cu = _application(
        system: ShanghaiTransitUnionIds.cuSystem,
        confirmed: false,
      );

      final result = ShanghaiTransitUnionResult.build(tu: tu, cu: cu);

      expect(result.matchedPrefix, ShanghaiTransitUnionIds.cardNumberPrefix);
      expect(result.structureConfirmed, isFalse);
      expect(result.isShanghaiTransitUnion, isFalse);
      expect(result.status, ShanghaiTransitUnionStatus.unknown);
      expect(result.mergedCard, isNull);
    });
  });

  group('ShanghaiTransitTripMerger', () {
    ApduRecord record({
      required String label,
      required DateTime time,
      required String terminal,
      int balanceDelta = 0,
    }) =>
        ApduRecord()
          ..type = 2
          ..label = label
          ..timestamp = time
          ..terminalHex = terminal
          ..balanceDelta = balanceDelta;

    test('同一笔交易（分钟 + 终端号一致）只保留 TU 记录', () {
      final tu = [
        record(
          label: 'TU 0x18#1',
          time: DateTime(2026, 3, 1, 8, 30, 12),
          terminal: '3100000000001234',
          balanceDelta: -200,
        ),
      ];
      final cu = [
        record(
          label: 'CU 0x18#2',
          time: DateTime(2026, 3, 1, 8, 30, 55),
          terminal: '000000001234',
        ),
      ];

      final merge = ShanghaiTransitTripMerger.merge(
        tuRecords: tu,
        cuRecords: cu,
      );

      expect(merge.records, hasLength(1));
      expect(merge.duplicateCount, 1);
      expect(merge.records.single.label, 'TU 0x18#1');
    });

    test('交易类型矛盾 / 时间不同 / 终端不可判定时不判重', () {
      final tu = [
        record(
          label: 'TU 0x18#1',
          time: DateTime(2026, 3, 1, 8, 30, 12),
          terminal: '3100000000001234',
          balanceDelta: -200,
        ),
        record(
          label: 'TU 0x18#2',
          time: DateTime(2026, 3, 1, 9, 0, 1),
          terminal: '3100000000001234',
          balanceDelta: -300,
        ),
      ];
      final cu = [
        // 类型矛盾（充值 vs 消费）
        record(
          label: 'CU 0x1A#3',
          time: DateTime(2026, 3, 1, 8, 30, 40),
          terminal: '000000001234',
        ),
        // 时间不同
        record(
          label: 'CU 0x18#4',
          time: DateTime(2026, 3, 1, 10, 0, 0),
          terminal: '000000001234',
        ),
        // 终端号未写入
        record(
          label: 'CU 0x18#5',
          time: DateTime(2026, 3, 1, 9, 0, 30),
          terminal: '000000000000',
        ),
      ];

      final merge = ShanghaiTransitTripMerger.merge(
        tuRecords: tu,
        cuRecords: cu,
      );

      expect(merge.duplicateCount, 0);
      expect(merge.records, hasLength(5));
    });
  });

  test('TU 未命中时仍执行 CU 探测（双路独立，不跳过另一侧）', () async {
    final apdus = <List<int>>[];
    final parser = ShanghaiTransitUnionCardParser((apdu) async {
      apdus.add(List<int>.of(apdu));
      return const [0x6A, 0x82]; // 文件未找到：所有 AID 均不可用
    });

    final result = await parser.read();

    expect(result.status, ShanghaiTransitUnionStatus.unknown);
    expect(result.mergedCard, isNull);
    expect(
      apdus.any((apdu) => _contains(apdu, _tuWalletAid)),
      isTrue,
      reason: 'TU 侧 AID 选择必须执行',
    );
    expect(
      apdus.any((apdu) => _contains(apdu, _cuAid)),
      isTrue,
      reason: 'TU 未命中后 CU 侧仍必须执行',
    );
    expect(result.tu.errors, isNotEmpty);
    expect(result.cu.errors, isNotEmpty);
  });
}

const _tuWalletAid = <int>[
  0xA0, 0x00, 0x00, 0x06, 0x32, 0x01, 0x01, 0x05,
];

const _cuAid = <int>[
  0xA0, 0x00, 0x00, 0x00, 0x03, 0x86, 0x98, 0x07, 0x01,
];

bool _contains(List<int> apdu, List<int> pattern) {
  if (pattern.isEmpty || apdu.length < pattern.length) return false;
  for (var i = 0; i + pattern.length <= apdu.length; i++) {
    var matched = true;
    for (var j = 0; j < pattern.length; j++) {
      if (apdu[i + j] != pattern[j]) {
        matched = false;
        break;
      }
    }
    if (matched) return true;
  }
  return false;
}