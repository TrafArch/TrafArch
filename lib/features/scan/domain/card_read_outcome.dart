import '../../../protocols/transit/card_parser.dart';
import '../../../protocols/felica/felica.dart';
import '../../../protocols/transit/multiapp/application_evidence.dart';
import '../../../protocols/transit/local/cards/shanghai_transit_union_models.dart';
import '../../../protocols/bank/domain/models/bank_card_result.dart';

sealed class CardReadOutcome {
  const CardReadOutcome();
}

final class TransitReadOutcome extends CardReadOutcome {
  const TransitReadOutcome(
    this.card, {
    this.shanghai,
    this.applications = const [],
  });
  final ParsedCard card;
  final ShanghaiTransitUnionResult? shanghai;

  /// 本次会话逐应用探测证据（TU/CU/地方钱包/银行等并列）。
  final List<ApplicationEvidence> applications;
}

final class BankReadOutcome extends CardReadOutcome {
  const BankReadOutcome(this.card);
  final BankCardResult card;
}

final class FelicaReadOutcome extends CardReadOutcome {
  const FelicaReadOutcome(this.card);
  final FelicaScanResult card;
}

final class UnsupportedReadOutcome extends CardReadOutcome {
  const UnsupportedReadOutcome();
}
