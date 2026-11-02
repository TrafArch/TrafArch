import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_journey_merge.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/features/trips/trip_cards_view.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_presenter.dart';
import 'package:transit_card_analyzer/features/trips/trip_filters.dart';

void main() {
  test('两个结构候选不能先按余额过滤成唯一候选再吸收缺失进站的观察', () {
    final fixture = _MergeFixture();
    final first = fixture.completed(
      batch: 'complete-first',
      entryKeys: {'entry-first'},
      exitKeys: {'shared-exit'},
      balance: '¥ 97.00',
    );
    final second = fixture.completed(
      batch: 'complete-second',
      entryKeys: {'entry-second'},
      exitKeys: {'shared-exit'},
      balance: '¥ 96.00',
    );
    final exitOnly = fixture.exitOnly(
      batch: 'partial',
      keys: {'shared-exit'},
      balance: '¥ 97.00',
    );

    final merged = mergeArchiveJourneys([
      first,
      second,
      exitOnly,
    ], fixture.keys);

    expect(merged, hasLength(3));
    expect(
      merged.where((journey) => journey.state == JourneyState.incomplete),
      hasLength(1),
    );
    expect(
      merged
          .where((journey) => journey.state == JourneyState.completed)
          .map((journey) => journey.events.length),
      everyElement(2),
    );
    expect(merged.expand((journey) => journey.events), hasLength(5));
  });

  test('未知余额的传递关联不能隐藏两端已知余额冲突', () {
    final fixture = _MergeFixture();
    final first = fixture.completed(
      batch: 'confirmed-first',
      entryKeys: {'entry-first'},
      exitKeys: {'exit-first'},
      balance: '¥ 97.00',
    );
    final bridge = fixture.completed(
      batch: 'unknown-bridge',
      entryKeys: {'entry-first', 'entry-second'},
      exitKeys: {'exit-first', 'exit-second'},
    );
    final second = fixture.completed(
      batch: 'confirmed-second',
      entryKeys: {'entry-second'},
      exitKeys: {'exit-second'},
      balance: '¥ 96.00',
    );

    final merged = mergeArchiveJourneys([first, bridge, second], fixture.keys);

    expect(merged, hasLength(3));
    expect(merged.map((journey) => journey.balanceAfterText).toSet(), {
      '¥ 97.00',
      null,
      '¥ 96.00',
    });
    expect(merged.map((journey) => journey.events.length), everyElement(2));
    expect(merged.expand((journey) => journey.events), hasLength(6));
  });

  test('同批次重复进站候选不能拆成单例后逐个并入另一批次的完成行程', () {
    final fixture = _MergeFixture();
    final complete = fixture.completed(
      batch: 'complete',
      entryKeys: {'shared-entry'},
      exitKeys: {'known-exit'},
    );
    final duplicateOne = fixture.entryOnly(
      batch: 'ambiguous-capture',
      keys: {'shared-entry'},
    );
    final duplicateTwo = fixture.entryOnly(
      batch: 'ambiguous-capture',
      keys: {'shared-entry'},
    );

    final merged = mergeArchiveJourneys([
      complete,
      duplicateOne,
      duplicateTwo,
    ], fixture.keys);

    expect(merged, hasLength(3));
    expect(
      merged.where((journey) => journey.state == JourneyState.inProgress),
      hasLength(2),
    );
    expect(
      merged
          .singleWhere((journey) => journey.state == JourneyState.completed)
          .events,
      hasLength(2),
    );
    expect(merged.expand((journey) => journey.events), hasLength(4));
  });

  test('含同批次多义证据的完成候选仍参与结构候选计数', () {
    final fixture = _MergeFixture();
    final ambiguousFirst = fixture.completed(
      batch: 'ambiguous-completed-capture',
      entryKeys: {'shared-entry'},
      exitKeys: {'first-exit'},
    );
    final ambiguousSecond = fixture.completed(
      batch: 'ambiguous-completed-capture',
      entryKeys: {'shared-entry'},
      exitKeys: {'second-exit'},
    );
    final clean = fixture.completed(
      batch: 'clean-completed-capture',
      entryKeys: {'shared-entry'},
      exitKeys: {'third-exit'},
    );
    final pending = fixture.entryOnly(
      batch: 'partial-capture',
      keys: {'shared-entry'},
    );

    final merged = mergeArchiveJourneys([
      ambiguousFirst,
      ambiguousSecond,
      clean,
      pending,
    ], fixture.keys);

    expect(merged, hasLength(4));
    expect(
      merged.where((journey) => journey.state == JourneyState.inProgress),
      hasLength(1),
    );
    expect(
      merged
          .where((journey) => journey.state == JourneyState.completed)
          .map((journey) => journey.events.length),
      everyElement(2),
    );
    expect(merged.expand((journey) => journey.events), hasLength(7));
  });

  test('完成行程的未知余额不能按吸收顺序选取两个冲突余额中的一个', () {
    final fixture = _MergeFixture();
    final complete = fixture.completed(
      batch: 'complete-with-unknown-balance',
      entryKeys: {'known-entry'},
      exitKeys: {'shared-exit'},
    );
    final first = fixture.exitOnly(
      batch: 'first-confirmed-exit',
      keys: {'shared-exit'},
      balance: '¥ 97.00',
    );
    final second = fixture.exitOnly(
      batch: 'second-confirmed-exit',
      keys: {'shared-exit'},
      balance: '¥ 96.00',
    );

    final merged = mergeArchiveJourneys([
      complete,
      first,
      second,
    ], fixture.keys);

    expect(merged, hasLength(3));
    expect(
      merged
          .singleWhere((journey) => journey.state == JourneyState.completed)
          .balanceAfterText,
      isNull,
    );
    expect(
      merged
          .where((journey) => journey.state == JourneyState.incomplete)
          .map((journey) => journey.balanceAfterText)
          .toSet(),
      {'¥ 97.00', '¥ 96.00'},
    );
    expect(merged.expand((journey) => journey.events), hasLength(4));
  });
}

/// These journeys have already been paired inside distinct original captures.
/// Literal operation witnesses isolate the later display merge from parsing.
class _MergeFixture {
  final keys = <ArchiveJourneyEntry, Set<String>>{};

  ArchiveJourney completed({
    required String batch,
    required Set<String> entryKeys,
    required Set<String> exitKeys,
    String? balance,
  }) {
    final entry = _event(batch, JourneyEventRole.entry, entryKeys);
    final exit = _event(batch, JourneyEventRole.exit, exitKeys);
    return JourneyPresentation(
      events: [entry, exit],
      mode: TripModeFilter.rail,
      state: JourneyState.completed,
      start: entry.endpoint,
      end: exit.endpoint,
      duration: const Duration(minutes: 30),
      amountText: '-¥ 3.00',
      balanceAfterText: balance,
    );
  }

  ArchiveJourney entryOnly({required String batch, required Set<String> keys}) {
    final entry = _event(batch, JourneyEventRole.entry, keys);
    return JourneyPresentation(
      events: [entry],
      mode: TripModeFilter.rail,
      state: JourneyState.inProgress,
      start: entry.endpoint,
    );
  }

  ArchiveJourney exitOnly({
    required String batch,
    required Set<String> keys,
    String? balance,
  }) {
    final exit = _event(batch, JourneyEventRole.exit, keys);
    return JourneyPresentation(
      events: [exit],
      mode: TripModeFilter.rail,
      state: JourneyState.incomplete,
      end: exit.endpoint,
      amountText: '-¥ 3.00',
      balanceAfterText: balance,
    );
  }

  JourneyEvent<ArchiveJourneyEntry> _event(
    String batch,
    JourneyEventRole role,
    Set<String> operationKeys,
  ) {
    final time = DateTime.utc(
      2026,
      10,
      31,
      14,
      role == JourneyEventRole.entry ? 0 : 30,
    );
    final entry = TripCardPresentation<ArchiveRecordKind>(
      info: TripEntryInfo(
        sourceLabel: '0x18 交易明细',
        title: '$batch ${role.name}',
        isConsume: true,
      ),
      source: ArchiveRecordKind.transaction,
      mode: TripModeFilter.rail,
      dateText: '2026-10-31',
      remote: false,
    );
    keys[entry] = operationKeys;
    return JourneyEvent(
      payload: entry,
      mode: TripModeFilter.rail,
      role: role,
      endpoint: JourneyEndpoint(time: time),
      scopeKey: 'same-captured-wallet-clock',
      sourceIds: {batch},
      cityCode: '1000',
      evidenceSource: JourneyEvidenceSource.transaction,
    );
  }
}
