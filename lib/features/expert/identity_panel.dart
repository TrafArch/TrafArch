import 'package:flutter/material.dart';

import 'expert_widgets.dart';
import '../../app/app_dependencies.dart';
import '../../protocols/transit/card_parser.dart';
import '../transit_analysis/tunion_analysis_models.dart';
import '../../protocols/transit/local/cards/shanghai_transit_union_models.dart';
import '../home/presentation/result_labels.dart';

class IdentityPanel extends StatelessWidget {
  const IdentityPanel({super.key, required this.app});
  final AppDependencies app;
  @override
  Widget build(BuildContext context) => Column(children: _identifyFields(app));
  List<Widget> _identifyFields(AppDependencies app) {
    final parsed = app.parsedCard;
    final info = app.cardInfo;
    final identity = app.analysis?.identity;
    final isTUnion = CardParserIds.isTUnionFamily(parsed?.parserId);
    final isCityUnion = parsed?.parserId == CardParserIds.cityUnion;
    final isShanghai = parsed?.parserId == CardParserIds.shanghaiTunion;
    return [
      ExpertField('解析器', parsed?.parserName ?? '—'),
      ExpertField(
        '选中 AID',
        (parsed == null || parsed.selectedAidHex.isEmpty)
            ? '—'
            : parsed.selectedAidHex,
      ),
      // 交通联合应用：交通联合解析器专属字段，仅在命中时展示
      if (isTUnion) ExpertField('交通联合应用', '已发现'),
      if (isShanghai) ...[
        ExpertField(
          '上海交通卡识别状态',
          app.shanghaiTransitUnion?.status.label ?? '未知',
        ),
        ExpertField('TU 应用', app.shanghaiTransitUnion?.tu.stateText ?? '未知'),
        ExpertField('CU 应用', app.shanghaiTransitUnion?.cu.stateText ?? '未知'),
        if (app.shanghaiTransitUnion?.matchedPrefix != null)
          ExpertField('辅助前缀', app.shanghaiTransitUnion!.matchedPrefix!),
      ],
      // 城市一卡通应用：城市一卡通解析器命中，或同一张卡上附带住建部
      // 应用时展示（后者标注「双应用卡」）。
      if (isCityUnion || app.cityUnionFiles.isNotEmpty)
        ExpertField(
          '城市一卡通应用',
          parsed?.dualApplication == true ? '已发现（双应用卡）' : '已发现',
        ),
      ExpertField(
        '识别城市',
        identity?.cityName ?? app.cityUnionCard?.city ?? '未知',
      ),
      ExpertField('卡种', identity?.cardFamily ?? '未知'),
      ExpertField(
        '卡片名称',
        transitDisplayName(
          parserId: parsed?.parserId,
          identifiedName:
              app.lastIdentified?.displayName ??
              app.cardPrefixByIssuerId(info?.issuerId)?.cardName ??
              app.cityUnionCard?.cardName,
          localName: parsed?.localCard?.info.cardKindLabel,
        ),
      ),
      for (final e in identity?.evidence ?? const <Evidence>[])
        ExpertField(
          e.source,
          '${e.detail}${e.weight > 0 ? '（权重 ${e.weight}）' : ''}',
        ),
    ];
  }
}
