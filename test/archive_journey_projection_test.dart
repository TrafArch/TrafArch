import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/features/trips/trip_cards_view.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_presenter.dart';
import 'package:transit_card_analyzer/features/trips/trip_filters.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_process_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_trip_matcher.dart';

void main() {
  test('归档完成行程仅采用出站交易后余额且进行中不显示', () {
    final entry = _transaction(
      status: '进站',
      sequence: 10,
      minute: 0,
      extra: {'balanceAfterFen': 9000, 'balanceAfterIsRecorded': false},
    );
    final exit = _transaction(
      status: '出站',
      sequence: 11,
      minute: 30,
      extra: {'balanceAfterFen': 8700, 'balanceAfterIsRecorded': false},
    );
    final events = _project([entry, exit]);
    expect(events.first.balanceAfterText, '¥ 87.00');
    expect(projectJourneys(events).single.balanceAfterText, '¥ 87.00');
    expect(projectJourneys(_project([entry])).single.balanceAfterText, isNull);
    final unknownExit = _transaction(
      status: '出站',
      sequence: 11,
      minute: 30,
      extra: {'balanceAfterFen': null, 'balanceAfterIsRecorded': null},
    );
    expect(
      projectJourneys(_project([entry, unknownExit])).single.balanceAfterText,
      isNull,
    );
  });

  test('归档v8行程后余额要求明确false来源且保留旧详情显示', () {
    for (final flag in [false, true, null, 'missing']) {
      final event = _project([
        _transaction(
          status: '出站',
          sequence: 1,
          minute: 0,
          extra: {
            'balanceAfterFen': 8000,
            if (flag != 'missing') 'balanceAfterIsRecorded': flag,
          },
        ),
      ]).single;
      expect(event.balanceAfterText, flag == false ? '¥ 80.00' : null);
      expect(
        event.payload.fields,
        contains((flag == true ? '记录余额' : '交易后余额', '¥ 80.00')),
      );
    }
    final zero = _project([
      _transaction(
        status: '出站',
        sequence: 1,
        minute: 0,
        extra: {'balanceAfterFen': 0, 'balanceAfterIsRecorded': false},
      ),
    ]).single;
    expect(zero.balanceAfterText, '¥ 0.00');
  });

  test('归档v6v7继续捕获时余额语义而旧记录余额不提升', () {
    for (final version in [5, 6, 7]) {
      for (final balance in [9000, 8000, null]) {
        final event = _project([
          _transaction(
            status: '出站',
            sequence: 1,
            minute: 0,
            parseVersion: version,
            extra: {
              'balanceAfterFen': balance,
              'balanceAfterIsRecorded': false,
              'matchedProcess': _process(type: 4, app: 1),
            },
          ),
        ]).single;
        expect(
          event.balanceAfterText,
          version >= 6 && balance == 8000 ? '¥ 80.00' : null,
        );
      }
    }
  });

  test('独立1E记录余额和1A进站余额不得冒充行程后余额', () {
    final process = _project([
      _record(ArchiveRecordKind.process, _process(type: 4, app: 1)),
    ]).single;
    expect(process.balanceAfterText, isNull);
    expect(process.payload.fields, contains(('记录余额', '¥ 90.00')));
    final application = _project([_application(ArchiveRecordKind.rail)]);
    expect(
      application.every((event) => event.balanceAfterText == null),
      isTrue,
    );
    expect(projectJourneys(application).single.balanceAfterText, isNull);
  });

  test('归档仅按明确大兴机场线人民币50元消费规则标商务座', () {
    for (final (line, fare, consume, currency, expected) in [
      ('大兴机场线', 5000, true, 'CNY', '商务座'),
      ('大兴机场线', 3500, true, 'CNY', null),
      ('11号线', 5000, true, 'CNY', null),
      ('大兴机场线', 5000, false, 'CNY', null),
      ('大兴机场线', 5000, true, 'HKD', null),
    ]) {
      final event = _project([
        _transaction(
          status: '出站',
          sequence: 1,
          minute: 0,
          context: _context(currency: currency),
          extra: {'lineLabel': line, 'amountFen': fare, 'consume': consume},
        ),
      ]).single;
      expect(event.seatLabel, expected);
    }
  });

  test('归档1A席别使用本侧线路金额且完成行程采用出站侧', () {
    for (final (entryLine, entryFare, exitLine, exitFare, expected) in [
      ('2号线', 0, '大兴机场线', 5000, '商务座'),
      ('大兴机场线', 5000, '2号线', 5000, null),
      ('大兴机场线', 5000, '大兴机场线', 3500, null),
    ]) {
      final events = _project([
        _application(
          ArchiveRecordKind.rail,
          extra: {
            'entryAmountFen': entryFare,
            'exitAmountFen': exitFare,
            'capturedDisplay': {
              'entry': {'line': entryLine},
              'exit': {'line': exitLine},
            },
          },
        ),
      ]);
      expect(events.first.seatLabel, expected);
      expect(projectJourneys(events).single.seatLabel, expected);
    }
  });

  test('归档独立1E席别使用保存线路和过程消费类型', () {
    for (final (type, expected) in [(4, '商务座'), (3, null), (9, null)]) {
      final event = _project([
        _record(ArchiveRecordKind.process, {
          ..._process(type: type, app: 1),
          'amountFen': 5000,
          'capturedDisplay': {'line': '大兴机场线'},
        }),
      ]).single;
      expect(event.seatLabel, expected);
    }
  });

  test('归档已捕获公交数字线路显示路字而旧原码保留原样', () {
    for (final decoded in [null, '345']) {
      final event = _project([
        _transaction(
          sequence: 1,
          minute: 0,
          extra: {
            'appTypeName': '公共汽电车',
            'lineLabel': decoded ?? '0010',
            if (decoded != null) 'capturedDisplay': {'line': decoded},
          },
        ),
      ]).single;
      expect(event.endpoint.line, decoded == null ? '0010' : '345路');
    }
  });

  test('归档只用捕获的独立两端显示证据而保留原详情与原码', () {
    final events = _project([
      _application(
        ArchiveRecordKind.rail,
        extra: {
          'capturedDisplay': {
            'entry': {'line': '捕获1号线', 'station': '捕获起站'},
            'exit': {'line': '捕获2号线', 'station': '捕获终站'},
          },
        },
      ),
    ]);
    expect(events.last.endpoint.line, '捕获1号线');
    expect(events.first.endpoint.line, '捕获2号线');
    expect(events.last.endpoint.station, '捕获起站');
    expect(events.first.endpoint.station, '捕获终站');
    expect(events.last.payload.fields, contains(('进闸站点（原始）', '00000001')));
    expect(events.last.payload.fields, contains(('进入站点', '人民广场')));
  });

  test('独立1E以捕获原始槽号配对而不用cycle数组下标猜序号', () {
    final events = _project([
      _processAt(2, type: 3, minute: 0),
      _processAt(1, type: 4, minute: 30),
    ]);
    expect(events.last.processPositions, {'capture-1': 2});
    expect(events.first.processPositions, {'capture-1': 1});
    expect(events.every((event) => event.sequence == null), isTrue);
    final journeys = projectJourneys(events);
    expect(journeys, hasLength(1));
    expect(journeys.single.duration, const Duration(minutes: 30));
  });

  test('北京窗口边界的交易出站继承原始1E槽9并与独立槽10进站配对', () {
    final exitProcess = _reportedProcess(9);
    final entryProcess = _reportedProcess(10);
    final transaction = _reportedTransaction(exitProcess);
    final records = [transaction, exitProcess, entryProcess];
    final before = jsonEncode(records.map((record) => record.fields).toList());
    final events = _project(records);
    expect(events, hasLength(2));
    final exit = events.singleWhere((event) => event.sequence == 33);
    expect(exit.processPositions, {'capture-1': 9});
    final journeys = projectJourneys(events);
    expect(journeys, hasLength(1));
    expect(journeys.single.state, JourneyState.completed);
    expect(journeys.single.start!.station, '北沙滩');
    expect(journeys.single.end!.station, '奥林匹克公园');
    expect(journeys.single.duration, const Duration(minutes: 9, seconds: 17));
    expect(journeys.single.amountText, '-¥ 3.00');
    expect(journeys.single.balanceAfterText, '¥ 138.50');
    expect(journeys.single.events, hasLength(2));
    expect(jsonEncode(records.map((record) => record.fields).toList()), before);
  });

  test('北京345路的1A和独立1E四侧只呈现一段行程且保留所有详情', () {
    final records = [
      _reportedBusApplication(),
      _reportedProcess(11),
      _reportedProcess(12),
    ];
    final before = jsonEncode(records.map((record) => record.fields).toList());
    final events = _project(records);
    expect(events, hasLength(4));
    final journeys = projectJourneys(events);
    expect(journeys, hasLength(1));
    final journey = journeys.single;
    expect(journey.state, JourneyState.completed);
    expect(journey.start!.line, '345路');
    expect(journey.start!.station, '站点19');
    expect(journey.end!.station, '站点5');
    expect(journey.duration, const Duration(hours: 1, minutes: 3, seconds: 55));
    expect(journey.amountText, '-¥ 2.00');
    expect(journey.balanceAfterText, '¥ 141.50');
    expect(journey.events, hasLength(4));
    expect(
      journey.events.map((event) => event.payload),
      unorderedEquals(events.map((event) => event.payload)),
    );
    expect(jsonEncode(records.map((record) => record.fields).toList()), before);
  });

  test('归档独立1E公交以两端余额差校验下车后余额', () {
    final events = _project([
      _balanceProcessAt(
        2,
        type: 3,
        minute: 0,
        amount: 0,
        balance: 10000,
        app: 2,
      ),
      _balanceProcessAt(
        1,
        type: 4,
        minute: 10,
        amount: 300,
        balance: 9700,
        app: 2,
      ),
    ]);
    final journey = projectJourneys(events).single;
    expect(journey.state, JourneyState.completed);
    expect(journey.amountText, '-¥ 3.00');
    expect(journey.balanceAfterText, '¥ 97.00');
    expect(journey.events, hasLength(2));
  });

  test('归档公交余额差不能越过批次币种缺槽或不可靠来源', () {
    final invalidEntries = [
      _balanceProcessAt(
        2,
        type: 3,
        minute: 0,
        amount: 0,
        balance: 10000,
        app: 2,
        batch: 'other-capture',
      ),
      _balanceProcessAt(
        2,
        type: 3,
        minute: 0,
        amount: 0,
        balance: 10000,
        app: 2,
        context: _context(currency: 'HKD'),
      ),
      _balanceProcessAt(
        3,
        type: 3,
        minute: 0,
        amount: 0,
        balance: 10000,
        app: 2,
      ),
      _balanceProcessAt(
        2,
        type: 3,
        minute: 0,
        amount: 0,
        balance: 10000,
        app: 2,
        reliable: false,
      ),
    ];
    for (final entry in invalidEntries) {
      final journeys = projectJourneys(
        _project([
          entry,
          _balanceProcessAt(
            1,
            type: 4,
            minute: 10,
            amount: 300,
            balance: 9700,
            app: 2,
          ),
        ]),
      );
      expect(journeys, hasLength(2));
      expect(
        journeys.every((journey) => journey.balanceAfterText == null),
        isTrue,
      );
    }
  });

  test('归档公交两端余额差或进站金额不符时不推导余额', () {
    for (final (entryAmount, exitBalance) in [(0, 9800), (100, 9700)]) {
      final journey = projectJourneys(
        _project([
          _balanceProcessAt(
            2,
            type: 3,
            minute: 0,
            amount: entryAmount,
            balance: 10000,
            app: 2,
          ),
          _balanceProcessAt(
            1,
            type: 4,
            minute: 10,
            amount: 300,
            balance: exitBalance,
            app: 2,
          ),
        ]),
      ).single;
      expect(journey.state, JourneyState.completed);
      expect(journey.balanceAfterText, isNull);
    }
  });

  test('归档轨道扣款前记录余额由更晚相邻1E零金额进站局部校验', () {
    final records = [
      _balanceProcessAt(3, type: 3, minute: 0, amount: 0, balance: 10000),
      _balanceProcessAt(2, type: 4, minute: 10, amount: 300, balance: 10000),
      _balanceProcessAt(1, type: 3, minute: 20, amount: 0, balance: 9700),
    ];
    final before = jsonEncode(records.map((record) => record.fields).toList());
    final journeys = projectJourneys(_project(records));
    final completed = journeys.singleWhere(
      (journey) => journey.state == JourneyState.completed,
    );
    expect(completed.balanceAfterText, '¥ 97.00');
    expect(completed.events, hasLength(2));
    expect(
      journeys
          .singleWhere((journey) => journey.state == JourneyState.inProgress)
          .balanceAfterText,
      isNull,
    );
    expect(jsonEncode(records.map((record) => record.fields).toList()), before);
  });

  test('归档未知或矛盾的余额解释不能仅凭direct字符串升级原始余额', () {
    for (final observation in [
      null,
      'direct',
      {'version': 2, 'semantics': 'direct'},
      {'version': 1, 'semantics': 'direct', 'product': 'unknown'},
    ]) {
      final context = ArchiveContext.fromJson({
        ..._context().toJson(),
        'balanceInterpretation': observation,
      });
      final journey = projectJourneys(
        _project([
          _balanceProcessAt(
            2,
            type: 3,
            minute: 0,
            amount: 0,
            balance: 10000,
            app: 2,
            context: context,
          ),
          _balanceProcessAt(
            1,
            type: 4,
            minute: 10,
            amount: 300,
            balance: 9700,
            app: 2,
            context: context,
          ),
        ]),
      ).single;
      expect(journey.balanceAfterText, isNull, reason: '$observation');
    }
  });

  test('归档两端1E余额相等但没有局部锚时不猜扣款后余额', () {
    final journey = projectJourneys(
      _project([
        _balanceProcessAt(2, type: 3, minute: 0, amount: 0, balance: 10000),
        _balanceProcessAt(1, type: 4, minute: 10, amount: 300, balance: 10000),
      ]),
    ).single;
    expect(journey.state, JourneyState.completed);
    expect(journey.balanceAfterText, isNull);
  });

  test('归档局部余额锚不跨批次币种缺槽或不可靠来源', () {
    final invalidAnchors = [
      _balanceProcessAt(
        2,
        type: 3,
        minute: 20,
        amount: 0,
        balance: 9700,
        batch: 'other-capture',
      ),
      _balanceProcessAt(
        2,
        type: 3,
        minute: 20,
        amount: 0,
        balance: 9700,
        context: _context(currency: 'HKD'),
      ),
      _balanceProcessAt(1, type: 3, minute: 20, amount: 0, balance: 9700),
      _balanceProcessAt(
        2,
        type: 3,
        minute: 20,
        amount: 0,
        balance: 9700,
        reliable: false,
      ),
      _balanceProcessAt(
        2,
        type: 3,
        minute: 20,
        amount: 0,
        balance: 9700,
        provenanceRaw: 'DEADBEEF',
      ),
      _balanceProcessAt(2, type: 3, minute: 20, amount: 100, balance: 9700),
      _balanceProcessAt(2, type: 3, minute: 20, amount: 0, balance: 9800),
    ];
    for (final anchor in invalidAnchors) {
      final journeys = projectJourneys(
        _project([
          _balanceProcessAt(4, type: 3, minute: 0, amount: 0, balance: 10000),
          _balanceProcessAt(
            3,
            type: 4,
            minute: 10,
            amount: 300,
            balance: 10000,
          ),
          anchor,
        ]),
      );
      final completed = journeys.singleWhere(
        (journey) => journey.state == JourneyState.completed,
      );
      expect(completed.balanceAfterText, isNull);
    }
  });

  test('归档局部锚的原始槽号在完整列表中重复时不推导余额', () {
    final journeys = projectJourneys(
      _project([
        _balanceProcessAt(3, type: 3, minute: 0, amount: 0, balance: 10000),
        _balanceProcessAt(2, type: 4, minute: 10, amount: 300, balance: 10000),
        _balanceProcessAt(1, type: 3, minute: 20, amount: 0, balance: 9700),
        _balanceProcessAt(1, type: 3, minute: 21, amount: 0, balance: 9700),
      ]),
    );
    expect(
      journeys
          .singleWhere((journey) => journey.state == JourneyState.completed)
          .balanceAfterText,
      isNull,
    );
  });

  test('归档出站和局部锚之间的已知交易阻断余额推导', () {
    final journeys = projectJourneys(
      _project([
        _balanceProcessAt(3, type: 3, minute: 0, amount: 0, balance: 10000),
        _balanceProcessAt(2, type: 4, minute: 10, amount: 300, balance: 10000),
        _transaction(
          sequence: 80,
          minute: 15,
          extra: {
            'cityCode': '1000',
            'consume': false,
            'typeName': '充值',
            'amountFen': 500,
            'balanceAfterFen': null,
            'balanceAfterIsRecorded': null,
          },
        ),
        _balanceProcessAt(1, type: 3, minute: 20, amount: 0, balance: 9700),
      ]),
    );
    expect(
      journeys
          .singleWhere((journey) => journey.state == JourneyState.completed)
          .balanceAfterText,
      isNull,
    );
  });

  test('归档已有可靠交易后余额优先于过程余额关系', () {
    final exit = _balanceProcessAt(
      1,
      type: 4,
      minute: 10,
      amount: 300,
      balance: 9700,
    );
    final journeys = projectJourneys(
      _project([
        _balanceProcessAt(2, type: 3, minute: 0, amount: 0, balance: 10000),
        exit,
        _reportedTransaction(exit, extra: {'balanceAfterFen': 9600}),
      ]),
    );
    expect(journeys, hasLength(1));
    expect(journeys.single.state, JourneyState.completed);
    expect(journeys.single.balanceAfterText, '¥ 96.00');
  });

  test('旧版已保存1E重开即可校验余额且快照JSON原文不改写', () {
    final captured = [
      _balanceProcessAt(
        2,
        type: 3,
        minute: 0,
        amount: 0,
        balance: 10000,
        app: 2,
      ),
      _balanceProcessAt(
        1,
        type: 4,
        minute: 10,
        amount: 300,
        balance: 9700,
        app: 2,
      ),
    ];
    final savedJson = const JsonEncoder.withIndent('  ').convert({
      'v': 3,
      'parseVersion': 9,
      'cityCode': '1000',
      'context': _context().toJson(),
      'trips': <Object?>[],
      'rails': <Object?>[],
      'buses': <Object?>[],
      'cycle': [for (final record in captured) record.fields],
      'rawEvidence': <Object?>[],
      'recordProvenance': {
        for (var index = 0; index < captured.length; index++)
          'cycle[$index]':
              (captured[index].sources.single.provenance as Map)['record'],
      },
      'retainedExtension': {'source': 'legacy-capture', 'raw': '000001'},
    });
    final snapshot = CardSessionSnapshot.decode(savedJson)!;
    final envelope = jsonDecode(snapshot.encode()) as Map<String, dynamic>;
    final cycle = envelope['cycle'] as List;
    final provenance = envelope['recordProvenance'] as Map;
    final reopened = [
      for (var index = 0; index < cycle.length; index++)
        ArchiveHistoryRecord(
          kind: ArchiveRecordKind.process,
          fields: Map<String, dynamic>.from(cycle[index] as Map),
          context: snapshot.context,
          cardCityCode: snapshot.cardCityCode,
          sources: [
            ArchiveRecordSource('saved-capture', 'cycle[$index]', 9, {
              'record': provenance['cycle[$index]'],
            }),
          ],
        ),
    ];
    final journey = projectJourneys(_project(reopened)).single;
    expect(journey.state, JourneyState.completed);
    expect(journey.balanceAfterText, '¥ 97.00');
    expect(snapshot.encode(), savedJson);
    expect(envelope['cycle'], [for (final record in captured) record.fields]);
    expect(envelope['retainedExtension'], {
      'source': 'legacy-capture',
      'raw': '000001',
    });
  });

  test('交易继承1E槽位必须同批次同上下文时间方向和金额且关联唯一', () {
    final process = _reportedProcess(9);
    final timestamp = process.fields['time'] as int;
    final invalidTransactions = [
      _reportedTransaction(process, batches: ['other-capture']),
      _reportedTransaction(process, context: _context(application: 'other')),
      _reportedTransaction(process, extra: {'time': timestamp + 1000}),
      _reportedTransaction(process, extra: {'cityCode': '3100'}),
      _reportedTransaction(process, extra: {'rideStatusName': '进站'}),
      _reportedTransaction(process, extra: {'amountFen': 301}),
      _reportedTransaction(
        process,
        extra: {'displayProcessKey': null, 'matchedProcess': null},
      ),
    ];
    for (final transaction in invalidTransactions) {
      final events = _project([transaction, process, _reportedProcess(10)]);
      expect(
        events.singleWhere((event) => event.sequence == 33).processPositions,
        isEmpty,
      );
    }
    final ambiguous = _project([
      _reportedTransaction(process),
      _reportedTransaction(process, extra: {'sequence': 34}),
      process,
      _reportedProcess(10),
    ]);
    expect(
      ambiguous
          .where((event) => event.sequence != null)
          .every((event) => event.processPositions.isEmpty),
      isTrue,
    );
  });

  test('独立1E不能因跨批次同秒或终端冲突继承1A行程身份', () {
    final application = _reportedBusApplication();
    for (final process in [
      _reportedProcess(12, batch: 'other-capture'),
      _reportedProcess(12, context: _context(application: 'other')),
      _reportedProcess(12, extra: {'terminalId': '0000001009009999'}),
      _reportedProcess(12, extra: {'cityCode': '3100'}),
      _reportedProcess(
        12,
        extra: {'time': (_reportedProcess(12).fields['time'] as int) + 1000},
      ),
    ]) {
      final events = _project([application, process]);
      expect(
        events
            .singleWhere((event) => event.processPositions.isNotEmpty)
            .applicationRecordId,
        isNull,
      );
    }
  });

  test('交易不能经合并的1E历史记录继承另一批次才存在的1A身份', () {
    final captured = _reportedProcess(12);
    final process = ArchiveHistoryRecord(
      kind: captured.kind,
      fields: captured.fields,
      context: captured.context,
      cardCityCode: captured.cardCityCode,
      sources: [
        ...captured.sources,
        ArchiveRecordSource(
          'capture-2',
          captured.sources.single.path,
          9,
          captured.sources.single.provenance,
        ),
      ],
    );
    final transaction = _reportedTransaction(
      process,
      batches: ['capture-2'],
      extra: {
        'rideStatusName': '上车',
        'appTypeName': '公共汽电车',
        'amountFen': 0,
        'lineLabel': '345路',
        'stationLabel': '站点19',
      },
    );
    final events = _project([_reportedBusApplication(), process, transaction]);
    final transactionEvent = events.singleWhere(
      (event) => event.sequence == 33,
    );
    expect(transactionEvent.processPositions, {'capture-2': 12});
    expect(transactionEvent.applicationRecordId, isNull);
  });

  test('同一1A侧有多个1E候选或同一1E有多个1A候选时不折叠', () {
    final duplicateCycle = _project([
      _reportedBusApplication(),
      _reportedProcess(12),
      _reportedProcess(12),
    ]);
    expect(
      duplicateCycle
          .where((event) => event.payload.sourceLabel == '0x1E 过程记录')
          .every((event) => event.applicationRecordId == null),
      isTrue,
    );
    expect(projectJourneys(duplicateCycle), hasLength(3));
    final duplicateApplication = _project([
      _reportedBusApplication(),
      _reportedBusApplication(),
      _reportedProcess(12),
    ]);
    expect(
      duplicateApplication
          .singleWhere((event) => event.processPositions.isNotEmpty)
          .applicationRecordId,
      isNull,
    );
    expect(projectJourneys(duplicateApplication), hasLength(3));
  });

  test('30条明确独立过程事件保留全部详情并组成15次行程', () {
    final events = _project([
      for (var i = 0; i < 30; i++)
        _processAt(30 - i, type: i.isEven ? 3 : 4, minute: i),
    ]);
    expect(events, hasLength(30));
    final journeys = projectJourneys(events);
    expect(journeys, hasLength(15));
    expect(
      journeys.every((journey) => journey.state == JourneyState.completed),
      isTrue,
    );
    expect(journeys.expand((journey) => journey.events), hasLength(30));
  });

  test('归档过程的压缩cycle路径不等于原始槽号证据', () {
    final events = _project([
      _processAt(2, type: 3, minute: 0, reliable: false),
      _processAt(1, type: 4, minute: 30, reliable: false),
    ]);
    expect(events.every((event) => event.processPositions.isEmpty), isTrue);
    expect(projectJourneys(events), hasLength(2));
  });

  test('过程来源原码冲突或槽位重复不获得邻接证据', () {
    final mismatch = _processAt(
      2,
      type: 3,
      minute: 0,
      provenanceRaw: 'DEADBEEF',
    );
    final duplicate = _processAt(2, type: 0x7F, minute: 50);
    final events = _project([
      mismatch,
      _processAt(2, type: 3, minute: 0),
      _processAt(1, type: 4, minute: 30),
      duplicate,
    ]);
    expect(
      events
          .where((event) => event.role == JourneyEventRole.entry)
          .every((event) => event.processPositions.isEmpty),
      isTrue,
    );
    expect(
      projectJourneys(events)
          .any((journey) => journey.state == JourneyState.completed),
      isFalse,
    );
  });

  test('归档1E原始缺槽或不同来源批次不得在排序后重新拼接', () {
    for (final entry in [
      _processAt(3, type: 3, minute: 0),
      _processAt(2, type: 3, minute: 0, batch: 'other-read'),
    ]) {
      final events = _project([entry, _processAt(1, type: 4, minute: 30)]);
      expect(projectJourneys(events), hasLength(2));
    }
  });

  test('归档接入保留条目数量原始详情诊断对象及未改写快照', () {
    final first = _transaction(status: '进站', sequence: 10, minute: 0);
    final last = _transaction(status: '出站', sequence: 11, minute: 30);
    final before = jsonEncode([first.fields, last.fields]);
    final diagnosed = <ArchiveHistoryRecord>[];
    final projection = presentArchiveTrips([
      first,
      last,
    ], onDiagnostics: diagnosed.add);
    expect(projection.entries, hasLength(2));
    expect(projection.transactionCount, 2);
    expect(projection.processRecordCount, 0);
    final entries = projection.entries;
    final events = _events(entries);
    expect(identical(events.first.payload, entries.first.info), isTrue);
    expect(entries.first.info.title, '出站 · 终点站 · 序号 11');
    expect(entries.first.info.fields, contains(('终端编号', '000000000011')));
    expect(entries.first.info.subText, '交易后余额 ¥ 90.00');
    entries.first.onDiagnostics!();
    expect(identical(diagnosed.single, last), isTrue);
    expect(jsonEncode([first.fields, last.fields]), before);
    final journeys = projectJourneys(events);
    expect(journeys, hasLength(1));
    expect(journeys.single.state, JourneyState.completed);
    expect(journeys.single.duration, const Duration(minutes: 30));
    expect(journeys.single.amountText, '-¥ 3.00');
    expect(journeys.single.cityLabel, '上海');
  });

  test('未知时区的捕获civil保留卡内钟面且同批次只做同钟面时长', () {
    final events = _project([
      _transaction(status: '进站', sequence: 10, minute: 0),
      _transaction(status: '出站', sequence: 11, minute: 30),
    ]);
    expect(events.last.endpoint.timeText, '08:00:00');
    expect(events.first.endpoint.timeText, '08:30:00');
    expect(events.last.payload.timeText, contains('时区未经核实'));
    // Epoch values deliberately disagree with captured clock-face values.
    expect(events.last.endpoint.time!.hour, 8);
    final journeys = projectJourneys(events);
    expect(journeys, hasLength(1));
    expect(journeys.single.duration, const Duration(minutes: 30));
  });

  test('只有旧epoch且时区未知保留显示证据但不生成可配对时间', () {
    final events = _project([
      _transaction(
        status: '进站',
        sequence: 10,
        minute: 0,
        extra: {'capturedTimes': null},
      ),
      _transaction(
        status: '出站',
        sequence: 11,
        minute: 30,
        extra: {'capturedTimes': null},
      ),
    ]);
    expect(events.every((event) => event.endpoint.time == null), isTrue);
    expect(events.first.endpoint.timeText, contains('UTC'));
    expect(events.first.payload.timeText, contains('时区未知'));
    expect(projectJourneys(events), hasLength(2));
  });

  test('明确偏移的旧epoch按捕获钟面显示并计算同偏移时长', () {
    final context = _context(offset: 480);
    final start = DateTime.utc(2026, 10, 27);
    final events = _project([
      _transaction(
        status: '进站',
        sequence: 10,
        minute: 0,
        context: context,
        extra: {'capturedTimes': null, 'time': start.millisecondsSinceEpoch},
      ),
      _transaction(
        status: '出站',
        sequence: 11,
        minute: 30,
        context: context,
        extra: {
          'capturedTimes': null,
          'time': start.add(const Duration(minutes: 30)).millisecondsSinceEpoch,
        },
      ),
    ]);
    expect(events.last.endpoint.time, start.add(const Duration(hours: 8)));
    expect(events.last.endpoint.timeText, '08:00:00');
    expect(projectJourneys(events), hasLength(1));
  });

  test('明确偏移跨午夜时日期坐标与卡内时分秒保持同一天', () {
    final context = _context(offset: 480);
    final events = _project([
      _transaction(
        status: '进站',
        sequence: 10,
        minute: 0,
        context: context,
        extra: {
          'capturedTimes': null,
          'time': DateTime.utc(2026, 10, 26, 16, 10).millisecondsSinceEpoch,
        },
      ),
      _transaction(
        status: '出站',
        sequence: 11,
        minute: 30,
        context: context,
        extra: {
          'capturedTimes': null,
          'time': DateTime.utc(2026, 10, 26, 16, 40).millisecondsSinceEpoch,
        },
      ),
    ]);
    expect(events.last.endpoint.time, DateTime.utc(2026, 10, 27, 0, 10));
    expect(events.last.endpoint.timeText, '00:10:00');
    final journeys = projectJourneys(events);
    expect(journeys, hasLength(1));
    expect(journeys.single.duration, const Duration(minutes: 30));
  });

  test('旧isUtc字段与新basis字段的civil各自保留且不同schema不猜等价', () {
    final events = _project([
      _transaction(
        status: '进站',
        sequence: 10,
        minute: 0,
        extra: {
          'capturedTimes': {
            'time': {'civil': '2026-10-27T08:00:00.000', 'isUtc': false},
          },
        },
      ),
      _transaction(status: '出站', sequence: 11, minute: 30),
    ]);
    expect(events.last.endpoint.timeText, '08:00:00');
    expect(events.last.endpoint.time!.hour, 8);
    expect(projectJourneys(events), hasLength(2));
  });

  test('UTC捕获和未知时区civil禁止仅凭相同钟面合并', () {
    final events = _project([
      _transaction(
        status: '进站',
        sequence: 10,
        minute: 0,
        extra: {
          'capturedTimes': {
            'time': {
              'civil': '2026-10-27T08:00:00.000Z',
              'basis': 'utc',
              'conversionOffsetMinutes': 0,
            },
          },
        },
      ),
      _transaction(status: '出站', sequence: 11, minute: 30),
    ]);
    expect(events.last.endpoint.timeText, '08:00:00');
    expect(projectJourneys(events), hasLength(2));
  });

  test('非法civil日期不经过自动进位成为可配对日期', () {
    final events = _project([
      _transaction(
        status: '进站',
        sequence: 10,
        minute: 0,
        extra: {
          'capturedTimes': {
            'time': {
              'civil': '2026-02-30T08:00:00',
              'basis': 'parser-local-unverified',
            },
          },
        },
      ),
    ]);
    expect(events.single.endpoint.time, isNull);
    expect(events.single.scopeKey, isNull);
  });

  test('矛盾UTC标记不被解释为有效captured时钟', () {
    final events = _project([
      _transaction(
        status: '进站',
        sequence: 10,
        minute: 0,
        extra: {
          'capturedTimes': {
            'time': {
              'civil': '2026-10-27T08:00:00Z',
              'basis': 'parser-local-unverified',
            },
          },
        },
      ),
    ]);
    expect(events.single.endpoint.time, isNull);
    expect(events.single.scopeKey, isNull);
  });

  test('超范围捕获偏移不能作为两个记录相同的有效时间上下文', () {
    final context = _context(offset: 1500);
    final events = _project([
      _transaction(status: '进站', sequence: 10, minute: 0, context: context),
      _transaction(status: '出站', sequence: 11, minute: 30, context: context),
    ]);
    expect(events.every((event) => event.scopeKey == null), isTrue);
    expect(projectJourneys(events), hasLength(2));
  });

  for (final (name, context) in [
    ('未知上下文', const ArchiveContext()),
    ('另一应用', _context(application: 'other-wallet')),
    ('另一币种', _context(currency: 'HKD')),
    ('另一精度', _context(digits: 0)),
    ('另一时钟依据', _context(clock: 'different-clock')),
    ('另一时区偏移', _context(offset: 480)),
  ]) {
    test('$name禁止连续序号跨范围配对', () {
      final events = _project([
        _transaction(status: '进站', sequence: 10, minute: 0),
        _transaction(status: '出站', sequence: 11, minute: 30, context: context),
      ]);
      expect(projectJourneys(events), hasLength(2));
    });
  }

  test('批次来源以集合交集建立关系且不跨无关读取配对', () {
    final start = _transaction(
      status: '进站',
      sequence: 10,
      minute: 0,
      batches: ['read-a', 'read-common'],
    );
    final shared = _project([
      start,
      _transaction(
        status: '出站',
        sequence: 11,
        minute: 30,
        batches: ['read-common', 'read-b'],
      ),
    ]);
    expect(shared.last.sourceIds, {'read-a', 'read-common'});
    expect(projectJourneys(shared), hasLength(1));
    final separate = _project([
      start,
      _transaction(status: '出站', sequence: 11, minute: 30, batches: ['read-c']),
    ]);
    expect(projectJourneys(separate), hasLength(2));
  });

  test('1A同一记录两端共享身份并保留各自线路站点和金额', () {
    final events = _project([_application(ArchiveRecordKind.rail)]);
    expect(events, hasLength(2));
    final entry = events.last;
    final exit = events.first;
    expect(entry.applicationRecordId, isNotNull);
    expect(entry.applicationRecordId, exit.applicationRecordId);
    expect(entry.endpoint.station, '人民广场');
    expect(exit.endpoint.station, '世纪大道');
    expect(entry.endpoint.line, '1');
    expect(exit.endpoint.line, '2');
    expect(entry.endpoint.timeText, '08:00:00');
    expect(exit.endpoint.timeText, '08:30:00');
    final journeys = projectJourneys(events);
    expect(journeys, hasLength(1));
    expect(journeys.single.amountText, '-¥ 3.00');
    expect(journeys.single.seatLabel, isNull);
    expect(exit.payload.fields, contains(('进闸站点（原始）', '00000001')));
  });

  test('1A不把单一lineName复制成两个端点的线路证据', () {
    final events = _project([
      _application(
        ArchiveRecordKind.rail,
        extra: {'entryLineCode': null, 'exitLineCode': null},
      ),
    ]);
    expect(events.every((event) => event.endpoint.line == null), isTrue);
    expect(events.every((event) => event.payload.line == '保存的单侧线路'), isTrue);
  });

  test('不同1A记录不因内容相同共享配对身份', () {
    final first = _project([_application(ArchiveRecordKind.rail)]);
    final second = _project([_application(ArchiveRecordKind.rail)]);
    expect(first.first.applicationRecordId, isNotNull);
    expect(
      second.first.applicationRecordId,
      isNot(first.first.applicationRecordId),
    );
  });

  test('已保存唯一1A关联使隐藏两侧的非连续交易可组成同一行程', () {
    final application = _application(ArchiveRecordKind.rail);
    final projection = presentArchiveTrips([
      _linkedTransaction(application, entry: true),
      _linkedTransaction(application, entry: false),
      application,
    ], onDiagnostics: (_) {});
    expect(projection.entries, hasLength(2));
    expect(projection.processRecordCount, 0);
    expect(projection.mergedRecordCount, 1);
    final events = _events(projection.entries);
    expect(events.last.sequence, 10);
    expect(events.first.sequence, 12);
    expect(events.last.applicationRecordId, isNotNull);
    expect(events.first.applicationRecordId, events.last.applicationRecordId);
    final journeys = projectJourneys(events);
    expect(journeys, hasLength(1));
    expect(journeys.single.state, JourneyState.completed);
  });

  for (final (label, kind, conflictingEntry) in [
    ('轨道进站', ArchiveRecordKind.rail, true),
    ('轨道出站', ArchiveRecordKind.rail, false),
    ('公交下车', ArchiveRecordKind.bus, false),
  ]) {
    test('已存1A应用key的$label已知金额冲突不能建立行程身份', () {
      final application = _application(kind, extra: {'amountFen': 300});
      final events = _project([
        _linkedTransaction(
          application,
          entry: true,
          extra: conflictingEntry ? {'amountFen': 1} : const {},
        ),
        _linkedTransaction(
          application,
          entry: false,
          extra: conflictingEntry ? const {} : {'amountFen': 301},
        ),
        application,
      ]);

      final conflicting = events.singleWhere(
        (event) => event.sequence == (conflictingEntry ? 10 : 12),
      );
      expect(conflicting.applicationRecordId, isNull);
      expect(
        events.singleWhere((event) => event != conflicting).applicationRecordId,
        isNotNull,
      );
      expect(
        projectJourneys(events)
            .every((journey) => journey.state != JourneyState.completed),
        isTrue,
      );
    });
  }

  test('公交1A标注金额和下车金额不能当作上车交易金额校验', () {
    final application = _application(
      ArchiveRecordKind.bus,
      extra: {'amountFen': 300, 'annotateAmountFen': 500},
    );
    final events = _project([
      _linkedTransaction(application, entry: true),
      _linkedTransaction(application, entry: false),
      application,
    ]);

    final entry = events.singleWhere((event) => event.sequence == 10);
    final exit = events.singleWhere((event) => event.sequence == 12);
    expect(entry.applicationRecordId, isNotNull);
    expect(exit.applicationRecordId, entry.applicationRecordId);
    expect(projectJourneys(events).single.state, JourneyState.completed);
  });

  test('已存应用key仅POS相同但时间不吻合不能提供行程身份', () {
    final application = _application(ArchiveRecordKind.rail);
    final events = _project([
      _linkedTransaction(application, entry: true),
      _linkedTransaction(
        application,
        entry: false,
        extra: {
          'time': DateTime.utc(2026, 10, 27, 23).millisecondsSinceEpoch,
          'capturedTimes': {'time': _civil('10:00:00')},
        },
      ),
      application,
    ]);
    expect(events.first.applicationRecordId, isNull);
    expect(projectJourneys(events), hasLength(2));
  });

  test('已存应用key不能跨不同上下文或读取批次建立隐藏行程关系', () {
    final application = _application(ArchiveRecordKind.rail);
    for (final wrong in [
      _linkedTransaction(
        application,
        entry: false,
        context: _context(application: 'different-wallet'),
      ),
      _linkedTransaction(application, entry: false, batches: ['other-capture']),
      _linkedTransaction(
        application,
        entry: false,
        extra: {'cityCode': '1000'},
      ),
    ]) {
      final events = _project([
        _linkedTransaction(application, entry: true),
        wrong,
        application,
      ]);
      final transaction = events.singleWhere((event) => event.sequence == 12);
      expect(transaction.applicationRecordId, isNull);
    }
  });

  test('多个相同应用key候选不任意选择其中一条记录作配对依据', () {
    final application = _application(ArchiveRecordKind.rail);
    final events = _project([
      _linkedTransaction(application, entry: true),
      _linkedTransaction(application, entry: false),
      application,
      _application(ArchiveRecordKind.rail),
    ]);
    expect(
      events
          .where((event) => event.sequence != null)
          .every((event) => event.applicationRecordId == null),
      isTrue,
    );
  });

  test('同一应用侧对应多个交易时不任意选一笔继承身份', () {
    final application = _application(ArchiveRecordKind.rail);
    final events = _project([
      _linkedTransaction(application, entry: true),
      _linkedTransaction(application, entry: true, extra: {'sequence': 9}),
      _linkedTransaction(application, entry: false),
      application,
    ]);
    expect(
      events
          .where((event) => event.role == JourneyEventRole.entry)
          .every((event) => event.applicationRecordId == null),
      isTrue,
    );
    expect(
      projectJourneys(events)
          .any((journey) => journey.state == JourneyState.completed),
      isFalse,
    );
  });

  test('隐藏1A状态01旧exit不能给交易补身份或把未知角色当进行中', () {
    final application = _application(
      ArchiveRecordKind.rail,
      extra: {'status': 1},
    );
    final events = _project([
      _linkedTransaction(
        application,
        entry: true,
        extra: {'rideStatusName': null, 'isEntry': false},
      ),
      _linkedTransaction(application, entry: false),
      application,
    ]);
    expect(events.first.applicationRecordId, isNull);
    expect(events.last.role, JourneyEventRole.unknown);
    expect(
      projectJourneys(events).every(
        (journey) =>
            journey.state != JourneyState.completed &&
            journey.state != JourneyState.inProgress,
      ),
      isTrue,
    );
  });

  test('1A状态01旧出站字段保留但不补成当前行程', () {
    final events = _project([
      _application(ArchiveRecordKind.rail, extra: {'status': 1}),
    ]);
    expect(events, hasLength(2));
    expect(events.first.role, JourneyEventRole.unknown);
    expect(events.first.applicationRecordId, isNull);
    expect(events.last.role, JourneyEventRole.entry);
    final journeys = projectJourneys(events);
    expect(journeys, hasLength(2));
    expect(
      journeys.any((journey) => journey.state == JourneyState.completed),
      isFalse,
    );
  });

  test('1A未知时间不使用公元0年或默认零字段虚构侧事件', () {
    final events = _project([
      _application(
        ArchiveRecordKind.rail,
        extra: {'entryTime': null, 'exitTime': null, 'capturedTimes': null},
      ),
    ]);
    expect(events, hasLength(1));
    expect(events.single.endpoint.time, isNull);
    expect(events.single.endpoint.timeText, isNull);
    expect(events.single.role, JourneyEventRole.unknown);
    expect(events.single.applicationRecordId, isNull);
  });

  test('公交单次交易保存原始站码而已解析第N站保留站序语义', () {
    for (final (raw, expected) in [
      ('0010', '站点0010'),
      ('第17站', '站点17'),
      ('北京站东', '北京站东'),
      ('0000', null),
    ]) {
      final events = _project([
        _transaction(
          sequence: 10,
          minute: 0,
          extra: {
            'appTypeName': '公共汽电车',
            'stationLabel': raw,
            'stationConfidence': 'unmatched',
            'lineLabel': '100路',
          },
        ),
      ]);
      expect(events, hasLength(1));
      expect(events.single.role, JourneyEventRole.single);
      expect(events.single.endpoint.station, expected);
      expect(events.single.seatLabel, isNull);
    }
  });

  test('公交1A字节站号可转十进制但原始码与金额仍保存在详情', () {
    final events = _project([
      _application(
        ArchiveRecordKind.bus,
        extra: {
          'entryStationName': null,
          'exitStationName': null,
          'entryStationCode': '0A',
          'exitStationCode': '11',
          'entryLineCode': '0001',
          'exitLineCode': '0001',
          'amountFen': 250,
        },
      ),
    ]);
    expect(events.last.endpoint.station, '站点10');
    expect(events.first.endpoint.station, '站点17');
    expect(events.first.payload.fields, contains(('上车站（原始）', '0A')));
    final journeys = projectJourneys(events);
    expect(journeys, hasLength(1));
    expect(journeys.single.amountText, '-¥ 2.50');
  });

  test('含0和F的合法公交站码不被误作全零或全FF占位', () {
    final bus = _project([
      _application(
        ArchiveRecordKind.bus,
        extra: {
          'entryStationName': null,
          'exitStationName': null,
          'entryStationCode': '0F',
          'exitStationCode': 'F0',
          'entryLineCode': '0001',
          'exitLineCode': '0001',
          'amountFen': 250,
        },
      ),
    ]);
    expect(bus.last.endpoint.station, '站点15');
    expect(bus.first.endpoint.station, '站点240');
    final process = _project([
      _record(ArchiveRecordKind.process, {
        ..._process(type: 6, app: 2),
        'lineStationCode': '0001000F000100',
      }),
    ]);
    expect(process.single.endpoint.station, '站点000F');
  });

  test('零金额和isEntry为false不能给未识别轨道交易推断出站', () {
    final events = _project([
      _transaction(
        sequence: 10,
        minute: 0,
        extra: {'amountFen': 0, 'isEntry': false},
      ),
      _transaction(
        sequence: 11,
        minute: 30,
        extra: {'amountFen': 300, 'isEntry': false},
      ),
    ]);
    expect(
      events.every((event) => event.role == JourneyEventRole.unknown),
      isTrue,
    );
    expect(projectJourneys(events), hasLength(2));
  });

  test('归档明确isEntry及已保存过程类型可提供进出站角色', () {
    final events = _project([
      _transaction(sequence: 10, minute: 0, extra: {'isEntry': true}),
      _transaction(
        sequence: 11,
        minute: 30,
        extra: {'matchedProcess': _process(type: 4, app: 1)},
      ),
    ]);
    expect(events.last.role, JourneyEventRole.entry);
    expect(events.first.role, JourneyEventRole.exit);
    expect(projectJourneys(events), hasLength(1));
  });

  test('归档独立公交过程类型和站码不依赖即时查询', () {
    final events = _project([
      _record(ArchiveRecordKind.process, {
        ..._process(type: 6, app: 2),
        'cityCode': '3100',
        'capturedTimes': {'time': _civil('08:00:00')},
      }),
    ]);
    expect(events, hasLength(1));
    expect(events.single.mode, TripModeFilter.bus);
    expect(events.single.role, JourneyEventRole.single);
    expect(events.single.endpoint.station, '站点0010');
    expect(events.single.sequence, isNull);
  });

  test('上海账本推断依据友好展示且未来来源按原值保留', () {
    for (final (source, expected) in [
      ('shanghai-cu-ledger-inference', '按上海本地轨道账本推断'),
      ('future-parser-v2', 'future-parser-v2'),
    ]) {
      final events = _project([
        _transaction(
          status: '进站',
          sequence: 10,
          minute: 0,
          extra: {'rideStatusSource': source},
        ),
      ]);
      expect(events.single.payload.fields, contains(('进出站依据', expected)));
    }
  });
}

List<JourneyEvent<TripEntryInfo>> _events(
  List<TripCardPresentation<ArchiveRecordKind>> entries,
) {
  expect(entries.every((entry) => entry.journeyEvent != null), isTrue);
  return [for (final entry in entries) entry.journeyEvent!];
}

List<JourneyEvent<TripEntryInfo>> _project(
  List<ArchiveHistoryRecord> records,
) => _events(presentArchiveTrips(records, onDiagnostics: (_) {}).entries);

ArchiveContext _context({
  String application = 'wallet-01',
  String currency = 'CNY',
  int digits = 2,
  int? offset,
  String clock = 'device-local-card-time-unverified',
}) => ArchiveContext(
  systemId: 'TU',
  applicationId: application,
  currencyCode: currency,
  minorUnitDigits: digits,
  timeZoneOffsetMinutes: offset,
  clockBasis: clock,
);

ArchiveHistoryRecord _record(
  ArchiveRecordKind kind,
  Map<String, dynamic> fields, {
  ArchiveContext? context,
  List<String> batches = const ['capture-1'],
  int parseVersion = 8,
}) => ArchiveHistoryRecord(
  kind: kind,
  fields: fields,
  context: context ?? _context(),
  cardCityCode: '3100',
  sources: [
    for (final batch in batches)
      ArchiveRecordSource(batch, '/records/0', parseVersion, null),
  ],
);

Map<String, dynamic> _civil(String time) => {
  'civil': '2026-10-27T$time',
  'conversionOffsetMinutes': -300,
  'basis': 'parser-local-unverified',
};

ArchiveHistoryRecord _transaction({
  String? status,
  required int sequence,
  required int minute,
  ArchiveContext? context,
  List<String> batches = const ['capture-1'],
  int parseVersion = 8,
  Map<String, dynamic> extra = const {},
}) => _record(
  ArchiveRecordKind.transaction,
  {
    'time': DateTime.utc(2026, 10, 27, 21, minute).millisecondsSinceEpoch,
    'capturedTimes': {
      'time': _civil('08:${minute.toString().padLeft(2, '0')}:00'),
    },
    'sequence': sequence,
    'consume': true,
    'typeName': '消费',
    'rideStatusName': status,
    'appTypeName': '城市轨道交通',
    'stationLabel': status == '出站' ? '终点站' : '起点站',
    'lineLabel': '2号线',
    'cityCode': '3100',
    'cityName': '上海市',
    'amountFen': status == '进站' ? 0 : 300,
    'balanceAfterFen': 9000,
    'terminalId': sequence.toString().padLeft(12, '0'),
    ...extra,
  },
  context: context,
  batches: batches,
  parseVersion: parseVersion,
);

ArchiveHistoryRecord _application(
  ArchiveRecordKind kind, {
  Map<String, dynamic> extra = const {},
}) => _record(kind, {
  'status': 2,
  'entryTime': DateTime.utc(2026, 10, 27, 21).millisecondsSinceEpoch,
  'exitTime': DateTime.utc(2026, 10, 27, 21, 30).millisecondsSinceEpoch,
  'capturedTimes': {
    'entryTime': _civil('08:00:00'),
    'exitTime': _civil('08:30:00'),
  },
  'entryCityCode': '3100',
  'exitCityCode': '3100',
  'entryStationId': '00000001',
  'exitStationId': '00000002',
  'entryStationName': '人民广场',
  'exitStationName': '世纪大道',
  'entryLineCode': 1,
  'exitLineCode': 2,
  'lineName': '保存的单侧线路',
  'entryAmountFen': 0,
  'exitAmountFen': 300,
  'entryBalanceFen': 9000,
  ...extra,
});

ArchiveHistoryRecord _linkedTransaction(
  ArchiveHistoryRecord application, {
  required bool entry,
  ArchiveContext? context,
  List<String> batches = const ['capture-1'],
  Map<String, dynamic> extra = const {},
}) {
  final side = entry ? 'entry' : 'exit';
  final bus = application.kind == ArchiveRecordKind.bus;
  return _transaction(
    status: bus ? (entry ? '上车' : '下车') : (entry ? '进站' : '出站'),
    sequence: entry ? 10 : 12,
    minute: entry ? 0 : 30,
    context: context,
    batches: batches,
    extra: {
      'appTypeName': bus ? '公共汽电车' : '城市轨道交通',
      'amountFen': entry ? 0 : 300,
      'displayApplicationKey': tunionDisplayKey(
        '1A-${bus ? 'bus' : 'rail'}-$entry',
        DateTime.fromMillisecondsSinceEpoch(
          application.fields['${side}Time'] as int,
          isUtc: true,
        ),
        application.fields['${side}TerminalId'] as String?,
        application.fields['rawHex'] as String?,
      ),
      ...extra,
    },
  );
}

Map<String, dynamic> _process({required int type, required int app}) => {
  'time': DateTime.utc(2026, 10, 27, 21).millisecondsSinceEpoch,
  'typeCode': type,
  'appTypeCode': app,
  'cityCode': '3100',
  'terminalId': '0000000000000001',
  'lineStationCode': '00010010000100',
  'amountFen': 300,
  'balanceFen': 9000,
};

ArchiveHistoryRecord _processAt(
  int number, {
  required int type,
  required int minute,
  String batch = 'capture-1',
  bool reliable = true,
  String? provenanceRaw,
}) {
  final raw = [
    type,
    number,
    ...List.filled(46, 1),
  ].map((value) => value.toRadixString(16).padLeft(2, '0')).join(' ');
  return ArchiveHistoryRecord(
    kind: ArchiveRecordKind.process,
    context: _context(),
    sources: [
      ArchiveRecordSource(batch, 'cycle[0]', 8, {
        'record': {
          'sfi': 0x1E,
          'recordNumber': number,
          'recordNumberIsReliable': reliable,
          'rawHex': provenanceRaw ?? raw,
        },
      }),
    ],
    fields: {
      ..._process(type: type, app: 1),
      'rawHex': raw,
      'time': DateTime.utc(2026, 10, 27, 21, minute).millisecondsSinceEpoch,
      'capturedTimes': {
        'time': _civil('08:${minute.toString().padLeft(2, '0')}:00'),
      },
    },
  );
}

// Serialize real 1E payloads so captured balance fields and provenance bytes
// agree. These fixtures carry no card identity and require no live reread.
ArchiveHistoryRecord _balanceProcessAt(
  int slot, {
  required int type,
  required int minute,
  required int amount,
  required int balance,
  int app = 1,
  String batch = 'capture-1',
  ArchiveContext? context,
  bool reliable = true,
  String? provenanceRaw,
}) {
  final bytes = _reportedBytes(_reportedCycles[9]!)
    ..[0] = type
    ..[9] = app;
  for (var index = 0; index < 4; index++) {
    bytes[0x11 + index] = (amount >> (8 * (3 - index))) & 0xFF;
    bytes[0x15 + index] = (balance >> (8 * (3 - index))) & 0xFF;
  }
  bytes.setRange(0x19, 0x20, [
    0x20,
    0x26,
    0x10,
    0x27,
    0x08,
    ((minute ~/ 10) << 4) | (minute % 10),
    0,
  ]);
  final process = const TUnionProcessParser().parseCycleTrip(bytes)!;
  final fields = Map<String, dynamic>.from(
    (jsonDecode(
          CardSessionSnapshot(
            context: context ?? _context(),
            processTrips: [process],
          ).encode(),
        ) as Map<String, dynamic>)['cycle'].single
        as Map,
  );
  return ArchiveHistoryRecord(
    kind: ArchiveRecordKind.process,
    fields: {
      ...fields,
      'capturedDisplay': {
        'line': app == 2 ? '345' : '2号线',
        'station': type == 3 ? '起点' : '终点',
        'cityName': '北京市',
      },
    },
    context: context ?? _context(),
    cardCityCode: '1000',
    sources: [
      ArchiveRecordSource(batch, 'cycle[${slot - 1}]', 9, {
        'record': {
          'sfi': 0x1E,
          'recordNumber': slot,
          'recordNumberIsReliable': reliable,
          'rawHex': provenanceRaw ?? process.rawHex,
        },
      }),
    ],
  );
}

// Transaction-window and duplicate-application evidence from the 2026-10-27
// Beijing report. These records contain no card identity or public-file data.
const _reportedCycles = {
  9: '04 00 00 30 00 89 00 03 44 01 08 00 19 00 30 00 00 00 00 01 2C 00 00 37 46 20 26 10 18 10 36 56 10 00 01 01 10 00 FF FF FF FF 00 00 00 00 00 00',
  10: '03 00 00 30 01 59 00 00 72 01 0F 00 1D 00 37 00 00 00 00 00 00 00 00 37 46 20 26 10 18 10 27 39 10 00 01 01 10 00 FF FF FF FF 00 00 00 00 00 00',
  11: '04 00 00 00 10 09 00 15 48 02 01 59 00 05 00 01 00 00 00 00 C8 00 00 37 46 20 26 10 18 10 23 52 10 00 11 01 10 00 FF FF FF FF 00 00 00 00 00 00',
  12: '03 00 00 00 10 09 00 15 63 02 01 59 00 13 00 01 00 00 00 00 00 00 00 38 0E 20 26 10 18 09 19 57 10 00 11 01 10 00 FF FF FF FF 00 00 00 00 00 00',
};

List<int> _reportedBytes(String raw) => [
  for (final byte in raw.split(' ')) int.parse(byte, radix: 16),
];

ArchiveHistoryRecord _reportedProcess(
  int slot, {
  String batch = 'capture-1',
  ArchiveContext? context,
  Map<String, dynamic> extra = const {},
}) {
  final cycle = const TUnionProcessParser().parseCycleTrip(
    _reportedBytes(_reportedCycles[slot]!),
  )!;
  final snapshot = CardSessionSnapshot(
    context: _context(),
    processTrips: [cycle],
  );
  final fields = Map<String, dynamic>.from(
    (jsonDecode(snapshot.encode()) as Map<String, dynamic>)['cycle'].single
        as Map,
  );
  return ArchiveHistoryRecord(
    kind: ArchiveRecordKind.process,
    fields: {
      ...fields,
      'capturedDisplay': {
        'line': slot == 9
            ? '8号线'
            : slot == 10
            ? '15号线'
            : '345',
        'station': slot == 9
            ? '奥林匹克公园'
            : slot == 10
            ? '北沙滩'
            : slot == 11
            ? '站点5'
            : '站点19',
        'cityName': '北京市',
      },
      ...extra,
    },
    context: context ?? _context(),
    cardCityCode: '1000',
    sources: [
      ArchiveRecordSource(batch, 'cycle[${slot - 1}]', 9, {
        'record': {
          'sfi': 0x1E,
          'recordNumber': slot,
          'recordNumberIsReliable': true,
          'rawHex': cycle.rawHex,
        },
      }),
    ],
  );
}

ArchiveHistoryRecord _reportedTransaction(
  ArchiveHistoryRecord process, {
  ArchiveContext? context,
  List<String> batches = const ['capture-1'],
  Map<String, dynamic> extra = const {},
}) {
  final fields = process.fields;
  return _record(
    ArchiveRecordKind.transaction,
    {
      'sequence': 33,
      'time': fields['time'],
      'capturedTimes': fields['capturedTimes'],
      'terminalId': '300089000344',
      'consume': true,
      'typeName': '复合消费',
      'rideStatusName': '出站',
      'appTypeName': '城市轨道交通',
      'cityCode': '1000',
      'cityName': '北京市',
      'lineLabel': '8号线',
      'stationLabel': '奥林匹克公园',
      'amountFen': 300,
      'balanceAfterFen': 13850,
      'balanceAfterIsRecorded': false,
      'matchedProcess': fields,
      'displayProcessKey': tunionDisplayKey(
        '1E',
        DateTime.fromMillisecondsSinceEpoch(fields['time'] as int, isUtc: true),
        fields['terminalId'] as String,
        fields['rawHex'] as String?,
        '${fields['typeCode']}:${fields['amountFen']}:${fields['lineStationCode']}',
      ),
      ...extra,
    },
    context: context,
    batches: batches,
    parseVersion: 9,
  );
}

ArchiveHistoryRecord _reportedBusApplication() {
  const raw =
      '27 02 7D 01 01 00 00 00 00 00 00 00 00 00 02 10 00 11 01 10 00 FF FF FF FF 00 01 01 59 13 30 30 30 33 32 31 33 31 00 00 00 10 09 00 15 63 20 26 10 18 09 19 57 00 00 01 F4 AB 10 00 11 01 10 00 FF FF FF FF 00 01 01 59 05 30 30 30 33 32 31 33 31 00 00 00 10 09 00 15 48 20 26 10 18 10 23 52 00 00 00 C8 06 40 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 6D 59';
  final bus = const TUnionProcessParser().parseBusTransit(
    2,
    _reportedBytes(raw),
  )!;
  final snapshot = CardSessionSnapshot(context: _context(), buses: [bus]);
  final fields = Map<String, dynamic>.from(
    (jsonDecode(snapshot.encode()) as Map<String, dynamic>)['buses'].single
        as Map,
  );
  return _record(ArchiveRecordKind.bus, {
    ...fields,
    'capturedDisplay': {
      'entry': {'line': '345', 'station': '站点19', 'cityName': '北京市'},
      'exit': {'line': '345', 'station': '站点5', 'cityName': '北京市'},
    },
  });
}
