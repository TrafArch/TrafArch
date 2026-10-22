import 'package:flutter/material.dart';

import 'expert_widgets.dart';
import 'expert_formatters.dart';
import '../../protocols/transit/city_union/city_union_models.dart';
import '../reference_data/data/city_union_lookup_rules.dart';

typedef CuStationNameLookup = String? Function(
  String? terminal, {
  String? cityCode,
  int? decodedCarrierType,
  DateTime? transactionTime,
  bool busLookupEnabled,
});

class CityUnionPanel extends StatelessWidget {
  const CityUnionPanel({
    super.key,
    required this.files,
    required this.resolveStationName,
    this.terminalProfile = CuLocalTerminalProfile.standard,
    this.busLookupEnabled = false,
  });
  final List<CityUnionFileView> files;
  final CuStationNameLookup resolveStationName;
  final CuLocalTerminalProfile terminalProfile;
  final bool busLookupEnabled;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: _cityUnionTransitFields(context),
  );
  List<Widget> _cityUnionTransitFields(BuildContext context) {
    if (files.isEmpty) {
      return [
        ExpertHint(
          '已命中城市一卡通应用，但未读取到标准文件数据'
          '（0x15 / 0x18 / 0x1A）',
        ),
      ];
    }
    final public = files.where((f) => f.sfi == 0x15).toList();
    final local = files.where((f) => f.sfi == 0x18).toList();
    final recharge = files.where((f) => f.sfi == 0x1A).toList();
    // CU 城市代码（0x15 字节 03-04 HEX 解码 4 位）：用于终端索引同地区优先匹配。
    final cuCityCode = public
        .whereType<CjT331PublicInfo>()
        .firstOrNull
        ?.cityCode;

    return [
      ExpertField('已读取文件视图', '${files.length} 项'),
      const Divider(height: 28),
      _cjPublicInfoSection(context, public),
      _cjRecordGroupTile(
        context,
        title: '电子钱包本地消费交易明细（0x18）',
        storageKey: 'cj-local',
        records: local,
        cityCode: cuCityCode,
        emptyHint: '未读取到本地消费交易明细（文件不存在或记录未写入）',
      ),
      _cjRecordGroupTile(
        context,
        title: '电子钱包充值交易明细（0x1A）',
        storageKey: 'cj-recharge',
        records: recharge,
        emptyHint: '未读取到充值交易明细（文件不存在或记录未写入）',
      ),
    ];
  }

  /// 公共应用基本信息文件（0x15）：直接按字段视图展示
  /// （原始值 / 解码值 / 说明 / 异常）与原始数据；未读取到时给出提示。
  Widget _cjPublicInfoSection(
    BuildContext context,
    List<CityUnionFileView> views,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final view = views.isEmpty ? null : views.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '公共应用基本信息文件（0x15）',
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(color: scheme.primary),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            view == null
                ? '未读取到'
                : view.fields.isEmpty
                ? '未按标准解析（保留原始数据）'
                : '已解析 · ${view.fields.length} 字段',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.outline),
          ),
        ),
        if (view == null)
          ExpertHint('未读取到公共应用基本信息文件（文件不存在或读取被拒）')
        else ...[
          if (view.fields.isEmpty)
            for (final e in view.errors) ExpertHint(e)
          else
            for (final f in view.fields) ExpertField(f.name, cuFieldValue(f)),
          const SizedBox(height: 6),
          ExpertHex(view.rawHex),
        ],
      ],
    );
  }

  /// 记录文件子菜单（0x18 / 0x1A）：展开后逐条展示记录字段视图。
  Widget _cjRecordGroupTile(
    BuildContext context, {
    required String title,
    required String storageKey,
    required List<CityUnionFileView> records,
    required String emptyHint,
    String? cityCode,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ExpansionTile(
      key: PageStorageKey<String>(storageKey),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text(title),
      subtitle: Text(
        records.isEmpty ? '未读取到' : '${records.length} 条',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: scheme.outline),
      ),
      children: records.isEmpty
          ? [ExpertHint(emptyHint)]
          : [
              for (var i = 0; i < records.length; i++)
                _cjRecordView(
                  context,
                  i,
                  records[i],
                  last: i == records.length - 1,
                  cityCode: cityCode,
                ),
            ],
    );
  }

  /// 单条 City Union 记录视图：字段列表 + 原始数据；布局不符的记录
  /// 展示解析器给出的原因并保留原始字节（不猜测字段值）。本地消费
  /// （0x18）记录附带按交易终端编号经 terminal_index 解析的站点名。
  Widget _cjRecordView(
    BuildContext context,
    int index,
    CityUnionFileView record, {
    required bool last,
    String? cityCode,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final stationName = _cuStationName(record, cityCode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '记录 ${index + 1}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                cuRecordSubtitle(record),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.outline),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (record.fields.isEmpty)
          for (final e in record.errors) ExpertHint(e)
        else
          for (final f in record.fields) ExpertField(f.name, cuFieldValue(f)),
        if (stationName != null) ExpertField('站点（终端解析）', stationName),
        const SizedBox(height: 6),
        ExpertHex(record.rawHex),
        if (!last) const Divider(height: 24),
      ],
    );
  }

  /// CU 本地消费记录（0x18）→ 站点名：以交易终端编号经 CU terminal_index
  String? _cuStationName(CityUnionFileView record, String? cityCode) {
    if (record is CjT331WalletLocalConsumption) {
      final identity = CityUnionLookupRules.identifyTerminal(
        record.terminalNumber,
        cardCityCode: cityCode,
        profile: terminalProfile,
      );
      if (identity == null) return null;
      return resolveStationName(
        identity.terminal,
        cityCode: identity.regionCode,
        decodedCarrierType: identity.carrier,
        transactionTime: CityUnionLookupRules.transactionTime(
          record.transactionDate,
          record.transactionTime,
        ),
        busLookupEnabled: busLookupEnabled,
        // CJ/T331 instruction 06/09 never supplies the dictionary carrier.
      );
    }
    return null;
  }
}
