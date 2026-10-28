import 'package:flutter/material.dart';

import 'expert_widgets.dart';
import 'expert_formatters.dart';
import '../../protocols/transit/tunion/tunion_models.dart';

class CycleProcessPanel extends StatelessWidget {
  const CycleProcessPanel({
    super.key,
    required this.records,
    required this.values,
  });
  final List<TUnionProcessRecord> records;
  final ExpertValues values;
  @override
  Widget build(BuildContext context) => _cycleProcessTile(context, records);
  Widget _cycleProcessTile(
    BuildContext context,
    List<TUnionProcessRecord> records,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return ExpansionTile(
      key: const PageStorageKey<String>('process-cycle'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      shape: const Border(),
      collapsedShape: const Border(),
      title: const Text('公共交通过程信息循环记录'),
      subtitle: Text(
        records.isEmpty ? '未写入' : '${records.length} 条',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: scheme.outline),
      ),
      children: records.isEmpty
          ? [ExpertHint('卡片未写入过程循环记录（0x1E）')]
          : [
              for (var i = 0; i < records.length; i++)
                _cycleRecordView(
                  context,
                  records[i],
                  last: i == records.length - 1,
                ),
            ],
    );
  }

  /// 单条 0x1E 循环记录（目标输出格式）：解码成功展示字段，失败展示原始数据。
  Widget _cycleRecordView(
    BuildContext context,
    TUnionProcessRecord r, {
    required bool last,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final trip = r.trip;
    final name = r.recordNumber > 0 ? '循环记录 ${r.recordNumber}' : r.recordName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(name, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                values.processRecordSubtitle(r),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.outline),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (trip != null) ...[
          ExpertField('交易类型', codeName(trip.typeCode, trip.typeName)),
          ExpertField('终端编号', trip.terminalId),
          ExpertField('应用分类码', codeName(trip.appTypeCode, trip.appTypeName)),
          ExpertField('线路', expertValue(trip.lineCode)),
          ExpertField('站点', expertValue(trip.stationCode)),
          ExpertField('运营代码', expertValue(trip.operatorCode)),
          ExpertField('交易金额', values.amountCell(trip.amountFen)),
          ExpertField('记录余额', values.balanceCell(trip.balanceFen)),
          ExpertField('交易日期时间', dateTimeDigits(trip.time)),
          ExpertField('受理方城市代码', values.cityCell(trip.cityCode)),
          ExpertField('受理方机构标识', hexLower(trip.acquirerId)),
        ] else ...[
          ExpertField('字节数', '${r.raw.length} 字节'),
          ExpertField('说明', '记录未写入或长度不足，未能解码为字段'),
          const SizedBox(height: 6),
          ExpertHex(r.rawHex),
        ],
        if (!last) const Divider(height: 24),
      ],
    );
  }
}
