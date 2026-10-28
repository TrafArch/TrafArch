import '../../protocols/transit/card_parser.dart';
import '../../protocols/transit/tunion/tunion_models.dart';
import '../transit_analysis/cu_transaction_analysis.dart';

/// A display-only partition. Both lists retain the original CU view objects.
class ShanghaiMirroredRecords {
  ShanghaiMirroredRecords({
    required Iterable<CuTransactionView> independent,
    required Iterable<CuTransactionView> mirrored,
  }) : independent = List.unmodifiable(independent),
       mirrored = List.unmodifiable(mirrored);

  final List<CuTransactionView> independent;
  final List<CuTransactionView> mirrored;

  int get mirroredCount => mirrored.length;
}

ShanghaiMirroredRecords partitionShanghaiMirroredRecords({
  required String? parserId,
  required Iterable<TUnionTransaction> tunionTransactions,
  required Iterable<CuTransactionView> cityUnionTransactions,
}) {
  if (parserId != CardParserIds.shanghaiTunion) {
    return ShanghaiMirroredRecords(
      independent: cityUnionTransactions,
      mirrored: const [],
    );
  }
  final candidates = <String, List<TUnionTransaction>>{};
  for (final transaction in tunionTransactions) {
    final raw = _normalizedRecord(transaction.rawHex);
    if (raw != null) candidates.putIfAbsent(raw, () => []).add(transaction);
  }
  final independent = <CuTransactionView>[];
  final mirrored = <CuTransactionView>[];
  for (final view in cityUnionTransactions) {
    final raw = _normalizedRecord(view.record.rawHex);
    final available = raw == null ? null : candidates[raw];
    final index = view.record.sfi != 0x18 || available == null
        ? -1
        : available.indexWhere((tu) => _matches(tu, view, raw!));
    if (index < 0) {
      independent.add(view);
    } else {
      // Each TU observation can account for only one CU observation.
      available!.removeAt(index);
      mirrored.add(view);
    }
  }
  return ShanghaiMirroredRecords(independent: independent, mirrored: mirrored);
}

String? _normalizedRecord(String? raw) {
  final compact = raw?.replaceAll(RegExp(r'\s'), '').toUpperCase();
  return compact != null && RegExp(r'^[0-9A-F]{46}$').hasMatch(compact)
      ? compact
      : null;
}

bool _matches(TUnionTransaction tu, CuTransactionView view, String raw) {
  final cu = view.record;
  final sequence = int.parse(raw.substring(0, 4), radix: 16);
  final amount = int.parse(raw.substring(10, 18), radix: 16);
  final type = int.parse(raw.substring(18, 20), radix: 16);
  final terminal = raw.substring(20, 32);
  final time = tu.time;
  if (!RegExp(r'^[0-9]{12}$').hasMatch(terminal) ||
      time.year < 2000 ||
      time.year > 2100 ||
      time.millisecond != 0 ||
      time.microsecond != 0 ||
      tu.sequence != sequence ||
      cu.sequence != sequence ||
      tu.amountFen != amount ||
      cu.amountRaw != amount ||
      tu.rawType != type ||
      cu.transactionType != type ||
      tu.terminalId != terminal ||
      cu.terminalNumber != terminal) {
    return false;
  }
  String two(int value) => value.toString().padLeft(2, '0');
  final date =
      '${time.year.toString().padLeft(4, '0')}-'
      '${two(time.month)}-${two(time.day)}';
  final clock = '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  // TU stores card civil time; the CU projection converts it to UTC+08. The
  // card date/time fields, not the device timezone, establish byte equivalence.
  return cu.transactionDate == date &&
      cu.transactionTime == clock &&
      raw.substring(32) == date.replaceAll('-', '') + clock.replaceAll(':', '');
}
