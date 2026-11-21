part of 'gallery_app.dart';

extension _GalleryLiveArchive on _GalleryViewState {
  void _archiveNotice(String message, bool failed) => _toast(
    message,
    type: failed ? GalleryFeedbackType.error : GalleryFeedbackType.success,
  );

  Widget _liveCards(
    AppDependencies app,
  ) => StreamBuilder<List<ArchiveCardSummary>>(
    stream: _archiveCards ??= watchArchiveCardSummaries(app.cardRepository),
    builder: (context, snapshot) {
      final controls = Align(
        alignment: Alignment.centerRight,
        child: ArchiveTransferButtons(app: app, onNotice: _archiveNotice),
      );
      if (snapshot.hasError) {
        return _list([
          controls,
          _empty(
            '无法读取卡包',
            '档案尚未加载，请重试。',
            action: _button('重试', () {
              _updateDetail(() => _archiveCards = null);
            }),
          ),
        ]);
      }
      if (!snapshot.hasData) {
        return _list([
          controls,
          const Center(child: CircularProgressIndicator()),
        ]);
      }
      final summaries = snapshot.data!;
      return ListView.builder(
        key: const PageStorageKey('live-archive-cards'),
        padding: EdgeInsets.fromLTRB(16, 6, 16, _navLayout.listBottom),
        itemCount: summaries.isEmpty ? 2 : summaries.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) return controls;
          if (summaries.isEmpty) {
            return _empty('暂无已保存卡片', '可以在首页读取后保存，也可以从本机导入卡片 JSON。');
          }
          final summary = summaries[index - 1];
          final card = summary.card;
          return Padding(
            key: ValueKey(card.id),
            padding: const EdgeInsets.only(bottom: 12),
            child: _panel(
              ListTile(
                contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                leading: Icon(Icons.contactless_outlined, color: t.onTone),
                title: _text(
                  summary.amusementIcIdentity?.displayName(card.customName) ??
                      card.displayName,
                  role: GalleryTypography.card,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (card.cardType != CardTypes.amusementIc)
                      _text(
                        _archiveBalance(card, app) ?? '余额未知',
                        role: GalleryTypography.lead,
                      ),
                    Divider(color: t.line),
                    _text(
                      [
                        if (card.cityName case final city? when city.isNotEmpty)
                          city,
                        summary.amusementIcIdentity?.defaultName ??
                            cardTypeLabel(card.cardType),
                        _archiveReadDate(card),
                      ].join(' · '),
                      role: GalleryTypography.caption,
                      color: t.muted,
                    ),
                  ],
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => c.openCardId(card.id),
              ),
              radius: 24,
              padding: EdgeInsets.zero,
            ),
          );
        },
      );
    },
  );

  String _archiveReadDate(SavedCard card) {
    final time = card.lastReadFullText;
    return time == null ? '日期未记录' : time.split(' ').first;
  }

  String? _archiveBalance(
    SavedCard card,
    AppDependencies app, {
    ArchiveHistoryResult? history,
  }) => archiveCardBalanceText(
    card,
    includeShanghaiOverdraft: app.includeShanghaiOverdraft,
    balanceSnapshot: history?.balanceSource?.snapshot,
    capturedText: history?.balanceText,
  );

  Widget _liveArchiveDetail(AppDependencies app) =>
      StreamBuilder<ArchiveHistoryResult>(
        stream: _archiveHistory ??= ArchiveHistory(app.cardRepository)
            .watch(_entry.cardId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _list([
              _header('卡片详情', back: true),
              _empty(
                '无法读取卡片历史',
                '请重试。',
                action: _button('重试', () {
                  _updateDetail(() => _archiveHistory = null);
                }),
              ),
            ]);
          }
          final history = snapshot.data;
          if (history == null) {
            return _list([
              _header('卡片详情', back: true),
              const Center(child: CircularProgressIndicator()),
            ]);
          }
          final card = history.card;
          if (card == null) {
            return _list([
              _header('卡片详情', back: true),
              _empty('卡片不存在或已删除', '请返回卡包。'),
            ]);
          }
          final details = <Widget>[
            _header(
              '卡片详情',
              back: true,
              actions: [
                _icon(
                  Icons.download_outlined,
                  '导出卡片 JSON',
                  () => exportArchiveJson(
                    context,
                    app,
                    card: card,
                    onNotice: _archiveNotice,
                  ),
                ),
                _icon(Icons.delete_outline_rounded, '删除卡片', () async {
                  if (await confirmDeleteArchiveCard(context, app, card) &&
                      mounted &&
                      c.page == GalleryPage.detail) {
                    c.back();
                  }
                }),
              ],
            ),
            _panel(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _text(card.displayName, role: GalleryTypography.section),
                  if (card.cardType != CardTypes.amusementIc) ...[
                    _gap(),
                    _text(
                      _archiveBalance(card, app, history: history) ?? '余额未知',
                      role: GalleryTypography.stat,
                    ),
                  ],
                ],
              ),
              radius: 24,
            ),
            _gap(),
            _tabs(
              const ['最近交易', '消费统计', '卡片信息'],
              c.detailTab,
              (index) => c.update(() => c.detailTab = index),
              scroll: true,
              id: 'live-archive-tabs',
            ),
            _gap(),
          ];
          if (c.detailTab == 1) {
            final summary = projectGalleryArchiveSpending(
              history,
              selection: _spendingSelection,
            );
            details.addAll([
              _text(
                '统计仅使用档案中已确认的扣款与币种。余额差、过程事件、充值及币种或金额单位不明的记录不计入。',
                role: GalleryTypography.caption,
                color: t.muted,
              ),
              _gap(),
              ..._spendingWidgets(summary, now: DateTime.now()),
            ]);
          } else {
            details.add(
              ArchiveDetailContent(
                history: history,
                repository: app.cardRepository,
                includeShanghaiOverdraft: app.includeShanghaiOverdraft,
                recoveryFilters: app.recoveryFilters,
                section: c.detailTab == 0
                    ? ArchiveDetailSection.records
                    : ArchiveDetailSection.information,
              ),
            );
          }
          return _list(details, id: 'live-archive-${card.id}');
        },
      );
}
