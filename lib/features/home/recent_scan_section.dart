import 'package:flutter/material.dart';

import 'presentation/recent_result_selection.dart';
import 'presentation/transit_summary_panel.dart';
import 'presentation/bank_summary_panel.dart';

import '../../app/app_dependencies.dart';

/// 「最近扫描」展示类型：NFC 卡片 / 银行卡只读分析。

/// 首页「最近扫描」模块（版式：模块标题 → 卡片名称 → 分隔线 → 字段列表）。
///
/// - 卡片视图按最新一次读取自动切换类型：交通联合（TU）与城市一卡通
///   （CU）按解析结果展示对应字段；交通应用未命中时自动展示 EMV / PBOC
///   银行卡只读分析结果，无需手动切换；
/// - 卡片与银行卡数据并存时由顶部分段按钮手动切换；
/// - 无任何数据时不占用页面空间（返回空尺寸）。数据获取入口在首页
///   上方模块，本模块只负责展示，不发起任何读取 / 扫描操作。
class RecentScanSection extends StatefulWidget {
  final AppDependencies app;

  const RecentScanSection({super.key, required this.app});

  @override
  State<RecentScanSection> createState() => _RecentScanSectionState();
}

class _RecentScanSectionState extends State<RecentScanSection> {
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
    app.addListener(_onAppChanged);
  }

  @override
  void didUpdateWidget(covariant RecentScanSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app != widget.app) {
      oldWidget.app.removeListener(_onAppChanged);
      _bind();
    }
  }

  @override
  void dispose() {
    widget.app.removeListener(_onAppChanged);
    super.dispose();
  }

  void _onAppChanged() {
    if (!mounted) return;
    final app = widget.app;
    _selection.observe(card: app.lastResult, bank: app.lastBankCardResult);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final bankResult = app.lastBankCardResult;
    // 银行卡分析结果存在（交通应用未命中）时不再展示空交通卡片视图。
    // 解析进行中 parsedCard / felicaResult 已被 _resetCard 清空，此时
    // 不能用 lastResult 兜底，否则整段解析期间会显示「未识别卡片」假面板。
    final hasCard =
        app.parsedCard != null ||
        app.felicaResult != null ||
        (!app.parsing && app.lastResult != null && bankResult == null);
    final hasBank = bankResult != null;
    if (!hasCard && !hasBank) return const SizedBox.shrink();

    final available = <RecentResultKind>[
      if (hasCard) RecentResultKind.card,
      if (hasBank) RecentResultKind.bank,
    ];
    final kind = _selection.resolve(available);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.history,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '最近扫描',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (available.length > 1) ...[
              SegmentedButton<RecentResultKind>(
                segments: [
                  if (hasCard)
                    const ButtonSegment(
                      value: RecentResultKind.card,
                      label: Text('NFC 卡片'),
                    ),
                  if (hasBank)
                    const ButtonSegment(
                      value: RecentResultKind.bank,
                      label: Text('银行卡'),
                    ),
                ],
                selected: {kind},
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  padding: WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
                onSelectionChanged: (selection) {
                  setState(() => _selection.selected = selection.first);
                },
              ),
              const SizedBox(height: 12),
            ],
            switch (kind) {
              RecentResultKind.card => TransitSummaryPanel(app: app),
              RecentResultKind.bank => BankSummaryPanel(bank: bankResult!),
            },
          ],
        ),
      ),
    );
  }
}
