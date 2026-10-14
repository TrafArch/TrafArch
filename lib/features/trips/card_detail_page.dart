// 新建文件：lib/features/trips/card_detail_page.dart
import 'package:flutter/material.dart';
import '../../core/analysis/tunion_analysis_models.dart';
import '../../core/transit/tunion/tunion_models.dart';
import '../../database/app_database.dart';
import '../../state/app_state.dart';
import '../card_archive/models/card_name_extension.dart';
import '../card_archive/repositories/card_repository.dart';

/// 卡片详情页：展示单张卡片的最近一次读取快照
/// （名称 / 卡号 / 余额 / 交易记录条数 / 最近读取时间），
/// 支持编辑自定义名称；当本次会话读取的正是该卡片时，
/// 同时展示解析出的行程数据；数据流监听数据库，改名与重复读取后即时刷新。
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
    // 当前会话读取的正是该卡片时优先展示实时解析结果；否则回退最近一次
    // 保存到档案的行程记录快照——读取新卡片后，老卡片的记录不再消失。
    final snapshot = card.sessionSnapshot;
    final liveTrips = isCurrentSession
        ? (app.analysis?.trips ?? const <TransitTrip>[])
        : const <TransitTrip>[];
    final liveRail = isCurrentSession ? app.railTransitRecord : null;
    final liveBus = isCurrentSession ? app.busTransitRecord : null;
    final hasLive = liveTrips.isNotEmpty || liveRail != null || liveBus != null;
    final List<TransitTrip> trips =
        hasLive ? liveTrips : (snapshot?.trips ?? const <TransitTrip>[]);
    final TransitRecord? railRecord = hasLive ? liveRail : snapshot?.railRecord;
    final BusTransitRecord? busRecord = hasLive ? liveBus : snapshot?.busRecord;

    // 异地用卡判定：实时数据按当前卡片城市；快照按读取时记录的城市代码。
    bool isRemoteOf(String? code) => hasLive
        ? app.isRemoteUse(code)
        : (snapshot?.isRemoteUse(code) ?? false);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          card.displayName,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          card.subtitle,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                _kv(context, '卡号', card.cardNumberText),
                _kv(context, '余额', card.balanceText ?? '未读取到'),
                _kv(context, '交易记录', card.transactionCountText ?? '未记录'),
                _kv(context, '最近读取', card.lastReadFullText ?? '未记录'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: () => _renameCard(context, repository, card),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('编辑卡片名称'),
          ),
        ),
        if (trips.isNotEmpty || railRecord != null || busRecord != null) ...[
          const SizedBox(height: 24),
          Text(
            hasLive ? '本次读取行程' : '最近读取记录',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          for (final trip in trips)
            _DetailTripCard(trip: trip, isRemote: isRemoteOf(trip.cityCode)),
          if (railRecord != null) ...[
            const SizedBox(height: 8),
            _DetailRailCard(record: railRecord),
          ],
          if (busRecord != null) ...[
            const SizedBox(height: 8),
            _DetailBusCard(record: busRecord),
          ],
        ],
      ],
    );
  }
}

Widget _kv(BuildContext context, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );

/// 详情页内嵌行程卡片（与行程页共用展示逻辑）。
class _DetailTripCard extends StatelessWidget {
  final TransitTrip trip;
  final bool isRemote;
  const _DetailTripCard({required this.trip, required this.isRemote});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final titleParts = <String>[
      trip.rideStatusName ?? trip.typeName,
      if (trip.stationLabel != null) trip.stationLabel!,
      '序号 ${trip.sequence}',
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    titleParts.join(' · '),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (isRemote)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '异地用卡',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onTertiaryContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
            if (trip.lineLabel != null) ...[
              const SizedBox(height: 4),
              Text(
                trip.lineLabel!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              trip.timeText,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  trip.amountText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: trip.isConsume ? scheme.error : scheme.primary,
                  ),
                ),
                if (trip.balanceAfterText != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    '余额 ${trip.balanceAfterText}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.outline),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRailCard extends StatelessWidget {
  final TransitRecord record;
  const _DetailRailCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '城市轨道交通 · 进出站记录',
              style:
                  theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _detailKv(context, '交易状态', record.statusName),
            if (record.entryTime != null)
              _detailKv(context, '进站时间', _fmtDt(record.entryTime!)),
            if (record.exitTime != null)
              _detailKv(context, '出站时间', _fmtDt(record.exitTime!)),
            if (record.exitAmountFen != null)
              _detailKv(
                context,
                '出站金额',
                '¥${(record.exitAmountFen! / 100).toStringAsFixed(2)}',
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailBusCard extends StatelessWidget {
  final BusTransitRecord record;
  const _DetailBusCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '公共汽电车 · 上下车记录',
              style:
                  theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _detailKv(context, '交易状态', record.statusName),
            if (record.entryTime != null)
              _detailKv(context, '上车时间', _fmtDt(record.entryTime!)),
            if (record.exitTime != null)
              _detailKv(context, '下车时间', _fmtDt(record.exitTime!)),
            if (record.transactionAmountFen != null)
              _detailKv(
                context,
                '交易金额',
                '¥${(record.transactionAmountFen! / 100).toStringAsFixed(2)}',
              ),
          ],
        ),
      ),
    );
  }
}

Widget _detailKv(BuildContext context, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );

String _fmtDt(DateTime t) {
  String pad2(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${pad2(t.month)}-${pad2(t.day)} '
      '${pad2(t.hour)}:${pad2(t.minute)}:${pad2(t.second)}';
}

/// 编辑自定义卡片名称：留空恢复显示正式卡名；保存失败仅提示不中断。
Future<void> _renameCard(
  BuildContext context,
  CardRepository repository,
  SavedCard card,
) async {
  final controller = TextEditingController(text: card.customName ?? '');

  final name = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('自定义卡片名称'),
        content: TextField(
          controller: controller,
          maxLength: 40,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '例如：上学用的卡',
            helperText: '留空则恢复显示正式卡名',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      );
    },
  );
  controller.dispose();

  if (name == null) return;

  try {
    await repository.renameCard(card.id, name.isEmpty ? null : name);
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('卡片名称保存失败：$e')),
    );
  }
}