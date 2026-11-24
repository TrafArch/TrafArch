import '../../protocols/transit/card_parser.dart';
import '../../protocols/transit/city_union/city_union_models.dart';
import '../../protocols/transit/tunion/tunion_models.dart';
import '../archive/domain/card_types.dart';
import '../reference_data/data/city_union_lookup_rules.dart';
import '../transit_analysis/cu_transaction_analysis.dart';

/// A display-only partition. Both lists retain the original CU view objects.
class ShanghaiMirroredRecords {
  ShanghaiMirroredRecords({
    required Iterable<CuTransactionView> independent,
    required Iterable<CuTransactionView> mirrored,
    Map<TUnionTransaction, CuTransactionView> walletMirrors = const {},
  }) : independent = List.unmodifiable(independent),
       mirrored = List.unmodifiable(mirrored),
       walletMirrors = Map.unmodifiable(walletMirrors);

  final List<CuTransactionView> independent;
  final List<CuTransactionView> mirrored;

  /// One-to-one TU and CU 0x18 observations from the same read.
  final Map<TUnionTransaction, CuTransactionView> walletMirrors;

  int get mirroredCount => mirrored.length;
}

ShanghaiMirroredRecords partitionShanghaiMirroredRecords({
  required String? parserId,
  String? displayCardType,
  required Iterable<TUnionTransaction> tunionTransactions,
  required Iterable<CuTransactionView> cityUnionTransactions,
}) {
  final shanghai =
      parserId == CardParserIds.shanghaiTunion ||
      (parserId == CardParserIds.tunion &&
          displayCardType == CardTypes.shanghaiTransitUnion);
  final harbin =
      parserId == CardParserIds.harbinTunion ||
      (parserId == CardParserIds.tunion &&
          displayCardType == CardTypes.harbinTransitUnion);
  if (!shanghai && !harbin) {
    return ShanghaiMirroredRecords(
      independent: cityUnionTransactions,
      mirrored: const [],
    );
  }

  final tuRows = <String, List<TUnionTransaction>>{};
  for (final transaction in tunionTransactions) {
    final time = transaction.time;
    if (time.millisecond != 0 || time.microsecond != 0) continue;
    final civil = time.toIso8601String().substring(0, 19);
    final raw = _verifiedRaw(
      transaction.rawHex,
      transaction.sequence,
      transaction.amountFen,
      transaction.rawType,
      transaction.terminalId,
      civil,
    );
    if (raw != null) tuRows.putIfAbsent(raw, () => []).add(transaction);
  }

  // A Shanghai top-up can occur in all three files. Each primary row covers
  // one copy per file, even if the CU recharge file was read first.
  final tuCounts = tuRows.map((raw, rows) => MapEntry(raw, rows.length));
  final rechargeCounts = Map.of(tuCounts);
  final walletMirrors = <TUnionTransaction, CuTransactionView>{};
  final cu = cityUnionTransactions.toList();
  final folded = <int>{};
  for (final (index, view) in cu.indexed) {
    final row = view.record;
    if (row.sfi != 0x18) continue;
    final raw = _cuRaw(row);
    if (raw == null) continue;
    final uniqueTu = tuRows[raw]?.singleOrNull;
    if (_take(tuCounts, raw)) {
      folded.add(index);
      if (uniqueTu != null) walletMirrors[uniqueTu] = view;
    } else {
      // A repeated CU row cannot establish which physical slot supplied the match.
      if (uniqueTu != null) walletMirrors.remove(uniqueTu);
      if (row.kind == CityUnionTransactionKind.recharge &&
          row.transactionType == 0x02) {
        rechargeCounts.update(raw, (n) => n + 1, ifAbsent: () => 1);
      }
    }
  }
  final independent = <CuTransactionView>[];
  final mirrored = <CuTransactionView>[];
  for (final (index, view) in cu.indexed) {
    final row = view.record;
    final copy =
        shanghai &&
        row.sfi == 0x06 &&
        row.transactionType == 0x02 &&
        row.kind == CityUnionTransactionKind.recharge &&
        _take(rechargeCounts, _cuRaw(row));
    (copy || folded.contains(index) ? mirrored : independent).add(view);
  }
  return ShanghaiMirroredRecords(
    independent: independent,
    mirrored: mirrored,
    walletMirrors: walletMirrors,
  );
}

bool _take(Map<String, int> counts, String? raw) {
  if (raw == null) return false;
  final count = counts[raw] ?? 0;
  if (count == 0) return false;
  counts[raw] = count - 1;
  return true;
}

String? _cuRaw(CityUnionWalletTransaction row) {
  final date = row.transactionDate;
  final time = row.transactionTime;
  if (CityUnionLookupRules.transactionTime(date, time) == null) return null;
  return _verifiedRaw(
    row.rawHex,
    row.sequence,
    row.amountRaw,
    row.transactionType,
    row.terminalNumber,
    '${date}T$time',
  );
}

// Both projections must agree with the original 23 bytes, including civil
// time, before one can stand in for the other across applications or files.
String? _verifiedRaw(
  String? raw,
  int sequence,
  int amount,
  int type,
  String? terminal,
  String civil,
) {
  final compact = raw?.replaceAll(RegExp(r'\s'), '').toUpperCase();
  if (compact == null ||
      !RegExp(r'^[0-9A-F]{20}[0-9]{26}$').hasMatch(compact) ||
      terminal != compact.substring(20, 32) ||
      sequence != int.parse(compact.substring(0, 4), radix: 16) ||
      amount != int.parse(compact.substring(10, 18), radix: 16) ||
      type != int.parse(compact.substring(18, 20), radix: 16) ||
      civil.replaceAll(RegExp(r'[-T:]'), '') != compact.substring(32)) {
    return null;
  }
  final year = int.parse(compact.substring(32, 36));
  return year >= 2000 && year <= 2100 ? compact : null;
}
