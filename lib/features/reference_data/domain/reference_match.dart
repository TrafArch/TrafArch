enum ReferenceNamespace { tu, cu }

enum ReferenceMatchStatus { matched, ambiguous, unknown, unavailable }

/// Candidates retain source keys even when no unique display result is possible.
class ReferenceMatch<T> {
  ReferenceMatch(this.status, Iterable<T> candidates, {this.issue})
    : candidates = List.unmodifiable(candidates);
  final ReferenceMatchStatus status;
  final List<T> candidates;
  final String? issue;
  T? get value =>
      status == ReferenceMatchStatus.matched && candidates.isNotEmpty
      ? candidates.first
      : null;
}

/// `decodedCarrierType` is a source-dictionary carrier code, NOT the CJ/T331
/// transaction instruction byte (06/09). Unknown values remain null.
class CuLookupContext {
  const CuLookupContext({
    required this.regionCode,
    this.decodedCarrierType,
    this.transactionTime,
    this.busLookupEnabled = false,
  });
  final String regionCode;
  final int? decodedCarrierType;
  final DateTime? transactionTime;
  final bool busLookupEnabled;
}
