// 新建文件：lib/features/cards/cards_page.dart
import 'package:flutter/material.dart';
import '../../core/ui_constants.dart';
import '../../database/app_database.dart';
import '../../state/app_state.dart';
import '../card_archive/models/card_name_extension.dart';
import '../card_archive/repositories/card_repository.dart';
import '../settings/settings_action_button.dart';
import '../trips/card_detail_page.dart';

/// 卡片列表页：展示已保存的卡片档案摘要，
/// 数据流监听数据库（重复读取与改名后自动刷新），最近读取的在前。
class CardsPage extends StatelessWidget {
  final AppState app;
  const CardsPage({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: const Text('卡片列表'),
            actions: [SettingsActionButton(app: app)],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                12,
                12,
                12,
                UiConstants.floatingNavBarClearance,
              ),
              child: StreamBuilder<List<SavedCard>>(
                stream: app.cardRepository.watchCards(),
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
                      for (final card in cards)
                        _SavedCardTile(card: card, app: app),
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
/// 右侧余额快照与交易记录条数；点击进入卡片详情页查看读取快照与行程。
class _SavedCardTile extends StatelessWidget {
  final SavedCard card;
  final AppState app;

  const _SavedCardTile({required this.card, required this.app});

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
              app: app,
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
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      card.cardNumberText,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      card.lastReadShortText ?? '—',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.outline),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    card.balanceText ?? '—',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    card.transactionCountText ?? '—',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.outline),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}