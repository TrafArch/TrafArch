import 'package:flutter/material.dart';

import 'expert_widgets.dart';
import 'expert_formatters.dart';
import '../../protocols/transit/tunion/tunion_models.dart';

class RailProcessPanel extends StatelessWidget {
  const RailProcessPanel({
    super.key,
    required this.record,
    required this.values,
    this.fallback,
  });
  final TUnionProcessRecord? record;
  final TransitRecord? fallback;
  final ExpertValues values;
  @override
  Widget build(BuildContext context) => _railProcessTile(context, record);
  Widget _railProcessTile(BuildContext context, TUnionProcessRecord? record) {
    final scheme = Theme.of(context).colorScheme;
    final transit = record?.railTransit ?? fallback;
    return ExpansionTile(
      key: const PageStorageKey<String>('process-var-1'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      shape: const Border(),
      collapsedShape: const Border(),
      title: const Text('城市轨道应用信息记录'),
      subtitle: Text(
        record == null ? '未写入' : railRecordSubtitle(record, projected: transit),
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: scheme.outline),
      ),
      children: record == null
          ? [ExpertHint('卡片未写入该记录（0x1A 记录 1）')]
          : transit != null
          ? _railTransitFields(transit)
          : _rawFallback(record),
    );
  }

  List<Widget> _rawFallback(TUnionProcessRecord record) {
    return [
      ExpertField('数据长度', '${record.raw.length} 字节'),
      const SizedBox(height: 6),
      ExpertHex(record.rawHex),
      const SizedBox(height: 6),
      ExpertHint('记录长度不足或字段布局不符，未做推测解析，按原始数据展示'),
    ];
  }

  List<Widget> _railTransitFields(TransitRecord rec) {
    return [
      ExpertField('交易状态', codeName(rec.statusCode, rec.statusName)),
      ExpertField('进闸城市代码', values.cityCell(rec.entryCityCode)),
      ExpertField('出闸城市代码', values.cityCell(rec.exitCityCode)),
      ExpertField('进闸机构标识', hexLower(rec.entryAgencyId)),
      ExpertField('出闸机构标识', hexLower(rec.exitAgencyId)),
      ExpertField('进闸站点', hexLower(rec.entryStationId)),
      ExpertField('出闸站点', hexLower(rec.exitStationId)),
      ExpertField('进闸终端编号', hexLower(rec.entryTerminalId)),
      ExpertField('出闸终端编号', hexLower(rec.exitTerminalId)),
      ExpertField('进站时间', bcdTimeCell(rec.entryTime, rec.entryTimeBcd)),
      ExpertField('出站时间', bcdTimeCell(rec.exitTime, rec.exitTimeBcd)),
      ExpertField('标注金额', values.amountCell(rec.annotateAmountFen)),
      ExpertField('入站线路号', hexByteCell(rec.entryLineCode)),
      ExpertField('出站线路号', hexByteCell(rec.exitLineCode)),
      ExpertField('进站交易金额', values.amountCell(rec.entryAmountFen)),
      ExpertField('进站钱包余额', values.amountCell(rec.entryBalanceFen)),
      ExpertField('出闸交易金额', values.amountCell(rec.exitAmountFen)),
      if (rec.issuerCustom != null)
        ExpertField('发卡机构自定义', hexLower(rec.issuerCustom)),
    ];
  }
}
