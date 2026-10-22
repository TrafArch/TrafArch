import 'package:flutter/material.dart';

import '../transit_analysis/tunion_analysis_models.dart';
import 'expert_widgets.dart';

class CompliancePanel extends StatelessWidget {
  const CompliancePanel({super.key, required this.analysis});
  final CardAnalysisResult? analysis;
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
                  item.detail,
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
