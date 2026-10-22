import 'package:flutter/material.dart';

import '../../../protocols/felica/models/felica_models.dart';

import 'summary_widgets.dart';
import 'summary_formatters.dart';

class FelicaSummaryPanel extends StatelessWidget {
  const FelicaSummaryPanel({super.key, required this.felica});
  final FelicaScanResult felica;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: _felicaPanel(context, felica),
  );
  List<Widget> _felicaPanel(BuildContext context, FelicaScanResult felica) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final crossBorder = felica.crossBorder;
    final now = DateTime.now();
    return [
      ...summaryNameLine(context, felica.displayName),
      summaryField(context, '识别状态', felica.stateText),
      if (felica.idm != null) summaryField(context, 'IDm', felica.idm!),
      if (felica.systemCodes.isNotEmpty)
        summaryField(context, '系统码', felica.systemCodeText),
      if (felica.transitCapability != null)
        summaryField(context, '交通功能', felica.transitCapability!),
      for (final wallet in felica.wallets)
        summaryField(
          context,
          wallet.currency.isEmpty
              ? wallet.name
              : '${wallet.name}（${wallet.currency}）',
          wallet.balanceText ?? wallet.errorMessage ?? wallet.note ?? '暂不可读取',
        ),
      if (crossBorder != null) ...[
        summaryField(
          context,
          '跨境支付',
          '${crossBorder.sourceCurrency} 钱包 → ${crossBorder.targetCurrency}'
              '（按发卡方汇率折算，不是独立 '
              '${crossBorder.targetCurrency} 钱包）',
        ),
        if (crossBorder.hasVerifiedExchangeRate &&
            !crossBorder.isExpiredAt(now))
          summaryField(
            context,
            '汇率',
            '1 ${crossBorder.sourceCurrency} = '
                '${crossBorder.exchangeRateText} '
                '${crossBorder.targetCurrency}'
                '${crossBorder.rateUpdatedAt == null ? '' : '（更新于 ${summaryDate(crossBorder.rateUpdatedAt!)}）'}',
          ),
      ],
      if (felica.wallets.length > 1)
        summaryHint(
          context,
          '双钱包产品：两个钱包需分别验证服务与读取权限，'
          '未读到的钱包不显示为 0',
        ),
      if (felica.transactions.isNotEmpty) ...[
        const SizedBox(height: 4),
        summaryField(context, '交易记录', '${felica.transactions.length} 条'),
        for (final tx in felica.transactions.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '块 ${tx.sequence ?? '-'} · ${felicaTime(tx)} · '
              '${felicaAmountText(tx, felica.wallets)}'
              '${tx.locationCode == null ? '' : ' · 终端 ${tx.locationCode}'}'
              '${tx.crossBorder ? ' · 跨境交易' : ''}'
              '${tx.decoded ? '' : ' · 未解析'}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: tx.decoded ? null : scheme.outline,
              ),
            ),
          ),
        if (felica.transactions.length > 5)
          summaryHint(context, '仅展示最近 5 条，完整记录见原始数据块'),
      ],
      if (felica.statuses.isNotEmpty) ...[
        const SizedBox(height: 4),
        for (final status in felica.statuses)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '· ${status.stage}：${status.state.label} — ${status.message}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: status.state.isFailure ? scheme.error : scheme.outline,
              ),
            ),
          ),
      ],
      if (felica.rawBlocks.isNotEmpty)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          shape: const Border(),
          collapsedShape: const Border(),
          title: Text(
            '原始数据块（${felica.rawBlocks.length}）',
            style: theme.textTheme.titleSmall,
          ),
          children: [
            for (final block in felica.rawBlocks)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${block.label}：'
                    '${block.isSuccess ? block.hex : '读取失败（${block.error}）'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
          ],
        ),
    ];
  }
}
