import '../../protocols/transit/city_union/city_union_models.dart';
import '../reference_data/data/city_union_lookup_rules.dart';
import '../reference_data/data/tunion_knowledge_base.dart';
import '../reference_data/domain/reference_match.dart';
import '../reference_data/domain/station_codes.dart';

/// CU keeps its own records and namespace; no TU transaction or fare decoder
/// participates. Unknown amount units and missing classifications remain raw.
class CuTransactionView {
  const CuTransactionView({
    required this.record,
    required this.location,
    this.transactionTime,
    this.regionCode,
    this.carrier,
  });

  final CityUnionWalletTransaction record;
  final DateTime? transactionTime;
  final String? regionCode;
  final int? carrier;
  final ReferenceMatch<StationCodeEntry> location;

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
}

List<CuTransactionView> analyzeCuTransactions(
  Iterable<CityUnionFileView> files,
  KnowledgeBase knowledge, {
  bool busLookupEnabled = true,
}) {
  final results = <CuTransactionView>[];
  for (final record in files.whereType<CityUnionWalletTransaction>()) {
    final time = CityUnionLookupRules.transactionTime(
      record.transactionDate,
      record.transactionTime,
    );
    // Issuer city is not proof of the transaction's accepting region. Only an
    // independently recognized terminal classification can establish it here.
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
