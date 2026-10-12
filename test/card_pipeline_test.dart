import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/core/analysis/analysis_engine.dart';
import 'package:transit_card_analyzer/core/analysis/analysis_models.dart';
import 'package:transit_card_analyzer/core/card/card_parser.dart';
import 'package:transit_card_analyzer/core/data/knowledge_base.dart';
import 'package:transit_card_analyzer/core/data/station_codes.dart';
import 'package:transit_card_analyzer/core/data/terminal_decoder.dart';
import 'package:transit_card_analyzer/core/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/core/transit/tunion/tunion_parser.dart';
import 'package:transit_card_analyzer/core/transit/tunion/tunion_process_parser.dart';

void main() {
  group('TUnionParser 解析管道', () {
    test('完整读取：标准文件 + 余额 + 交易记录', () async {
      final parsed = await TUnionParser(_baseLink().call).parse();

      expect(parsed, isNotNull);
      final info = parsed!.info;
      expect(info.issuerId, '1122334455667788');
      expect(info.applicationSerial, '01020304050607080900');
      expect(info.effectiveDate, DateTime(2024, 1, 1));
      expect(info.expireDate, DateTime(2029, 12, 31));
      expect(info.cityCode, '3910');
      expect(info.balanceFen, 10000);
      expect(parsed.selectedAidHex, 'A000000632010105');
      expect(parsed.transactions, hasLength(2));

      final first = parsed.transactions.first;
      expect(first.amountFen, 4660);
      expect(first.terminalId, '123456789012');
      expect(first.time, DateTime(2024, 5, 1, 8, 30, 0));
      expect(first.typeName, '消费');
      expect(first.isConsume, isTrue);
    });

    test('70 模板包裹的交易记录可解码', () async {
      final link = _baseLink(
        b2Response: _sw9000([0x70, 0x17, ..._record()]),
      );
      final parsed = await TUnionParser(link.call).parse();
      expect(parsed, isNotNull);
      expect(parsed!.transactions, hasLength(1));
      expect(parsed.transactions.first.amountFen, 4660);
    });

    test('全零记录被跳过', () async {
      final link = _baseLink(
        b2Response: _sw9000([...List.filled(23, 0), ..._record(seq: 2, day: 2)]),
      );
      final parsed = await TUnionParser(link.call).parse();
      expect(parsed!.transactions, hasLength(1));
      expect(parsed.transactions.first.sequence, 2);
    });

    test('0x18 充值交易（类型 0x02）按实测表解码为充值', () async {
      final link = _baseLink(
        b2Response: _sw9000(_record(amountFen: 5000, rawType: 0x02)),
      );
      final parsed = await TUnionParser(link.call).parse();

      final txn = parsed!.transactions.single;
      expect(txn.typeName, '充值');
      expect(txn.isRecharge, isTrue);
      expect(txn.isConsume, isFalse);
      expect(txn.amountFen, 5000);
    });

    test('过程记录：0x1A 变长记录与 0x1E 循环记录', () async {
      final link = _ScriptedLink();
      link.enqueue(0xA4, const [0x90, 0x00]); // 选择主文件 MF
      link.enqueue(0xA4, _sw9000(const [])); // 选择电子钱包 AID
      link.enqueue(0xB0, _sw9000(_publicFile()));
      link.enqueue(0xB0, _sw9000(_holderFile()));
      link.enqueue(0xB0, _sw9000(_managementFile()));
      link.enqueue(0x5C, const [0x00, 0x00, 0x27, 0x10, 0x90, 0x00]);
      link.enqueue(0xB2, _sw9000(_record())); // 0x18 交易明细整体读取
      link.enqueue(0xB2, _sw9000(_varProcessRecord(0x01))); // 0x1A 记录 1
      link.enqueue(0xB2, _sw9000(_varProcessRecord(0x02))); // 0x1A 记录 2
      link.enqueue(0xB2, const [0x6A, 0x83]); // 0x1A 记录 3 未找到
      link.enqueue(0xB2, _sw9000(_cycleProcessRecord())); // 0x1E 记录 1
      link.enqueue(0xB2, const [0x6A, 0x83]); // 0x1E 记录 2 未找到

      final parsed = await TUnionParser(link.call).parse();

      expect(parsed, isNotNull);
      final records = parsed!.transitProcessRecords;
      expect(records, hasLength(3));
      expect(records[0].sfi, 0x1A);
      expect(records[0].recordName, '城市轨道应用信息记录');
      expect(records[0].rawHex, '01 02 20 24 05 01 00 78 35 09');
      expect(records[0].trip, isNull); // trip 仅用于 0x1E 循环记录
      expect(records[0].railTransit, isNull); // 10 字节占位数据过短，不解析
      expect(records[1].recordName, '公共汽电车应用信息记录');
      expect(records[2].sfi, 0x1E);
      expect(records[2].recordName, '循环记录 1');

      final trip = records[2].trip;
      expect(trip, isNotNull);
      expect(trip!.typeName, 'EP 出站/下车/出场等');
      expect(trip.appTypeCode, 0x01);
      expect(trip.appTypeName, '城市轨道交通');
      expect(trip.terminalId, '0000300089000340');
      expect(trip.lineStationCode, '08001900300000');
      expect(trip.amountFen, 500);
      expect(trip.amountText, '5.00 元');
      expect(trip.balanceFen, 3585);
      expect(trip.balanceText, '35.85 元');
      expect(trip.time, DateTime(2024, 12, 29, 14, 17, 40));
      expect(trip.cityCode, '1000');
      expect(trip.acquirerId, '01011000FFFFFFFF');
    });

    test('0x1A 逐条读取不可用时，整体数据按 70 模板切分并解析记录 1/2', () async {
      final link = _ScriptedLink();
      link.enqueue(0xA4, const [0x90, 0x00]); // 选择主文件 MF
      link.enqueue(0xA4, _sw9000(const [])); // 选择电子钱包 AID
      link.enqueue(0xB0, _sw9000(_publicFile()));
      link.enqueue(0xB0, _sw9000(_holderFile()));
      link.enqueue(0xB0, _sw9000(_managementFile()));
      link.enqueue(0x5C, const [0x00, 0x00, 0x27, 0x10, 0x90, 0x00]);
      link.enqueue(0xB2, _sw9000([..._record(), ..._record(seq: 2, day: 2)]));
      link.enqueue(0xB2, const [0x6A, 0x83]); // 0x1A 记录 1：逐条读取不支持
      final rail = _railTransitRecord();
      final bus = _busTransitRecord();
      link.enqueue(
        0xB2,
        _sw9000([0x70, rail.length, ...rail, 0x70, bus.length, ...bus]),
      ); // 0x1A 整体读取：70 模板拼接
      link.enqueue(0xB2, const [0x6A, 0x83]); // 0x1E 整体读取失败
      link.enqueue(0xB2, const [0x6A, 0x83]); // 0x1E 逐条读取失败

      final parsed = await TUnionParser(link.call).parse();

      expect(parsed, isNotNull);
      final varRecords =
          parsed!.transitProcessRecords.where((r) => r.sfi == 0x1A).toList();
      expect(varRecords, hasLength(2));
      expect(varRecords[0].recordNumber, 1);
      expect(varRecords[0].recordName, '城市轨道应用信息记录');
      expect(varRecords[0].railTransit, isNotNull);
      // 记录头内的交易流水号仅用于结构探测，模型不产出该字段（见类注释）
      expect(varRecords[0].railTransit!.entryTimeBcd, '20260808090602');
      expect(varRecords[0].railTransit!.exitAmountFen, 300);
      expect(varRecords[1].recordNumber, 2);
      expect(varRecords[1].busTransit, isNotNull); // 完整格式头按记录体偏移解析
    });

    test('0x1A 逐条读取不可用时，完整格式整体数据按 27 记录头切分', () async {
      final link = _ScriptedLink();
      link.enqueue(0xA4, const [0x90, 0x00]); // 选择主文件 MF
      link.enqueue(0xA4, _sw9000(const [])); // 选择电子钱包 AID
      link.enqueue(0xB0, _sw9000(_publicFile()));
      link.enqueue(0xB0, _sw9000(_holderFile()));
      link.enqueue(0xB0, _sw9000(_managementFile()));
      link.enqueue(0x5C, const [0x00, 0x00, 0x27, 0x10, 0x90, 0x00]);
      link.enqueue(0xB2, _sw9000(_record())); // 0x18 交易明细整体读取
      link.enqueue(0xB2, const [0x6A, 0x83]); // 0x1A 记录 1：逐条读取不支持
      final rail = _railFullRecord();
      final bus = [0x27, 0x02, 0x7D, ...List.filled(0x7D, 0x00)];
      link.enqueue(0xB2, _sw9000([...rail, ...bus])); // 0x1A 整体读取
      link.enqueue(0xB2, const [0x6A, 0x83]); // 0x1E 整体读取失败
      link.enqueue(0xB2, const [0x6A, 0x83]); // 0x1E 逐条读取失败

      final parsed = await TUnionParser(link.call).parse();

      expect(parsed, isNotNull);
      final varRecords =
          parsed!.transitProcessRecords.where((r) => r.sfi == 0x1A).toList();
      expect(varRecords, hasLength(2));
      expect(varRecords[0].recordNumber, 1);
      expect(varRecords[0].recordName, '城市轨道应用信息记录');
      expect(varRecords[0].railTransit, isNotNull);
      expect(varRecords[0].railTransit!.serialNumber, '0000000000000001');
      expect(varRecords[0].railTransit!.exitAmountFen, 300);
      expect(varRecords[1].recordNumber, 2);
      expect(varRecords[1].busTransit, isNotNull); // 完整格式记录头命中，按偏移解析
    });
  });

  group('TUnionProcessParser 过程记录解析', () {
    const parser = TUnionProcessParser();

    test('0x1E 循环记录按已知布局完整解码', () {
      final trip = parser.parseCycleTrip(_cycleProcessRecord());

      expect(trip, isNotNull);
      expect(trip!.typeName, 'EP 出站/下车/出场等');
      expect(trip.appTypeCode, 0x01);
      expect(trip.appTypeName, '城市轨道交通');
      expect(trip.terminalId, '0000300089000340');
      expect(trip.lineStationCode, '08001900300000');
      expect(trip.lineCode, '0800'); // [0A-10] 前 4 位
      expect(trip.stationCode, '1900'); // 中间 4 位
      expect(trip.operatorCode, '3000'); // 后 4 位（余 2 位不展示）
      expect(trip.amountFen, 500);
      expect(trip.amountText, '5.00 元');
      expect(trip.balanceFen, 3585);
      expect(trip.balanceText, '35.85 元');
      expect(trip.time, DateTime(2024, 12, 29, 14, 17, 40));
      expect(trip.cityCode, '1000');
      expect(trip.acquirerId, '01011000FFFFFFFF');
    });

    test('0x1E 交易类型与应用分类码按标准表解码', () {
      final base = parser.parseCycleTrip(_cycleProcessRecord())!;
      expect(base.appTypeCode, 0x01);
      expect(base.appTypeLabel, '城市轨道交通');

      final entry = parser.parseCycleTrip(_cycleProcessRecord()..[0] = 0x03)!;
      expect(entry.typeName, 'EP 入站/上车/进场等');
      expect(entry.isEntry, isTrue);

      final consume = parser.parseCycleTrip(_cycleProcessRecord()..[0] = 0x05)!;
      expect(consume.typeName, 'EC 单次消费');
      expect(consume.isEntry, isFalse);

      final bus = parser.parseCycleTrip(_cycleProcessRecord()..[9] = 0x02)!;
      expect(bus.appTypeName, '公共汽电车');

      final reserved =
          parser.parseCycleTrip(_cycleProcessRecord()..[9] = 0x10)!;
      expect(reserved.appTypeLabel, isNull);
      expect(reserved.appTypeName, '未知(0x10)');
    });

    test('0x1E 未写入 / 过短 / 时间非法时返回 null（不猜测）', () {
      expect(parser.parseCycleTrip(const []), isNull);
      expect(parser.parseCycleTrip(List.filled(48, 0x00)), isNull);
      expect(parser.parseCycleTrip(List.filled(48, 0xFF)), isNull);
      expect(parser.parseCycleTrip(const [0x04, 0x01, 0x02]), isNull);
    });

    test('0x1A 记录过短时不解析（保持 null，不猜测）', () {
      final data = _varProcessRecord(0x01); // 10 字节占位数据
      expect(parser.parseRailTransit(1, data), isNull);
      expect(parser.parseRailTransit(2, data), isNull); // 非记录 1 恒为 null
      expect(parser.parseRailTransit(1, const []), isNull);
    });

    test('0x1A 记录：70 记录模板包裹时先剥离再解析', () {
      final rail = _railTransitRecord();
      final rec = parser.parseRailTransit(1, [0x70, rail.length, ...rail]);
      expect(rec, isNotNull);
      expect(rec!.statusCode, 0x02);
      expect(rec.entryCityCode, '2900');
      expect(rec.entryTime, DateTime(2026, 8, 8, 9, 6, 2));
      expect(rec.exitAmountFen, 300);

      final bus = _busTransitRecord();
      expect(parser.parseBusTransit(2, [0x70, bus.length, ...bus]), isNotNull);
    });

    test('0x1A 记录：多层嵌套 70 模板逐层剥离后再解析', () {
      final rail = _railTransitRecord();
      final nested = [0x70, rail.length + 2, 0x70, rail.length, ...rail];
      final rec = parser.parseRailTransit(1, nested);
      expect(rec, isNotNull);
      expect(rec!.statusCode, 0x02);
      expect(rec.entryCityCode, '2900');
      expect(rec.exitTime, DateTime(2026, 8, 8, 9, 12, 31));
      expect(rec.exitAmountFen, 300);
    });

    test('0x1A 记录：不足标准长度时按可用字节解析（越界字段为 null）', () {
      final railPartial = _railTransitRecord().sublist(0, 0x35); // 53 字节
      final rail = parser.parseRailTransit(1, railPartial);
      expect(rail, isNotNull);
      expect(rail!.entryTerminalId, '0000000000001A23');
      expect(rail.exitTerminalId, '0000000000001568');
      expect(rail.entryTime, isNull); // [0x35-0x3B] 越界
      expect(rail.exitAmountFen, isNull); // [0x51-0x54] 越界

      final busPartial = _busTransitRecord().sublist(0, 0x20); // 32 字节
      final bus = parser.parseBusTransit(2, busPartial);
      expect(bus, isNotNull);
      expect(bus!.entryTerminalId, '0000000000000000');
      expect(bus.entryTime, isNull); // [0x20-0x26] 越界
    });

    test('0x1A 记录 1：128 字节完整格式按记录头偏移解析', () {
      final rec = parser.parseRailTransit(1, _railFullRecord());
      expect(rec, isNotNull);
      expect(rec!.statusCode, 0x02);
      expect(rec.statusName, '出闸');
      expect(rec.entryCityCode, '2900'); // 字段体与 85 字节布局一致
      expect(rec.entryTime, DateTime(2026, 8, 8, 9, 6, 2));
      expect(rec.exitAmountFen, 300);
      expect(rec.issuerCustom, List.filled(29, '5A').join());
    });

    test('0x1A 记录 1：发卡机构自定义全零视为未读取到有效信息，不产出', () {
      final full = [..._railFullRecord()];
      full.fillRange(99, 128, 0x00); // 尾部自定义区写入全零
      final rec = parser.parseRailTransit(1, full);
      expect(rec, isNotNull);
      expect(rec!.issuerCustom, isNull);
    });

    test('0x1A 记录 1：完整格式被 70 模板包裹时先剥离再解析', () {
      final full = _railFullRecord();
      final rec = parser.parseRailTransit(1, [0x70, 0x81, full.length, ...full]);
      expect(rec, isNotNull);
      expect(rec!.entryCityCode, '2900'); // 剥离模板后记录头偏移仍生效
      expect(rec.issuerCustom, List.filled(29, '5A').join());
    });

    test('0x1A 记录 1：记录头不合法时返回 null（不按错位偏移猜测）', () {
      final wrongNumber = [..._railFullRecord()];
      wrongNumber[1] = 0x02;
      expect(parser.parseRailTransit(1, wrongNumber), isNull);

      final wrongLength = [..._railFullRecord()];
      wrongLength[2] = 0x44;
      expect(parser.parseRailTransit(1, wrongLength), isNull);
    });

    test('0x1A 记录 1：交易状态 0x01 显示进闸', () {
      final body = [..._railTransitRecord()];
      body[0] = 0x01;
      expect(parser.parseRailTransit(1, body)!.statusName, '进闸');
    });

    test('0x1A 记录 2：完整格式（27 02 7D 记录头）命中后按偏移解析', () {
      final busFull = [0x27, 0x02, 0x7D, ...List.filled(0x7D, 0x00)];
      final rec = parser.parseBusTransit(2, busFull);
      expect(rec, isNotNull);
      expect(rec!.hasRecordHeader, isTrue);
      expect(rec.statusCode, 0x00); // 记录体全 0：未写入
    });

    test('0x1A 记录 2：携带 14 字节记录头时记录体偏移自动后移', () {
      final body = _busTransitRecordFilled(); // 按公共汽电车布局构造的非零 88 字节体
      final withHeader = [
        0x27, 0x02, 0x7D, 0x01, // 记录标识 / 记录长度 / 应用有效标识
        0x00, 0x00, // 互联互通交易标识 / 应用锁定标志
        ..._bcd('2026010100000001'), // [06-13] 交易流水号
        ...body,
        ...List.filled(26, 0x00), // 发卡机构自定义
      ];
      final rec = parser.parseBusTransit(2, withHeader);
      expect(rec, isNotNull);
      expect(rec!.hasRecordHeader, isTrue);
      expect(rec.statusCode, 0x02); // 记录体字段按后移偏移读取
      expect(rec.entryCityCode, '2900');
      expect(rec.entryTime, DateTime(2026, 8, 8, 9, 6, 2));
      expect(rec.transactionAmountFen, 300);
      expect(rec.mileage, 5);

      final bare = parser.parseBusTransit(2, body);
      expect(bare!.hasRecordHeader, isFalse);
      expect(rec.entryCityCode, bare.entryCityCode); // 体字段两种形态一致
      expect(rec.transactionAmountFen, bare.transactionAmountFen);
    });

    test('0x1A 记录 2：发卡机构自定义含数据时保留，全 0 时视为无有效信息', () {
      final filledTail = [..._busTransitRecord(), ...List.filled(26, 0x5A)];
      final rec = parser.parseBusTransit(2, filledTail);
      expect(rec, isNotNull);
      expect(rec!.hasRecordHeader, isFalse);
      expect(rec.hasIssuerCustomData, isTrue);
      expect(rec.issuerCustomHex, List.filled(26, '5A').join());

      final zeroTail = [..._busTransitRecord(), ...List.filled(26, 0x00)];
      expect(parser.parseBusTransit(2, zeroTail)!.hasIssuerCustomData, isFalse);
    });

    test('0x1A 记录 1：城市轨道应用信息记录按目标格式解码', () {
      final rec = parser.parseRailTransit(1, _railTransitRecord());
      expect(rec, isNotNull);
      expect(rec!.statusCode, 0x02);
      expect(rec.statusName, '出闸');
      expect(rec.issuerCustom, isNull); // 裸 85 字节字段体无记录头，不产出自定义区
      expect(rec.entryCityCode, '2900');
      expect(rec.exitCityCode, '2900');
      expect(rec.entryAgencyId, '0000000000000010');
      expect(rec.exitAgencyId, '0000000000000008');
      expect(rec.entryStationId, '0000000000000057');
      expect(rec.exitStationId, '0000000000000036');
      expect(rec.entryTerminalId, '0000000000001A23');
      expect(rec.exitTerminalId, '0000000000001568');
      expect(rec.entryTime, DateTime(2026, 8, 8, 9, 6, 2));
      expect(rec.entryTimeBcd, '20260808090602');
      expect(rec.exitTime, DateTime(2026, 8, 8, 9, 12, 31));
      expect(rec.exitTimeBcd, '20260808091231');
      expect(rec.annotateAmountFen, 0);
      expect(rec.entryLineCode, 0);
      expect(rec.exitLineCode, 0);
      expect(rec.entryAmountFen, 0);
      expect(rec.entryBalanceFen, 0);
      expect(rec.exitAmountFen, 300);
    });

    test('0x1A 记录 2：公共汽电车应用信息记录按目标格式解码', () {
      final rec = parser.parseBusTransit(2, _busTransitRecord());
      expect(rec, isNotNull);
      expect(rec!.statusCode, 0x00);
      expect(rec.statusName, '初始值');
      expect(rec.entryCityCode, '0000');
      expect(rec.entryAgencyId, '0000000000000000');
      expect(rec.entryOperatorCode, '0000');
      expect(rec.entryLineCode, '0000');
      expect(rec.entryStationCode, '00');
      expect(rec.entryTime, isNull);
      expect(rec.entryTimeBcd, '00000000000000');
      expect(rec.annotateAmountFen, 0);
      expect(rec.directionCode, 0);
      expect(rec.directionName, '未知方向');
      expect(rec.exitTime, isNull);
      expect(rec.exitTimeBcd, '00000000000000');
      expect(rec.transactionAmountFen, 0);
      expect(rec.mileage, 0);
      // 非记录 2 恒为 null；长度不足不解析
      expect(parser.parseBusTransit(1, _busTransitRecord()), isNull);
      expect(parser.parseBusTransit(2, _varProcessRecord(0x02)), isNull);
    });

    test('TransitRecord 目标格式：进出站配对与金额文本契约', () {
      final rec = TransitRecord(
        statusCode: 0x02,
        entryAgencyId: '0001',
        entryStationId: '08001900300000',
        entryTime: DateTime(2024, 12, 29, 8, 5, 0),
        exitAgencyId: '0001',
        exitStationId: '08001900300001',
        exitTime: DateTime(2024, 12, 29, 14, 17, 40),
        entryLineCode: 8,
        exitLineCode: 8,
        entryAmountFen: 800,
        exitAmountFen: 1800,
        transactionAmountFen: 200,
      );

      expect(rec.statusName, '出闸');
      expect(rec.entryAmountText, '8.00 元');
      expect(rec.exitAmountText, '18.00 元');
      expect(rec.transactionAmountText, '2.00 元');
      expect(rec.entryStationName, isNull); // 线路库接入前留空
      expect(rec.exitStationName, isNull);
      expect(rec.lineName, isNull);
    });
  });

  group('TerminalDecoder 终端编号解码', () {
    test('按规则切分城市/线路/站点', () {
      final rules = TerminalRuleSet.fromJson({
        'rules': [
          {
            'id': 'test-rule',
            'priority': 1,
            'match': {'terminalPrefix': '1234'},
            'layout': {
              'cityCode': [0, 4],
              'lineCode': [4, 7],
              'stationCode': [7, 12],
            },
            'note': '测试规则',
          }
        ],
      });
      final decoder = TerminalDecoder(rules);

      final loc = decoder.decode('123456789012');
      expect(loc, isNotNull);
      expect(loc!.ruleId, 'test-rule');
      expect(loc.cityCode, '1234');
      expect(loc.lineCode, '567');
      expect(loc.stationCode, '89012');
      expect(loc.hasLocation, isTrue);

      // 无匹配规则 → null（保持未知，不猜测）
      expect(decoder.decode('999999999999'), isNull);
      // 非 12 位十进制 → null
      expect(decoder.decode('123456'), isNull);
    });

    test('三个匹配条件全空的规则不生效（防空规则误配）', () {
      final rules = TerminalRuleSet.fromJson({
        'rules': [
          {'id': 'catch-all', 'layout': {'lineCode': [0, 4]}}
        ],
      });
      expect(TerminalDecoder(rules).decode('123456789012'), isNull);
    });
  });

  group('StationCodeTable 站点代码表', () {
    // 数据集顺序刻意让公交在前、地铁在后，验证冲突时按类别优先级取地铁。
    final table = StationCodeTable.fromDatasets(const [
      StationDataset(
        file: 'Yunnan/Kunming/bus-tu.csv',
        cityCode: '3910',
        system: 'tu',
        kind: 'bus',
        codes: {
          '0231': StationCodeEntry(
              code: '0231', type: '公交', line: '31路', station: '某站'),
        },
      ),
      StationDataset(
        file: 'Fujian/Fuzhou/metro-tu.csv',
        cityCode: '3910',
        system: 'tu',
        kind: 'metro',
        codes: {
          '02': StationCodeEntry(code: '02', type: '地铁', line: '2号线'),
          '0231': StationCodeEntry(
              code: '0231', type: '地铁', line: '2号线', station: '苏洋'),
        },
      ),
      StationDataset(
        file: 'Guangdong/Guangzhou/bus-yct.csv',
        system: 'yct',
        kind: 'bus',
        codes: {
          '01001': StationCodeEntry(code: '01001', type: '公交', line: '1路'),
        },
      ),
    ]);

    test('按城市 + 编码精确查询，未收录返回 null（不猜测）', () {
      final entry = table.lookup(code: '0231', cityCode: '3910');
      expect(entry, isNotNull);
      expect(entry!.line, '2号线');
      expect(entry.station, '苏洋');
      expect(entry.displayLabel, '地铁 · 2号线 · 苏洋');
      expect(table.lookup(code: '0231', cityCode: '1100'), isNull);
      expect(table.lookup(code: '9999', cityCode: '3910'), isNull);
      expect(table.lookup(code: '0231', cityCode: null), isNull);
    });

    test('同编码多数据集冲突时保留高优先级类别（地铁 > 公交）', () {
      // 公交数据集先加载、地铁后加载；地铁优先级更高，应覆盖公交条目
      expect(table.lookup(code: '0231', cityCode: '3910')!.type, '地铁');
    });

    test('prefix 模式数据集（无城市键）不参与查询', () {
      expect(table.lookup(code: '01001', cityCode: '0100'), isNull);
    });

    test('资产缺失降级为空表', () {
      expect(
        StationCodeTable.fromDatasets(const [])
            .lookup(code: '02', cityCode: '3910'),
        isNull,
      );
      expect(
        StationCodeTable.empty.lookup(code: '02', cityCode: '3910'),
        isNull,
      );
    });
  });

  group('识别与分析引擎', () {
    final kb = KnowledgeBase.fromJsonStrings(
      cardPrefixes: jsonEncode({
        'entries': [
          {
            'prefix': '31050600',
            'issuer': '01283910',
            'cardName': '福路通·榕城通',
            'city': '福州市',
            'province': '福建省',
          },
        ]
      }),
      issuerFingerprints: jsonEncode({
        'entries': [
          {
            'issuerId': '1122334455667788',
            'cityCode': '3910',
            'cityName': '福州市',
            'operator': '示例运营方',
            'cardFamily': '测试卡',
          }
        ]
      }),
      terminalRules: jsonEncode({
        'rules': [
          {
            'id': 'r1',
            'match': {'terminalPrefix': '3910'},
            'layout': {
              'cityCode': [0, 4],
              'lineCode': [4, 6],
              'stationCode': [8, 10],
            },
          }
        ]
      }),
      stationCodes: StationCodeTable.fromDatasets(const [
        StationDataset(
          file: 'Fujian/Fuzhou/metro-tu.csv',
          cityCode: '3910',
          system: 'tu',
          kind: 'metro',
          codes: {
            '02': StationCodeEntry(code: '02', type: '地铁', line: '2号线'),
            '0231': StationCodeEntry(
                code: '0231', type: '地铁', line: '2号线', station: '苏洋'),
          },
        ),
      ]),
    );

    test('卡片名称：发卡机构标识前 8 位反查卡前缀库', () {
      // 前 8 位为发卡机构代码（issuer 字段）→ 直接命中
      expect(
        kb.cardPrefixes.lookupByIssuerId('01283910AABBCCDD')?.cardName,
        '福路通·榕城通',
      );
      // 小写、带分隔符同样可识别
      expect(
        kb.cardPrefixes.lookupByIssuerId('01283910-aabb-ccdd')?.cardName,
        '福路通·榕城通',
      );
      // 前 8 位为 IIN（31 开头）→ 回退按 prefix 字段命中
      expect(
        kb.cardPrefixes.lookupByIssuerId('31050600AABBCCDD')?.cardName,
        '福路通·榕城通',
      );
      expect(kb.cardPrefixes.lookupByIssuerId('1122334455667788'), isNull);
      expect(kb.cardPrefixes.lookupByIssuerId(null), isNull);
    });

    test('指纹 + 城市码证据融合', () {
      final engine = AnalysisEngine(kb);
      final parsed = const ParsedCard(
        parserName: 't',
        info: TUnionCardInfo(issuerId: '1122334455667788', cityCode: '3910'),
        transactions: [],
        selectedAidHex: 'A000000632010105',
      );
      final result = engine.analyze(parsed, now: DateTime(2026, 10, 7));

      expect(result.identity.cityName, '福州市');
      expect(result.identity.provinceName, '福建省');
      expect(result.identity.operatorName, '示例运营方');
      expect(result.identity.cardFamily, '测试卡');
      expect(result.identity.confidence, closeTo(0.85, 0.001));
      expect(result.identity.evidence, hasLength(2));
    });

    test('证据冲突产生异常；过期卡片符合性判定失败', () {
      final engine = AnalysisEngine(kb);
      final parsed = ParsedCard(
        parserName: 't',
        info: TUnionCardInfo(
          issuerId: '1122334455667788',
          cityCode: '1100',
          effectiveDate: DateTime(2024, 1, 1),
          expireDate: DateTime(2024, 12, 31),
          balanceFen: 10000,
        ),
        transactions: [
          _txn(seq: 1, time: DateTime(2024, 5, 1), amountFen: 200),
        ],
        selectedAidHex: 'A000000632010105',
      );
      final result = engine.analyze(parsed, now: DateTime(2026, 10, 7));

      expect(result.anomalies.any((a) => a.code == 'identity-conflict'),
          isTrue);
      expect(result.anomalies.any((a) => a.code == 'card-expired'), isTrue);
      expect(result.compliance.scorePercent, inInclusiveRange(0, 100));
      expect(
        result.compliance.items.any((i) =>
            i.id == 'not-expired' && i.status == ComplianceStatus.fail),
        isTrue,
      );
      expect(result.trips, hasLength(1));
      // 终端 999… 不匹配规则 → 线路保持 null（不猜测）
      expect(result.trips.first.lineLabel, isNull);
    });

    test('行程按时间倒序排列', () {
      final engine = AnalysisEngine(kb);
      final parsed = ParsedCard(
        parserName: 't',
        info: const TUnionCardInfo(),
        transactions: [
          _txn(seq: 1, time: DateTime(2024, 5, 1), amountFen: 100),
          _txn(seq: 2, time: DateTime(2024, 6, 1), amountFen: 200),
        ],
        selectedAidHex: 'A000000632010105',
      );
      final result = engine.analyze(parsed, now: DateTime(2026, 10, 7));
      expect(result.trips.first.time, DateTime(2024, 6, 1));
    });

    test('充值交易：行程保留充值类型，金额按收入展示（+）', () {
      final engine = AnalysisEngine(kb);
      final parsed = ParsedCard(
        parserName: 't',
        info: const TUnionCardInfo(),
        transactions: [
          _txn(
            seq: 1,
            time: DateTime(2024, 5, 1),
            amountFen: 5000,
            rawType: 0x02,
          ),
        ],
        selectedAidHex: 'A000000632010105',
      );
      final result = engine.analyze(parsed, now: DateTime(2026, 10, 7));

      final trip = result.trips.single;
      expect(trip.typeName, '充值');
      expect(trip.isConsume, isFalse);
      expect(trip.amountText, '+¥50.00');
    });

    test('0 元交易配对 0x1E 入站记录：标记进站并补齐线路/站点', () {
      final engine = AnalysisEngine(kb);
      final parsed = ParsedCard(
        parserName: 't',
        info: const TUnionCardInfo(cityCode: '3910'),
        transactions: [
          _txn(seq: 1, time: DateTime(2024, 5, 1, 8, 30), amountFen: 0),
        ],
        transitProcessRecords: [_entryRecord(time: DateTime(2024, 5, 1, 8, 30))],
        selectedAidHex: 'A000000632010105',
      );
      final result = engine.analyze(parsed, now: DateTime(2026, 10, 7));

      final trip = result.trips.single;
      expect(trip.isEntry, isTrue);
      expect(trip.lineLabel, '2号线'); // "90020031…" 分段布局 → "0231" 查表
      expect(trip.stationLabel, '苏洋');
      expect(trip.appTypeName, '城市轨道交通');
    });

    test('0 元交易无 0x1E 入站记录配对：不标记进站（不猜测）', () {
      final engine = AnalysisEngine(kb);
      final parsed = ParsedCard(
        parserName: 't',
        info: const TUnionCardInfo(cityCode: '3910'),
        transactions: [
          _txn(seq: 1, time: DateTime(2024, 5, 1, 8, 30), amountFen: 0),
        ],
        selectedAidHex: 'A000000632010105',
      );
      final result = engine.analyze(parsed, now: DateTime(2026, 10, 7));

      final trip = result.trips.single;
      expect(trip.isEntry, isFalse);
      expect(trip.stationLabel, isNull); // 配对未命中 → 无 0x1E 注解补齐
    });

    test('0 元交易配对 0x1A 记录 1 进站：标记进站并补齐进站城市/站点', () {
      final engine = AnalysisEngine(kb);
      final parsed = ParsedCard(
        parserName: 't',
        info: const TUnionCardInfo(cityCode: '3910'),
        transactions: [
          _txn(seq: 1, time: DateTime(2024, 5, 1, 8, 30), amountFen: 0),
        ],
        transitProcessRecords: [
          _railEntryRecord(time: DateTime(2024, 5, 1, 8, 30)),
        ],
        selectedAidHex: 'A000000632010105',
      );
      final result = engine.analyze(parsed, now: DateTime(2026, 10, 7));

      final trip = result.trips.single;
      expect(trip.isEntry, isTrue);
      expect(trip.cityName, '福州市'); // 进闸城市 3910 → 城市表
      expect(trip.stationLabel, '0800190030000123'); // 进闸站点原始编码
      expect(trip.lineLabel, isNull); // 0x1A 记录不产出线路（不猜测）
    });

    test('0x1A 与 0x1E 均可配对：0x1E 注解优先', () {
      final engine = AnalysisEngine(kb);
      final parsed = ParsedCard(
        parserName: 't',
        info: const TUnionCardInfo(cityCode: '3910'),
        transactions: [
          _txn(seq: 1, time: DateTime(2024, 5, 1, 8, 30), amountFen: 0),
        ],
        transitProcessRecords: [
          _railEntryRecord(time: DateTime(2024, 5, 1, 8, 30)),
          _entryRecord(time: DateTime(2024, 5, 1, 8, 30)),
        ],
        selectedAidHex: 'A000000632010105',
      );
      final result = engine.analyze(parsed, now: DateTime(2026, 10, 7));

      final trip = result.trips.single;
      expect(trip.isEntry, isTrue);
      expect(trip.lineLabel, '2号线'); // 0x1E 注解查表结果
      expect(trip.stationLabel, '苏洋'); // 不用 0x1A 原始编码兜底
      expect(trip.appTypeName, '城市轨道交通');
    });

    test('0x1A 记录 1 进站交易金额非 0：不参与配对（不猜测）', () {
      final engine = AnalysisEngine(kb);
      final parsed = ParsedCard(
        parserName: 't',
        info: const TUnionCardInfo(cityCode: '3910'),
        transactions: [
          _txn(seq: 1, time: DateTime(2024, 5, 1, 8, 30), amountFen: 0),
        ],
        transitProcessRecords: [
          _railEntryRecord(
            time: DateTime(2024, 5, 1, 8, 30),
            entryAmountFen: 200,
          ),
        ],
        selectedAidHex: 'A000000632010105',
      );
      final result = engine.analyze(parsed, now: DateTime(2026, 10, 7));

      final trip = result.trips.single;
      expect(trip.isEntry, isFalse);
      expect(trip.stationLabel, isNull);
    });

    test('0 元交易配对 0x1A 记录 2 上车：标记进站并补齐进站城市/站点', () {
      final engine = AnalysisEngine(kb);
      final parsed = ParsedCard(
        parserName: 't',
        info: const TUnionCardInfo(cityCode: '3910'),
        transactions: [
          _txn(seq: 1, time: DateTime(2024, 5, 1, 8, 30), amountFen: 0),
        ],
        transitProcessRecords: [
          _busEntryRecord(time: DateTime(2024, 5, 1, 8, 30)),
        ],
        selectedAidHex: 'A000000632010105',
      );
      final result = engine.analyze(parsed, now: DateTime(2026, 10, 7));

      final trip = result.trips.single;
      expect(trip.isEntry, isTrue);
      expect(trip.cityName, '福州市');
      expect(trip.stationLabel, '02'); // 上车站点原始编码
    });

    test('终端解码编码 → 站点代码表补齐线路/站点名称', () {
      final engine = AnalysisEngine(kb);
      final parsed = ParsedCard(
        parserName: 't',
        info: const TUnionCardInfo(cityCode: '3910'),
        transactions: [
          _txn(
            seq: 1,
            time: DateTime(2024, 5, 1),
            amountFen: 200,
            // 12 位终端号（6 字节 BCD）：城市 3910 / 线路 02 / 站点 31
            terminalId: '391002003100',
          ),
        ],
        selectedAidHex: 'A000000632010105',
      );
      final result = engine.analyze(parsed, now: DateTime(2026, 10, 7));

      final trip = result.trips.first;
      expect(trip.location, isNotNull);
      expect(trip.location!.lineCode, '02');
      expect(trip.location!.stationCode, '31');
      expect(trip.cityName, '福州市');
      // 候选编码 "02"+"31" 拼接为 "0231" 命中站点代码表
      expect(trip.lineLabel, '2号线');
      expect(trip.stationLabel, '苏洋');
      expect(trip.stationType, '地铁');
    });

    test('站点未收录时保持原始编码（不猜测）', () {
      final engine = AnalysisEngine(kb);
      final parsed = ParsedCard(
        parserName: 't',
        info: const TUnionCardInfo(cityCode: '3910'),
        transactions: [
          _txn(
            seq: 1,
            time: DateTime(2024, 5, 1),
            amountFen: 100,
            // 12 位终端号：城市 3910 / 线路 02 / 站点 99（"0299"/"99" 未收录）
            terminalId: '391002999999',
          ),
        ],
        selectedAidHex: 'A000000632010105',
      );
      final result = engine.analyze(parsed, now: DateTime(2026, 10, 7));

      final trip = result.trips.first;
      expect(trip.lineLabel, '2号线'); // "02" 单独命中线路条目
      expect(trip.stationLabel, '99'); // "0299"/"99" 未收录 → 回退原始编码
    });
  });
}

/// 按 INS 字节匹配的脚本化 APDU 链路（无需真机）。
class _ScriptedLink {
  final Map<int, List<List<int>>> _queues = {};

  void enqueue(int ins, List<int> resp) =>
      _queues.putIfAbsent(ins, () => []).add(resp);

  Future<List<int>> call(List<int> apdu) async {
    final ins = apdu.length > 1 ? apdu[1] : -1;
    final queue = _queues[ins];
    if (queue == null || queue.isEmpty) return const [0x6A, 0x82];
    return queue.removeAt(0);
  }
}

List<int> _sw9000(List<int> data) => [...data, 0x90, 0x00];

_ScriptedLink _baseLink({List<int>? b2Response}) {
  final link = _ScriptedLink();
  link.enqueue(0xA4, const [0x90, 0x00]); // 选择主文件 MF
  link.enqueue(0xA4, _sw9000(const [])); // 选择电子钱包 AID
  link.enqueue(0xB0, _sw9000(_publicFile()));
  link.enqueue(0xB0, _sw9000(_holderFile()));
  link.enqueue(0xB0, _sw9000(_managementFile()));
  link.enqueue(0x5C, const [0x00, 0x00, 0x27, 0x10, 0x90, 0x00]);
  link.enqueue(
    0xB2,
    b2Response ?? _sw9000([..._record(), ..._record(seq: 2, day: 2)]),
  );
  return link;
}

List<int> _publicFile() {
  final b = List.filled(30, 0);
  for (var i = 0; i < 8; i++) {
    b[i] = 0x11 * (i + 1);
  }
  b[8] = 0x01;
  b[9] = 0x01;
  const serial = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x00];
  for (var i = 0; i < 10; i++) {
    b[10 + i] = serial[i];
  }
  b[20] = 0x20;
  b[21] = 0x24;
  b[22] = 0x01;
  b[23] = 0x01; // 20240101
  b[24] = 0x20;
  b[25] = 0x29;
  b[26] = 0x12;
  b[27] = 0x31; // 20291231
  b[28] = 0xAA;
  b[29] = 0xBB;
  return b;
}

List<int> _holderFile() {
  final b = List.filled(55, 0);
  b[0] = 0x01;
  b[54] = 0x01;
  return b;
}

List<int> _managementFile() {
  final b = List.filled(60, 0);
  b[6] = 0x39;
  b[7] = 0x10; // 城市代码 3910
  b[10] = 0x01;
  return b;
}

List<int> _record({
  int seq = 1,
  int amountFen = 4660,
  int day = 1,
  int rawType = 0x06,
}) => [
      (seq >> 8) & 0xFF,
      seq & 0xFF,
      0, 0, 0,
      (amountFen >> 24) & 0xFF,
      (amountFen >> 16) & 0xFF,
      (amountFen >> 8) & 0xFF,
      amountFen & 0xFF,
      rawType,
      0x12, 0x34, 0x56, 0x78, 0x90, 0x12, // 终端 123456789012
      0x20, 0x24, 0x05, day, // 2024050d
      0x08, 0x30, 0x00, // 08:30:00
    ];

TUnionTransaction _txn({
  required int seq,
  required DateTime time,
  required int amountFen,
  String terminalId = '999999999999',
  int rawType = 0x06,
}) =>
    TUnionTransaction(
      sequence: seq,
      overdraftLimitFen: 0,
      amountFen: amountFen,
      rawType: rawType,
      terminalId: terminalId,
      time: time,
    );

List<int> _varProcessRecord(int type) =>
    [type, 0x02, 0x20, 0x24, 0x05, 0x01, 0x00, 0x78, 0x35, 0x09];

/// 0x1E 入站类记录（EC 0x01 / EP 0x03）模型构造：进站不承载扣费金额
/// （默认 0 分）；线路和站点代码按福州分段布局 "90020031000000" →
/// 第 3-4 位线路 "02" + 第 7-8 位站点 "31" → 编码 "0231" 查表。
TUnionProcessRecord _entryRecord({
  required DateTime time,
  int amountFen = 0,
  int typeCode = 0x03,
}) =>
    TUnionProcessRecord(
      sfi: 0x1E,
      recordNumber: 1,
      recordName: '循环记录 1',
      raw: const [],
      trip: TUnionTripRecord(
        typeCode: typeCode,
        terminalId: '0000300089000340',
        appTypeCode: 0x01,
        lineStationCode: '90020031000000',
        amountFen: amountFen,
        balanceFen: 5340,
        time: time,
        cityCode: '3910',
      ),
    );

/// 0x1A 记录 1（城市轨道应用信息记录）进站模型构造：进闸城市 3910，
/// 进闸站点 0800190030000123（线路库接入前仅产出原始编码）；进站交易
/// 金额默认 0 分（进站不承载扣费金额）。
TUnionProcessRecord _railEntryRecord({
  required DateTime time,
  int? entryAmountFen = 0,
}) =>
    TUnionProcessRecord(
      sfi: 0x1A,
      recordNumber: 1,
      recordName: '城市轨道应用信息记录',
      raw: const [],
      railTransit: TransitRecord(
        statusCode: 0x02,
        entryCityCode: '3910',
        entryStationId: '0800190030000123',
        entryTime: time,
        entryAmountFen: entryAmountFen,
      ),
    );

/// 0x1A 记录 2（公共汽电车应用信息记录）上车模型构造：上车城市 3910，
/// 上车站点原始编码 02。
TUnionProcessRecord _busEntryRecord({required DateTime time}) =>
    TUnionProcessRecord(
      sfi: 0x1A,
      recordNumber: 2,
      recordName: '公共汽电车应用信息记录',
      raw: const [],
      busTransit: BusTransitRecord(
        statusCode: 0x02,
        entryCityCode: '3910',
        entryStationCode: '02',
        entryTime: time,
      ),
    );

/// 0x1A 记录 1 示例数据（85 字节，按目标输出格式构造，仅用于验证解析偏移）：
/// 出站；进/出闸城市码 2900；2026-08-08 09:06:02 进站 / 09:12:31 出站；
/// 出站交易金额 300 分。
List<int> _railTransitRecord() => [
      0x02, // 交易状态：出站
      0x29, 0x00, 0x29, 0x00, // 进/出闸城市代码 2900
      ...List.filled(7, 0), 0x10, // 进闸机构标识
      ...List.filled(7, 0), 0x08, // 出闸机构标识
      ...List.filled(7, 0), 0x57, // 进闸站点
      ...List.filled(7, 0), 0x36, // 出闸站点
      ...List.filled(6, 0), 0x1A, 0x23, // 进闸终端编号
      ...List.filled(6, 0), 0x15, 0x68, // 出闸终端编号
      0x20, 0x26, 0x08, 0x08, 0x09, 0x06, 0x02, // 进站时间
      0x20, 0x26, 0x08, 0x08, 0x09, 0x12, 0x31, // 出站时间
      0x00, 0x00, 0x00, 0x00, // 标注金额
      0x00, 0x00, // 入/出站线路号
      0x00, 0x00, 0x00, 0x00, // 进站交易金额
      0x00, 0x00, 0x00, 0x00, // 进站钱包余额
      0x00, 0x00, 0x01, 0x2C, // 出站交易金额 300 分
    ];

/// 0x1A 记录 1 完整格式示例数据（128 字节）：27 记录头（14 字节）+
/// 85 字节字段体 + 29 字节发卡机构自定义。记录头：应用有效标识 01、
/// 互联互通交易标识 01、应用锁定标志 00、交易流水号 0000000000000001。
List<int> _railFullRecord() => [
      0x27, 0x01, 0x7D, // 记录 ID / 记录号 / 记录长度（125 = 128 − 3）
      0x01, 0x01, 0x00, // 应用有效标识 / 互联互通交易标识 / 应用锁定标志
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, // 交易流水号（BCD）
      ..._railTransitRecord(), // 字段体 85 字节
      ...List.filled(29, 0x5A), // 发卡机构自定义
    ];

/// 0x1A 记录 2 示例数据（88 字节，全初始值：公共汽电车应用未写入）。
List<int> _busTransitRecord() => List.filled(88, 0x00);

/// 0x1A 记录 2 示例数据（88 字节，按公共汽电车记录体布局构造的非零记录体）。
List<int> _busTransitRecordFilled() => [
      0x02, // [00] 交易状态
      0x29, 0x00, // [01-02] 上车城市代码 2900
      ...List.filled(7, 0), 0x10, // [03-0A] 上车机构标识
      0x00, 0x01, // [0B-0C] 上车运营商代码
      0x00, 0x08, // [0D-0E] 上车线路号
      0x02, // [0F] 上车站点
      ...List.filled(7, 0), 0x23, // [10-17] 上车车辆号
      ...List.filled(6, 0), 0x1A, 0x5A, // [18-1F] 上车终端编号
      0x20, 0x26, 0x08, 0x08, 0x09, 0x06, 0x02, // [20-26] 上车时间
      0x00, 0x00, 0x01, 0x2C, // [27-2A] 标注金额 300 分
      0x00, // [2B] 方向标识
      0x29, 0x00, // [2C-2D] 下车城市代码 2900
      ...List.filled(7, 0), 0x08, // [2E-35] 下车机构标识
      0x00, 0x01, // [36-37] 下车运营商代码
      0x00, 0x08, // [38-39] 下车线路号
      0x03, // [3A] 下车站点
      ...List.filled(7, 0), 0x36, // [3B-42] 下车车辆号
      ...List.filled(6, 0), 0x15, 0x68, // [43-4A] 下车终端编号
      0x20, 0x26, 0x08, 0x08, 0x09, 0x12, 0x31, // [4B-51] 下车时间
      0x00, 0x00, 0x01, 0x2C, // [52-55] 交易金额 300 分
      0x00, 0x05, // [56-57] 乘车里程 5
    ];

/// 0x1E 循环记录示例数据（48 字节）：出站 · 城市轨道交通 · 交易金额 500 分 ·
/// 交易后余额 3585 分 · 2024-12-29 14:17:40 · 城市码 1000。
/// 仅用于验证字段布局，为构造示例数据。
List<int> _cycleProcessRecord() => [
      0x04, // 交易类型
      0x00, 0x00, 0x30, 0x00, 0x89, 0x00, 0x03, 0x40, // 终端编号
      0x01, // 应用分类码：城市轨道交通
      0x08, 0x00, 0x19, 0x00, 0x30, 0x00, 0x00, // 线路和站点代码
      0x00, 0x00, 0x01, 0xF4, // 交易金额 500 分
      0x00, 0x00, 0x0E, 0x01, // 交易后余额 3585 分
      0x20, 0x24, 0x12, 0x29, 0x14, 0x17, 0x40, // 交易时间 2024-12-29 14:17:40
      0x10, 0x00, // 城市代码
      0x01, 0x01, 0x10, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, // 收单机构代码
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // 保留
    ];
