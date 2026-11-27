import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/expert/expert_formatters.dart';
import 'package:transit_card_analyzer/features/transit_analysis/shanghai_balance_display.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';

void main() {
  test('专家记录余额扣除额度，金额与十六进制观察保持原值', () {
    final values = ExpertValues(
      currency: Currency.cny,
      cityNameOf: (_) => null,
      balanceDisplay: const ShanghaiBalanceDisplay(offsetFen: -800),
    );
    expect(values.balanceCell(800), '(00000320)0.0元');
    expect(values.balanceCell(500), '(000001f4)-3.0元');
    expect(values.amountCell(800), '(00000320)8.0元');
    expect(values.balanceCell(null), '未知');
  });
}
