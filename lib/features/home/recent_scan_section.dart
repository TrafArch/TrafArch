import 'package:flutter/material.dart';

import '../../app/app_dependencies.dart';
import 'presentation/transit_summary_panel.dart';

/// 首页「最近扫描」模块，展示最新的交通卡、FeliCa 或未识别卡片结果。
class RecentScanSection extends StatelessWidget {
  final AppDependencies app;

  const RecentScanSection({super.key, required this.app});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: app,
    builder: (context, _) => _buildResult(context),
  );

  Widget _buildResult(BuildContext context) {
    // 解析期间 lastResult 已有 NFC 标签，等解析结束再显示未识别结果。
    if (app.parsedCard == null &&
        app.felicaResult == null &&
        (app.parsing || app.lastResult == null)) {
      return const SizedBox.shrink();
    }
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
            TransitSummaryPanel(app: app),
          ],
        ),
      ),
    );
  }
}
