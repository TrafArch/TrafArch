import '../../../protocols/transit/card_parser.dart';
import '../../../protocols/felica/felica.dart';
import '../../../protocols/transit/local/cards/shanghai_transit_union_models.dart';
import '../../../protocols/bank/domain/models/bank_card_result.dart';

sealed class CardReadOutcome {
  const CardReadOutcome();
}

final class TransitReadOutcome extends CardReadOutcome {
  const TransitReadOutcome(this.card, {this.shanghai});
  final ParsedCard card;
  final ShanghaiTransitUnionResult? shanghai;
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
