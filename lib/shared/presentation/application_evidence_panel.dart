import 'package:flutter/material.dart';

import '../../protocols/transit/multiapp/application_evidence.dart';

/// 逐应用探测状态的中文标签（实时专家页与恢复现场共用）。
String applicationProbeStateLabel(ApplicationProbeState state) =>
    switch (state) {
      ApplicationProbeState.notProbed => '未探测',
      ApplicationProbeState.selectRejected => '应用未确认',
      ApplicationProbeState.confirmed => '已确认',
      ApplicationProbeState.readSucceeded => '读取成功',
      ApplicationProbeState.partial => '部分读取',
      ApplicationProbeState.failed => '失败',
    };

/// 一芯多应用并列展示：每个应用一行，状态、身份、余额与记录数按应用独立。
///
/// 实时结果与恢复现场捕获快照均可消费同一组件；空列表渲染为空。
class ApplicationEvidencePanel extends StatelessWidget {
  const ApplicationEvidencePanel({
    super.key,
    required this.applications,
    this.title = '逐应用探测',
  });

  final List<ApplicationEvidence> applications;
  final String title;

  @override
  Widget build(BuildContext context) {
    if (applications.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: colors.primary),
            ),
            for (final application in applications)
              _ApplicationRow(application: application),
          ],
        ),
      ),
    );
  }
}

class _ApplicationRow extends StatelessWidget {
  const _ApplicationRow({required this.application});
  final ApplicationEvidence application;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final details = <String>[
      if (application.cardNumber case final cardNumber?)
        '卡号 $cardNumber',
      if (application.balanceFen case final balance?)
        '余额 $balance 分',
      if (application.recordCount > 0)
        '${application.recordCount} 条记录',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Icon(
              Icons.circle,
              size: 10,
              color: _stateColor(application.state, colors),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${application.displayName} · '
                  '${applicationProbeStateLabel(application.state)}',
                ),
                if (details.isNotEmpty)
                  Text(
                    details.join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (application.readError case final error?)
                  Text(
                    '$error',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.error,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Color _stateColor(ApplicationProbeState state, ColorScheme colors) =>
    switch (state) {
      ApplicationProbeState.notProbed => colors.outlineVariant,
      ApplicationProbeState.selectRejected => colors.outline,
      ApplicationProbeState.confirmed => colors.tertiary,
      ApplicationProbeState.readSucceeded => Colors.green.shade600,
      ApplicationProbeState.partial => colors.tertiary,
      ApplicationProbeState.failed => colors.error,
    };
