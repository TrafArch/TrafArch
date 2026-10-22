import 'package:flutter/material.dart';

import 'expert_widgets.dart';
import 'expert_formatters.dart';
import '../../protocols/transit/tunion/tunion_models.dart';

class BusProcessPanel extends StatelessWidget {
  const BusProcessPanel({
    super.key,
    required this.record,
    required this.values,
  });
  final TUnionProcessRecord? record;
  final ExpertValues values;
  @override
  Widget build(BuildContext context) => _busProcessTile(context, record);
  Widget _busProcessTile(BuildContext context, TUnionProcessRecord? record) {
    final scheme = Theme.of(context).colorScheme;
    final bus = record?.busTransit;
    return ExpansionTile(
      key: const PageStorageKey<String>('process-var-2'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      shape: const Border(),
      collapsedShape: const Border(),
      title: const Text('公共汽电车应用信息记录'),
      subtitle: Text(
        record == null ? '未写入' : busRecordSubtitle(record),
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: scheme.outline),
      ),
      children: record == null
          ? [ExpertHint('卡片未写入该记录（0x1A 记录 2）')]
          : bus != null
          ? _busTransitFields(bus)
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

  List<Widget> _busTransitFields(BusTransitRecord rec) {
    return [
      ExpertField('交易状态', codeName(rec.statusCode, rec.statusName)),
      ExpertField('上车城市代码', values.cityCell(rec.entryCityCode)),
      ExpertField('上车机构标识', hexLower(rec.entryAgencyId)),
      ExpertField('上车运营商代码', hexLower(rec.entryOperatorCode)),
      ExpertField('上车线路号', hexLower(rec.entryLineCode)),
      ExpertField('上车站点', hexLower(rec.entryStationCode)),
      ExpertField('上车车辆号', hexLower(rec.entryVehicleId)),
      ExpertField('上车终端编号', hexLower(rec.entryTerminalId)),
      ExpertField('上车时间', bcdTimeCell(rec.entryTime, rec.entryTimeBcd)),
      ExpertField('标注金额', values.amountCell(rec.annotateAmountFen)),
      ExpertField('方向标识', rec.directionName),
      ExpertField('下车城市代码', values.cityCell(rec.exitCityCode)),
      ExpertField('下车机构标识', hexLower(rec.exitAgencyId)),
      ExpertField('下车运营商代码', hexLower(rec.exitOperatorCode)),
      ExpertField('下车线路号', hexLower(rec.exitLineCode)),
      ExpertField('下车站点', hexLower(rec.exitStationCode)),
      ExpertField('下车车辆号', hexLower(rec.exitVehicleId)),
      ExpertField('下车终端编号', hexLower(rec.exitTerminalId)),
      ExpertField('下车时间', bcdTimeCell(rec.exitTime, rec.exitTimeBcd)),
      ExpertField('交易金额', values.amountCell(rec.transactionAmountFen)),
      ExpertField('乘车里程', intHexCell(rec.mileage)),
      if (rec.hasIssuerCustomData)
        ExpertField('发卡机构自定义', hexLower(rec.issuerCustomHex)),
    ];
  }
}
