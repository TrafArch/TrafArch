import '../../protocols/transit/city_union/city_union_models.dart';
import '../../protocols/transit/city_union/qingdao_metro_tap.dart';
import '../reference_data/data/city_union_lookup_rules.dart';
import '../reference_data/data/tunion_knowledge_base.dart';
import '../reference_data/domain/reference_match.dart';
import '../reference_data/domain/station_codes.dart';

typedef QingdaoMetroLink = ({String id, bool isEntry});

Set<String> completeQingdaoMetroLinks(Iterable<CuTransactionView> views) {
  final roles = <String, List<bool>>{};
  for (final view in views) {
    if (view.qingdaoMetro case final link?) {
      roles.putIfAbsent(link.id, () => []).add(link.isEntry);
    }
  }
  return {
    for (final group in roles.entries)
      if (group.value.length == 2 && group.value.first != group.value.last)
        group.key,
  };
}

/// CU keeps its own records and namespace; no TU transaction or fare decoder
/// participates. Unknown amount units and missing classifications remain raw.
class CuTransactionView {
  const CuTransactionView({
    required this.record,
    required this.location,
    this.transactionTime,
    this.regionCode,
    this.carrier,
    this.qingdaoMetro,
  });

  final CityUnionWalletTransaction record;
  final DateTime? transactionTime;
  final String? regionCode;
  final int? carrier;
  final QingdaoMetroLink? qingdaoMetro;
  final ReferenceMatch<StationCodeEntry> location;

  CuTransactionView withQingdaoMetro(QingdaoMetroLink? evidence) =>
      CuTransactionView(
        record: record,
        location: location,
        transactionTime: transactionTime,
        regionCode: regionCode,
        carrier: carrier,
        qingdaoMetro: evidence,
      );

  String get kindLabel => switch (record.kind) {
    CityUnionTransactionKind.consumption => '消费',
    CityUnionTransactionKind.recharge => '充值',
    CityUnionTransactionKind.foreignConsumption => '异地消费',
  };

  String get sourceLabel =>
      'CU 0x${record.sfi.toRadixString(16).toUpperCase().padLeft(2, '0')}'
      '${record.recordNumber == null ? '' : ' #${record.recordNumber}'}';

  String get timeLabel => transactionTime == null
      ? '交易时间未知'
      : '${record.transactionDate} ${record.transactionTime}';

  String get locationLabel =>
      location.value?.displayLabel ??
      switch (location.status) {
        ReferenceMatchStatus.ambiguous => '地点存在歧义',
        ReferenceMatchStatus.unavailable => '参考数据不可用',
        _ => '地点未匹配',
      };

  int? get interpretedAmountFen => record.interpretedAmountFen;

  String? amountText({String symbol = '¥'}) {
    final fen = interpretedAmountFen;
    if (fen == null) return null;
    final sign = record.kind == CityUnionTransactionKind.recharge ? '+' : '-';
    return '$sign$symbol${(fen.abs() / 100).toStringAsFixed(2)}';
  }
}

List<CuTransactionView> analyzeCuTransactions(
  Iterable<CityUnionFileView> files,
  KnowledgeBase knowledge, {
  bool busLookupEnabled = true,
}) {
  final results = <CuTransactionView>[];
  final metro = _matchLatestQingdaoMetro(files);
  for (final record in files.whereType<CityUnionWalletTransaction>()) {
    final time = CityUnionLookupRules.transactionTime(
      record.transactionDate,
      record.transactionTime,
    );
    // Issuer city is not proof of the transaction's accepting region. Only an
    // independently recognized terminal classification can establish it here.
    final link = metro[record];
    final identity = CityUnionLookupRules.identifyTerminal(record.terminalHex);
    final region = identity?.regionCode;
    final isRecharge = record.kind == CityUnionTransactionKind.recharge;
    final match = isRecharge || identity == null || region == null
        ? ReferenceMatch<StationCodeEntry>(
            ReferenceMatchStatus.unknown,
            const [],
            issue: isRecharge ? null : '缺少已核实的交易地区分类',
          )
        : knowledge.cuTerminals.resolve(
            identity.terminal,
            CuLookupContext(
              regionCode: region,
              decodedCarrierType: identity.carrier,
              transactionTime: time,
              busLookupEnabled: busLookupEnabled,
            ),
          );
    results.add(
      CuTransactionView(
        record: record,
        location: match,
        transactionTime: time,
        regionCode: region,
        carrier: identity?.carrier,
        qingdaoMetro: link,
      ),
    );
  }
  // Keep unknown timestamps in file order; never turn them into epoch dates.
  final indexed = results.indexed.toList();
  indexed.sort((a, b) {
    final first = a.$2.transactionTime;
    final second = b.$2.transactionTime;
    if (first == null || second == null) {
      if (first == null && second == null) return a.$1.compareTo(b.$1);
      return first == null ? 1 : -1;
    }
    final timeOrder = second.compareTo(first);
    return timeOrder == 0 ? a.$1.compareTo(b.$1) : timeOrder;
  });
  return List.unmodifiable(indexed.map((entry) => entry.$2));
}

/// Only the vendor-specific latest in/out clocks can establish direction.
/// Require unique matches and adjacent original wallet positions and sequence.
Map<CityUnionWalletTransaction, QingdaoMetroLink> _matchLatestQingdaoMetro(
  Iterable<CityUnionFileView> files,
) {
  final taps = files.whereType<QingdaoMetroTap>();
  final inClock = taps.where((tap) => tap.isEntry).singleOrNull?.clock;
  final outClock = taps.where((tap) => !tap.isEntry).singleOrNull?.clock;
  if (inClock == null || outClock == null || inClock.compareTo(outClock) >= 0) {
    return const {};
  }
  final rows = files.whereType<CityUnionWalletTransaction>().where(
    (record) => record.sfi == CityUnionFileIds.walletLocalConsumption,
  );
  String raw(CityUnionWalletTransaction record) =>
      record.rawHex.replaceAll(' ', '');
  CityUnionWalletTransaction? match(String clock) => rows.where((record) {
    final hex = raw(record);
    return hex.length == 46 && hex.endsWith(clock);
  }).singleOrNull;
  final entry = match(inClock);
  final exit = match(outClock);
  if (entry == null ||
      exit == null ||
      entry.kind != CityUnionTransactionKind.consumption ||
      exit.kind != CityUnionTransactionKind.consumption ||
      entry.amountRaw != 0 ||
      exit.amountRaw <= 0 ||
      exit.sequence != (entry.sequence + 1) % 0x10000 ||
      exit.recordNumber == null ||
      entry.recordNumber != exit.recordNumber! + 1) {
    return const {};
  }
  final from = CityUnionLookupRules.transactionTime(
    entry.transactionDate,
    entry.transactionTime,
  );
  final to = CityUnionLookupRules.transactionTime(
    exit.transactionDate,
    exit.transactionTime,
  );
  if (from == null ||
      to == null ||
      to.difference(from) > const Duration(hours: 24)) {
    return const {};
  }
  final id = '${raw(entry)}/${raw(exit)}';
  return {entry: (id: id, isEntry: true), exit: (id: id, isEntry: false)};
}
