import '../../transit_analysis/tunion_analysis_engine.dart';
import '../../transit_analysis/cu_transaction_analysis.dart';
import '../../transit_analysis/tunion_analysis_models.dart';
import '../../transit_analysis/balance_interpretation.dart';
import '../../../protocols/transit/card_parser.dart';
import '../../reference_data/data/tunion_knowledge_base.dart';
import '../../reference_data/domain/city_union_knowledge_base.dart';
import '../../../protocols/felica/felica.dart';
import '../../../protocols/transit/city_union/city_union_models.dart';
import '../../../protocols/transit/local/local_card_models.dart';
import '../../../protocols/transit/local/cards/shanghai_transit_union_models.dart';
import '../../../protocols/transit/tunion/tunion_models.dart';
import '../../../protocols/transit/tunion/tunion_process_parser.dart';
import '../../../protocols/bank/domain/models/bank_card_result.dart';
import 'card_read_outcome.dart';

/// Immutable display projection, rebuilt once when an attempt completes.
/// Original protocol data remains available independently of derived trips.
class ScanPresentation {
  ScanPresentation(this.outcome, KnowledgeBase knowledge)
    : knowledge = knowledge,
      parsedCard = outcome is TransitReadOutcome ? outcome.card : null {
    final card = parsedCard;
    analysis = card != null && CardParserIds.isTUnionFamily(card.parserId)
        ? AnalysisEngine(knowledge).analyze(card)
        : null;
    cityUnionTransactions = analyzeCuTransactions(
      card?.cityUnionFiles ?? const [],
      knowledge,
    );
    railTransitRecord = _deriveRail();
    busTransitRecord = _deriveBus();
  }
  final CardReadOutcome outcome;
  final KnowledgeBase knowledge;
  final ParsedCard? parsedCard;
  late final CardAnalysisResult? analysis;
  late final List<CuTransactionView> cityUnionTransactions;
  late final TransitRecord? railTransitRecord;
  late final BusTransitRecord? busTransitRecord;
  TUnionCardInfo? get cardInfo => parsedCard?.info;
  List<TUnionTransaction> get transactions =>
      parsedCard?.transactions ?? const [];
  List<TUnionProcessRecord> get transitProcessRecords =>
      parsedCard?.transitProcessRecords ?? const [];
  List<TUnionTripRecord> get cycleProcessTrips => [
    for (final r in transitProcessRecords)
      if (r.sfi == 0x1E && !r.isBlank && r.trip != null) r.trip!,
  ];
  bool get tunionDetected => CardParserIds.isTUnionFamily(parsedCard?.parserId);
  bool get cityUnionDetected => parsedCard?.parserId == CardParserIds.cityUnion;
  bool get dualApplicationDetected => parsedCard?.dualApplication ?? false;
  int? get cityUnionBalanceFen => parsedCard?.cityUnionBalanceFen;
  List<CityUnionFileView> get cityUnionFiles =>
      parsedCard?.cityUnionFiles ?? const [];
  ReadResult? get localReadResult => parsedCard?.localCard;
  BankCardResult? get lastBankCardResult => switch (outcome) {
    BankReadOutcome(:final card) => card,
    _ => null,
  };
  FelicaScanResult? get felicaResult => switch (outcome) {
    FelicaReadOutcome(:final card) => card,
    _ => null,
  };
  ShanghaiTransitUnionResult? get shanghaiTransitUnion => switch (outcome) {
    TransitReadOutcome(:final shanghai) => shanghai,
    _ => null,
  };
  CjT331PublicInfo? get cityUnionPublicInfo {
    for (final file in cityUnionFiles) {
      if (file is CjT331PublicInfo) return file;
    }
    return null;
  }

  CityUnionCardInfo? get cityUnionCard => knowledge.cityUnionCards.resolveCard(
    cityCode: cityUnionPublicInfo?.cityCode,
    rawHex: cityUnionPublicInfo?.rawHex.replaceAll(' ', ''),
  );
  Currency get cardCurrency =>
      analysis?.currency ??
      Currency.fromCode(localReadResult?.info.currencyCode);
  BalanceInterpretation? get balanceInterpretation => parsedCard == null
      ? null
      : BalanceInterpretation.fromParsedCard(
          parsedCard!,
          metadataCurrency: cardCurrency.code,
        );
  String? get cardCityCode => cityUnionDetected
      ? cityUnionPublicInfo?.cityCode
      : analysis?.identity.cityCode ?? parsedCard?.info.cityCode;
  bool isRemoteUse(String? code) {
    final local = cardCityCode;
    if (local == null ||
        code == null ||
        local.replaceAll('0', '').isEmpty ||
        code.replaceAll('0', '').isEmpty) {
      return false;
    }
    return local.trim().toUpperCase() != code.trim().toUpperCase();
  }

  TransitRecord? _deriveRail() {
    TUnionProcessRecord? whole;
    for (final r in transitProcessRecords) {
      if (r.sfi != 0x1A) continue;
      if (r.recordNumber == 1) return r.isBlank ? null : r.railTransit;
      if (r.recordNumber == 0) whole = r;
    }
    return whole == null
        ? null
        : const TUnionProcessParser().parseRailTransit(1, whole.raw);
  }

  BusTransitRecord? _deriveBus() {
    for (final r in transitProcessRecords) {
      if (r.sfi == 0x1A && r.recordNumber == 2) {
        return r.isBlank ? null : r.busTransit;
      }
    }
    return null;
  }
}
