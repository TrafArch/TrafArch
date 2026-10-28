import '../../transit_analysis/shanghai_balance_display.dart';
import '../data/app_database.dart';
import '../domain/archive_balance.dart';
import '../domain/card_name_extension.dart';
import '../domain/card_session_snapshot.dart';

/// Card-list/header formatting only. Captured scalars and JSON stay unchanged.
ShanghaiBalanceDisplay archiveCardBalanceDisplay(
  SavedCard card, {
  required bool includeShanghaiOverdraft,
  CardSessionSnapshot? balanceSnapshot,
}) {
  final latest = card.sessionSnapshot;
  final source = balanceSnapshot ?? retainedBalanceSnapshot(card, latest);
  final snapshot = source ?? latest;
  final context = snapshot?.context;
  if (context?.minorUnitDigits != null && context!.minorUnitDigits != 2) {
    return const ShanghaiBalanceDisplay();
  }
  return ShanghaiBalanceDisplay.forCard(
    includeShanghaiOverdraft: includeShanghaiOverdraft,
    parserId: context?.systemId,
    applicationId: context?.applicationId,
    cardType: card.cardType,
    currencyCode: source?.context.currencyCode ?? card.currencyCode,
  );
}

String? archiveCardBalanceText(
  SavedCard card, {
  required bool includeShanghaiOverdraft,
  CardSessionSnapshot? balanceSnapshot,
  String? capturedText,
}) {
  final display = archiveCardBalanceDisplay(
    card,
    includeShanghaiOverdraft: includeShanghaiOverdraft,
    balanceSnapshot: balanceSnapshot,
  );
  if (display.offsetFen == 0) return capturedText ?? card.balanceText;
  final fen = display.balanceFen(card.balanceFen);
  return fen == null
      ? capturedText ?? card.balanceText
      : const ArchiveContext(
          currencyCode: 'CNY',
          minorUnitDigits: 2,
        ).formatAmount(fen);
}
