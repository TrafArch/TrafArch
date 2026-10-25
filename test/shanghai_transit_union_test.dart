// test/shanghai_transit_union_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/scan/application/local_card_reader.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_models.dart';
import 'package:transit_card_analyzer/protocols/transit/local/cards/shanghai_transit_union_card.dart';
import 'package:transit_card_analyzer/protocols/transit/local/cards/shanghai_transit_union_models.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

const _shanghaiSerial = '3104770000000000001';

CjT331PublicInfo _publicInfo({
  String serial = _shanghaiSerial,
  String? cityCode = '3100',
  String rawHex = '86 98 20 00',
}) => CjT331PublicInfo(
  issuerCode: '8698',
  cityCode: cityCode,
  applicationSerialNumber: serial,
  fields: const [],
  rawHex: rawHex,
);

ParsedCard _tuCard({
  String serial = _shanghaiSerial,
  int? balanceFen = 1000,
  List<TUnionTransaction> transactions = const [],
}) => ParsedCard(
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

ParsedCard _cuCard({CjT331PublicInfo? public, int? balanceFen = 500}) =>
    ParsedCard(
      parserId: CardParserIds.cityUnion,
      parserName: '城市一卡通',
      info: const TUnionCardInfo().withBalance(balanceFen),
      transactions: const [],
      cityUnionFiles: [?public],
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
}) => ShanghaiTransitApplication(
  system: system,
  confirmed: confirmed,
  readSucceeded: readSucceeded,
  dataComplete: dataComplete,
  card: card,
  identity: identity,
  // 读取层会把解析出的卡号回填到 CardInfo；测试按同一约定构造，
  // 避免用空 CardInfo 模拟真实读取结果。
  cardInfo: CardInfo()
    ..cardNumber =
        card?.info.applicationSerial ?? identity?.applicationSerial ?? '',
  records: List<ApduRecord>.of(records),
);

void main() {
  for (final serial in [
    '03104770000000000001',
    '00310477000000000001',
    '03100000000000000001',
    '99104770000000000001',
    '0310477000000000000A',
    null,
  ]) {
    for (final unified in [false, true]) {
      test('门控及独立 fallback serial=$serial unified=$unified', () async {
        final link = _GateLink(serial: serial);
        final isShanghai =
            serial != null &&
            RegExp(r'^[0-9]+$').hasMatch(serial) &&
            serial.replaceFirst(RegExp(r'^0+'), '').startsWith('31047700');
        final ordinaryTu = serial == '03100000000000000001';
        if (unified) {
          final result = await LocalCardReader(link.call).read();
          expect(
            result!.parsedCard!.parserId,
            isShanghai
                ? CardParserIds.shanghaiTunion
                : ordinaryTu
                ? CardParserIds.tunion
                : CardParserIds.cityUnion,
          );
          expect(result.shanghai != null, isShanghai);
        } else {
          final result = await ShanghaiTransitUnionCardParser(link.call).read();
          expect(result.isShanghaiTransitUnion, isShanghai);
          expect(result.cu.probed, isShanghai);
          if (!isShanghai) {
            expect(result.cu.errors, isEmpty);
            expect(result.cu.records, isEmpty);
          }
        }
        final shouldCu = isShanghai || (unified && !ordinaryTu);
        expect(link.cuSelects, shouldCu ? 1 : 0);
        expect(link.cuReads, shouldCu ? 1 : 0);
        expect(link.tuReads, serial == null ? 0 : 1);
        expect(link.mfCount, shouldCu ? 2 : 1);
      });
    }
  }
  for (final unified in [false, true]) {
    for (final failCu in [false, true]) {
      test(
        '部分上海 TU 余额异常仍读 CU，CU失败保留TU unified=$unified failCu=$failCu',
        () async {
          final link = _GateLink(
            serial: '00310477000000000001',
            failBalance: true,
            failCu: failCu,
          );
          final result = unified
              ? (await LocalCardReader(link.call).read())!.shanghai!
              : await ShanghaiTransitUnionCardParser(link.call).read();
          expect(result.tu.confirmed, isTrue);
          expect(result.tu.dataComplete, isFalse);
          expect(result.tu.errors, isNotEmpty);
          expect(result.mergedCard!.info.applicationSerial, link.serial);
          expect(result.mergedCard!.info.balanceFen, isNull);
          expect(result.cu.probed, isTrue);
          expect(result.cu.errors.isNotEmpty, failCu);
          expect(link.tuReads, 1);
          expect(link.cuSelects, 1);
          expect(link.cuReads, failCu ? 0 : 1);
        },
      );
    }
  }
  group('ShanghaiTransitUnionResult', () {
    test('来源隔离：CU 卡号和 TU 发行方不能替代对应来源', () {
      for (final raw in ['', '86 98', '02 00 29 00', '00 86 98 20 00']) {
        final result = ShanghaiTransitUnionResult.build(
          tu: _application(
            system: ShanghaiTransitUnionIds.tuSystem,
            confirmed: true,
            identity: const TUnionCardInfo(issuerId: '86982000'),
            card: _tuCard(serial: '3100990000000000001'),
          ),
          cu: _application(
            system: ShanghaiTransitUnionIds.cuSystem,
            confirmed: true,
            card: _cuCard(public: _publicInfo(rawHex: raw)),
          ),
        );
        expect(result.isShanghaiTransitUnion, isFalse);
      }
    });

    test('不完整侧保留证据但不算双标，汇总不修改侧内对象', () {
      for (final complete in [false, true]) {
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
          dataComplete: complete,
          card: _cuCard(public: _publicInfo()),
        );
        tu.cardInfo.isTU = true;
        cu.cardInfo.isCU = true;
        final result = ShanghaiTransitUnionResult.build(tu: tu, cu: cu);
        expect(result.mergedCardInfo, isNot(same(tu.cardInfo)));
        expect(result.mergedCardInfo, isNot(same(cu.cardInfo)));
        expect(result.mergedCardInfo.isTU, isTrue);
        expect(result.mergedCardInfo.isCU, complete);
        expect(result.mergedCard!.dualApplication, complete);
        expect(result.mergedCard!.cityUnionFiles, hasLength(1));
        expect(tu.cardInfo.isCU, isFalse);
        expect(cu.cardInfo.isTU, isFalse);
        expect(cu.cardInfo.isCU, isTrue);
        if (complete) {
          expect(result.mergedCardInfo.cardKindLabel, contains('双应用'));
        }
      }
    });
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

    test('仅 CU 可用：保留辅助前缀但不认定上海 TU', () {
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
      expect(result.matchedPrefix, ShanghaiTransitUnionIds.issuerIdPrefix);
      expect(result.isShanghaiTransitUnion, isFalse);
      expect(result.mergedCard, isNull);
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

      expect(result.matchedPrefix, isNull);
      expect(result.structureConfirmed, isFalse);
      expect(result.isShanghaiTransitUnion, isFalse);
      expect(result.status, ShanghaiTransitUnionStatus.unknown);
      expect(result.mergedCard, isNull);
    });
  });

  test('CardInfo.copy 保留 nullable 余额及全部字段，rawInfo 独立', () {
    final source = CardInfo()
      ..cardNumber = '123'
      ..issuerCode = '86'
      ..issuerCode2 = '98'
      ..cityCode = 1
      ..terminalCode = 2
      ..previousBalance = 3
      ..deposit = 4
      ..bonus = 5
      ..extraBalance = 6
      ..remainingTrips = 7
      ..validFromDays = 8
      ..cardTypeCode = 9
      ..subtypeCode = 10
      ..issueDate = DateTime(2020)
      ..expiryDate = DateTime(2030)
      ..startDate = DateTime(2021)
      ..timezoneOffsetMinutes = 480
      ..rawInfo = [1, 2]
      ..isSuzhou = true
      ..isTU = true
      ..isCU = true
      ..isBeijing = true
      ..isWHCTC = true
      ..isTFT = true
      ..isSZT = true
      ..isYCT = true
      ..isSuxin = true
      ..isCika = true
      ..isCikaMode = true
      ..specialLocal = true
      ..lastSeenRecordIndex = 11;
    List<Object?> values(CardInfo c) => [
      c.cardNumber,
      c.issuerCode,
      c.issuerCode2,
      c.cityCode,
      c.terminalCode,
      c.observedBalance,
      c.previousBalance,
      c.deposit,
      c.bonus,
      c.extraBalance,
      c.remainingTrips,
      c.validFromDays,
      c.cardTypeCode,
      c.subtypeCode,
      c.issueDate,
      c.expiryDate,
      c.startDate,
      c.timezoneOffsetMinutes,
      c.rawInfo,
      c.isSuzhou,
      c.isTU,
      c.isCU,
      c.isBeijing,
      c.isWHCTC,
      c.isTFT,
      c.isSZT,
      c.isYCT,
      c.isSuxin,
      c.isCika,
      c.isCikaMode,
      c.specialLocal,
      c.lastSeenRecordIndex,
    ];
    final copy = source.copy();
    expect(values(copy), values(source));
    expect(copy.observedBalance, isNull);
    copy.rawInfo![0] = 9;
    expect(source.rawInfo, [1, 2]);
    for (final balance in [0, 1234]) {
      source.balance = balance;
      expect(values(source.copy()), values(source));
    }
    expect(CardInfo().copy().rawInfo, isNull);
  });

  group('ShanghaiTransitTripMerger', () {
    ApduRecord record({
      required String label,
      required DateTime time,
      required String terminal,
      int balanceDelta = 0,
    }) => ApduRecord()
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

  test('同一 APDU 通道先读 TU 成功再读 CU 成功，保留双应用独立数据', () async {
    List<int> bytes(String hex) => [
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];
    String hex(List<int> data) => data
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    String compact(String raw) => raw.replaceAll(' ', '');

    const tuPublic =
        '02002900123456780101031047700000000000012024010120291231AABB';
    const cuPublic =
        '869820000126000001022000112233445566778820240101203012310000';
    const tuTransaction = '0001000000000000C80612345678901220240501083000';
    const cuTransaction = '00020000000000012C0612345678903420240502093000';
    const cuRecharge = '0003000000000003E80212345678905620240503103000';
    final holder = List<int>.filled(55, 0)..[0] = 1;
    final management = List<int>.filled(60, 0)
      ..[6] = 0x31
      ..[10] = 1;
    final replies = <String, Map<String, List<int>>>{
      'TU': {
        '00B0950000': bytes(tuPublic),
        '00B0960000': holder,
        '00B0970000': management,
        '805C000204': bytes('00002710'),
        '00B201C500': bytes(tuTransaction),
      },
      'CU': {
        '00B095001E': bytes(cuPublic),
        '00B201C417': bytes(cuTransaction),
        '00B201D417': bytes(cuRecharge),
        '805C000204': bytes('000001F4'),
      },
    };
    const mf = '00A40000023F0000';
    const tuSelect = '00A4040008A00000063201010500';
    const cuSelect = '00A4040009A0000000038698070100';
    final commands = <String>[];
    final successfulReads = <String>[];
    String? selected;
    final parser = ShanghaiTransitUnionCardParser((apdu) async {
      final command = hex(apdu);
      commands.add(command);
      if (command == mf) {
        selected = null;
        return [0x90, 0x00];
      }
      if (command == tuSelect || command == cuSelect) {
        selected = command == tuSelect ? 'TU' : 'CU';
        return [0x90, 0x00];
      }
      final data = replies[selected]?[command];
      if (data != null) {
        successfulReads.add('$selected:$command');
        return [...data, 0x90, 0x00];
      }
      return apdu[1] == 0xB2 ? [0x6A, 0x83] : [0x6A, 0x82];
    });

    final result = await parser.read();

    expect(successfulReads, [
      'TU:00B0950000',
      'TU:00B0960000',
      'TU:00B0970000',
      'TU:805C000204',
      'TU:00B201C500',
      'CU:00B095001E',
      'CU:805C000204',
      'CU:00B201C417',
      'CU:00B201D417',
    ]);
    final cuStart = commands.indexOf(cuSelect);
    expect(cuStart, greaterThan(commands.indexOf('00B201C500')));
    expect(commands.first, mf);
    expect(commands[1], tuSelect);
    expect(commands[cuStart - 1], mf);
    expect(commands.skip(cuStart), [
      cuSelect,
      '00B095001E',
      '805C000204',
      '00B201C417',
      '00B202C417',
      '00B201D417',
      '00B202D417',
    ]);
    for (final side in [result.tu, result.cu]) {
      expect(side.confirmed, isTrue);
      expect(side.readSucceeded, isTrue);
      expect(side.dataComplete, isTrue);
      expect(side.available, isTrue);
      expect(side.errors, isEmpty);
      expect(side.warnings, isEmpty);
    }
    expect(result.status, ShanghaiTransitUnionStatus.bothAvailable);
    expect(result.isShanghaiTransitUnion, isTrue);
    expect(result.mergedCardInfo.isTU, isTrue);
    expect(result.mergedCardInfo.isCU, isTrue);
    expect(result.mergedCardInfo.cardKindLabel, contains('双应用'));
    expect(result.tu.cardInfo.isCU, isFalse);
    expect(result.cu.cardInfo.isTU, isFalse);
    expect(result.tu.cardInfo.observedBalance, 10000);
    expect(result.cu.cardInfo.observedBalance, 500);
    final tu = result.tu.card!;
    final cu = result.cu.card!;
    final merged = result.mergedCard!;
    expect(tu.selectedAidHex, 'A000000632010105');
    expect(cu.selectedAidHex, 'A00000000386980701');
    expect(tu.info.applicationSerial, '0$_shanghaiSerial');
    expect(tu.info.balanceFen, 10000);
    expect(cu.info.balanceFen, 500);
    expect(tu.transactions.single.rawHex, tuTransaction);
    expect(tu.transactions.single.amountFen, 200);
    expect(tu.cityUnionFiles, isEmpty);
    expect(cu.transactions, isEmpty);
    expect(cu.cityUnionFiles.map((f) => compact(f.rawHex)), [
      cuPublic,
      cuTransaction,
      cuRecharge,
    ]);
    expect(cu.cityUnionFiles.first, isA<CjT331PublicInfo>());
    expect(cu.cityUnionFiles[1], isA<CjT331WalletLocalConsumption>());
    expect(cu.cityUnionFiles[2], isA<CjT331WalletRecharge>());
    expect(result.tu.records, hasLength(1));
    expect(result.cu.records, hasLength(2));
    expect(result.cu.records.map((r) => r.label), ['CU 0x18#2', 'CU 0x1A#3']);
    expect(merged.dualApplication, isTrue);
    expect(merged.info.balanceFen, 10000);
    expect(merged.cityUnionBalanceFen, 500);
    expect(merged.transactions, tu.transactions);
    expect(merged.cityUnionFiles, cu.cityUnionFiles);
    expect(result.readResult.records, hasLength(3));
  });

  test('专用入口 TU 未命中时 CU 未探测，不伪造 SELECT 失败', () async {
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
      isFalse,
      reason: 'TU 未命中不得进入上海 CU',
    );
    expect(result.tu.errors, isNotEmpty);
    expect(result.cu.errors, isEmpty);
    expect(result.cu.probed, isFalse);
    expect(result.cu.stateText, '应用未探测');
  });
}

// Synthetic application-aware channel: only APDU transport is substituted.
class _GateLink {
  _GateLink({this.serial, this.failBalance = false, this.failCu = false});
  final String? serial;
  final bool failBalance;
  final bool failCu;
  String? selected;
  int tuReads = 0;
  int cuReads = 0;
  int cuSelects = 0;
  int mfCount = 0;

  Future<List<int>> call(List<int> apdu) async {
    final hex = apdu
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    List<int> ok(String data) => [
      for (var i = 0; i < data.length; i += 2)
        int.parse(data.substring(i, i + 2), radix: 16),
      0x90,
      0,
    ];
    if (hex == '00A40000023F0000') {
      mfCount++;
      selected = null;
      return ok('');
    }
    if (_contains(apdu, _tuWalletAid) && serial != null) {
      selected = 'TU';
      return ok('');
    }
    if (_contains(apdu, _cuAid)) {
      cuSelects++;
      if (failCu) throw Exception('CU select failed');
      selected = 'CU';
      return ok('');
    }
    if (selected == 'TU' && hex == '00B0950000') {
      tuReads++;
      return ok('02002900123456780101${serial!}2024010120291231AABB');
    }
    if (selected == 'CU' && hex == '00B095001E') {
      cuReads++;
      return ok('869820000126000001022000112233445566778820240101203012310000');
    }
    if (apdu[1] == 0x5C) {
      if (selected == 'TU' && failBalance) throw Exception('TU balance failed');
      return ok('000001F4');
    }
    return [0x6A, 0x82];
  }
}

const _tuWalletAid = <int>[0xA0, 0x00, 0x00, 0x06, 0x32, 0x01, 0x01, 0x05];

const _cuAid = <int>[0xA0, 0x00, 0x00, 0x00, 0x03, 0x86, 0x98, 0x07, 0x01];

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
