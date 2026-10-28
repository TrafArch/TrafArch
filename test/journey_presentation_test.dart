import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/features/trips/trip_filters.dart';

void main() {
  test('同一应用的1A和1E重复两侧折叠为一段行程并保留四份来源', () {
    final result = projectJourneys([
      event(
        'application-exit',
        role: JourneyEventRole.exit,
        minute: 25,
        recordId: 'same-application',
        source: JourneyEvidenceSource.application,
        amount: '-¥2.00',
        line: '345路',
        mode: TripModeFilter.bus,
      ),
      event(
        'cycle-exit',
        role: JourneyEventRole.exit,
        minute: 25,
        recordId: 'same-application',
        source: JourneyEvidenceSource.cycle,
        processPositions: {'batch-one': 11},
        amount: '-¥2.00',
        line: '345路',
        station: '站点5',
        mode: TripModeFilter.bus,
      ),
      event(
        'application-entry',
        role: JourneyEventRole.entry,
        minute: 10,
        recordId: 'same-application',
        source: JourneyEvidenceSource.application,
        line: '345路',
        mode: TripModeFilter.bus,
      ),
      event(
        'cycle-entry',
        role: JourneyEventRole.entry,
        minute: 10,
        recordId: 'same-application',
        source: JourneyEvidenceSource.cycle,
        processPositions: {'batch-one': 12},
        line: '345路',
        station: '站点13',
        mode: TripModeFilter.bus,
      ),
    ]);
    expect(result, hasLength(1));
    expect(result.single.state, JourneyState.completed);
    expect(result.single.start?.station, '站点13');
    expect(result.single.end?.station, '站点5');
    expect(result.single.amountText, '-¥2.00');
    expect(result.single.events.map((e) => e.payload).toSet(), {
      'application-entry',
      'cycle-entry',
      'application-exit',
      'cycle-exit',
    });
    expect(
      result.single.events.first.evidenceSource,
      JourneyEvidenceSource.cycle,
    );
  });

  test('同一应用同侧存在两个1E候选时不能任意折叠', () {
    final result = projectJourneys([
      event(
        'application-exit',
        role: JourneyEventRole.exit,
        minute: 25,
        recordId: 'same',
        source: JourneyEvidenceSource.application,
      ),
      event(
        'cycle-exit-one',
        role: JourneyEventRole.exit,
        minute: 25,
        recordId: 'same',
        source: JourneyEvidenceSource.cycle,
      ),
      event(
        'cycle-exit-two',
        role: JourneyEventRole.exit,
        minute: 25,
        recordId: 'same',
        source: JourneyEvidenceSource.cycle,
      ),
      event(
        'application-entry',
        role: JourneyEventRole.entry,
        minute: 10,
        recordId: 'same',
        source: JourneyEvidenceSource.application,
      ),
    ]);
    expect(result, hasLength(4));
    expect(result.every((j) => j.state != JourneyState.completed), isTrue);
  });

  test('重复身份不能跨时间城市批次及未知来源折叠', () {
    for (final variant in [
      event(
        'cycle',
        role: JourneyEventRole.exit,
        minute: 26,
        recordId: 'same',
        source: JourneyEvidenceSource.cycle,
      ),
      event(
        'cycle',
        role: JourneyEventRole.exit,
        minute: 25,
        recordId: 'same',
        source: JourneyEvidenceSource.cycle,
        city: '1000',
      ),
      event(
        'cycle',
        role: JourneyEventRole.exit,
        minute: 25,
        recordId: 'same',
        source: JourneyEvidenceSource.cycle,
        sources: {'other-batch'},
      ),
      event(
        'unknown',
        role: JourneyEventRole.exit,
        minute: 25,
        recordId: 'same',
      ),
    ]) {
      final result = projectJourneys([
        event(
          'application',
          role: JourneyEventRole.exit,
          minute: 25,
          recordId: 'same',
          source: JourneyEvidenceSource.application,
        ),
        variant,
      ]);
      expect(result, hasLength(2));
      expect(result.expand((j) => j.events), hasLength(2));
    }
  });

  test('交易代表的1E出站与窗口外独立1E进站凭真实槽位配对', () {
    final result = projectJourneys([
      event(
        'transaction-exit',
        role: JourneyEventRole.exit,
        time: DateTime(2026, 10, 18, 10, 36, 56),
        sequence: 33,
        processPositions: {'batch-one': 9},
        line: '8号线',
        station: '奥林匹克公园',
        amount: '-¥3.00',
      ),
      event(
        'cycle-entry',
        role: JourneyEventRole.entry,
        time: DateTime(2026, 10, 18, 10, 27, 39),
        processPositions: {'batch-one': 10},
        line: '15号线',
        station: '北沙滩',
      ),
    ]);
    expect(result, hasLength(1));
    expect(result.single.state, JourneyState.completed);
    expect(result.single.start?.station, '北沙滩');
    expect(result.single.end?.station, '奥林匹克公园');
    expect(result.single.duration, const Duration(minutes: 9, seconds: 17));
    expect(result.single.amountText, '-¥3.00');
    expect(result.single.events.map((event) => event.payload), [
      'cycle-entry',
      'transaction-exit',
    ]);
  });

  test('真实1E槽位不能推翻两个交易已知的序号缺口', () {
    final result = projectJourneys([
      event(
        'exit',
        role: JourneyEventRole.exit,
        minute: 25,
        sequence: 43,
        processPositions: {'batch-one': 9},
      ),
      event(
        'entry',
        role: JourneyEventRole.entry,
        minute: 10,
        sequence: 41,
        processPositions: {'batch-one': 10},
      ),
    ]);
    expect(result, hasLength(2));
  });

  test('独立1E无交易序号时凭同批次原始连续槽号组成行程', () {
    final result = projectJourneys([
      event(
        'exit',
        role: JourneyEventRole.exit,
        minute: 25,
        processPositions: {'batch-one': 1},
        amount: '-¥3.00',
      ),
      event(
        'entry',
        role: JourneyEventRole.entry,
        minute: 10,
        processPositions: {'batch-one': 2},
      ),
    ]);
    expect(result, hasLength(1));
    expect(result.single.state, JourneyState.completed);
    expect(result.single.duration, const Duration(minutes: 15));
    expect(result.single.amountText, '-¥3.00');
    expect(
      result.single.events.every((event) => event.sequence == null),
      isTrue,
    );
  });

  test('1E原始索引方向不替代实际时间正序且payload映射保留位置', () {
    final entry = event(
      'entry',
      role: JourneyEventRole.entry,
      minute: 10,
      processPositions: {'batch-one': 7},
    ).withPayload(100);
    final exit = event(
      'exit',
      role: JourneyEventRole.exit,
      minute: 25,
      processPositions: {'batch-one': 8},
    ).withPayload(200);
    final result = projectJourneys([entry, exit]);
    expect(result, hasLength(1));
    expect(result.single.events.first.processPositions, {'batch-one': 7});
  });

  for (final (name, position, source) in [
    ('槽号缺口', {'batch-one': 4}, {'batch-one'}),
    ('循环首尾', {'batch-one': 30}, {'batch-one'}),
    ('零槽号', {'batch-one': 0}, {'batch-one'}),
    ('不同槽位批次', {'batch-two': 2}, {'batch-one', 'batch-two'}),
    ('槽位批次不属于来源', {'unrelated': 2}, {'batch-one'}),
  ]) {
    test('1E$name禁止把展示邻接当作原始连续', () {
      final result = projectJourneys([
        event(
          'exit',
          role: JourneyEventRole.exit,
          minute: 25,
          processPositions: {'batch-one': 1, 'unrelated': 1},
        ),
        event(
          'entry',
          role: JourneyEventRole.entry,
          minute: 10,
          processPositions: position,
          sources: source,
        ),
      ]);
      expect(result, hasLength(2));
    });
  }

  test('1E可以使用共同批次对应的位置而不使用各自第一个来源', () {
    final result = projectJourneys([
      event(
        'exit',
        role: JourneyEventRole.exit,
        minute: 25,
        sources: {'old', 'batch-one'},
        processPositions: {'old': 4, 'batch-one': 1},
      ),
      event(
        'entry',
        role: JourneyEventRole.entry,
        minute: 10,
        sources: {'new', 'batch-one'},
        processPositions: {'new': 9, 'batch-one': 2},
      ),
    ]);
    expect(result, hasLength(1));
  });

  test('1E中间未知角色或无时间记录不能被过滤后跨过', () {
    for (final minute in <int?>[15, null]) {
      final result = projectJourneys([
        event(
          'exit',
          role: JourneyEventRole.exit,
          minute: 25,
          processPositions: {'batch-one': 1},
        ),
        event('unknown', minute: minute, processPositions: {'batch-one': 2}),
        event(
          'entry',
          role: JourneyEventRole.entry,
          minute: 10,
          processPositions: {'batch-one': 3},
        ),
      ]);
      expect(result, hasLength(3));
      expect(
        result.any((journey) => journey.state == JourneyState.completed),
        isFalse,
      );
    }
  });

  test('1E同批次重复槽位即使另一个时间不在区间内也阻断配对', () {
    final result = projectJourneys([
      event(
        'exit',
        role: JourneyEventRole.exit,
        minute: 25,
        processPositions: {'batch-one': 1},
      ),
      event(
        'entry',
        role: JourneyEventRole.entry,
        minute: 10,
        processPositions: {'batch-one': 2},
      ),
      event('duplicate', minute: 50, processPositions: {'batch-one': 2}),
    ]);
    expect(result, hasLength(3));
  });

  test('1E槽位与0x18交易序号不能混合建立关系', () {
    final result = projectJourneys([
      event('exit', role: JourneyEventRole.exit, minute: 25, sequence: 1),
      event(
        'entry',
        role: JourneyEventRole.entry,
        minute: 10,
        processPositions: {'batch-one': 2},
      ),
    ]);
    expect(result, hasLength(2));
  });

  test('两端城市不同仍可凭同批次原始连续1E槽号组成跨城行程', () {
    final result = projectJourneys([
      event(
        'exit',
        role: JourneyEventRole.exit,
        minute: 25,
        city: '3310',
        processPositions: {'batch-one': 1},
      ),
      event(
        'entry',
        role: JourneyEventRole.entry,
        minute: 10,
        city: '3370',
        processPositions: {'batch-one': 2},
      ),
    ]);
    expect(result, hasLength(1));
    expect(result.single.state, JourneyState.completed);
    expect(result.single.cityLabel, isNull);
    expect(result.single.isCrossCity, isTrue);
    expect(result.single.events.map((event) => event.cityCode), [
      '3370',
      '3310',
    ]);
  });

  for (final variant in <String, JourneyEvent<String>>{
    '上下文不同': event(
      'entry',
      role: JourneyEventRole.entry,
      minute: 10,
      scope: 'other-clock',
      processPositions: {'batch-one': 2},
    ),
    '方式不同': event(
      'entry',
      role: JourneyEventRole.entry,
      minute: 10,
      mode: TripModeFilter.bus,
      processPositions: {'batch-one': 2},
    ),
    '未知角色': event('entry', minute: 10, processPositions: {'batch-one': 2}),
    '时间逆序': event(
      'entry',
      role: JourneyEventRole.entry,
      minute: 40,
      processPositions: {'batch-one': 2},
    ),
  }.entries) {
    test('1E${variant.key}仍不能因连续槽位配对', () {
      final result = projectJourneys([
        event(
          'exit',
          role: JourneyEventRole.exit,
          minute: 25,
          processPositions: {'batch-one': 1},
        ),
        variant.value,
      ]);
      expect(result, hasLength(2));
    });
  }

  test('连续序号的明确进出站呈现完整行程并保留两侧详情', () {
    final result = projectJourneys([
      event(
        'exit',
        role: JourneyEventRole.exit,
        minute: 25,
        sequence: 42,
        line: '2号线',
        station: '终站',
        amount: '-¥7.00',
      ),
      event(
        'entry',
        role: JourneyEventRole.entry,
        minute: 10,
        sequence: 41,
        line: '1号线',
        station: '始站',
        amount: '-¥0.00',
      ),
    ]);

    expect(result, hasLength(1));
    final journey = result.single;
    expect(journey.state, JourneyState.completed);
    expect(journey.isCrossCity, isFalse);
    expect(journey.cityLabel, '上海');
    expect(journey.start?.station, '始站');
    expect(journey.start?.line, '1号线');
    expect(journey.end?.station, '终站');
    expect(journey.end?.line, '2号线');
    expect(journey.duration, const Duration(minutes: 15));
    expect(journey.amountText, '-¥7.00');
    expect(journey.events.map((e) => e.payload), ['entry', 'exit']);
  });

  test('同一明确1A记录允许双端跨越无关事件但保留该事件', () {
    final result = projectJourneys([
      event(
        'entry',
        role: JourneyEventRole.entry,
        minute: 10,
        recordId: 'rail-raw-record',
      ),
      event('unknown', minute: 15),
      event(
        'exit',
        role: JourneyEventRole.exit,
        minute: 25,
        recordId: 'rail-raw-record',
        amount: '-¥7.00',
      ),
    ]);

    expect(result, hasLength(2));
    expect(result.first.state, JourneyState.completed);
    expect(result.first.events.map((e) => e.payload), ['entry', 'exit']);
    expect(result.last.events.single.payload, 'unknown');
  });

  test('进行中只有进入端并隐藏即使原记录提供的金额', () {
    final result = projectJourneys([
      event('entry', role: JourneyEventRole.entry, amount: '-¥8.00'),
    ]);
    expect(result, hasLength(1));
    final journey = result.single;

    expect(journey.state, JourneyState.inProgress);
    expect(journey.start?.station, '站点');
    expect(journey.end, isNull);
    expect(journey.duration, isNull);
    expect(journey.amountText, isNull);
    expect(journey.events.single.amountText, '-¥8.00');
  });

  test('只有出站记录时保留终点和扣款但不虚构起点及用时', () {
    final result = projectJourneys([
      event('exit', role: JourneyEventRole.exit, amount: '-¥8.00'),
    ]);
    expect(result, hasLength(1));
    final journey = result.single;

    expect(journey.state, JourneyState.incomplete);
    expect(journey.start, isNull);
    expect(journey.end?.station, '站点');
    expect(journey.duration, isNull);
    expect(journey.amountText, '-¥8.00');
  });

  test('无上下车规则的单次公交保留线路与扣款而不生成端点', () {
    final result = projectJourneys([
      event(
        'single-bus',
        role: JourneyEventRole.single,
        mode: TripModeFilter.bus,
        line: '100路',
        station: null,
        amount: '-¥1.00',
      ),
    ]);
    expect(result, hasLength(1));
    final journey = result.single;

    expect(journey.state, JourneyState.single);
    expect(journey.start, isNull);
    expect(journey.end, isNull);
    expect(journey.duration, isNull);
    expect(journey.events.single.endpoint.line, '100路');
    expect(journey.events.single.endpoint.station, isNull);
    expect(journey.amountText, '-¥1.00');
  });

  test('金额为零和相邻序号不能把未知事件变成进出站', () {
    final result = projectJourneys([
      event('zero', minute: 10, sequence: 41, amount: '-¥0.00'),
      event('paid', minute: 25, sequence: 42, amount: '-¥7.00'),
    ]);

    expect(result, hasLength(2));
    expect(result.every((j) => j.state == JourneyState.incomplete), isTrue);
    expect(result.every((j) => j.start == null && j.end == null), isTrue);
  });

  for (final variant in <String, JourneyEvent<String>>{
    '不同范围': event(
      'exit',
      role: JourneyEventRole.exit,
      minute: 25,
      sequence: 42,
      scope: 'other-wallet',
    ),
    '缺少范围': event(
      'exit',
      role: JourneyEventRole.exit,
      minute: 25,
      sequence: 42,
      scope: null,
    ),
    '不同批次': event(
      'exit',
      role: JourneyEventRole.exit,
      minute: 25,
      sequence: 42,
      sources: {'other-batch'},
    ),
    '没有来源批次': event(
      'exit',
      role: JourneyEventRole.exit,
      minute: 25,
      sequence: 42,
      sources: {},
    ),
    '城市未知': event(
      'exit',
      role: JourneyEventRole.exit,
      minute: 25,
      sequence: 42,
      city: null,
    ),
    '城市为零': event(
      'exit',
      role: JourneyEventRole.exit,
      minute: 25,
      sequence: 42,
      city: '0000',
    ),
    '不同方式': event(
      'exit',
      role: JourneyEventRole.exit,
      minute: 25,
      sequence: 42,
      mode: TripModeFilter.bus,
    ),
    '序号缺口': event(
      'exit',
      role: JourneyEventRole.exit,
      minute: 25,
      sequence: 43,
    ),
    '序号缺失': event('exit', role: JourneyEventRole.exit, minute: 25),
    '顺序冲突': event('exit', role: JourneyEventRole.exit, minute: 5, sequence: 42),
    '同刻记录': event(
      'exit',
      role: JourneyEventRole.exit,
      minute: 10,
      sequence: 42,
    ),
    '时间未知': event(
      'exit',
      role: JourneyEventRole.exit,
      minute: null,
      sequence: 42,
    ),
  }.entries) {
    test('${variant.key}阻止序号配对', () {
      final result = projectJourneys([
        event('entry', role: JourneyEventRole.entry, minute: 10, sequence: 41),
        variant.value,
      ]);
      expect(result, hasLength(2));
      expect(result.any((j) => j.state == JourneyState.completed), isFalse);
    });
  }

  test('交易中间有未知事件时即使序号相邻也不配对', () {
    final result = projectJourneys([
      event('entry', role: JourneyEventRole.entry, minute: 10, sequence: 41),
      event('unknown', minute: 15),
      event('exit', role: JourneyEventRole.exit, minute: 25, sequence: 42),
    ]);
    expect(result, hasLength(3));
    expect(result.any((j) => j.state == JourneyState.completed), isFalse);
  });

  test('原始列表中间的无时间事件也阻断序号配对', () {
    final result = projectJourneys([
      event('exit', role: JourneyEventRole.exit, minute: 25, sequence: 42),
      event('unknown', minute: null),
      event('entry', role: JourneyEventRole.entry, minute: 10, sequence: 41),
    ]);
    expect(result, hasLength(3));
  });

  test('同刻有额外候选事件时不依据输入顺序选一对', () {
    final result = projectJourneys([
      event('entry-a', role: JourneyEventRole.entry, minute: 10, sequence: 41),
      event('exit', role: JourneyEventRole.exit, minute: 25, sequence: 42),
      event('entry-b', role: JourneyEventRole.entry, minute: 10, sequence: 41),
    ]);
    expect(result, hasLength(3));
  });

  test('同一1A标识存在多义进入端时保留全部证据', () {
    final result = projectJourneys([
      event(
        'entry-a',
        role: JourneyEventRole.entry,
        minute: 10,
        recordId: 'same-record',
      ),
      event(
        'entry-b',
        role: JourneyEventRole.entry,
        minute: 11,
        recordId: 'same-record',
      ),
      event(
        'exit',
        role: JourneyEventRole.exit,
        minute: 25,
        recordId: 'same-record',
      ),
    ]);
    expect(result, hasLength(3));
    expect(result.expand((j) => j.events).map((e) => e.payload).toSet(), {
      'entry-a',
      'entry-b',
      'exit',
    });
  });

  test('同一1A标识可跨已知城市建立行程', () {
    final result = projectJourneys([
      event(
        'entry',
        role: JourneyEventRole.entry,
        minute: 10,
        recordId: 'same-record',
        city: '3370',
      ),
      event(
        'exit',
        role: JourneyEventRole.exit,
        minute: 25,
        recordId: 'same-record',
        city: '3310',
      ),
    ]);
    expect(result, hasLength(1));
    expect(result.single.state, JourneyState.completed);
    expect(result.single.cityLabel, isNull);
    expect(result.single.isCrossCity, isTrue);
  });

  test('1A标识也不能跨批次建立行程', () {
    final result = projectJourneys([
      event(
        'entry',
        role: JourneyEventRole.entry,
        minute: 10,
        recordId: 'same-record',
      ),
      event(
        'exit',
        role: JourneyEventRole.exit,
        minute: 25,
        recordId: 'same-record',
        city: '1100',
        sources: {'other'},
      ),
    ]);
    expect(result, hasLength(2));
  });

  test('跨午夜的同上下文行程按真实时间差计算', () {
    final result = projectJourneys([
      event(
        'entry',
        role: JourneyEventRole.entry,
        sequence: 41,
        time: DateTime(2026, 10, 26, 23, 50),
      ),
      event(
        'exit',
        role: JourneyEventRole.exit,
        sequence: 42,
        time: DateTime(2026, 10, 27, 0, 10),
      ),
    ]);
    expect(result, hasLength(1));
    expect(result.single.duration, const Duration(minutes: 20));
  });

  test('超过24小时的1A双端不自动呈现为完成行程', () {
    final result = projectJourneys([
      event(
        'entry',
        role: JourneyEventRole.entry,
        recordId: 'same-record',
        time: DateTime(2026, 10, 26, 8),
      ),
      event(
        'exit',
        role: JourneyEventRole.exit,
        recordId: 'same-record',
        time: DateTime(2026, 10, 27, 8, 1),
      ),
    ]);
    expect(result, hasLength(2));
  });

  test('UTC与本地卡内时间表示不混合计算行程', () {
    final result = projectJourneys([
      event(
        'entry',
        role: JourneyEventRole.entry,
        sequence: 41,
        time: DateTime.utc(2026, 10, 26, 8),
      ),
      event(
        'exit',
        role: JourneyEventRole.exit,
        sequence: 42,
        time: DateTime(2026, 10, 26, 8, 30),
      ),
    ]);
    expect(result, hasLength(2));
  });

  test('公交只有同一明确线路的上下车事件可以配对', () {
    final result = projectJourneys([
      event(
        'entry',
        role: JourneyEventRole.entry,
        minute: 10,
        sequence: 41,
        mode: TripModeFilter.bus,
        line: '100路',
      ),
      event(
        'exit',
        role: JourneyEventRole.exit,
        minute: 25,
        sequence: 42,
        mode: TripModeFilter.bus,
        line: '100路',
      ),
    ]);
    expect(result, hasLength(1));
    expect(result.single.state, JourneyState.completed);
  });

  for (final line in ['101路', null, '']) {
    test('公交目的线路为${line ?? '未知'}时不与100路配对', () {
      final result = projectJourneys([
        event(
          'entry',
          role: JourneyEventRole.entry,
          minute: 10,
          sequence: 41,
          mode: TripModeFilter.bus,
          line: '100路',
        ),
        event(
          'exit',
          role: JourneyEventRole.exit,
          minute: 25,
          sequence: 42,
          mode: TripModeFilter.bus,
          line: line,
        ),
      ]);
      expect(result, hasLength(2));
    });
  }

  test('有共同捕获批次的历史记录可以在同一上下文内配对', () {
    final result = projectJourneys([
      event(
        'entry',
        role: JourneyEventRole.entry,
        minute: 10,
        sequence: 41,
        sources: {'batch-old', 'batch-shared'},
      ),
      event(
        'exit',
        role: JourneyEventRole.exit,
        minute: 25,
        sequence: 42,
        sources: {'batch-shared', 'batch-new'},
      ),
    ]);
    expect(result, hasLength(1));
    expect(result.single.state, JourneyState.completed);
  });

  test('机场高金额且没有席别证据时保留席别未知', () {
    final result = projectJourneys([
      event(
        'entry',
        role: JourneyEventRole.entry,
        minute: 10,
        sequence: 41,
        line: '大兴机场线',
      ),
      event(
        'exit',
        role: JourneyEventRole.exit,
        minute: 25,
        sequence: 42,
        line: '大兴机场线',
        amount: '-¥150.00',
      ),
    ]);
    expect(result, hasLength(1));
    expect(result.single.seatLabel, isNull);
  });

  test('完成行程使用出站扣款的席别而不沿用进站侧席别', () {
    final consistent = projectJourneys([
      event(
        'entry',
        role: JourneyEventRole.entry,
        minute: 10,
        sequence: 41,
        seat: '商务座',
      ),
      event(
        'exit',
        role: JourneyEventRole.exit,
        minute: 25,
        sequence: 42,
        seat: '商务座',
      ),
    ]);
    expect(consistent, hasLength(1));
    expect(consistent.single.seatLabel, '商务座');
    final conflicting = projectJourneys([
      event(
        'entry',
        role: JourneyEventRole.entry,
        minute: 10,
        sequence: 41,
        seat: '商务座',
      ),
      event(
        'exit',
        role: JourneyEventRole.exit,
        minute: 25,
        sequence: 42,
        seat: '普通座',
      ),
    ]);
    expect(conflicting, hasLength(1));
    expect(conflicting.single.seatLabel, '普通座');
  });

  test('未知站名和线路仍为空且payload映射保留原配对证据', () {
    final entry = event(
      'entry',
      role: JourneyEventRole.entry,
      minute: 10,
      sequence: 41,
      line: null,
      station: null,
    ).withPayload(100);
    final exit = event(
      'exit',
      role: JourneyEventRole.exit,
      minute: 25,
      sequence: 42,
      line: null,
      station: null,
    ).withPayload(200);
    final result = projectJourneys([entry, exit]);
    expect(result, hasLength(1));
    expect(result.single.start?.station, isNull);
    expect(result.single.end?.line, isNull);
    expect(result.single.events.map((e) => e.payload), [100, 200]);
  });

  test('输出按事件最新时间倒序且未知时间稳定置后', () {
    final inputs = [
      event('unknown-first', minute: null),
      event('old', minute: 5),
      event('new', minute: 25),
      event('unknown-last', minute: null),
    ];
    final result = projectJourneys(inputs);
    expect(result.map((j) => j.events.single.payload), [
      'new',
      'old',
      'unknown-first',
      'unknown-last',
    ]);
    expect(inputs.first.payload, 'unknown-first');
  });
}

JourneyEvent<String> event(
  String payload, {
  JourneyEventRole role = JourneyEventRole.unknown,
  TripModeFilter mode = TripModeFilter.rail,
  int? minute = 10,
  DateTime? time,
  int? sequence,
  Map<String, int> processPositions = const {},
  String? scope = 'wallet/application/card-clock',
  Set<String> sources = const {'batch-one'},
  String? city = '3100',
  String? line = '1号线',
  String? station = '站点',
  String? recordId,
  JourneyEvidenceSource source = JourneyEvidenceSource.unknown,
  String? amount,
  String? seat,
}) => JourneyEvent(
  payload: payload,
  mode: mode,
  role: role,
  endpoint: JourneyEndpoint(
    line: line,
    station: station,
    time: time ?? (minute == null ? null : DateTime(2026, 10, 26, 8, minute)),
  ),
  scopeKey: scope,
  sourceIds: sources,
  cityCode: city,
  cityLabel: city == '3100' ? '上海' : null,
  sequence: sequence,
  processPositions: processPositions,
  applicationRecordId: recordId,
  evidenceSource: source,
  amountText: amount,
  seatLabel: seat,
);
