import 'dart:convert';

import '../../../protocols/transit/tunion/tunion_process_parser.dart';
import '../../transit_analysis/balance_interpretation.dart';
import '../../trips/journey_presentation.dart';
import '../../trips/trip_cards_view.dart';
import '../application/archive_history.dart';
import '../domain/card_session_snapshot.dart';

typedef ArchiveJourney =
    JourneyPresentation<TripCardPresentation<ArchiveRecordKind>>;
typedef ArchiveJourneyEntry = TripCardPresentation<ArchiveRecordKind>;

/// An operation witness, never a journey pairing rule. Raw bytes and captured
/// facts establish repeated observations; names, fares and array slots do not.
String? archiveJourneyOperationKey(
  ArchiveHistoryRecord record, {
  required String? side,
  required JourneyEvent<dynamic> event,
}) {
  final raw = _hex(record.fields['rawHex']);
  if (raw == null || event.scopeKey == null || event.endpoint.time == null) {
    return null;
  }
  final fields = record.fields;
  final Object identity;
  switch (record.kind) {
    case ArchiveRecordKind.transaction:
      if (raw.length < 46) return null;
      identity = {
        for (final field in fields.entries)
          if (!_transactionAnnotations.contains(field.key))
            field.key: field.key == 'rawHex' ? raw : field.value,
      };
    case ArchiveRecordKind.process:
      if (raw.length != 96) return null;
      identity = {
        for (final field in fields.entries)
          if (field.key != 'capturedDisplay')
            field.key: field.key == 'rawHex' ? raw : field.value,
      };
    case ArchiveRecordKind.rail:
    case ArchiveRecordKind.bus:
      // A mutable 1A record carries two operations. Validate its own side
      // against the original protocol payload, ignoring status/opposite side.
      if (side == null ||
          (event.role != JourneyEventRole.entry &&
              event.role != JourneyEventRole.exit)) {
        return null;
      }
      final bytes = [
        for (var i = 0; i < raw.length; i += 2)
          int.parse(raw.substring(i, i + 2), radix: 16),
      ];
      const parser = TUnionProcessParser();
      final rail = record.kind == ArchiveRecordKind.rail;
      final parsedRail = rail ? parser.parseRailTransit(1, bytes) : null;
      final parsedBus = rail ? null : parser.parseBusTransit(2, bytes);
      if (parsedRail == null && parsedBus == null) return null;
      final captured = jsonDecode(
        CardSessionSnapshot(rails: [?parsedRail], buses: [?parsedBus]).encode(),
      ) as Map<String, dynamic>;
      final decoded =
          (captured[rail ? 'rails' : 'buses'] as List).single as Map;
      final parsedTime = side == 'entry'
          ? (parsedRail?.entryTime ?? parsedBus?.entryTime)
          : (parsedRail?.exitTime ?? parsedBus?.exitTime);
      if (parsedTime == null ||
          _civil(parsedTime) != _civil(event.endpoint.time!) ||
          _useful(decoded['${side}CityCode']) == null ||
          _useful(decoded['${side}TerminalId']) == null) {
        return null;
      }
      final ownFields = {
        for (final key in decoded.keys.cast<String>())
          if (key.startsWith(side) &&
              key != '${side}Time' &&
              !key.endsWith('Name'))
            key: decoded[key],
      };
      for (final field in ownFields.entries) {
        if (fields[field.key] != field.value) return null;
      }
      identity = {
        ...ownFields,
        'civil': _civil(parsedTime),
        // Unknown/custom source fields must not silently become equivalent.
        for (final field in fields.entries)
          if ((!decoded.containsKey(field.key) &&
                  field.key != 'capturedDisplay') ||
              field.key == 'issuerCustom' ||
              field.key == 'issuerCustomHex')
            field.key: field.value,
      };
  }
  return jsonEncode(
    _canonical({
      'kind': record.kind.name,
      'scope': event.scopeKey,
      'cardCityCode': record.cardCityCode,
      'context': _identityContext(record.context),
      'city': event.cityCode,
      'mode': event.mode.name,
      'role': event.role.name,
      'identity': identity,
    }),
  );
}

Map<String, dynamic> _identityContext(ArchiveContext context) {
  final identity = {
    for (final field in context.toJson().entries)
      if (!const {
        'referencePackages',
        'observedFields',
        'captureDeviceOffsetMinutes',
      }.contains(field.key))
        field.key: field.value,
  };
  final observation = identity['balanceInterpretation'];
  if (observation is! Map<String, dynamic>) return identity;
  try {
    if (observation['version'] != BalanceInterpretation.currentVersion ||
        BalanceInterpretation.fromJson(observation).semantics ==
            BalanceSemantics.unknown) {
      return identity;
    }
  } catch (_) {
    // Malformed/unknown monetary context never gains identity equivalence.
    return identity;
  }
  // These are current readings, not properties of an older card operation.
  // Product, semantics, serial, currencies and all unknown extensions remain.
  identity['balanceInterpretation'] = {
    for (final field in observation.entries)
      if (field.key != 'observedAmountMinor' &&
          field.key != 'accountBalanceMinor')
        field.key: field.key == 'verifiedAccountBalance' && field.value is Map
            ? {
                for (final verified in (field.value as Map).entries)
                  if (verified.key != 'amountMinor' &&
                      verified.key != 'evidenceSource')
                    verified.key: verified.value,
              }
            : field.value,
  };
  return identity;
}

const _transactionAnnotations = {
  'capturedDisplay',
  'cityName',
  'lineLabel',
  'stationLabel',
  'stationType',
  'appTypeName',
  'balanceAfterFen',
  'balanceAfterIsRecorded',
  'rideStatusName',
  'rideStatusSource',
  'isEntry',
  'displayProcessKey',
  'displayApplicationKey',
  'location',
  'stationConfidence',
  'matchedProcess',
};

/// Every input has already been paired and financially checked inside one
/// original capture. This function only joins repeated presentations and never
/// runs the matcher or extends a balance ledger after combining evidence.
List<ArchiveJourney> mergeArchiveJourneys(
  List<ArchiveJourney> captures,
  Map<ArchiveJourneyEntry, Set<String>> operationKeys,
) {
  Set<String> keys(ArchiveJourney journey, JourneyEventRole role) => {
    for (final event in journey.events)
      if (event.role == role) ...?operationKeys[event.payload],
  };
  bool sameOperation(
    ArchiveJourney a,
    ArchiveJourney b,
    JourneyEventRole role,
  ) => keys(a, role).any(keys(b, role).contains);
  JourneyEventRole? onlyRole(ArchiveJourney journey) {
    final roles = journey.events.map((event) => event.role).toSet();
    return roles.length == 1 ? roles.single : null;
  }

  final occurrences = <(String, String), Set<ArchiveJourney>>{};
  for (final journey in captures) {
    for (final event in journey.events) {
      for (final key in operationKeys[event.payload] ?? <String>{}) {
        for (final batch in event.sourceIds) {
          occurrences.putIfAbsent((batch, key), () => {}).add(journey);
        }
      }
    }
  }
  final ambiguous = {
    for (final candidates in occurrences.values)
      if (candidates.length > 1) ...candidates,
  };

  bool sameJourney(ArchiveJourney a, ArchiveJourney b) {
    if (ambiguous.contains(a) || ambiguous.contains(b)) return false;
    if (a.mode != b.mode || a.state != b.state) return false;
    if (a.state == JourneyState.completed) {
      final role = a.startsWithFareAdjustment
          ? JourneyEventRole.fareAdjustment
          : JourneyEventRole.entry;
      return a.startsWithFareAdjustment == b.startsWithFareAdjustment &&
          sameOperation(a, b, role) &&
          sameOperation(a, b, JourneyEventRole.exit);
    }
    final role = onlyRole(a);
    return role != null && role == onlyRole(b) && sameOperation(a, b, role);
  }

  // Find all equivalent observations before choosing a presentation. A null
  // field cannot act as a bridge that hides two conflicting known balances.
  final pending = captures.toSet();
  final groups = <List<ArchiveJourney>>[];
  while (pending.isNotEmpty) {
    final group = <ArchiveJourney>[pending.first];
    pending.remove(group.first);
    for (var i = 0; i < group.length; i++) {
      final related = pending
          .where((candidate) => sameJourney(group[i], candidate))
          .toList();
      group.addAll(related);
      pending.removeAll(related);
    }
    final batches = <String>{};
    final uniqueCaptures = group.every((journey) {
      final sources = _batches(journey);
      final overlap = sources.any(batches.contains);
      batches.addAll(sources);
      return sources.isNotEmpty && !overlap;
    });
    if (uniqueCaptures && _consistentFacts(group)) {
      groups.add(group);
    } else {
      groups.addAll(group.map((journey) => [journey]));
    }
  }

  final completed = groups
      .where((group) => group.first.state == JourneyState.completed)
      .toList();
  final absorbed = <List<ArchiveJourney>>{};
  final attachments = <List<ArchiveJourney>, List<List<ArchiveJourney>>>{};
  for (final group in groups) {
    if (group.first.state == JourneyState.completed ||
        group.any(ambiguous.contains)) {
      continue;
    }
    final role = onlyRole(group.first);
    if (role != JourneyEventRole.entry && role != JourneyEventRole.exit) {
      continue;
    }
    final matches = completed.where((target) {
      final witness = target.first;
      if (group.first.mode != witness.mode ||
          !group.any(
            (source) =>
                target.any((known) => sameOperation(source, known, role!)),
          )) {
        return false;
      }
      return true;
    }).toList();
    if (matches.length != 1) continue;
    final target = matches.single;
    final targetBatches = {for (final item in target) ..._batches(item)};
    if (!target.any(ambiguous.contains) &&
        group.every((item) => !_batches(item).any(targetBatches.contains))) {
      attachments.putIfAbsent(target, () => []).add(group);
    }
  }
  // Validate all proposed observations together. Iterative absorption could
  // otherwise choose one of two conflicting balances by iteration order.
  for (final attachment in attachments.entries) {
    final additions = attachment.value.expand((group) => group).toList();
    final all = [...attachment.key, ...additions];
    if (_consistentFacts(all)) {
      attachment.key.addAll(additions);
      absorbed.addAll(attachment.value);
    }
  }
  final result = [
    for (final group in groups)
      if (!absorbed.contains(group)) _combine(group),
  ];
  result.sort((a, b) {
    DateTime? latest(ArchiveJourney journey) => journey.events
        .map((event) => event.endpoint.time)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    final aTime = latest(a);
    final bTime = latest(b);
    return aTime == null
        ? (bTime == null ? 0 : 1)
        : bTime == null
        ? -1
        : bTime.compareTo(aTime);
  });
  return List.unmodifiable(result);
}

bool _consistentFacts(List<ArchiveJourney> group) => [
  (ArchiveJourney j) => j.amountText,
  (ArchiveJourney j) => j.fareAdjustmentAmountText,
  (ArchiveJourney j) => j.balanceAfterText,
  (ArchiveJourney j) => j.seatLabel,
].every((field) => group.map(field).whereType<String>().toSet().length <= 1);

Set<String> _batches(ArchiveJourney journey) => {
  for (final event in journey.events) ...event.sourceIds,
};

ArchiveJourney _combine(List<ArchiveJourney> group) {
  final preferred = group.first;
  String? known(String? Function(ArchiveJourney) field) =>
      group.map(field).whereType<String>().firstOrNull;
  return JourneyPresentation(
    events: List.unmodifiable([for (final journey in group) ...journey.events]),
    mode: preferred.mode,
    state: preferred.state,
    cityLabel: preferred.cityLabel,
    start: preferred.start,
    end: preferred.end,
    duration: preferred.duration,
    amountText: known((j) => j.amountText),
    fareAdjustmentAmountText: known((j) => j.fareAdjustmentAmountText),
    balanceAfterText: known((j) => j.balanceAfterText),
    seatLabel: known((j) => j.seatLabel),
  );
}

String? _hex(Object? value) {
  if (value is! String) return null;
  final normalized = value.replaceAll(RegExp(r'\s+'), '').toUpperCase();
  return normalized.isNotEmpty &&
          normalized.length.isEven &&
          RegExp(r'^[0-9A-F]+$').hasMatch(normalized) &&
          !RegExp(r'^[0F]+$').hasMatch(normalized)
      ? normalized
      : null;
}

String? _useful(Object? value) =>
    value is String &&
        value.isNotEmpty &&
        !RegExp(r'^[0F]+$', caseSensitive: false).hasMatch(value)
    ? value
    : null;

String _civil(DateTime time) =>
    '${time.year}-${time.month}-${time.day}-${time.hour}-${time.minute}-${time.second}';

Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  return value is List ? value.map(_canonical).toList() : value;
}
