import 'package:flutter/material.dart';

import 'expert_widgets.dart';
import 'expert_formatters.dart';
import '../../protocols/transit/card_parser.dart';
import '../transit_analysis/tunion_analysis_models.dart';
import '../transit_analysis/balance_interpretation.dart';
import '../../protocols/transit/tunion/tunion_models.dart';
import 'rail_process_panel.dart';
import 'bus_process_panel.dart';
import 'cycle_process_panel.dart';

class TunionPanel extends StatelessWidget {
  const TunionPanel({
    super.key,
    required this.parsed,
    required this.analysis,
    required this.processRecords,
    required this.fallbackRail,
    required this.values,
  });
  final ParsedCard parsed;
  final CardAnalysisResult? analysis;
  final List<TUnionProcessRecord> processRecords;
  final TransitRecord? fallbackRail;
  final ExpertValues values;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: _tunionTransitFields(context),
  );
  List<Widget> _tunionTransitFields(BuildContext context) {
    final info = parsed.info;
    final wallet = analysis?.wallet;
    final balance = BalanceInterpretation.fromParsedCard(parsed);
    final trips = analysis?.trips ?? const <TransitTrip>[];
    final firstTrip = trips.isEmpty ? null : trips.first;
    final varRecords = processRecords.where((r) => r.sfi == 0x1A).toList();
    final cycleRecords = processRecords.where((r) => r.sfi == 0x1E).toList();
    // 过程记录仅保留三类：0x1A 记录 1（城市轨道应用信息记录）、记录 2（公共
    // 汽电车应用信息记录）与全部 0x1E 过程循环记录，其余变长记录不在界面展示。
    TUnionProcessRecord? railRecord;
    TUnionProcessRecord? busRecord;
    TUnionProcessRecord? wholeVarBlob;
    for (final r in varRecords) {
      if (r.recordNumber == 1) {
        railRecord = r;
      } else if (r.recordNumber == 2) {
        busRecord = r;
      } else if (r.recordNumber == 0) {
        wholeVarBlob = r;
      }
    }
    // The scan projection computes the whole-file rail fallback once.
    // Keep its original blob for inspection even when the field view is absent.
    return [
      ExpertField('逻辑卡号', expertValue(info.displayCardNumber)),
      ExpertField('发卡机构标识', expertValue(info.issuerId)),
      ExpertField('应用类型标识', expertValue(info.appTypeId)),
      ExpertField('应用版本', expertValue(info.appVersion)),
      ExpertField('生效日期', expertDate(info.effectiveDate)),
      ExpertField('失效日期', expertDate(info.expireDate)),
      ExpertField('发卡机构 FCI', expertValue(info.issuerFci)),
      ExpertField('国际代码', expertValue(info.countryCode)),
      ExpertField('省级代码', expertValue(info.provinceCode)),
      ExpertField('城市代码', expertValue(info.cityCode)),
      ExpertField('互通卡种', expertValue(info.interopCardType)),
      ExpertField('卡种类型', expertValue(info.cardKind)),
      ExpertField(
        '余额',
        balance.semantics == BalanceSemantics.direct ||
                values.balanceDisplay.isCityUnionBalance
            ? values.balanceDisplay.formatBalance(
                    wallet?.balanceFen,
                    symbol: values.currency.symbol,
                  ) ??
                  '未知'
            : balance.accountBalanceText,
      ),
      if (balance.semantics != BalanceSemantics.direct &&
          !values.balanceDisplay.isCityUnionBalance &&
          balance.observedBalanceText != null)
        ExpertField(balance.observationLabel, balance.observedBalanceText!),
      ExpertField('剩余有效天数', daysRemainingText(wallet?.daysRemaining)),
      ExpertField('交易记录', '${trips.length} 条'),
      ExpertField('最近交易', expertTime(firstTrip?.time)),
      ExpertField('交易金额', firstTrip?.amountText ?? '未知'),
      ExpertField('交易类型', firstTrip?.typeName ?? '未知'),
      ExpertField('交易序号', firstTrip?.sequence.toString() ?? '未知'),
      ExpertField('终端编号', firstTrip?.terminalId ?? '未知'),
      ExpertField('终端解码', terminalDecodeText(firstTrip)),
      ExpertField(
        '过程记录',
        processRecords.isEmpty
            ? '无'
            : '${processRecords.length} 条'
                  '（0x1A ${varRecords.length} · 0x1E ${cycleRecords.length}）',
      ),
      const Divider(height: 28),
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '过程记录 · 0x1A / 0x1E',
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      ),
      if (processRecords.isEmpty)
        ExpertHint('未读取到过程记录（卡片未实现该文件、记录为空或读取条件不满足）')
      else ...[
        RailProcessPanel(
          record: railRecord ?? wholeVarBlob,
          fallback: railRecord == null ? fallbackRail : null,
          values: values,
        ),
        BusProcessPanel(record: busRecord, values: values),
        CycleProcessPanel(records: cycleRecords, values: values),
      ],
    ];
  }
}
