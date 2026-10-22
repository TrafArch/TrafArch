import 'dart:convert';

import '../../transit_analysis/balance_interpretation.dart';
import '../data/app_database.dart';
import 'card_session_snapshot.dart';
import 'card_types.dart';

/// Exact capture evidence plus the time at which it supplied the retained
/// balance. Payload deduplication may leave the batch's original time earlier.
class ArchiveBalanceSource {
  final String payloadJson;
  final int observedAt;
  final String? batchId;

  const ArchiveBalanceSource({
    required this.payloadJson,
    required this.observedAt,
    this.batchId,
  });

  CardSessionSnapshot? get snapshot => CardSessionSnapshot.decode(payloadJson);

  static ArchiveBalanceSource? fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['version'] != 1 ||
        value['payloadJson'] is! String ||
        value['observedAt'] is! int ||
        (value['batchId'] != null && value['batchId'] is! String)) {
      return null;
    }
    final source = ArchiveBalanceSource(
      payloadJson: value['payloadJson'] as String,
      observedAt: value['observedAt'] as int,
      batchId: value['batchId'] as String?,
    );
    return snapshotObservesBalance(source.snapshot) ? source : null;
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'payloadJson': payloadJson,
    'observedAt': observedAt,
    'batchId': batchId,
  };
}

bool snapshotObservesBalance(CardSessionSnapshot? snapshot) {
  final values = snapshot?.extensions['observations'];
  return snapshot?.context.observedFields['balanceFen'] == true &&
      values is Map<String, dynamic> &&
      values['balanceFen'] is int;
}

bool snapshotBalanceMatches(SavedCard card, CardSessionSnapshot? snapshot) {
  final values = snapshot?.extensions['observations'];
  return snapshotObservesBalance(snapshot) &&
      values is Map<String, dynamic> &&
      values['balanceFen'] == card.balanceFen &&
      values['currencyCode'] == card.currencyCode;
}

/// A source link is added only to a supported partial envelope. Its current
/// observations remain null; no historical raw capture is rewritten.
String withRetainedBalanceSource(String payload, ArchiveBalanceSource? source) {
  final decoded = CardSessionSnapshot.decodeResult(payload);
  if (decoded.formatVersion != 3 ||
      decoded.status != SnapshotDecodeStatus.supported ||
      snapshotObservesBalance(decoded.snapshot)) {
    return payload;
  }
  final json = jsonDecode(payload) as Map<String, dynamic>;
  if (source == null) {
    if (!json.containsKey('retainedBalanceSource')) return payload;
    json.remove('retainedBalanceSource');
  } else {
    json['retainedBalanceSource'] = source.toJson();
  }
  return jsonEncode(json);
}

CardSessionSnapshot? retainedBalanceSnapshot(
  SavedCard card,
  CardSessionSnapshot? latest,
) {
  if (snapshotBalanceMatches(card, latest) || card.balanceFen == null) {
    return latest;
  }
  // An explicit but inconsistent current observation must never fall through
  // to an older, coincidentally equal interpretation.
  if (snapshotObservesBalance(latest)) return null;
  final source = ArchiveBalanceSource.fromJson(
    latest?.extensions['retainedBalanceSource'],
  );
  return source != null && snapshotBalanceMatches(card, source.snapshot)
      ? source.snapshot
      : null;
}

/// An interpretation belongs to the capture that produced the retained
/// scalar amount. A later partial session cannot relabel that amount.
BalanceInterpretation? capturedBalanceInterpretation(
  SavedCard card,
  CardSessionSnapshot? snapshot,
) {
  snapshot = retainedBalanceSnapshot(card, snapshot);
  final raw = snapshot?.context.extensions['balanceInterpretation'];
  if (raw is! Map<String, dynamic>) return null;
  final interpretation = BalanceInterpretation.fromJson(raw);
  if (interpretation.observedAmountMinor != card.balanceFen ||
      interpretation.parserId != snapshot!.context.systemId ||
      interpretation.selectedAidHex.toUpperCase() !=
          (snapshot.context.applicationId ?? '').toUpperCase() ||
      (snapshot.recordProvenance.containsKey('rawApplicationSerial') &&
          interpretation.rawApplicationSerial !=
              snapshot.recordProvenance['rawApplicationSerial']) ||
      (interpretation.semantics != BalanceSemantics.unknown &&
          interpretation.observedCurrency != card.currencyCode)) {
    return null;
  }
  return interpretation;
}

/// Legacy numbers remain untouched. Product identity only prevents the old
/// scalar from being presented as a verified HKD account balance.
bool isOctopusArchiveCard(SavedCard card) {
  if (card.cardType == CardTypes.octopusTunion) return true;
  if (card.cardType != CardTypes.chinaTunion) return false;
  final serial = card.cardNumber;
  return serial != null &&
      RegExp(r'^[0-9]{8,20}$').hasMatch(serial) &&
      serial
          .replaceFirst(RegExp(r'^0+'), '')
          .startsWith(BalanceInterpretation.octopusPrefix);
}

const unknownHistoricalOctopusBalance = '港币余额未读取（历史金额口径待核验）';
