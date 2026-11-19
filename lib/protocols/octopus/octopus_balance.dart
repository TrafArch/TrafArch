/// A balance obtained from the current card, expressed in Hong Kong cents.
class OctopusBalanceResult {
  const OctopusBalanceResult({
    required this.balanceMinor,
    required this.idmHex,
    required this.readAt,
  });

  final int balanceMinor;
  final String idmHex;
  final DateTime readAt;
}

class OctopusBalanceException implements Exception {
  const OctopusBalanceException(this.message, {this.code = 'balance'});

  final String message;
  final String code;
}

/// The protocol owns polling and card identity checks; the owner supplies an
/// exclusively read-only NFC-F transport and an immediate cancellation signal.
typedef OctopusBalanceExecute = Future<OctopusBalanceResult> Function({
  required Future<List<int>> Function(List<int>) transceiveFelica,
  required bool Function() isCancelled,
  String? expectedCardIdm,
});
