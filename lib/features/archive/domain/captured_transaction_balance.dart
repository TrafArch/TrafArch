import '../../transit_analysis/tunion_analysis_models.dart';

/// Interpret the balance captured by that parser version, without rebuilding a
/// ledger from historical display rows or modifying the original process data.
({int? fen, bool isRecorded}) capturedTransactionBalance(
  Map<String, dynamic> fields,
  int parseVersion,
) {
  final value = fields['balanceAfterFen'];
  final stored = value is int ? value : null;
  final matched = _matchedProcessBalanceFen(fields);
  if (parseVersion < kBalanceReconstructionParseVersion) {
    return (fen: matched ?? stored, isRecorded: true);
  }
  // Explicit unknowns in v6+ stay unknown, even with raw process evidence.
  if (parseVersion >= kWalletAnchoredBalanceParseVersion) {
    return (
      fen: stored,
      isRecorded: stored != null && fields['balanceAfterIsRecorded'] == true,
    );
  }
  // v6/v7 did not capture provenance separately. Retain their old semantics.
  return (
    fen: stored,
    isRecorded: stored != null && matched != null && stored == matched,
  );
}

int? _matchedProcessBalanceFen(Map<String, dynamic> fields) {
  final matched = fields['matchedProcess'];
  if (matched is Map<String, dynamic> &&
      [
        'typeCode',
        'appTypeCode',
        'amountFen',
        'balanceFen',
        'time',
      ].every((key) => matched[key] is int) &&
      [
        'terminalId',
        'lineStationCode',
      ].every((key) => matched[key] is String)) {
    return matched['balanceFen'] as int;
  }
  return null;
}
