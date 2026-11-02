import '../../protocols/transit/card_parser.dart';
import '../archive/domain/card_types.dart';

/// Display-only balance adjustment. Captured balances and transaction amounts
/// remain unchanged so settings can be toggled without cumulative deductions.
class ShanghaiBalanceDisplay {
  const ShanghaiBalanceDisplay({
    this.offsetFen = 0,
    this.isCityUnionBalance = false,
  });

  final int offsetFen;
  final bool isCityUnionBalance;

  factory ShanghaiBalanceDisplay.forCard({
    required bool includeShanghaiOverdraft,
    String? parserId,
    String? cardType,
    String? applicationId,
    String? currencyCode,
  }) {
    // CU already reports the cash balance without the allowance. The Shanghai
    // merged parser can also carry CU-only info, so its actual AID takes
    // precedence over the parser ID or the saved product type.
    final aid = applicationId?.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    final isCityUnionBalance =
        parserId == CardParserIds.cityUnion || aid == 'A00000000386980701';
    final isShanghaiTransitUnion =
        !isCityUnionBalance &&
        (parserId == CardParserIds.shanghaiTunion ||
            cardType == CardTypes.shanghaiTransitUnion);
    final excludeOverdraft =
        !includeShanghaiOverdraft &&
        currencyCode == 'CNY' &&
        isShanghaiTransitUnion;
    return ShanghaiBalanceDisplay(
      offsetFen: excludeOverdraft ? -800 : 0,
      isCityUnionBalance: isCityUnionBalance,
    );
  }

  int? balanceFen(int? raw) => raw == null ? null : raw + offsetFen;

  String? formatBalance(int? raw, {String symbol = '¥'}) {
    final displayed = balanceFen(raw);
    return displayed == null
        ? null
        : '$symbol${(displayed / 100).toStringAsFixed(2)}';
  }
}
