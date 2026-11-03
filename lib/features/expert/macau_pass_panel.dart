import 'package:flutter/material.dart';

import '../../protocols/transit/local/local_card_models.dart';
import 'expert_formatters.dart';
import 'expert_widgets.dart';

class MacauPassPanel extends StatelessWidget {
  const MacauPassPanel({super.key, required this.result});

  final ReadResult result;

  @override
  Widget build(BuildContext context) {
    final info = result.info;
    final records = result.records
        .where((record) => record.label == '澳门通交易记录')
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExpertField('卡种', info.cardKindLabel),
        const ExpertField('识别状态', '澳门通钱包应用已确认'),
        ExpertField('卡号', info.cardNumber.isEmpty ? '未知' : info.cardNumber),
        ExpertField('发卡地', '未读取'),
        ExpertField('卡种细分', '未读取'),
        ExpertField(
          '余额',
          info.observedBalance == null
              ? '未读取到'
              : 'MOP \$${info.observedBalance}',
        ),
        const ExpertField('有效期至', '未读取'),
        const ExpertField('交通联合状态', '未提供（澳门通钱包应用字段）'),
        ExpertField('交易记录', '${records.length} 条'),
        const Divider(height: 28),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '钱包交易记录',
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(color: Theme.of(context).colorScheme.primary),
          ),
        ),
        if (records.isEmpty)
          const ExpertHint('未读取到交易记录')
        else
          for (final record in records) ...[
            ExpertField(
              '记录 ${record.recordNumber}',
              expertTime(
                record.timestamp.millisecondsSinceEpoch == 0
                    ? null
                    : record.timestamp,
              ),
            ),
            ExpertField('交易字段', '金额、类型和终端字段尚未完成可靠解码'),
            if (record.rawBody != null)
              Align(
                alignment: Alignment.centerLeft,
                child: ExpertHex(
                  record.rawBody!
                      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
                      .join(' ')
                      .toUpperCase(),
                ),
              ),
          ],
      ],
    );
  }
}
