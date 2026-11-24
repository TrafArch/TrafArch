// test/shanghai_transit_union_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/scan/application/local_card_reader.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_models.dart';
import 'package:transit_card_analyzer/protocols/transit/local/apdu_exchange.dart';
import 'package:transit_card_analyzer/protocols/transit/multiapp/application_evidence.dart';
import 'package:transit_card_analyzer/protocols/transit/local/cards/shanghai_transit_union_models.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/protocols/transport/transport_failure.dart';

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
  test('上海、哈尔滨和其他 TU 使用相同指令读取两套应用', () async {
    List<String>? baseline;
    for (final serial in [
      '03104770000000000001',
      '00310477000000000001',
      '03104970200000000001',
      '00310497020000000001',
      '03104970300000000001',
      '03100000000000000001',
    ]) {
      final link = _GateLink(serial: serial);
      final result = (await LocalCardReader(link.call).read())!;
      expect(result.parsedCard.parserId, CardParserIds.tunion);
      expect(result.parsedCard.info.applicationSerial, serial);
      expect(result.parsedCard.dualApplication, isTrue);
      expect(result.parsedCard.cityUnionBalanceFen, 500);
      expect(link.tuReads, 1);
      expect(link.cuReads, 1);
      expect(link.cuSelects, 1);
      expect(link.commands, baseline ??= List.of(link.commands));
    }
  });

  for (final serial in [null, '99104770000000000001', '0310477000000000000A']) {
    test('CU 在 TU 卡号不可用时仍独立取得身份 serial=$serial', () async {
      final link = _GateLink(serial: serial);
      final result = (await LocalCardReader(link.call).read())!;
      expect(result.parsedCard.parserId, CardParserIds.cityUnion);
      expect(
        result.applications.singleWhere((a) => a.appId == 'cu').confirmed,
        isTrue,
      );
      expect(
        result.applications.singleWhere((a) => a.appId == 'tu').cardNumber,
        isNull,
      );
      expect(link.cuSelects, 1);
      expect(link.cuReads, 1);
    });
  }

  for (final failure in [
    '00B0960000',
    '805C000204',
    '00B201C417',
    '00B201F500',
  ]) {
    test('掉卡保留已读的每个钱包且不再通信 $failure', () async {
      final link = _GateLink(
        serial: '03104770000000000001',
        failureCommand: failure,
      );
      final result = (await LocalCardReader(link.call).read())!;
      final cu = result.applications.singleWhere((a) => a.appId == 'cu');
      final reachedCu = failure == '00B201C417' || failure == '00B201F500';
      expect(result.parsedCard.info.applicationSerial, link.serial);
      expect(result.readResult.transportFailure, same(_tagLost));
      expect(result.readResult.readError, isA<ApduTransportException>());
      expect(cu.confirmed, reachedCu);
      expect(cu.balanceFen, reachedCu ? 500 : null);
      expect(
        result.applications.singleWhere((a) => a.appId == 'macau').state,
        ApplicationProbeState.notProbed,
      );
      expect(link.callsAfterFailure, 0);
    });
  }

  for (final reject in [true, false]) {
    test('TU 余额未知时也能发布身份，CU 余额独立 failCu=$reject', () async {
      final link = _GateLink(
        serial: '03104970200000000001',
        rejectBalance: true,
        failCu: reject,
      );
      final card = (await LocalCardReader(link.call).read())!.parsedCard;
      expect(card.info.applicationSerial, link.serial);
      expect(card.info.balanceFen, isNull);
      expect(card.cityUnionBalanceFen, reject ? isNull : 500);
    });
  }

  test('首个 MF 传输中断时保留原异常', () async {
    final link = _GateLink(failureCommand: '00A40000023F0000');
    await expectLater(
      LocalCardReader(link.call).read(),
      throwsA(
        isA<ApduTransportException>().having(
          (e) => e.failure,
          'original failure',
          same(_tagLost),
        ),
      ),
    );
    expect(link.callsAfterFailure, 0);
  });

  test('哈尔滨的 CU 可从 1A 读取消费，同时探测 06', () async {
    final link = _GateLink(serial: '03104970200000000001');
    final commands = <String>[];
    final result = (await LocalCardReader((apdu) async {
      final command = apdu
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join()
          .toUpperCase();
      if (link.selected == 'CU') {
        commands.add(command);
        if (command == '00B095001E') {
          return _hexReply(
            '869823000126000001022000112233445566778820240101203012310000',
          );
        }
        if (command == '00B201D417') {
          return _hexReply('00040000000000006406A1B2C3D4E5F620240504113000');
        }
      }
      return link.call(apdu);
    }).read())!;
    final cu = result.applications.singleWhere((a) => a.appId == 'cu');
    expect(
      result.parsedCard.cityUnionFiles
          .whereType<CjT331PublicInfo>()
          .single
          .cityCode,
      '2300',
    );
    expect(cu.records.single.label, 'CU 0x1A#1');
    expect(commands, containsAll(['00B2013417', '00B201D417']));
  });
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
          label: 'CU 0x10#3',
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

    for (final sfi in ['06', '1A']) {
      test('CU 0x$sfi 异地消费只与同笔 TU 消费去重，不与充值去重', () {
        final time = DateTime(2026, 3, 1, 8, 30, 12);
        final cu = record(
          label: 'CU 0x$sfi#1',
          time: time,
          terminal: '000000001234',
        );
        for (final delta in [-200, 200]) {
          final merge = ShanghaiTransitTripMerger.merge(
            tuRecords: [
              record(
                label: 'TU 0x18#1',
                time: time,
                terminal: '3100000000001234',
                balanceDelta: delta,
              ),
            ],
            cuRecords: [cu],
          );
          expect(merge.duplicateCount, delta < 0 ? 1 : 0);
          expect(merge.records, hasLength(delta < 0 ? 1 : 2));
        }
      });
    }
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
    const cuForeign = '00040000000000006406A1B2C3D4E5F620240504113000';
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
        '00B2018417': bytes(cuRecharge),
        '00B2013417': bytes(cuForeign),
        '805C000204': bytes('000001F4'),
      },
    };
    const mf = '00A40000023F0000';
    const tuSelect = '00A4040008A00000063201010500';
    const cuSelect = '00A4040009A0000000038698070100';
    final commands = <String>[];
    final successfulReads = <String>[];
    String? selected;
    final parser = LocalCardReader((apdu) async {
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

    final result = (await parser.read())!;
    expect(
      successfulReads,
      containsAllInOrder([
        'TU:00B0950000',
        'TU:00B0960000',
        'TU:00B0970000',
        'TU:805C000204',
        'TU:00B201C500',
        'CU:00B095001E',
        'CU:805C000204',
        'CU:00B201C417',
        'CU:00B2018417',
        'CU:00B2013417',
      ]),
    );
    final cuStart = commands.indexOf(cuSelect);
    expect(cuStart, greaterThan(commands.indexOf('00B201C500')));
    expect(commands[cuStart - 1], mf);
    expect(commands.lastIndexOf(tuSelect), greaterThan(cuStart));
    final tuEvidence = result.applications.singleWhere((a) => a.appId == 'tu');
    final cuEvidence = result.applications.singleWhere((a) => a.appId == 'cu');
    final tu = tuEvidence.payload! as ParsedCard;
    final cu = cuEvidence.payload! as ParsedCard;
    final merged = result.parsedCard;
    expect(tuEvidence.balanceFen, 10000);
    expect(cuEvidence.balanceFen, 500);
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
      cuForeign,
    ]);
    expect(cu.cityUnionFiles.first, isA<CjT331PublicInfo>());
    expect(cu.cityUnionFiles[1], isA<CjT331WalletLocalConsumption>());
    expect(cu.cityUnionFiles[2], isA<CjT331WalletRecharge>());
    expect(cu.cityUnionFiles[3], isA<CjT331WalletOfflineTransaction>());
    expect(cu.cityUnionFiles.map((file) => file.sfi), [0x15, 0x18, 0x10, 0x06]);
    final foreign = cu.cityUnionFiles[3] as CjT331WalletOfflineTransaction;
    expect(foreign.sequence, 4);
    expect(foreign.recordNumber, 1);
    expect(foreign.terminalHex, 'A1B2C3D4E5F6');
    expect(tuEvidence.records, hasLength(1));
    expect(cuEvidence.records, hasLength(3));
    expect(cuEvidence.records.map((r) => r.label), [
      'CU 0x18#1',
      'CU 0x10#1',
      'CU 0x06#1',
    ]);
    expect(merged.dualApplication, isTrue);
    expect(merged.info.balanceFen, 10000);
    expect(merged.cityUnionBalanceFen, 500);
    expect(merged.transactions, tu.transactions);
    expect(merged.cityUnionFiles, cu.cityUnionFiles);
    expect(result.readResult.records, hasLength(4));
  });

  test('所有应用拒绝时，TU 和 CU 都有实际探测证据', () async {
    final scan = await LocalCardReader((_) async => [0x6A, 0x82]).scan();
    expect(scan.result, isNull);
    for (final id in ['tu', 'cu', 'macau', 'suzhou_cika', 'tft']) {
      expect(
        scan.applications.singleWhere((a) => a.appId == id).state,
        ApplicationProbeState.selectRejected,
      );
    }
  });
}

// Synthetic application-aware channel: only APDU transport is substituted.
class _GateLink {
  _GateLink({
    this.serial,
    this.rejectBalance = false,
    this.failCu = false,
    this.failureCommand,
  });
  final String? serial;
  final bool rejectBalance;
  final bool failCu;
  final String? failureCommand;
  String? selected;
  int tuReads = 0;
  int cuReads = 0;
  int cuSelects = 0;
  final commands = <String>[];
  int callsAfterFailure = 0;
  bool failed = false;

  Future<List<int>> call(List<int> apdu) async {
    final hex = apdu
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    commands.add(hex);
    if (failed) callsAfterFailure++;
    if (hex == failureCommand) {
      failed = true;
      throw _tagLost;
    }
    List<int> ok(String data) => [
      for (var i = 0; i < data.length; i += 2)
        int.parse(data.substring(i, i + 2), radix: 16),
      0x90,
      0,
    ];
    if (hex == '00A40000023F0000') {
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
      if (selected == 'TU' && rejectBalance) return [0x69, 0x85];
      return ok('000001F4');
    }
    return [0x6A, 0x82];
  }
}

const _tagLost = TransportFailure(
  kind: TransportFailureKind.tagLost,
  code: 'TAG_LOST',
  message: 'synthetic card removed',
);

const _tuWalletAid = <int>[0xA0, 0x00, 0x00, 0x06, 0x32, 0x01, 0x01, 0x05];

const _cuAid = <int>[0xA0, 0x00, 0x00, 0x00, 0x03, 0x86, 0x98, 0x07, 0x01];

List<int> _hexReply(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
  0x90,
  0x00,
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
