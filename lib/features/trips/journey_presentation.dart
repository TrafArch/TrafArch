import 'trip_filters.dart';

/// A role established by record evidence, never by a zero or positive amount.
enum JourneyEventRole { entry, exit, single, unknown, fareAdjustment }

enum JourneyState { completed, inProgress, single, incomplete }

/// Source family used only to preserve and rank verified duplicate sides.
enum JourneyEvidenceSource { unknown, transaction, cycle, application }

/// Only call for a label established by a city decoder or reference lookup.
/// Encoded fallbacks must retain their original spelling and leading zeros.
String? formatJourneyBusLine(String? decodedLabel) {
  final label = decodedLabel?.trim();
  if (label == null || label.isEmpty) return null;
  return RegExp(r'^[1-9][0-9]*$').hasMatch(label) ? '$label路' : label;
}

/// User-confirmed fare rule: Daxing Airport Express business travel is CNY 50.
/// No rule is currently enabled for Shenzhen line 11 or other fare amounts.
String? journeySeatLabel({
  required String? line,
  required int? amountFen,
  required bool isConsume,
  required String? currencyCode,
}) =>
    isConsume &&
        currencyCode == 'CNY' &&
        line?.trim() == '大兴机场线' &&
        amountFen == 5000
    ? '商务座'
    : null;

/// A separately resolved end of a journey. Missing values remain missing.
class JourneyEndpoint {
  const JourneyEndpoint({this.line, this.station, this.time, this.timeText});

  final String? line;
  final String? station;

  /// A coordinate in the event's captured display clock. Archive adapters may
  /// use a UTC DateTime container for unverified civil-time arithmetic; this
  /// value is not an exported UTC instant. Pair only within the same scope.
  final DateTime? time;
  final String? timeText;
}

/// Original 1E monetary fields and their own verified capture coordinates.
/// These values remain record balances until local evidence proves their role.
class JourneyProcessBalanceEvidence {
  const JourneyProcessBalanceEvidence({
    required this.recordedFen,
    required this.amountFen,
    required this.currencyCode,
    required this.currencySymbol,
    required this.positions,
    this.minorUnitDigits = 2,
    this.balanceOffsetFen = 0,
  });

  final int recordedFen;
  final int amountFen;
  final String? currencyCode;
  final String currencySymbol;
  final Map<String, int> positions;
  final int minorUnitDigits;

  /// Presentation offset only; ledger checks continue to use captured values.
  final int balanceOffsetFen;

  String format(int fen) =>
      '$currencySymbol${((fen + balanceOffsetFen) / 100).toStringAsFixed(2)}';
}

/// Display-only event; [payload] retains the authoritative details and actions.
/// [scopeKey] identifies card/wallet/application/currency/clock context, while
/// [sourceIds] contains capture batch IDs. Unknown context cannot establish a pair.
class JourneyEvent<T> {
  const JourneyEvent({
    required this.payload,
    required this.mode,
    required this.role,
    this.endpoint = const JourneyEndpoint(),
    this.scopeKey,
    this.sourceIds = const {},
    this.cityCode,
    this.cityLabel,
    this.sequence,
    this.processPositions = const {},
    this.applicationRecordId,
    this.evidenceSource = JourneyEvidenceSource.unknown,
    this.amountText,
    this.balanceAfterText,
    this.confirmedBalanceFen,
    this.walletDeltaFen,
    this.processBalance,
    this.seatLabel,
  });

  final T payload;
  final TripModeFilter mode;
  final JourneyEventRole role;
  final JourneyEndpoint endpoint;
  final String? scopeKey;
  final Set<String> sourceIds;
  final String? cityCode;
  final String? cityLabel;
  final int? sequence;

  /// Positive original 0x1E record slots, keyed by their capture batch ID.
  /// These are not transaction sequence numbers or filtered list positions.
  final Map<String, int> processPositions;
  final String? applicationRecordId;
  final JourneyEvidenceSource evidenceSource;
  final String? amountText;

  /// Confirmed balance after this operation, excluding uninterpreted record balances.
  final String? balanceAfterText;
  final int? confirmedBalanceFen;

  /// Signed effect of an explicitly identified 0x18 recharge/consume operation.
  /// Unknown types remain null. Only confirmed same-capture balances may close
  /// a local 1E interval; this is never an anchor for extending the 1E ledger.
  final int? walletDeltaFen;
  final JourneyProcessBalanceEvidence? processBalance;
  final String? seatLabel;

  JourneyEvent<R> withPayload<R>(R payload) => JourneyEvent<R>(
    payload: payload,
    mode: mode,
    role: role,
    endpoint: endpoint,
    scopeKey: scopeKey,
    sourceIds: sourceIds,
    cityCode: cityCode,
    cityLabel: cityLabel,
    sequence: sequence,
    processPositions: processPositions,
    applicationRecordId: applicationRecordId,
    evidenceSource: evidenceSource,
    amountText: amountText,
    balanceAfterText: balanceAfterText,
    confirmedBalanceFen: confirmedBalanceFen,
    walletDeltaFen: walletDeltaFen,
    processBalance: processBalance,
    seatLabel: seatLabel,
  );
}

/// A reversible projection; each source event appears exactly once in the output.
/// Single/unknown events expose their location through [events], without claiming
/// that it is an entry or exit endpoint.
class JourneyPresentation<T> {
  const JourneyPresentation({
    required this.events,
    required this.mode,
    required this.state,
    this.cityLabel,
    this.start,
    this.end,
    this.duration,
    this.amountText,
    this.fareAdjustmentAmountText,
    this.balanceAfterText,
    this.seatLabel,
  });

  final List<JourneyEvent<T>> events;
  final TripModeFilter mode;
  final JourneyState state;
  final String? cityLabel;
  final JourneyEndpoint? start;
  final JourneyEndpoint? end;
  final Duration? duration;
  final String? amountText;
  final String? fareAdjustmentAmountText;
  final String? balanceAfterText;
  final String? seatLabel;

  /// A correction point is known, but the actual entry place/time is not.
  bool get startsWithFareAdjustment =>
      start != null && events.first.role == JourneyEventRole.fareAdjustment;

  /// Endpoint cities describe acceptance, independently of the issuing city.
  /// Unknown city placeholders do not establish a cross-city journey.
  bool get isCrossCity =>
      events
          .map((event) => _journeyCityCode(event.cityCode))
          .whereType<String>()
          .toSet()
          .length >
      1;
}

/// Pairs only explicit application-record halves or adjacent, consecutive
/// transaction events. No balance, fare or station-name heuristic is involved.
/// Input order is evidence: callers must provide the complete unfiltered stream.
List<JourneyPresentation<T>> projectJourneys<T>(
  Iterable<JourneyEvent<T>> events,
) {
  final operations = _journeyOperations(events.toList(growable: false));
  final source = [for (final operation in operations) operation.event];
  final consumed = <int>{};
  final ambiguousApplication = <int>{};
  final projected = <(int, JourneyPresentation<T>)>[];
  final completedPairs = <(JourneyEvent<T>, JourneyEvent<T>)>[];
  final applicationGroups = <(String?, String), List<int>>{};
  final processSlotCounts = <(String?, String, int), int>{};
  for (var i = 0; i < source.length; i++) {
    final event = source[i];
    for (final position in event.processPositions.entries) {
      if (!event.sourceIds.contains(position.key) || position.value <= 0) {
        continue;
      }
      final slot = (event.scopeKey, position.key, position.value);
      processSlotCounts[slot] = (processSlotCounts[slot] ?? 0) + 1;
    }
    final id = _presentText(event.applicationRecordId);
    if (id != null) {
      applicationGroups.putIfAbsent((event.scopeKey, id), () => []).add(i);
    }
  }

  void pair(int entryIndex, int exitIndex) {
    consumed.addAll([entryIndex, exitIndex]);
    final entry = source[entryIndex];
    final exit = source[exitIndex];
    final adjustment = entry.role == JourneyEventRole.fareAdjustment;
    if (!adjustment) completedPairs.add((entry, exit));
    projected.add((
      entryIndex < exitIndex ? entryIndex : exitIndex,
      JourneyPresentation<T>(
        events: List.unmodifiable([
          ...operations[entryIndex].evidence,
          ...operations[exitIndex].evidence,
        ]),
        mode: entry.mode,
        state: JourneyState.completed,
        cityLabel:
            _journeyCityCode(entry.cityCode) == _journeyCityCode(exit.cityCode)
            ? _presentText(entry.cityLabel) ?? _presentText(exit.cityLabel)
            : null,
        start: entry.endpoint,
        end: exit.endpoint,
        duration: adjustment
            ? null
            : exit.endpoint.time!.difference(entry.endpoint.time!),
        amountText: exit.amountText,
        fareAdjustmentAmountText: adjustment ? entry.amountText : null,
        balanceAfterText:
            exit.balanceAfterText ??
            (adjustment
                ? null
                : _pairedProcessBalanceText(
                    entry,
                    exit,
                    source,
                    processSlotCounts,
                  )),
        seatLabel: _presentText(exit.seatLabel),
      ),
    ));
  }

  // Both halves must uniquely identify the same application record. Multiple
  // candidates never become a first-match choice, even if a sequence happens
  // to be consecutive later in the stream.
  for (final indexes in applicationGroups.values) {
    final entries = indexes
        .where((i) => source[i].role == JourneyEventRole.entry)
        .toList();
    final exits = indexes
        .where((i) => source[i].role == JourneyEventRole.exit)
        .toList();
    if (entries.length > 1 || exits.length > 1) {
      ambiguousApplication.addAll(indexes);
      continue;
    }
    if (entries.length == 1 &&
        exits.length == 1 &&
        _compatible(source[entries.single], source[exits.single])) {
      pair(entries.single, exits.single);
    }
  }

  // Do not remove already consumed or unknown events before checking adjacency:
  // doing so would conceal an intervening transaction or a missing timestamp.
  for (var i = 0; i + 1 < source.length; i++) {
    final j = i + 1;
    if (consumed.contains(i) ||
        consumed.contains(j) ||
        ambiguousApplication.contains(i) ||
        ambiguousApplication.contains(j)) {
      continue;
    }
    final entryIndex = _isJourneyStart(source[i].role) ? i : j;
    final exitIndex = entryIndex == i ? j : i;
    final entry = source[entryIndex];
    final exit = source[exitIndex];
    if (!_compatible(entry, exit)) continue;
    final entrySequence = entry.sequence;
    final exitSequence = exit.sequence;
    final consecutiveTransaction =
        entrySequence != null &&
        exitSequence != null &&
        entrySequence >= 0 &&
        exitSequence == entrySequence + 1;
    // Original 1E slots are a separate evidence type. Their positive physical
    // indexes may run in either direction, but never bridge a hole or wrap.
    final consecutiveProcess =
        (entrySequence == null ||
            exitSequence == null ||
            consecutiveTransaction) &&
        entry.processPositions.entries.any((position) {
          final batch = position.key;
          final a = position.value;
          final b = exit.processPositions[batch];
          return batch.trim().isNotEmpty &&
              entry.sourceIds.contains(batch) &&
              exit.sourceIds.contains(batch) &&
              a > 0 &&
              b != null &&
              b > 0 &&
              (a - b).abs() == 1 &&
              processSlotCounts[(entry.scopeKey, batch, a)] == 1 &&
              processSlotCounts[(exit.scopeKey, batch, b)] == 1;
        });
    if (!consecutiveTransaction && !consecutiveProcess) {
      continue;
    }
    if (entry.role == JourneyEventRole.fareAdjustment &&
        (!_unambiguousAdjustment(entry, source) ||
            entry.processPositions.entries.any((slot) {
              final other = exit.processPositions[slot.key];
              return other != null &&
                  ((slot.value - other).abs() != 1 ||
                      processSlotCounts[(
                            entry.scopeKey,
                            slot.key,
                            slot.value,
                          )] !=
                          1 ||
                      processSlotCounts[(exit.scopeKey, slot.key, other)] != 1);
            }))) {
      continue;
    }
    final entryApplication = _presentText(entry.applicationRecordId);
    final exitApplication = _presentText(exit.applicationRecordId);
    if (entryApplication != null &&
        exitApplication != null &&
        entryApplication != exitApplication) {
      continue;
    }
    final start = entry.endpoint.time!;
    final end = exit.endpoint.time!;
    final blocked = source.indexed.any((indexed) {
      final (index, event) = indexed;
      if (index == entryIndex || index == exitIndex) return false;
      final time = event.endpoint.time;
      return time != null && !time.isBefore(start) && !time.isAfter(end);
    });
    if (!blocked) pair(entryIndex, exitIndex);
  }

  for (var i = 0; i < source.length; i++) {
    if (consumed.contains(i)) continue;
    final event = source[i];
    final entry = event.role == JourneyEventRole.entry;
    final exit = event.role == JourneyEventRole.exit;
    projected.add((
      i,
      JourneyPresentation<T>(
        events: operations[i].evidence,
        mode: event.mode,
        state: switch (event.role) {
          JourneyEventRole.entry => JourneyState.inProgress,
          JourneyEventRole.single => JourneyState.single,
          _ => JourneyState.incomplete,
        },
        cityLabel: _presentText(event.cityLabel),
        start: entry ? event.endpoint : null,
        end: exit ? event.endpoint : null,
        amountText: entry ? null : event.amountText,
        balanceAfterText: entry
            ? null
            : event.balanceAfterText ??
                  _singleProcessBalanceText(
                    event,
                    source,
                    processSlotCounts,
                    completedPairs,
                  ),
        seatLabel: entry ? null : _presentText(event.seatLabel),
      ),
    ));
  }

  projected.sort((a, b) {
    final at = _latestTime(a.$2);
    final bt = _latestTime(b.$2);
    final byTime = at == null
        ? (bt == null ? 0 : 1)
        : bt == null
        ? -1
        : bt.compareTo(at);
    return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
  });
  return [for (final item in projected) item.$2];
}

class _JourneyOperation<T> {
  _JourneyOperation(this.event, Iterable<JourneyEvent<T>> evidence)
    : evidence = List.unmodifiable(evidence);

  final JourneyEvent<T> event;
  final List<JourneyEvent<T>> evidence;
}

/// Fold only sides whose adapters have already verified the same application
/// operation. Repeated candidates from one family remain ambiguous. All raw
/// events survive in evidence, including their original positions and payloads.
List<_JourneyOperation<T>> _journeyOperations<T>(List<JourneyEvent<T>> events) {
  final groups = <(String, String, JourneyEventRole), List<int>>{};
  for (var i = 0; i < events.length; i++) {
    final event = events[i];
    final scope = _presentText(event.scopeKey);
    final identity = _presentText(event.applicationRecordId);
    if (scope == null ||
        identity == null ||
        (event.role != JourneyEventRole.entry &&
            event.role != JourneyEventRole.exit)) {
      continue;
    }
    groups.putIfAbsent((scope, identity, event.role), () => []).add(i);
  }
  final aliases = <int, List<JourneyEvent<T>>>{};
  final consumed = <int>{};
  for (final indexes in groups.values) {
    if (indexes.length < 2) continue;
    final sides = [for (final index in indexes) events[index]];
    final first = sides.first;
    final families = sides.map((event) => event.evidenceSource).toSet();
    final city = _presentText(first.cityCode)?.toUpperCase();
    final batches = first.sourceIds.where((id) => id.trim().isNotEmpty).toSet();
    for (final side in sides.skip(1)) {
      batches.retainAll(side.sourceIds);
    }
    if (families.contains(JourneyEvidenceSource.unknown) ||
        families.length != sides.length ||
        batches.isEmpty ||
        city == null ||
        RegExp(r'^[0F]+$').hasMatch(city) ||
        first.mode == TripModeFilter.other ||
        first.endpoint.time == null ||
        sides.any(
          (side) =>
              side.mode != first.mode ||
              _presentText(side.cityCode)?.toUpperCase() != city ||
              side.endpoint.time != first.endpoint.time ||
              side.endpoint.time?.isUtc != first.endpoint.time?.isUtc,
        )) {
      continue;
    }
    final positions = <String, int>{};
    var conflictingPosition = false;
    for (final side in sides) {
      for (final slot in side.processPositions.entries) {
        if (!side.sourceIds.contains(slot.key) || slot.value <= 0) continue;
        if (positions.containsKey(slot.key) &&
            positions[slot.key] != slot.value) {
          conflictingPosition = true;
        }
        positions[slot.key] = slot.value;
      }
    }
    if (conflictingPosition) continue;
    sides.sort(
      (a, b) => a.evidenceSource.index.compareTo(b.evidenceSource.index),
    );
    aliases[indexes.first] = sides;
    consumed.addAll(indexes.skip(1));
  }
  return [
    for (var i = 0; i < events.length; i++)
      if (!consumed.contains(i))
        if (aliases[i] case final sides?)
          _JourneyOperation(_operationEvent(sides), sides)
        else
          _JourneyOperation(events[i], [events[i]]),
  ];
}

JourneyEvent<T> _operationEvent<T>(List<JourneyEvent<T>> sides) {
  final preferred = sides.first;
  final balanceOwner = sides
      .where((side) => side.processBalance != null)
      .singleOrNull;
  final originalBalance = balanceOwner?.processBalance;
  // Validate against the original owner before unioning side provenance.
  // Another application's batch/slot must not revive invalid 1E evidence.
  final processBalance = originalBalance == null
      ? null
      : JourneyProcessBalanceEvidence(
          recordedFen: originalBalance.recordedFen,
          amountFen: originalBalance.amountFen,
          currencyCode: originalBalance.currencyCode,
          currencySymbol: originalBalance.currencySymbol,
          minorUnitDigits: originalBalance.minorUnitDigits,
          balanceOffsetFen: originalBalance.balanceOffsetFen,
          positions: Map.unmodifiable({
            for (final slot in originalBalance.positions.entries)
              if (balanceOwner!.sourceIds.contains(slot.key) &&
                  balanceOwner.processPositions[slot.key] == slot.value)
                slot.key: slot.value,
          }),
        );
  final endpoint =
      sides
          .where((side) => side.evidenceSource == JourneyEvidenceSource.cycle)
          .firstOrNull ??
      preferred;
  return JourneyEvent(
    payload: preferred.payload,
    mode: preferred.mode,
    role: preferred.role,
    endpoint: endpoint.endpoint,
    scopeKey: preferred.scopeKey,
    sourceIds: {for (final side in sides) ...side.sourceIds},
    cityCode: preferred.cityCode,
    cityLabel: endpoint.cityLabel ?? preferred.cityLabel,
    sequence: sides.map((side) => side.sequence).whereType<int>().firstOrNull,
    processPositions: {for (final side in sides) ...side.processPositions},
    applicationRecordId: preferred.applicationRecordId,
    evidenceSource: preferred.evidenceSource,
    amountText: preferred.amountText ?? endpoint.amountText,
    balanceAfterText: preferred.balanceAfterText,
    confirmedBalanceFen: preferred.confirmedBalanceFen,
    walletDeltaFen: preferred.walletDeltaFen,
    processBalance: processBalance,
    seatLabel: preferred.seatLabel ?? endpoint.seatLabel,
  );
}

/// A single-charge bus has no entry half. Close its debit between the preceding
/// independently balanced pair and an immediately newer zero-debit entry.
/// Accepting-city changes do not change the wallet. Raw record values survive.
String? _singleProcessBalanceText<T>(
  JourneyEvent<T> event,
  List<JourneyEvent<T>> source,
  Map<(String?, String, int), int> slotCounts,
  List<(JourneyEvent<T>, JourneyEvent<T>)> completedPairs,
) {
  final evidence = event.processBalance;
  final time = event.endpoint.time;
  if (event.role != JourneyEventRole.single ||
      event.mode != TripModeFilter.bus ||
      evidence == null ||
      !_validProcessBalance(evidence) ||
      evidence.amountFen <= 0 ||
      _presentText(event.scopeKey) == null ||
      _journeyCityCode(event.cityCode) == null ||
      time == null) {
    return null;
  }
  final confirmed = <int>{};
  for (final slot in evidence.positions.entries) {
    if (!_validProcessSlot(event, evidence, slot.key, slot.value, slotCounts)) {
      continue;
    }
    for (final anchor in source) {
      final next = anchor.processBalance;
      final nextTime = anchor.endpoint.time;
      if (identical(anchor, event) ||
          anchor.role != JourneyEventRole.entry ||
          anchor.mode == TripModeFilter.other ||
          anchor.scopeKey != event.scopeKey ||
          _journeyCityCode(anchor.cityCode) == null ||
          next == null ||
          !_validProcessBalance(next) ||
          next.amountFen != 0 ||
          nextTime == null ||
          nextTime.isUtc != time.isUtc ||
          !nextTime.isAfter(time) ||
          !_validProcessSlot(
            anchor,
            next,
            slot.key,
            slot.value - 1,
            slotCounts,
          ) ||
          (anchor.confirmedBalanceFen != null &&
              anchor.confirmedBalanceFen != next.recordedFen) ||
          (event.confirmedBalanceFen != null &&
              event.confirmedBalanceFen != next.recordedFen) ||
          (evidence.recordedFen != next.recordedFen &&
              evidence.recordedFen - evidence.amountFen != next.recordedFen) ||
          _balanceIntervalBlocked(source, event, anchor, slot.key) ||
          !_singleProcessDebitCloses(
            event,
            source,
            slotCounts,
            completedPairs,
            slot.key,
            slot.value,
            next.recordedFen,
          )) {
        continue;
      }
      confirmed.add(next.recordedFen);
    }
  }
  return confirmed.length == 1 ? evidence.format(confirmed.single) : null;
}

bool _singleProcessDebitCloses<T>(
  JourneyEvent<T> event,
  List<JourneyEvent<T>> source,
  Map<(String?, String, int), int> slotCounts,
  List<(JourneyEvent<T>, JourneyEvent<T>)> completedPairs,
  String batch,
  int singleSlot,
  int postFen,
) {
  final debit = event.processBalance!.amountFen;
  // Reuse actual accepted pairs, including identity, sequence and ambiguity
  // guards. Monetary closure alone must not turn rejected sides into a journey.
  for (final (entry, exit) in completedPairs) {
    final after = exit.processBalance;
    final end = exit.endpoint.time;
    if (entry.role != JourneyEventRole.entry ||
        exit.role != JourneyEventRole.exit ||
        exit.scopeKey != event.scopeKey ||
        after == null ||
        !_validProcessBalance(after) ||
        after.amountFen <= 0 ||
        after.recordedFen - debit != postFen ||
        (exit.confirmedBalanceFen != null &&
            exit.confirmedBalanceFen != after.recordedFen) ||
        end == null ||
        end.isUtc != event.endpoint.time!.isUtc ||
        !end.isBefore(event.endpoint.time!) ||
        !_validProcessSlot(exit, after, batch, singleSlot + 1, slotCounts) ||
        _balanceIntervalBlocked(source, exit, event, batch)) {
      continue;
    }
    final before = entry.processBalance;
    if (before == null ||
        !_validProcessBalance(before) ||
        before.amountFen != 0 ||
        before.recordedFen - after.amountFen != after.recordedFen ||
        (entry.confirmedBalanceFen != null &&
            entry.confirmedBalanceFen != before.recordedFen) ||
        !_validProcessSlot(entry, before, batch, singleSlot + 2, slotCounts) ||
        _balanceIntervalBlocked(source, entry, exit, batch)) {
      continue;
    }
    return true;
  }
  return false;
}

bool _validProcessSlot<T>(
  JourneyEvent<T> event,
  JourneyProcessBalanceEvidence evidence,
  String batch,
  int slot,
  Map<(String?, String, int), int> slotCounts,
) =>
    batch.trim().isNotEmpty &&
    slot > 0 &&
    event.sourceIds.contains(batch) &&
    event.processPositions[batch] == slot &&
    evidence.positions[batch] == slot &&
    slotCounts[(event.scopeKey, batch, slot)] == 1;

/// Prove each journey locally, rather than extending the 0x18 wallet ledger
/// through 1E. Recharges can be absent from an otherwise contiguous 1E file.
String? _pairedProcessBalanceText<T>(
  JourneyEvent<T> entry,
  JourneyEvent<T> exit,
  List<JourneyEvent<T>> source,
  Map<(String?, String, int), int> slotCounts,
) {
  final before = entry.processBalance;
  final after = exit.processBalance;
  if (entry.role != JourneyEventRole.entry ||
      before == null ||
      after == null ||
      !_validProcessBalance(before) ||
      !_validProcessBalance(after) ||
      before.amountFen != 0 ||
      after.amountFen <= 0 ||
      (entry.confirmedBalanceFen != null &&
          entry.confirmedBalanceFen != before.recordedFen)) {
    return null;
  }
  final postFen = before.recordedFen - after.amountFen;
  if (postFen < 0 ||
      (exit.confirmedBalanceFen != null &&
          exit.confirmedBalanceFen != postFen) ||
      (after.recordedFen != postFen &&
          after.recordedFen != before.recordedFen)) {
    return null;
  }

  bool validSlot(
    JourneyEvent<T> event,
    JourneyProcessBalanceEvidence evidence,
    String batch,
    int slot,
  ) =>
      batch.trim().isNotEmpty &&
      slot > 0 &&
      event.sourceIds.contains(batch) &&
      event.processPositions[batch] == slot &&
      evidence.positions[batch] == slot &&
      slotCounts[(event.scopeKey, batch, slot)] == 1;

  for (final position in after.positions.entries) {
    final batch = position.key;
    final exitSlot = position.value;
    if (!validSlot(exit, after, batch, exitSlot) ||
        !validSlot(entry, before, batch, exitSlot + 1)) {
      continue;
    }
    if (_balanceIntervalBlocked(source, entry, exit, batch)) continue;
    // Both halves independently explain the debit: this exit already contains
    // the post-fare value. Do not subtract the fare from it a second time.
    if (after.recordedFen == postFen) return after.format(postFen);

    // A recharge need not write 1E. Use its independently confirmed 0x18
    // balance only when the immediately newer physical 1E operation also has
    // a confirmed 0x18 debit, and every intervening operation closes exactly.
    if (_rechargeIntervalCloses(
      exit,
      source,
      slotCounts,
      batch,
      exitSlot,
      postFen,
    )) {
      return after.format(postFen);
    }

    // Equal records alone cannot establish pre-fare semantics. Require the
    // immediately newer 1E operation to be a zero-debit entry with the expected
    // balance, and reject any known intervening operation (including recharge).
    final end = exit.endpoint.time!;
    for (final anchor in source) {
      final evidence = anchor.processBalance;
      final time = anchor.endpoint.time;
      if (identical(anchor, entry) ||
          identical(anchor, exit) ||
          evidence == null ||
          !_validProcessBalance(evidence) ||
          anchor.role != JourneyEventRole.entry ||
          anchor.mode == TripModeFilter.other ||
          anchor.scopeKey != exit.scopeKey ||
          _presentText(anchor.cityCode)?.toUpperCase() !=
              _presentText(exit.cityCode)?.toUpperCase() ||
          time == null ||
          time.isUtc != end.isUtc ||
          !time.isAfter(end) ||
          evidence.amountFen != 0 ||
          evidence.recordedFen != postFen ||
          (anchor.confirmedBalanceFen != null &&
              anchor.confirmedBalanceFen != evidence.recordedFen) ||
          !validSlot(anchor, evidence, batch, exitSlot - 1)) {
        continue;
      }
      if (!_balanceIntervalBlocked(source, exit, anchor, batch)) {
        return after.format(postFen);
      }
    }
  }
  return null;
}

bool _rechargeIntervalCloses<T>(
  JourneyEvent<T> exit,
  List<JourneyEvent<T>> source,
  Map<(String?, String, int), int> slotCounts,
  String batch,
  int exitSlot,
  int postFen,
) {
  final end = exit.endpoint.time!;
  for (final anchor in source) {
    final evidence = anchor.processBalance;
    final time = anchor.endpoint.time;
    final confirmed = anchor.confirmedBalanceFen;
    if (anchor.evidenceSource != JourneyEvidenceSource.transaction ||
        (anchor.role != JourneyEventRole.single &&
            anchor.role != JourneyEventRole.exit) ||
        anchor.scopeKey != exit.scopeKey ||
        _journeyCityCode(anchor.cityCode) == null ||
        evidence == null ||
        !_validProcessBalance(evidence) ||
        evidence.amountFen <= 0 ||
        confirmed == null ||
        confirmed != evidence.recordedFen ||
        anchor.walletDeltaFen != -evidence.amountFen ||
        time == null ||
        time.isUtc != end.isUtc ||
        !time.isAfter(end) ||
        !_validProcessSlot(anchor, evidence, batch, exitSlot - 1, slotCounts)) {
      continue;
    }
    final recharges = <JourneyEvent<T>>[];
    var blocked = false;
    for (final other in source) {
      if (identical(other, exit) || identical(other, anchor)) continue;
      final otherTime = other.endpoint.time;
      if (otherTime == null) {
        if (other.scopeKey == exit.scopeKey &&
            other.sourceIds.contains(batch)) {
          blocked = true;
          break;
        }
        continue;
      }
      if (otherTime.isBefore(end) || otherTime.isAfter(time)) continue;
      final delta = other.walletDeltaFen;
      if (otherTime.isUtc != end.isUtc ||
          !otherTime.isAfter(end) ||
          !otherTime.isBefore(time) ||
          other.scopeKey != exit.scopeKey ||
          !other.sourceIds.contains(batch) ||
          other.evidenceSource != JourneyEvidenceSource.transaction ||
          other.role != JourneyEventRole.unknown ||
          other.processBalance != null ||
          other.processPositions.isNotEmpty ||
          delta == null ||
          delta <= 0 ||
          other.confirmedBalanceFen == null) {
        blocked = true;
        break;
      }
      recharges.add(other);
    }
    if (blocked) continue;
    recharges.sort((a, b) => a.endpoint.time!.compareTo(b.endpoint.time!));
    var running = postFen;
    DateTime? previous;
    for (final recharge in recharges) {
      final rechargeTime = recharge.endpoint.time!;
      if (previous == rechargeTime ||
          running + recharge.walletDeltaFen! != recharge.confirmedBalanceFen) {
        blocked = true;
        break;
      }
      previous = rechargeTime;
      running = recharge.confirmedBalanceFen!;
    }
    if (!blocked && running + anchor.walletDeltaFen! == confirmed) return true;
  }
  return false;
}

bool _balanceIntervalBlocked<T>(
  List<JourneyEvent<T>> source,
  JourneyEvent<T> start,
  JourneyEvent<T> end,
  String batch,
) => source.any((other) {
  if (identical(other, start) || identical(other, end)) return false;
  final time = other.endpoint.time;
  if (time == null) {
    return other.scopeKey == start.scopeKey && other.sourceIds.contains(batch);
  }
  return !time.isBefore(start.endpoint.time!) &&
      !time.isAfter(end.endpoint.time!);
});

bool _validProcessBalance(JourneyProcessBalanceEvidence evidence) =>
    evidence.currencyCode == 'CNY' &&
    evidence.minorUnitDigits == 2 &&
    evidence.currencySymbol.trim().isNotEmpty &&
    evidence.recordedFen >= 0 &&
    evidence.amountFen >= 0;

bool _compatible<T>(JourneyEvent<T> entry, JourneyEvent<T> exit) {
  if (!_isJourneyStart(entry.role) ||
      exit.role != JourneyEventRole.exit ||
      (entry.role == JourneyEventRole.fareAdjustment &&
          entry.mode != TripModeFilter.rail) ||
      _presentText(entry.scopeKey) == null ||
      entry.scopeKey != exit.scopeKey ||
      entry.mode == TripModeFilter.other ||
      entry.mode != exit.mode) {
    return false;
  }
  if (_journeyCityCode(entry.cityCode) == null ||
      _journeyCityCode(exit.cityCode) == null ||
      !entry.sourceIds.any(
        (id) => id.trim().isNotEmpty && exit.sourceIds.contains(id),
      )) {
    return false;
  }
  final start = entry.endpoint.time;
  final end = exit.endpoint.time;
  if (start == null ||
      end == null ||
      start.isUtc != end.isUtc ||
      !end.isAfter(start) ||
      end.difference(start) > const Duration(hours: 24)) {
    return false;
  }
  if (entry.mode == TripModeFilter.bus) {
    final line = _presentText(entry.endpoint.line);
    if (line == null || line != _presentText(exit.endpoint.line)) return false;
  }
  return true;
}

bool _isJourneyStart(JourneyEventRole role) =>
    role == JourneyEventRole.entry || role == JourneyEventRole.fareAdjustment;

/// A correction can supply the known point before an exit only when there is
/// no open entry or competing correction. An earlier exit closes the previous
/// journey. Unknown clocks cannot prove which side of this boundary they belong.
bool _unambiguousAdjustment<T>(
  JourneyEvent<T> adjustment,
  List<JourneyEvent<T>> source,
) {
  final start = adjustment.endpoint.time!;
  final earlier = <JourneyEvent<T>>[];
  for (final other in source) {
    if (identical(other, adjustment) ||
        other.scopeKey != adjustment.scopeKey ||
        other.mode != TripModeFilter.rail ||
        !other.sourceIds.any(adjustment.sourceIds.contains)) {
      continue;
    }
    final time = other.endpoint.time;
    if (time == null) return false;
    if (time.isUtc == start.isUtc &&
        time.isBefore(start) &&
        start.difference(time) <= const Duration(hours: 24)) {
      earlier.add(other);
    }
  }
  earlier.sort((a, b) => b.endpoint.time!.compareTo(a.endpoint.time!));
  for (final other in earlier) {
    if (other.role == JourneyEventRole.exit) return true;
    if (_isJourneyStart(other.role)) return false;
  }
  return true;
}

String? _journeyCityCode(String? value) {
  final city = _presentText(value)?.toUpperCase();
  return city == null || RegExp(r'^[0F]+$').hasMatch(city) ? null : city;
}

String? _presentText(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}

DateTime? _latestTime<T>(JourneyPresentation<T> journey) {
  DateTime? latest;
  for (final event in journey.events) {
    final time = event.endpoint.time;
    if (time != null && (latest == null || time.isAfter(latest))) latest = time;
  }
  return latest;
}
