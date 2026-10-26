import 'package:flutter/material.dart';

import '../../protocols/transit/card_parser.dart';
import '../qr/presentation/qr_action_button.dart';
import '../../app/app_dependencies.dart';
import '../home/presentation/bank_summary_panel.dart';
import '../home/presentation/felica_summary_panel.dart';
import '../home/presentation/recent_result_selection.dart';
import '../settings/presentation/settings_action_button.dart';
import 'city_union_panel.dart';
import 'compliance_panel.dart';
import 'expert_formatters.dart';
import 'expert_widgets.dart';
import 'identity_panel.dart';
import 'raw_data_panel.dart';
import 'tunion_panel.dart';

/// Tab composition and result selection; protocol fields belong to leaf panels.
class ExpertPage extends StatefulWidget {
  const ExpertPage({super.key, required this.app});
  final AppDependencies app;
  @override
  State<ExpertPage> createState() => _ExpertPageState();
}

class _ExpertPageState extends State<ExpertPage> {
  late RecentResultSelection _selection;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    final app = widget.app;
    _selection = RecentResultSelection(
      card: app.lastResult,
      bank: app.lastBankCardResult,
    );
    app.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant ExpertPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app != widget.app) {
      oldWidget.app.removeListener(_refresh);
      _bind();
    }
  }

  @override
  void dispose() {
    widget.app.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    final app = widget.app;
    _selection.observe(card: app.lastResult, bank: app.lastBankCardResult);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final isTUnion = CardParserIds.isTUnionFamily(app.parsedCard?.parserId);
    final tabs = <Tab>[
      const Tab(text: '信息获取'),
      const Tab(text: '交通数据解析'),
      if (isTUnion) const Tab(text: 'JT/T 978 符合性'),
      const Tab(text: 'APDU / Raw Data'),
    ];
    return SafeArea(
      top: false,
      child: DefaultTabController(
        key: ValueKey('expert-tabs-${tabs.length}'),
        length: tabs.length,
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
                tabs: tabs,
              ),
            ),
          ],
          body: TabBarView(
            children: [
              _information(app),
              _tab('expert-parsed', _transitPanels(app)),
              if (isTUnion)
                _tab('expert-compliance', [
                  CompliancePanel(analysis: app.analysis),
                ]),
              _tab('expert-apdu', [
                RawDataPanel(
                  apduLog: app.apduLog,
                  processRecords: app.transitProcessRecords,
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(String key, List<Widget> children, {bool showReadHint = true}) =>
      ExpertTabBody(
        storageKey: key,
        hasResult: widget.app.lastResult != null,
        showReadHint: showReadHint,
        children: children,
      );

  Widget _information(AppDependencies app) {
    final bank = app.lastBankCardResult;
    final hasCard =
        app.parsedCard != null ||
        app.felicaResult != null ||
        (!app.parsing && app.lastResult != null && bank == null);
    final available = <RecentResultKind>[
      if (hasCard) RecentResultKind.card,
      if (bank != null) RecentResultKind.bank,
    ];
    if (available.isEmpty) {
      return _tab('expert-info-get', const [
        ExpertHomeHint('尚未读取卡片，请先在首页贴卡读取'),
        ExpertHomeHint('尚未读取银行卡：在首页贴卡读取后自动分析（交通应用未命中时按 EMV / PBOC 只读解析）'),
      ], showReadHint: false);
    }
    final kind = _selection.resolve(available);
    return _tab('expert-info-get', [
      if (available.length > 1) ...[
        SegmentedButton<RecentResultKind>(
          segments: [
            for (final item in available)
              ButtonSegment(
                value: item,
                label: Text(switch (item) {
                  RecentResultKind.card => '卡片识别',
                  RecentResultKind.bank => '银行卡',
                }),
              ),
          ],
          selected: {kind},
          showSelectedIcon: false,
          onSelectionChanged: (selection) =>
              setState(() => _selection.selected = selection.first),
        ),
        const SizedBox(height: 8),
      ],
      switch (kind) {
        RecentResultKind.card =>
          app.felicaResult != null && app.parsedCard == null
              ? FelicaSummaryPanel(felica: app.felicaResult!)
              : IdentityPanel(app: app),
        RecentResultKind.bank => BankSummaryPanel(bank: bank!, detailed: true),
      },
    ], showReadHint: false);
  }

  List<Widget> _transitPanels(AppDependencies app) {
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
            cityNameOf: app.cityNameOf,
          ),
        ),
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
    if (parsed.parserId == CardParserIds.cityUnion) {
      return [
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
