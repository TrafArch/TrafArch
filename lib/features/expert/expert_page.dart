import 'package:flutter/material.dart';

import '../../protocols/transit/card_parser.dart';
import '../../shared/presentation/application_evidence_panel.dart';
import '../qr/presentation/qr_action_button.dart';
import '../../app/app_dependencies.dart';
import '../home/presentation/felica_summary_panel.dart';
import '../home/presentation/transit_summary_panel.dart';
import '../settings/presentation/settings_action_button.dart';
import 'city_union_panel.dart';
import 'compliance_panel.dart';
import 'expert_formatters.dart';
import 'expert_widgets.dart';
import 'identity_panel.dart';
import 'macau_pass_panel.dart';
import 'raw_data_panel.dart';
import 'tunion_panel.dart';
import '../recovery/recovery_result_panel.dart';

/// Tab composition for the latest read. Protocol fields belong to leaf panels.
class ExpertPage extends StatelessWidget {
  const ExpertPage({super.key, required this.app});
  final AppDependencies app;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: app,
    builder: (context, _) => _buildResult(context),
  );

  Widget _buildResult(BuildContext context) {
    if (app.recoveredCapture != null) {
      return SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
          children: [
            const Text('专家分析 · 上次读取'),
            RecoveryResultPanel(app: app, showProbeDetails: true),
          ],
        ),
      );
    }
    final sections = ExpertReadSections(app);
    return SafeArea(
      top: false,
      child: DefaultTabController(
        key: ValueKey('expert-tabs-${sections.tabs.length}'),
        length: sections.tabs.length,
        child: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverAppBar(
              title: const Text('专家分析'),
              pinned: true,
              actions: [
                QrActionButton(app: app),
                SettingsActionButton(app: app),
              ],
              bottom: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  for (final section in sections.tabs) Tab(text: section.label),
                ],
              ),
            ),
          ],
          body: TabBarView(
            children: [
              for (final section in sections.tabs)
                ExpertTabBody(
                  storageKey: section.storageKey,
                  hasResult: app.lastResult != null,
                  showReadHint: section != ExpertReadTab.information,
                  children: sections.content(context, section),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum ExpertReadTab {
  information('信息获取', 'expert-info-get'),
  transit('交通数据解析', 'expert-parsed'),
  compliance('JT/T 978 符合性', 'expert-compliance'),
  raw('APDU / Raw Data', 'expert-apdu');

  const ExpertReadTab(this.label, this.storageKey);
  final String label;
  final String storageKey;
}

class ExpertReadSections {
  const ExpertReadSections(this.app);
  final AppDependencies app;

  List<ExpertReadTab> get tabs => [
    ExpertReadTab.information,
    ExpertReadTab.transit,
    if (CardParserIds.isTUnionFamily(app.parsedCard?.parserId))
      ExpertReadTab.compliance,
    ExpertReadTab.raw,
  ];

  List<Widget> content(BuildContext context, ExpertReadTab section) =>
      switch (section) {
        ExpertReadTab.information => _information(context),
        ExpertReadTab.transit => _transitPanels(context),
        ExpertReadTab.compliance => [
          CompliancePanel(
            analysis: app.analysis,
            balanceDisplay: app.balanceDisplay,
          ),
        ],
        ExpertReadTab.raw => [
          RawDataPanel(
            apduLog: app.apduLog,
            processRecords: app.transitProcessRecords,
          ),
        ],
      };

  List<Widget> _information(BuildContext context) {
    if (app.parsedCard == null &&
        app.felicaResult == null &&
        (app.parsing || app.lastResult == null)) {
      return const [ExpertHomeHint('尚未读取卡片，请先在首页贴卡读取')];
    }
    final felica = app.felicaResult;
    final local = app.localReadResult;
    return [
      if (app.isOctopusCard && felica != null && app.parsedCard == null)
        TransitSummaryPanel(app: app)
      else if (felica != null && app.parsedCard == null)
        FelicaSummaryPanel(felica: felica, stations: app.suicaStations)
      else if (local != null && local.info.isMacauPass)
        MacauPassPanel(result: local)
      else
        IdentityPanel(app: app),
      if (app.lastResult != null) ...[
        const Divider(height: 32),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '机构信息',
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(color: Theme.of(context).colorScheme.primary),
          ),
        ),
        const SizedBox(height: 4),
        ExpertField('芯片提供机构', app.cardProviders?.chip.displayText ?? '未提供'),
        ExpertField('IC卡提供机构', app.cardProviders?.icCard.displayText ?? '未提供'),
      ],
      if (app.applications.isNotEmpty) ...[
        const Divider(height: 32),
        ApplicationEvidencePanel(applications: app.applications),
      ],
    ];
  }

  List<Widget> _transitPanels(BuildContext context) {
    final parsed = app.parsedCard;
    if (parsed == null) {
      return [
        ExpertHint(
          app.lastResult == null
              ? '尚未读取卡片，读取成功后将展示交通数据字段'
              : '未发现受支持的交通应用，暂无交通数据字段',
        ),
      ];
    }
    if (CardParserIds.isTUnionFamily(parsed.parserId)) {
      return [
        TunionPanel(
          parsed: parsed,
          analysis: app.analysis,
          processRecords: app.transitProcessRecords,
          fallbackRail: app.railTransitRecord,
          values: ExpertValues(
            currency: app.cardCurrency,
            balanceDisplay: app.balanceDisplay,
            cityNameOf: app.cityNameOf,
          ),
        ),
        if (parsed.parserId == CardParserIds.lingnanTunion &&
            parsed.localCard != null)
          LingnanTransactionPanel(result: parsed.localCard!),
        if (parsed.cityUnionFiles.isNotEmpty) ...[
          const Divider(height: 32),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '城市一卡通应用（双应用 · 住建部 CJ/T 331-2016）',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
          ),
          const SizedBox(height: 4),
          ExpertField(
            '城市一卡通钱包余额',
            parsed.cityUnionBalanceFen == null
                ? '未知'
                : '${(parsed.cityUnionBalanceFen! / 100).toStringAsFixed(2)} 元',
          ),
          CityUnionPanel(
            files: app.cityUnionFiles,
            resolveStationName: app.resolveCuStationName,
            busLookupEnabled: true,
          ),
        ],
      ];
    }
    if (parsed.parserId == CardParserIds.lingnanTong &&
        parsed.localCard != null) {
      return [LingnanTransactionPanel(result: parsed.localCard!)];
    }
    if (parsed.parserId == CardParserIds.cityUnion) {
      return [
        ExpertField(
          '余额',
          app.balanceDisplay.formatBalance(
                parsed.info.balanceFen,
                symbol: app.cardCurrency.symbol,
              ) ??
              '未知',
        ),
        CityUnionPanel(
          files: app.cityUnionFiles,
          resolveStationName: app.resolveCuStationName,
          busLookupEnabled: true,
        ),
      ];
    }
    return const [ExpertHint('当前解析器暂未提供交通数据字段视图')];
  }
}
