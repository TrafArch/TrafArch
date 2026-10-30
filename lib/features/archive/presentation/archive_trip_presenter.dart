import 'dart:convert';

import '../../../shared/domain/remote_card_use.dart';
import '../../../protocols/transit/tunion/tunion_models.dart';
import '../../../protocols/transit/tunion/tunion_trip_matcher.dart';
import '../../transit_analysis/tunion_record_context.dart';
import '../../transit_analysis/balance_interpretation.dart';
import '../../transit_analysis/shanghai_balance_display.dart';
import '../../transit_analysis/tunion_analysis_models.dart'
    show kWalletAnchoredBalanceParseVersion;
import '../../trips/journey_presentation.dart';
import '../../trips/trip_cards_view.dart';
import '../../trips/trip_entry_presenter.dart';
import '../../trips/trip_filters.dart';
import '../application/archive_history.dart';
import '../domain/archive_context.dart';
import 'archive_record_presenter.dart';

const archiveTripSourceLabels = {
  ArchiveRecordKind.transaction: '0x18 交易',
  ArchiveRecordKind.process: '0x1E 过程',
  ArchiveRecordKind.rail: '0x1A 轨道',
  ArchiveRecordKind.bus: '0x1A 公交',
};

/// Saved-history projection plus the visible record counts. Captured display
/// links merge individual 1E/1A sides into 0x18. Independent 1E/1A payloads remain
/// available for evidence-backed journey folding; raw history stays untouched.
class ArchiveTripProjection {
  const ArchiveTripProjection({
    required this.entries,
    required this.transactionCount,
    required this.processRecordCount,
    required this.mergedRecordCount,
  });

  final List<TripCardPresentation<ArchiveRecordKind>> entries;
  final int transactionCount;
  final int processRecordCount;
  final int mergedRecordCount;

  String get summaryText =>
      '交易 $transactionCount 条 · 过程及应用记录 $processRecordCount 条'
      '${mergedRecordCount == 0 ? '' : '（$mergedRecordCount 条已并入 0x18 交易）'}';
}

/// Adapt the authoritative history, without re-merging records or looking up
/// anything in a live scan/reference database. A 0x1A record has up to two UI
/// events; both retain the complete record, captured context and attribution.
ArchiveTripProjection presentArchiveTrips(
  List<ArchiveHistoryRecord> records, {
  required void Function(ArchiveHistoryRecord) onDiagnostics,
  bool includeShanghaiOverdraft = true,
  String? cardType,
}) {
  _ArchiveEvent eventFor(ArchiveHistoryRecord record, {String? side}) {
    final display = record.context.minorUnitDigits != 2
        ? const ShanghaiBalanceDisplay()
        : ShanghaiBalanceDisplay.forCard(
            includeShanghaiOverdraft: includeShanghaiOverdraft,
            parserId: record.context.systemId,
            applicationId: record.context.applicationId,
            cardType: cardType,
            currencyCode: record.context.currencyCode,
          );
    return _ArchiveEvent(record, side: side, balanceDisplay: display);
  }

  // 保存时生成的关联按来源批次消费；不跨批次重新按 POS 配对。
  final links = <String, List<String>>{};
  for (final record in records) {
    if (record.kind != ArchiveRecordKind.transaction) continue;
    for (final source in record.sources) {
      final keys = links.putIfAbsent(source.batchId, () => []);
      for (final field in ['displayProcessKey', 'displayApplicationKey']) {
        final key = record.fields[field];
        if (key is String) keys.add(key);
      }
      if (record.fields['displayProcessKey'] == null) {
        final matched = record.fields['matchedProcess'];
        if (matched is Map<String, dynamic>) {
          final process = _processFromFields(matched);
          if (process != null) keys.add(cycleDisplayKey(process));
        }
      }
    }
  }
  bool consume(ArchiveHistoryRecord record, String key) {
    final batches = record.sources.map((s) => s.batchId).toSet();
    if (batches.isEmpty ||
        !batches.every((b) => links[b]?.contains(key) == true)) {
      return false;
    }
    for (final batch in batches) {
      links[batch]!.remove(key);
    }
    return true;
  }

  var transactionCount = 0;
  var processRecordCount = 0;
  var mergedRecordCount = 0;
  final events = <_ArchiveEvent>[];
  for (final record in records) {
    if (record.kind == ArchiveRecordKind.process) {
      final process = _processFromFields(record.fields);
      if (process != null && consume(record, cycleDisplayKey(process))) {
        mergedRecordCount++;
        continue;
      }
      processRecordCount++;
    } else if (record.kind == ArchiveRecordKind.transaction) {
      transactionCount++;
    } else {
      processRecordCount++;
    }
    if (record.kind == ArchiveRecordKind.rail ||
        record.kind == ArchiveRecordKind.bus) {
      final sides = [
        for (final side in ['entry', 'exit'])
          // Amount/code defaults alone do not establish an entry/exit event.
          if (record.fields['${side}Time'] is int) side,
      ];
      if (sides.isEmpty) {
        events.add(eventFor(record));
      } else {
        final visible = sides
            .where(
              (side) => !consume(record, _archiveApplicationKey(record, side)),
            )
            .toList();
        if (visible.isEmpty) {
          processRecordCount--;
          mergedRecordCount++;
        }
        events.addAll(visible.map((side) => eventFor(record, side: side)));
      }
    } else {
      events.add(eventFor(record));
    }
  }
  // Keep history order on ties, but place each side on its own event date.
  final indexed = events.indexed.toList()
    ..sort((a, b) {
      final time = (b.$2.epoch ?? -8640000000000000).compareTo(
        a.$2.epoch ?? -8640000000000000,
      );
      return time != 0 ? time : a.$1.compareTo(b.$1);
    });
  final transactionProcesses = _archiveTransactionProcessLinks(records);
  final applicationLinks = _archiveApplicationLinks(
    records,
    transactionProcesses,
  );
  final processPositions = _archiveProcessPositions(records);
  for (final transaction in transactionProcesses.entries) {
    processPositions[transaction.key] = Map.unmodifiable({
      for (final batch in transaction.value.entries)
        batch.key: ?processPositions[batch.value]?[batch.key],
    });
  }
  return ArchiveTripProjection(
    entries: [
      for (final (_, event) in indexed)
        event.present(
          onDiagnostics,
          linkedApplicationId: applicationLinks[event.record],
          processPositions: processPositions[event.record] ?? const {},
        ),
    ],
    transactionCount: transactionCount,
    processRecordCount: processRecordCount,
    mergedRecordCount: mergedRecordCount,
  );
}

TUnionTripRecord? _processFromFields(Map<String, dynamic> fields) {
  final typeCode = fields['typeCode'];
  final terminalId = fields['terminalId'];
  final appTypeCode = fields['appTypeCode'];
  final lineStationCode = fields['lineStationCode'];
  final amountFen = fields['amountFen'];
  final balanceFen = fields['balanceFen'];
  final time = fields['time'];
  if (typeCode is! int ||
      terminalId is! String ||
      appTypeCode is! int ||
      lineStationCode is! String ||
      amountFen is! int ||
      balanceFen is! int ||
      time is! int) {
    return null;
  }
  return TUnionTripRecord(
    typeCode: typeCode,
    terminalId: terminalId,
    appTypeCode: appTypeCode,
    lineStationCode: lineStationCode,
    amountFen: amountFen,
    balanceFen: balanceFen,
    time: DateTime.fromMillisecondsSinceEpoch(time, isUtc: true),
    cityCode: _text(fields['cityCode']),
    acquirerId: _text(fields['acquirerId']),
    rawHex: _text(fields['rawHex']),
  );
}

String? _text(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

String _archiveApplicationKey(ArchiveHistoryRecord record, String side) {
  final fields = record.fields;
  final time = fields['${side}Time'];
  return tunionDisplayKey(
    '1A-${record.kind == ArchiveRecordKind.rail ? 'rail' : 'bus'}-${side == 'entry'}',
    time is int ? DateTime.fromMillisecondsSinceEpoch(time, isUtc: true) : null,
    _text(fields['${side}TerminalId']),
    _text(fields['rawHex']),
  );
}

/// Retain the original 1E coordinates when a saved 0x18 display link represents
/// that exact operation. A POS-only display match never establishes adjacency.
/// Each capture batch is checked independently; array indexes are not slots.
Map<ArchiveHistoryRecord, Map<String, ArchiveHistoryRecord>>
_archiveTransactionProcessLinks(List<ArchiveHistoryRecord> records) {
  final cycles = <String, List<ArchiveHistoryRecord>>{};
  for (final record in records) {
    if (record.kind != ArchiveRecordKind.process) continue;
    final cycle = _processFromFields(record.fields);
    if (cycle == null) continue;
    cycles.putIfAbsent(cycleDisplayKey(cycle), () => []).add(record);
  }
  final matches = <ArchiveHistoryRecord, Map<String, ArchiveHistoryRecord>>{};
  final useCounts = <(ArchiveHistoryRecord, String), int>{};
  for (final record in records) {
    if (record.kind != ArchiveRecordKind.transaction) continue;
    final source = _ArchiveEvent(record);
    final event = source.journeyEvent(source.info);
    var key = _text(record.fields['displayProcessKey']);
    if (key == null) {
      final cycle = source.matchedProcess;
      if (cycle != null) key = cycleDisplayKey(cycle);
    }
    final candidates = cycles[key];
    if (candidates == null) continue;
    final compatible = candidates.where((candidate) {
      final other = _ArchiveEvent(candidate);
      return _sameArchiveOperation(
            source,
            event,
            other,
            other.journeyEvent(other.info),
          ) &&
          record.fields['amountFen'] is int &&
          record.fields['amountFen'] == candidate.fields['amountFen'];
    }).toList();
    for (final batch in event.sourceIds) {
      final choices = compatible
          .where(
            (candidate) =>
                candidate.sources.any((source) => source.batchId == batch),
          )
          .toList();
      if (choices.length != 1) continue;
      final process = choices.single;
      matches.putIfAbsent(record, () => {})[batch] = process;
      final identity = (process, batch);
      useCounts[identity] = (useCounts[identity] ?? 0) + 1;
    }
  }
  return {
    for (final match in matches.entries)
      match.key: Map.unmodifiable({
        for (final batch in match.value.entries)
          if (useCounts[(batch.value, batch.key)] == 1) batch.key: batch.value,
      }),
  };
}

bool _sameArchiveOperation(
  _ArchiveEvent source,
  JourneyEvent<TripEntryInfo> event,
  _ArchiveEvent other,
  JourneyEvent<TripEntryInfo> candidate,
) =>
    (event.role == JourneyEventRole.entry ||
        event.role == JourneyEventRole.exit) &&
    event.role == candidate.role &&
    event.mode == candidate.mode &&
    event.scopeKey != null &&
    event.scopeKey == candidate.scopeKey &&
    source.epoch == other.epoch &&
    event.endpoint.time != null &&
    event.endpoint.time == candidate.endpoint.time &&
    event.cityCode != null &&
    event.cityCode == candidate.cityCode &&
    event.sourceIds.any(candidate.sourceIds.contains);

/// Saved transaction links and exact, one-to-one 1A/1E side evidence can name
/// the same application record. All original payloads remain in the projection;
/// the journey model folds equivalent source families only for presentation.
Map<ArchiveHistoryRecord, String> _archiveApplicationLinks(
  List<ArchiveHistoryRecord> records,
  Map<ArchiveHistoryRecord, Map<String, ArchiveHistoryRecord>>
  transactionProcesses,
) {
  final candidates =
      <String, List<(_ArchiveEvent, JourneyEvent<TripEntryInfo>)>>{};
  for (final record in records) {
    if (record.kind != ArchiveRecordKind.rail &&
        record.kind != ArchiveRecordKind.bus) {
      continue;
    }
    for (final side in ['entry', 'exit']) {
      if (record.fields['${side}Time'] is! int) continue;
      final source = _ArchiveEvent(record, side: side);
      final event = source.journeyEvent(source.info);
      if (event.applicationRecordId == null ||
          event.scopeKey == null ||
          event.endpoint.time == null ||
          event.cityCode == null) {
        continue;
      }
      candidates
          .putIfAbsent(_archiveApplicationKey(record, side), () => [])
          .add((source, event));
    }
  }
  final matches =
      <ArchiveHistoryRecord, (_ArchiveEvent, JourneyEvent<TripEntryInfo>)>{};
  final useCounts =
      <(ArchiveHistoryRecord, String, ArchiveRecordKind, String), int>{};
  for (final record in records) {
    final transaction = record.kind == ArchiveRecordKind.transaction;
    if (!transaction && record.kind != ArchiveRecordKind.process) continue;
    final choices = transaction
        ? candidates[_text(record.fields['displayApplicationKey'])]
        : candidates.values.expand((sides) => sides).toList();
    if (choices == null) continue;
    final source = _ArchiveEvent(record);
    final event = source.journeyEvent(source.info);
    final compatible = choices.where((candidate) {
      final (application, side) = candidate;
      if (!_sameArchiveOperation(source, event, application, side)) {
        return false;
      }
      final amount = !application.rail && application.entry
          ? null
          : application.fields[application.rail
                ? '${application.side}AmountFen'
                : 'amountFen'];
      if (transaction) {
        return amount is! int || record.fields['amountFen'] == amount;
      }
      final cycle = source.process;
      if (cycle == null) return false;
      return matchesTunionJourneySide(
        isEntry: application.entry,
        isRail: application.rail,
        time: application.epoch == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                application.epoch!,
                isUtc: true,
              ),
        cityCode: application.city,
        terminalId: application.text('${application.side}TerminalId'),
        amountFen: amount is int ? amount : null,
        cycle: cycle,
      );
    }).toList();
    if (compatible.length != 1) continue;
    final match = compatible.single;
    matches[record] = match;
    for (final batch in event.sourceIds.intersection(match.$2.sourceIds)) {
      final identity = (match.$1.record, match.$1.side!, record.kind, batch);
      useCounts[identity] = (useCounts[identity] ?? 0) + 1;
    }
  }
  final result = <ArchiveHistoryRecord, String>{};
  final proofBatches = <ArchiveHistoryRecord, Set<String>>{};
  for (final match in matches.entries) {
    final batches = {
      for (final source in match.key.sources)
        if (useCounts[(
              match.value.$1.record,
              match.value.$1.side!,
              match.key.kind,
              source.batchId,
            )] ==
            1)
          source.batchId,
    };
    if (batches.isEmpty) continue;
    result[match.key] = match.value.$2.applicationRecordId!;
    proofBatches[match.key] = batches;
  }
  for (final transaction in transactionProcesses.entries) {
    final identities = {
      for (final batch in transaction.value.entries)
        if (proofBatches[batch.value]?.contains(batch.key) == true)
          ?result[batch.value],
    };
    if (identities.length != 1) continue;
    final identity = identities.single;
    final previous = result[transaction.key];
    if (previous == null || previous == identity) {
      result[transaction.key] = identity;
    } else {
      result.remove(transaction.key);
    }
  }
  return result;
}

/// The cycle[] JSON array contains only decoded items; its indexes are never
/// physical record slots. Only explicit, reliable capture provenance is used.
Map<ArchiveHistoryRecord, Map<String, int>> _archiveProcessPositions(
  List<ArchiveHistoryRecord> records,
) {
  final slots = <(String, int), int>{};
  final rawCounts = <(String, String), int>{};
  final candidates = <ArchiveHistoryRecord, Map<String, List<(int, String)>>>{};
  String? rawHex(Object? value) {
    if (value is! String) return null;
    final text = value.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    return text.isNotEmpty &&
            text.length.isEven &&
            RegExp(r'^[0-9A-F]+$').hasMatch(text)
        ? text
        : null;
  }

  for (final record in records) {
    if (record.kind != ArchiveRecordKind.process) continue;
    final raw = rawHex(record.fields['rawHex']);
    for (final source in record.sources) {
      final provenance = source.provenance;
      final evidence = provenance is Map ? provenance['record'] : null;
      if (evidence is! Map ||
          evidence['sfi'] != 0x1E ||
          source.batchId.trim().isEmpty) {
        continue;
      }
      final number = evidence['recordNumber'];
      if (number is! int || number <= 0) continue;
      final slot = (source.batchId, number);
      slots[slot] = (slots[slot] ?? 0) + 1;
      final sourceRaw = rawHex(evidence['rawHex']);
      if (sourceRaw == null) continue;
      final rawIdentity = (source.batchId, sourceRaw);
      rawCounts[rawIdentity] = (rawCounts[rawIdentity] ?? 0) + 1;
      if (evidence['recordNumberIsReliable'] != true || raw != sourceRaw) {
        continue;
      }
      candidates
          .putIfAbsent(record, () => {})
          .putIfAbsent(source.batchId, () => [])
          .add((number, sourceRaw));
    }
  }
  return {
    for (final record in candidates.entries)
      record.key: Map.unmodifiable({
        for (final batch in record.value.entries)
          if (batch.value.length == 1 &&
              slots[(batch.key, batch.value.single.$1)] == 1 &&
              rawCounts[(batch.key, batch.value.single.$2)] == 1)
            batch.key: batch.value.single.$1,
      }),
  };
}

class _ArchiveEvent {
  const _ArchiveEvent(
    this.record, {
    this.side,
    this.balanceDisplay = const ShanghaiBalanceDisplay(),
  });
  final ArchiveHistoryRecord record;
  final String? side;
  final ShanghaiBalanceDisplay balanceDisplay;
  Map<String, dynamic> get fields => record.fields;
  bool get entry => side == 'entry';
  bool get rail => record.kind == ArchiveRecordKind.rail;
  bool get transaction => record.kind == ArchiveRecordKind.transaction;
  String get timeKey => side == null ? 'time' : '${side}Time';
  int? get epoch => fields[timeKey] as int?;

  String? text(String key) {
    final value = fields[key];
    return value == null || value == '' ? null : value.toString();
  }

  String? capturedDisplay(String key) {
    final display = fields['capturedDisplay'];
    final endpoint = display is Map
        ? (side == null ? display : display[side])
        : null;
    final value = endpoint is Map ? endpoint[key] : null;
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  TUnionTripRecord? get process => record.kind != ArchiveRecordKind.process
      ? null
      : _processFromFields(fields);

  TUnionTripRecord? get matchedProcess {
    final matched = fields['matchedProcess'];
    return matched is Map<String, dynamic> ? _processFromFields(matched) : null;
  }

  TripModeFilter get mode {
    if (rail) return TripModeFilter.rail;
    if (record.kind == ArchiveRecordKind.bus) return TripModeFilter.bus;
    final cycle = process ?? matchedProcess;
    if (cycle != null && isTunionBusCycle(cycle)) return TripModeFilter.bus;
    final matched = fields['matchedProcess'];
    final appType =
        fields['appTypeCode'] ??
        (matched is Map ? matched['appTypeCode'] : null);
    return switch (fields['appTypeName'] ?? appType) {
      '城市轨道交通' || 1 => TripModeFilter.rail,
      '公共汽电车' || 2 => TripModeFilter.bus,
      _ => switch (fields['stationType']) {
        '公交' || 'BRT' || '公共汽电车' || 'bus' || 'brt' => TripModeFilter.bus,
        '地铁' || '城市轨道交通' || 'metro' || 'rail' => TripModeFilter.rail,
        _ => TripModeFilter.other,
      },
    };
  }

  TripCardPresentation<ArchiveRecordKind> present(
    void Function(ArchiveHistoryRecord) onDiagnostics, {
    String? linkedApplicationId,
    Map<String, int> processPositions = const {},
  }) {
    final details = info;
    return TripCardPresentation(
      info: details,
      source: record.kind,
      mode: mode,
      dateText: dateText,
      remote: remote,
      onDiagnostics: () => onDiagnostics(record),
      journeyEvent: journeyEvent(
        details,
        linkedApplicationId: linkedApplicationId,
        processPositions: processPositions,
      ),
    );
  }

  JourneyEvent<TripEntryInfo> journeyEvent(
    TripEntryInfo details, {
    String? linkedApplicationId,
    Map<String, int> processPositions = const {},
  }) {
    final clock = _archiveClock(fields, timeKey, record.context);
    final application = rail || record.kind == ArchiveRecordKind.bus;
    final staleExit = rail && side == 'exit' && fields['status'] == 1;
    final JourneyEventRole role;
    if (application) {
      role = side == null || epoch == null || staleExit
          ? JourneyEventRole.unknown
          : entry
          ? JourneyEventRole.entry
          : JourneyEventRole.exit;
    } else if (transaction) {
      role =
          _archiveStatusRole(text('rideStatusName'), mode) ??
          _archiveProcessRole(matchedProcess, mode) ??
          (fields['isEntry'] == true
              ? JourneyEventRole.entry
              : mode == TripModeFilter.bus && fields['consume'] == true
              ? JourneyEventRole.single
              : JourneyEventRole.unknown);
    } else {
      role = _archiveProcessRole(process, mode) ?? JourneyEventRole.unknown;
    }
    final capturedStation = capturedDisplay('station');
    final rawStation =
        capturedStation ??
        (side == null
            ? text('stationLabel') ?? process?.stationCode
            : text('${side}StationName') ??
                  text('${side}Station${rail ? 'Id' : 'Code'}'));
    final station = mode == TripModeFilter.bus
        ? _archiveBusStation(
            rawStation,
            rawHex:
                capturedStation == null &&
                record.kind == ArchiveRecordKind.bus &&
                text('${side}StationName') == null,
            rawCode:
                capturedStation == null &&
                (record.kind == ArchiveRecordKind.process ||
                    fields['stationConfidence'] != 'exact'),
          )
        : _usefulIdentifier(rawStation);
    final capturedLine = capturedDisplay('line');
    final line =
        (mode == TripModeFilter.bus
            ? formatJourneyBusLine(capturedLine)
            : capturedLine) ??
        (side == null
            ? text('lineLabel') ?? text('lineName') ?? process?.lineCode
            : text('${side}LineName') ??
                  text('${side}LineLabel') ??
                  text('${side}LineCode'));
    final label =
        capturedDisplay('cityName') ??
        text(side == null ? 'cityName' : '${side}CityName');
    final seatAmount =
        fields[rail && side != null ? '${side}AmountFen' : 'amountFen'];
    final cycle = process;
    final isSeatConsume = transaction
        ? fields['consume'] == true
        : cycle != null
        ? cycle.isConsume
        : rail
        ? side != null && seatAmount is int && seatAmount > 0
        : record.kind == ArchiveRecordKind.bus && side == 'exit';
    return JourneyEvent(
      payload: details,
      mode: mode,
      role: role,
      endpoint: JourneyEndpoint(
        line: _usefulIdentifier(line),
        station: station,
        time: clock.time,
        timeText: clock.text,
      ),
      scopeKey: _archiveScope(record.context, clock.scope),
      sourceIds: {
        for (final source in record.sources)
          if (source.batchId.trim().isNotEmpty) source.batchId,
      },
      cityCode: _usefulIdentifier(city),
      cityLabel: label != null && label.length > 1 && label.endsWith('市')
          ? label.substring(0, label.length - 1)
          : label,
      sequence: transaction && fields['sequence'] is int
          ? fields['sequence'] as int
          : null,
      processPositions: record.kind == ArchiveRecordKind.process || transaction
          ? processPositions
          : const {},
      applicationRecordId:
          application && side != null && epoch != null && !staleExit
          ? _archiveApplicationId(record)
          : linkedApplicationId,
      evidenceSource: switch (record.kind) {
        ArchiveRecordKind.transaction => JourneyEvidenceSource.transaction,
        ArchiveRecordKind.process => JourneyEvidenceSource.cycle,
        ArchiveRecordKind.rail ||
        ArchiveRecordKind.bus => JourneyEvidenceSource.application,
      },
      amountText: details.amountText,
      balanceAfterText: journeyBalanceAfterText,
      confirmedBalanceFen: journeyBalanceAfterText == null
          ? null
          : archiveRecordBalanceFen(record),
      processBalance: processBalanceEvidence(processPositions),
      seatLabel: mode == TripModeFilter.rail
          ? journeySeatLabel(
              line: _usefulIdentifier(line),
              amountFen: seatAmount is int ? seatAmount : null,
              isConsume: isSeatConsume,
              currencyCode: record.context.currencyCode,
            )
          : null,
    );
  }

  JourneyProcessBalanceEvidence? processBalanceEvidence(
    Map<String, int> positions,
  ) {
    final cycle = process ?? (transaction ? matchedProcess : null);
    final observation = record.context.extensions['balanceInterpretation'];
    final hasInterpretation = record.context.extensions.containsKey(
      'balanceInterpretation',
    );
    final directInterpretation =
        !hasInterpretation ||
        (observation is Map<String, dynamic> &&
            BalanceInterpretation.fromJson(observation).semantics ==
                BalanceSemantics.direct);
    if (cycle == null ||
        positions.isEmpty ||
        record.context.currencyCode != 'CNY' ||
        record.context.minorUnitDigits != 2 ||
        !directInterpretation) {
      return null;
    }
    return JourneyProcessBalanceEvidence(
      recordedFen: cycle.balanceFen,
      amountFen: cycle.amountFen,
      currencyCode: record.context.currencyCode,
      currencySymbol: '¥ ',
      positions: Map.unmodifiable(positions),
      balanceOffsetFen: balanceDisplay.offsetFen,
    );
  }

  String? get city => text(side == null ? 'cityCode' : '${side}CityCode');
  bool get remote => isRemoteCardUse(record.cardCityCode, city);

  String? timeText(String key) {
    final value = fields[key];
    if (value is! int) return null;
    final captured = fields['capturedTimes'];
    final representation = captured is Map ? captured[key] : null;
    final civil = representation is Map ? representation['civil'] : null;
    if (civil is String &&
        RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}').hasMatch(civil)) {
      return '${civil.replaceFirst('T', ' ')}（卡内时间，时区未经核实）';
    }
    return archiveTimeText(value, record.context);
  }

  String get dateText {
    final time = timeText(timeKey);
    return time == null
        ? '日期未知'
        : RegExp(r'^\d{4}-\d{2}-\d{2}').stringMatch(time) ?? '日期未知';
  }

  String? amount(String key, {bool debit = false}) {
    final value = fields[key];
    if (value is! int) return null;
    final displayed = key == 'entryBalanceFen'
        ? balanceDisplay.balanceFen(value)!
        : value;
    return '${debit && value > 0 ? '-' : ''}${record.context.formatAmount(displayed)}';
  }

  String? get recordBalanceText {
    final balance = balanceDisplay.balanceFen(archiveRecordBalanceFen(record));
    return balance == null ? null : record.context.formatAmount(balance);
  }

  String? get journeyBalanceAfterText {
    if (!transaction || archiveRecordBalanceIsRecorded(record)) return null;
    final version = record.sources.isEmpty
        ? 1
        : record.sources.first.capturedParseVersion;
    // v8 missing provenance remains compatible in legacy detail text, but is
    // insufficient to claim a reliable post-journey balance in the summary.
    if (version >= kWalletAnchoredBalanceParseVersion &&
        fields['balanceAfterIsRecorded'] != false) {
      return null;
    }
    return recordBalanceText;
  }

  TripEntryInfo get info {
    final cycle = process;
    final isConsume = transaction
        ? fields['consume'] == true
        : cycle != null
        ? cycle.isConsume && cycle.amountFen > 0
        : !entry;
    final amountKey = side == null || !rail ? 'amountFen' : '${side}AmountFen';
    final balance = transaction || cycle != null
        ? recordBalanceText
        : rail && entry
        ? amount('entryBalanceFen')
        : null;
    final balanceLabel = transaction || cycle != null
        ? (archiveRecordBalanceIsRecorded(record) ? '记录余额' : '交易后余额')
        : '余额';
    final station =
        capturedDisplay('station') ??
        text(side == null ? 'stationLabel' : '${side}StationName') ??
        (side == null ? null : text('${side}Station${rail ? 'Id' : 'Code'}'));
    final status = transaction
        ? text('rideStatusName') ?? text('typeName') ?? '其他'
        : cycle != null
        ? cycle.statusShortName ?? cycle.typeName
        : record.kind == ArchiveRecordKind.process
        ? '未知过程记录'
        : side != null
        ? (rail ? (entry ? '进站' : '出站') : (entry ? '上车' : '下车'))
        : rail
        ? TransitRecord(statusCode: fields['status'] as int).statusName
        : BusTransitRecord(statusCode: fields['status'] as int).statusName;
    final source = switch (record.kind) {
      ArchiveRecordKind.transaction => '0x18 交易明细',
      ArchiveRecordKind.process => '0x1E 过程记录',
      ArchiveRecordKind.rail => '0x1A 轨道记录',
      ArchiveRecordKind.bus => '0x1A 公交记录',
    };
    final batchCount = record.sources.map((s) => s.batchId).toSet().length;
    return TripEntryInfo(
      sourceLabel: source,
      title: [
        status,
        ?station,
        if (transaction) '序号 ${fields['sequence']}',
      ].join(' · '),
      line:
          capturedDisplay('line') ??
          text('lineLabel') ??
          text('lineName') ??
          (side == null ? null : text('${side}LineCode')),
      timeText: timeText(timeKey),
      amountText: record.kind == ArchiveRecordKind.bus && entry
          ? null
          : cycle != null && cycle.isRecharge
          ? '+${record.context.formatAmount(cycle.amountFen)}'
          : amount(amountKey, debit: isConsume),
      isConsume: isConsume,
      subText:
          record.kind == ArchiveRecordKind.bus &&
              !entry &&
              fields['mileage'] != null
          ? '里程 ${fields['mileage']} 站'
          : balance == null || (side != null && !entry)
          ? null
          : '$balanceLabel $balance',
      category:
          text('appTypeName') ??
          cycle?.appTypeLabel ??
          (mode == TripModeFilter.other ? null : tripModeLabels[mode]),
      badges: [
        if (fields['stationConfidence'] == 'ambiguous') '站名歧义',
        if (fields['stationConfidence'] == 'unmatched' ||
            fields['stationConfidence'] == 'probable')
          '未匹配',
        if (fields['stationConfidence'] == 'unavailable') '参考数据不可用',
      ],
      related:
          '已保存于 $batchCount 个批次'
          '${fields['matchedProcess'] is Map ? ' · 保存时已关联 0x1E 过程记录' : ''}',
      remoteCityText: remote ? '${text('cityName') ?? '未知城市'}（$city）' : null,
      rawHex: text('rawHex'),
      fields: detailFields(cycle),
    );
  }

  List<(String, String)> detailFields(TUnionTripRecord? cycle) => [
    if (cycle != null && text('appTypeName') == null)
      ('应用分类', cycle.appTypeName),
    if (text('rideStatusSource') case final source?)
      (
        '进出站依据',
        source == 'shanghai-cu-ledger-inference' ? '按上海本地轨道账本推断' : source,
      ),
    if (cycle != null) ('过程类型', cycle.typeName),
    if (rail)
      ('交易状态', TransitRecord(statusCode: fields['status'] as int).statusName),
    if (record.kind == ArchiveRecordKind.bus)
      (
        '交易状态',
        BusTransitRecord(statusCode: fields['status'] as int).statusName,
      ),
    for (final field in const {
      'typeName': '交易类型',
      'sequence': '交易序号',
      'stationLabel': '站点',
      'lineLabel': '线路',
      'lineName': '线路',
      'terminalId': '终端编号',
      'cityName': '城市',
      'cityCode': '城市代码',
      'appTypeName': '应用分类',
      'entryCityCode': '进入城市',
      'exitCityCode': '离开城市',
      'entryStationName': '进入站点',
      'exitStationName': '离开站点',
      'entryStationId': '进闸站点（原始）',
      'exitStationId': '出闸站点（原始）',
      'entryStationCode': '上车站（原始）',
      'exitStationCode': '下车站（原始）',
      'entryLineCode': '进入线路（原始）',
      'exitLineCode': '离开线路（原始）',
      'entryOperatorCode': '上车运营码',
      'exitOperatorCode': '下车运营码',
      'entryTerminalId': '进入终端',
      'exitTerminalId': '离开终端',
      'lineStationCode': '线路站点字段（原始）',
      'acquirerId': '受理方标识',
    }.entries)
      if (text(field.key) case final value?) (field.value, value),
    for (final field in const {
      'time': '交易时间',
      'entryTime': '进入时间',
      'exitTime': '离开时间',
    }.entries)
      if (timeText(field.key) case final value?) (field.value, value),
    for (final field in const {
      'amountFen': '金额',
      'entryBalanceFen': '进站时余额',
      'entryAmountFen': '进入时金额',
      'exitAmountFen': '离开时金额',
      'transactionAmountFen': '交易金额',
      'annotateAmountFen': '标注金额',
    }.entries)
      if (amount(
            field.key,
            debit:
                transaction &&
                fields['consume'] == true &&
                field.key == 'amountFen',
          )
          case final value?)
        (field.value, value),
    if (recordBalanceText case final balance?)
      (archiveRecordBalanceIsRecorded(record) ? '记录余额' : '交易后余额', balance),
    if (fields['mileage'] case final int mileage) ('里程', '$mileage 站'),
    if (fields['directionCode'] case final int direction)
      (
        '方向',
        BusTransitRecord(statusCode: 0, directionCode: direction).directionName,
      ),
    ('币种', record.context.currencyCode ?? '未知'),
    if (record.context.systemId case final system?) ('卡片系统', system),
    if (record.context.applicationId case final application?)
      ('卡片应用', application),
  ];
}

final _archiveApplicationIds = Expando<String>('archive-journey-record');
var _nextArchiveApplicationId = 0;
String _archiveApplicationId(ArchiveHistoryRecord record) =>
    _archiveApplicationIds[record] ??= 'archive:${_nextArchiveApplicationId++}';

JourneyEventRole? _archiveStatusRole(String? status, TripModeFilter mode) =>
    switch (status) {
      '进站' || '进闸' || '上车' => JourneyEventRole.entry,
      '出站' || '出闸' || '下车' => JourneyEventRole.exit,
      '单次消费' =>
        mode == TripModeFilter.bus
            ? JourneyEventRole.single
            : JourneyEventRole.unknown,
      '充值' || '补票' => JourneyEventRole.unknown,
      _ => null,
    };

JourneyEventRole? _archiveProcessRole(
  TUnionTripRecord? process,
  TripModeFilter mode,
) => process == null
    ? null
    : switch (process.typeCode) {
        1 || 3 => JourneyEventRole.entry,
        2 || 4 => JourneyEventRole.exit,
        5 || 6 when mode == TripModeFilter.bus => JourneyEventRole.single,
        _ => JourneyEventRole.unknown,
      };

String? _usefulIdentifier(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty || RegExp(r'^0+$|^[Ff]+$').hasMatch(text)
      ? null
      : text;
}

String? _archiveBusStation(
  String? value, {
  bool rawHex = false,
  bool rawCode = false,
}) {
  final text = _usefulIdentifier(value);
  if (text == null) return null;
  final ordinal = RegExp(r'^第(\d+)站$').firstMatch(text);
  if (ordinal != null) {
    final number = int.tryParse(ordinal.group(1)!);
    return number == null || number == 0 ? null : '站点$number';
  }
  if (rawHex && RegExp(r'^[0-9A-Fa-f]{1,2}$').hasMatch(text)) {
    return '站点${int.parse(text, radix: 16)}';
  }
  return rawCode && RegExp(r'^[0-9A-Fa-f]+$').hasMatch(text) ? '站点$text' : text;
}

String? _archiveScope(ArchiveContext context, String? clockScope) {
  final system = _text(context.systemId)?.trim();
  final application = _text(context.applicationId)?.trim();
  final currency = _text(context.currencyCode)?.trim();
  final basis = _text(context.clockBasis)?.trim();
  final digits = context.minorUnitDigits;
  final offset = context.timeZoneOffsetMinutes;
  if ([
        system,
        application,
        currency,
        basis,
        clockScope,
      ].any((value) => value == null || value.isEmpty) ||
      digits == null ||
      digits < 0 ||
      digits > 9 ||
      (offset != null && (offset < -1440 || offset > 1440))) {
    return null;
  }
  return jsonEncode([
    'archive',
    system,
    application,
    currency,
    digits,
    basis,
    context.timeZoneOffsetMinutes,
    clockScope,
  ]);
}

typedef _ArchiveClock = ({DateTime? time, String? text, String? scope});

_ArchiveClock _archiveClock(
  Map<String, dynamic> fields,
  String key,
  ArchiveContext context,
) {
  final epoch = fields[key];
  if (epoch is! int) return (time: null, text: null, scope: null);
  final captured = fields['capturedTimes'];
  final representation = captured is Map ? captured[key] : null;
  final civil = representation is Map ? representation['civil'] : null;
  if (civil is String) {
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?(Z)?$',
    ).firstMatch(civil);
    if (match != null) {
      final explicitUtc = match.group(8) != null;
      final basis = representation['basis'];
      final utcFlag = representation['isUtc'];
      final claimedUtc = basis == 'utc' || utcFlag == true;
      final claimedLocal =
          basis == 'parser-local-unverified' || utcFlag == false;
      if ((explicitUtc && claimedLocal) || (claimedUtc && claimedLocal)) {
        return (time: null, text: civil, scope: null);
      }
      final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
      final fraction = (match.group(7) ?? '').padRight(6, '0');
      // UTC is only a stable calendar-arithmetic coordinate for unknown civil
      // clocks. It does not assign UTC to the card: the scope isolates those
      // values and the detail text retains its unverified-timezone warning.
      final value = DateTime.utc(
        parts[0],
        parts[1],
        parts[2],
        parts[3],
        parts[4],
        parts[5],
        int.parse(fraction.substring(0, 3)),
        int.parse(fraction.substring(3)),
      );
      final actual = [
        value.year,
        value.month,
        value.day,
        value.hour,
        value.minute,
        value.second,
      ];
      if (List.generate(
        6,
        (i) => parts[i] == actual[i],
      ).every((same) => same)) {
        final utc = explicitUtc || claimedUtc;
        return (
          time: value,
          text: _archiveClockText(value),
          scope: jsonEncode([
            utc ? 'captured-utc' : 'captured-civil',
            representation['basis'],
            representation['isUtc'],
            representation['conversionOffsetMinutes'],
          ]),
        );
      }
    }
    return (time: null, text: civil, scope: null);
  }
  final offset = context.timeZoneOffsetMinutes;
  if (epoch < -8640000000000000 ||
      epoch > 8640000000000000 ||
      (offset != null && (offset < -1440 || offset > 1440))) {
    return (time: null, text: '$epoch 毫秒（原始时间）', scope: null);
  }
  if (offset == null) {
    return (time: null, text: archiveTimeText(epoch, context), scope: null);
  }
  final shifted = epoch + offset * 60000;
  if (shifted < -8640000000000000 || shifted > 8640000000000000) {
    return (time: null, text: '$epoch 毫秒（原始时间）', scope: null);
  }
  // The endpoint also provides the card's display date, so fixed-offset times
  // use the same clock-face coordinate as their displayed hours and minutes.
  final value = DateTime.fromMillisecondsSinceEpoch(shifted, isUtc: true);
  return (
    time: value,
    text: _archiveClockText(value),
    scope: 'captured-offset:$offset',
  );
}

String _archiveClockText(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}:'
    '${value.second.toString().padLeft(2, '0')}';
