import 'package:flutter/material.dart';

import '../../shared/presentation/ui_constants.dart';
import '../archive/data/app_database.dart';
import '../../app/app_dependencies.dart';
import '../archive/application/archive_record_count.dart';
import '../archive/domain/card_name_extension.dart';
import '../qr/presentation/qr_action_button.dart';
import '../settings/presentation/settings_action_button.dart';
import '../archive/presentation/card_detail_page.dart';
import '../archive/presentation/archive_balance_display.dart';
import '../archive/presentation/archive_transfer_dialogs.dart';

/// 卡片列表页：展示已保存的卡片档案摘要，
/// 数据流监听数据库（重复读取与改名后自动刷新），最近读取的在前。
class CardsPage extends StatefulWidget {
  final AppDependencies app;
  const CardsPage({super.key, required this.app});

  @override
  State<CardsPage> createState() => _CardsPageState();
}

class _CardsPageState extends State<CardsPage> {
  late Stream<List<ArchiveCardSummary>> _summaries;

  @override
  void initState() {
    super.initState();
    widget.app.addListener(_onChanged);
    _summaries = watchArchiveCardSummaries(widget.app.cardRepository);
  }

  @override
  void didUpdateWidget(covariant CardsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app != widget.app) {
      oldWidget.app.removeListener(_onChanged);
      widget.app.addListener(_onChanged);
    }
    if (oldWidget.app.cardRepository != widget.app.cardRepository) {
      _summaries = watchArchiveCardSummaries(widget.app.cardRepository);
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.app.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return SafeArea(
      top: false,
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: const Text('卡片列表'),
            actions: [
              ArchiveTransferButtons(app: app),
              QrActionButton(app: app),
              SettingsActionButton(app: app),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                12,
                12,
                12,
                UiConstants.floatingNavBarClearance,
              ),
              child: StreamBuilder<List<ArchiveCardSummary>>(
                stream: _summaries,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.error_outline),
                        title: const Text('读取卡片档案失败'),
                        subtitle: Text('${snapshot.error}'),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    );
                  }
                  final cards = snapshot.data!;
                  if (cards.isEmpty) {
                    return const Card(
                      child: ListTile(
                        leading: Icon(Icons.add_card_outlined),
                        title: Text('还没有保存的卡片'),
                        subtitle: Text('读取卡片并确认保存后在这里展示'),
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final summary in cards)
                        _SavedCardTile(
                          card: summary.card,
                          recordCount: summary.recordCount,
                          app: app,
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单张档案卡片（列表项）：左侧三行（名称 / 卡号 / 最近读取时间）、
/// 右侧余额快照与累计已保存记录条数；点击进入卡片详情页查看读取快照与行程，
/// 右侧操作菜单支持删除该档案。
class _SavedCardTile extends StatelessWidget {
  final SavedCard card;
  final ArchiveRecordCount recordCount;
  final AppDependencies app;

  const _SavedCardTile({
    required this.card,
    required this.recordCount,
    required this.app,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CardDetailPage(
              repository: app.cardRepository,
              cardId: card.id,
              settings: app.settings,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      card.cardNumberText,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      card.lastReadShortText ?? '—',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // 与左侧各占一半，右对齐贴住操作按钮；避免 loose Flexible
              // 的未用弹性空间把按钮顶离右缘，也避免长余额文本溢出。
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      archiveCardBalanceText(
                            card,
                            includeShanghaiOverdraft:
                                app.includeShanghaiOverdraft,
                          ) ??
                          '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      recordCount.listText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_SavedCardAction>(
                tooltip: '卡片操作',
                icon: Icon(Icons.more_vert, size: 20, color: scheme.outline),
                padding: EdgeInsets.zero,
                onSelected: (action) {
                  if (action == _SavedCardAction.delete) {
                    _delete(context);
                  } else if (action == _SavedCardAction.export) {
                    exportArchiveJson(context, app, card: card);
                  }
                },
                itemBuilder: (context) {
                  final error = Theme.of(context).colorScheme.error;
                  return [
                    const PopupMenuItem(
                      value: _SavedCardAction.export,
                      child: Row(
                        children: [
                          Icon(Icons.download_outlined),
                          SizedBox(width: 12),
                          Text('导出此卡 JSON'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: _SavedCardAction.delete,
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, color: error),
                          const SizedBox(width: 12),
                          Text('删除卡片', style: TextStyle(color: error)),
                        ],
                      ),
                    ),
                  ];
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 删除确认：删除档案与全部读取批次（含行程快照），不可恢复；
  /// 删除后列表随数据流自动刷新，成功 / 失败以 SnackBar 反馈。
  Future<void> _delete(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除卡片'),
        content: Text(
          '确定要删除「${card.displayName}」吗？\n'
          '该卡的档案与全部读取记录（含行程快照）将一并删除，且无法恢复。\n'
          '删除后再次读取该卡可重新加入。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await app.cardRepository.deleteCard(card.id);
      messenger.showSnackBar(
        SnackBar(content: Text('已删除：${card.displayName}')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('删除失败：$e')));
    }
  }
}

/// 卡片列表项的操作菜单项。
enum _SavedCardAction { export, delete }
