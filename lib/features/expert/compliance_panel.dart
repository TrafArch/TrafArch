import 'package:flutter/material.dart';

import '../transit_analysis/tunion_analysis_models.dart';
import '../transit_analysis/shanghai_balance_display.dart';
import 'expert_widgets.dart';

class CompliancePanel extends StatelessWidget {
  const CompliancePanel({
    super.key,
    required this.analysis,
    this.balanceDisplay = const ShanghaiBalanceDisplay(),
  });
  final CardAnalysisResult? analysis;
  final ShanghaiBalanceDisplay balanceDisplay;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      ExpertField(
        '综合覆盖度',
        analysis == null ? '—' : '${analysis!.compliance.scorePercent}%',
      ),
      for (final item in analysis?.compliance.items ?? const <ComplianceItem>[])
        _complianceRow(context, item),
    ],
  );
  Widget _complianceRow(BuildContext context, ComplianceItem item) {
    final displayedBalance = balanceDisplay.balanceFen(
      analysis?.wallet.balanceFen,
    );
    final detail =
        item.id == 'balance' &&
            balanceDisplay.offsetFen != 0 &&
            displayedBalance != null
        ? '余额 ${(displayedBalance / 100).toStringAsFixed(2)} ${analysis!.currency.unit}'
        : item.detail;
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, Color color) = switch (item.status) {
      ComplianceStatus.pass => (Icons.check_circle_outline, Colors.green),
      ComplianceStatus.warn => (Icons.warning_amber_outlined, Colors.orange),
      ComplianceStatus.fail => (Icons.cancel_outlined, scheme.error),
      ComplianceStatus.info => (Icons.info_outline, scheme.outline),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.outline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
