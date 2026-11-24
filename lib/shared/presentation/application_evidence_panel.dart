import 'package:flutter/material.dart';

import '../../protocols/transit/multiapp/application_evidence.dart';
import '../../protocols/transit/local/local_card_models.dart';

List<String> applicationObservationText(ApplicationEvidence application) {
  final wallet = application.payload;
  final local = wallet is ReadResult ? wallet : null;
  final info = local?.info;
  final number = application.cardNumber ?? info?.displayCardNumber;
  final balance = application.balanceFen ?? info?.observedBalance;
  final isWallet = switch (application.appId) {
    'lingnan_appy' || 'mot_bmac' || 'tuCash' => false,
    'df1001' => local != null,
    _ => true,
  };
  final slots = local?.extras.slots;
  return [
    if (number != null) '卡号 $number',
    if (info?.isSuxin == true && info!.cardNumber.isNotEmpty)
      '原始卡号 ${info.cardNumber}',
    if (info?.isCika == true)
      info!.observedRemainingTrips == null
          ? '剩余次数未知'
          : '剩余 ${info.observedRemainingTrips} 次'
    else if (isWallet && balance != null)
      '余额 $balance 分'
    else if (isWallet && application.confirmed)
      '余额未知',
    if (info?.expiryDate case final date?)
      '有效期至 ${date.toIso8601String().split('T').first}',
    if (slots?['suxin.statsDate'] case final String date)
      '统计日期 ${date.split('T').first}',
    if (slots?['suxin.statsCount'] case final int count) '统计次数 $count 次',
    if (slots?['tft.statsMonth'] case final int month) '统计月份 $month',
    if (slots?['tft.statsCount'] case final int count) '统计次数 $count 次',
    if (slots?['tft.statsAmountFen'] case final int amount) '统计金额 $amount 分',
    if (slots?['tft.monthlyCounts'] case final Map counts)
      for (final e in counts.entries) '${e.key} · ${e.value} 次',
    if (application.recordCount > 0) '${application.recordCount} 条记录',
    if (application.state == ApplicationProbeState.confirmed) '尚未读到应用数据',
    if (application.state == ApplicationProbeState.selectRejected) '选择被拒绝',
  ];
}

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
              style: Theme.of(context).textTheme.titleSmall
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
    final details = applicationObservationText(application);
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
                for (final note in application.notes.where(
                  (note) => note != application.readError?.toString(),
                ))
                  Text(note, style: Theme.of(context).textTheme.bodySmall),
                if (application.rawRecords.isNotEmpty)
                  TextButton(
                    onPressed: () => _showRecords(context, application),
                    child: const Text('查看记录原码'),
                  ),
                if (application.readError case final error?)
                  Text(
                    '$error',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.error),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void _showRecords(BuildContext context, ApplicationEvidence application) {
  final records = application.rawRecords.toList();
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${application.displayName} · 记录原码'),
      content: SizedBox(
        width: 420,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: records.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, index) {
            final row = records[index];
            return SelectableText(
              [if (row.source.isNotEmpty) row.source, row.rawHex].join('\n'),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
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
