// 新建文件：lib/features/trips/card_detail_page.dart
import 'package:flutter/material.dart';

import '../../core/analysis/tunion_analysis_models.dart';
import '../../core/transit/tunion/tunion_models.dart';
import '../../database/app_database.dart';
import '../../state/app_state.dart';
import '../card_archive/models/card_name_extension.dart';
import '../card_archive/models/card_session_snapshot.dart';
import '../card_archive/repositories/card_repository.dart';
import 'trip_stream_view.dart';

/// 卡片详情页：展示单张卡片的档案信息（名称 / 卡号 / 余额 / 交易记录
/// 条数 / 最近读取时间），支持编辑自定义名称；行程记录按**读取批次**
/// 累积合并展示（新读取追加批次、不覆盖历史），当前会话正在读取该卡
/// 时优先展示实时解析结果；数据流监听数据库，改名与重复读取后即时刷新。
class CardDetailPage extends StatelessWidget {
  final CardRepository repository;
  final String cardId;
  final AppState app;

  const CardDetailPage({
    super.key,
    required this.repository,
    required this.cardId,
    required this.app,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('卡片信息')),
      body: StreamBuilder<SavedCard?>(
        stream: repository.watchCard(cardId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('读取卡片信息失败：${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final card = snapshot.data;
          if (card == null) {
            return const Center(child: Text('卡片不存在或已删除'));
          }
          return _CardDetailBody(repository: repository, card: card, app: app);
        },
      ),
    );
  }
}

class _CardDetailBody extends StatelessWidget {
  final CardRepository repository;
  final SavedCard card;
  final AppState app;

  const _CardDetailBody({
    required this.repository,
    required this.card,
    required this.app,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCurrentSession = app.lastCardFingerprint == card.cardFingerprint;
    // 遗留的最近一次快照（升级前的单快照档案）作为一份历史并入合并池。
    final legacySnapshot = card.sessionSnapshot;
    return StreamBuilder<List<CardReadBatch>>(
      stream: repository.watchBatches(card.id),
      builder: (context, batchSnapshot) {
        final batches = batchSnapshot.data ?? const <CardReadBatch>[];
        // 历史累积：读取批次（新批次优先）+ 遗留快照 → 按记录身份去重合并。
        final histories = <CardSessionSnapshot?>[
          ...batches.map((b) => CardSessionSnapshot.decode(b.payloadJson)),
          if (batches.isEmpty) legacySnapshot,
        ].whereType<CardSessionSnapshot>().toList();
        // 当前会话正在读取该卡：实时解析结果并入合并池最前（较新优先），
        // 让尚未落库 / 刚落库的这一轮记录立即展示。
        final TransitRecord? liveRail = app.railTransitRecord;
        final BusTransitRecord? liveBus = app.busTransitRecord;
        final live = isCurrentSession
            ? CardSessionSnapshot(
                cardCityCode: app.cardCityCode,
                trips: app.analysis?.trips ?? const <TransitTrip>[],
                rails: [if (liveRail != null) liveRail],
                buses: [if (liveBus != null) liveBus],
                processTrips: app.cycleProcessTrips,
              )
            : null;
        final pool = <CardSessionSnapshot>[
          if (live != null && !live.isEmpty) live,
          ...histories,
        ];
        final view = pool.isEmpty
            ? const CardSessionSnapshot()
            : CardSessionSnapshot.mergeHistories(pool);
        // 0x18 交易明细为主干，0x1A 按侧拆分、0x1E 未关联记录独立保留。
        final stream = buildTripStream(
          trips: view.trips,
          rails: view.rails,
          buses: view.buses,
          processTrips: view.processTrips,
        );
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
          children: [
            _ArchiveHeader(card: card, repository: repository),
            const SizedBox(height: 12),
            Text(
              isCurrentSession
                  ? '行程记录 · ${batches.length + (histories.length > batches.length ? 1 : 0)} 次读取'
                  : '行程记录 · ${batches.length} 次读取',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            if (isCurrentSession && app.parsing)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              TripStreamView(
                stream: stream,
                app: app,
                isRemote: view.isRemoteUse,
              ),
          ],
        );
      },
    );
  }
}

/// 档案信息卡：名称 / 副标题 / 卡号 / 余额 / 交易条数 / 最近读取时间，
/// 右上角写入用户自定义名称（识别结果不被覆盖，改名后数据流即时刷新）。
class _ArchiveHeader extends StatelessWidget {
  final SavedCard card;
  final CardRepository repository;

  const _ArchiveHeader({required this.card, required this.repository});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.displayName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        card.subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '自定义名称',
                  onPressed: () => _rename(context),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _row(context, '卡号', card.cardNumberText),
            _row(context, '余额', card.balanceText ?? '—'),
            _row(context, '交易记录', card.transactionCountText ?? '—'),
            _row(context, '最近读取', card.lastReadFullText ?? '—'),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  /// 改名对话框：留空即清除自定义名称（回退展示正式卡名）。
  Future<void> _rename(BuildContext context) async {
    var editedName = card.customName ?? '';
    final messenger = ScaffoldMessenger.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('自定义卡片名称'),
        // The form field owns its controller for the complete route lifetime,
        // including the dismissal animation after showDialog has returned.
        content: TextFormField(
          initialValue: editedName,
          onChanged: (value) => editedName = value,
          autofocus: true,
          maxLength: 24,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: '留空则恢复正式卡名'),
          onFieldSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(editedName),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name == null) return;
    await repository.renameCard(card.id, name);
    if (messenger.mounted) {
      messenger.showSnackBar(const SnackBar(content: Text('已更新卡片名称')));
    }
  }
}
