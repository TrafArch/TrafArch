part of 'gallery_app.dart';

/// One revealed action behind a swiped card. Actions never run on the swipe
/// itself; the user must tap the revealed button.
class _GallerySwipeAction {
  const _GallerySwipeAction({
    required this.key,
    required this.icon,
    required this.label,
    required this.semanticsLabel,
    required this.background,
    required this.foreground,
    required this.onTap,
  });
  final Key key;
  final IconData icon;
  final String label, semanticsLabel;
  final Color background, foreground;
  final VoidCallback onTap;
}

/// Left-swipe shell shared by wallet rows and the trips card summary. A swipe
/// only reveals the action tray; each action requires a second tap.
class _GallerySwipeReveal extends StatefulWidget {
  const _GallerySwipeReveal({
    required this.actions,
    required this.child,
    required this.reduceMotion,
    this.enabled = true,
  });
  final List<_GallerySwipeAction> actions;
  final Widget child;
  final bool reduceMotion, enabled;

  @override
  State<_GallerySwipeReveal> createState() => _GallerySwipeRevealState();
}

class _GallerySwipeRevealState extends State<_GallerySwipeReveal>
    with SingleTickerProviderStateMixin {
  late final _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  void _settle(bool open) => _reveal.animateTo(
    open ? 1 : 0,
    duration: widget.reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 200),
    curve: Curves.easeOutCubic,
  );

  void _act(_GallerySwipeAction action) {
    if (!widget.enabled) return;
    _settle(false);
    action.onTap();
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.actions.isEmpty) return widget.child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = widget.actions.length;
        final actionWidth = math.min(
          constraints.maxWidth * .55 / count,
          math.max(80.0, MediaQuery.textScalerOf(context).scale(14) * 2 + 32),
        );
        final totalWidth = actionWidth * count;
        return AnimatedBuilder(
          animation: _reveal,
          builder: (context, _) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.enabled && _reveal.value > 0
                ? () => _settle(false)
                : null,
            onHorizontalDragUpdate: widget.enabled
                ? (details) {
                    _reveal.value =
                        (_reveal.value - details.delta.dx / totalWidth).clamp(
                          0.0,
                          1.0,
                        );
                  }
                : null,
            onHorizontalDragEnd: widget.enabled
                ? (details) {
                    final velocity = details.primaryVelocity ?? 0;
                    _settle(
                      velocity < -250 ||
                          velocity <= 250 && _reveal.value >= .35,
                    );
                  }
                : null,
            onHorizontalDragCancel: widget.enabled
                ? () => _settle(_reveal.value >= .35)
                : null,
            child: ClipRect(
              clipBehavior: _reveal.value == 0 ? Clip.none : Clip.hardEdge,
              child: Stack(
                children: [
                  if (_reveal.value > 0)
                    Positioned.fill(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (index, action)
                              in widget.actions.indexed) ...[
                            if (index > 0) const SizedBox(width: 4),
                            SizedBox(
                              width: actionWidth,
                              child: _GallerySwipeButton(
                                action: action,
                                trailing: index == count - 1,
                                onPressed: widget.enabled
                                    ? () => _act(action)
                                    : null,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  Transform.translate(
                    offset: Offset(-totalWidth * _reveal.value, 0),
                    child: AbsorbPointer(
                      absorbing: _reveal.value > 0 || !widget.enabled,
                      child: widget.child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GallerySwipeButton extends StatelessWidget {
  const _GallerySwipeButton({
    required this.action,
    required this.trailing,
    required this.onPressed,
  });

  final _GallerySwipeAction action;
  final bool trailing;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      key: action.key,
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: action.background,
        foregroundColor: action.foreground,
        padding: const EdgeInsets.all(6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(
            left: const Radius.circular(14),
            right: Radius.circular(trailing ? 24 : 14),
          ),
        ),
      ),
      child: Semantics(
        label: action.semanticsLabel,
        excludeSemantics: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 64;
            final icon = Icon(action.icon, size: compact ? 18 : 24);
            final label = Text(
              action.label,
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.center,
              style: GalleryTypography.feedback,
            );
            if (compact) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  icon,
                  const SizedBox(width: 4),
                  Flexible(
                    child: FittedBox(fit: BoxFit.scaleDown, child: label),
                  ),
                ],
              );
            }
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                icon,
                const SizedBox(height: 4),
                FittedBox(fit: BoxFit.scaleDown, child: label),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A swipe only reveals the action. Even a full-width fling cannot delete.
/// Collapse before removing the keyed row so its neighbours move continuously.
class _GalleryWalletItem extends StatefulWidget {
  const _GalleryWalletItem({
    super.key,
    required this.id,
    required this.name,
    required this.reduceMotion,
    required this.onFace,
    required this.onDelete,
    required this.child,
    this.inserted = false,
  });
  final String id, name;
  final bool reduceMotion, inserted;
  final VoidCallback onFace, onDelete;
  final Widget child;

  @override
  State<_GalleryWalletItem> createState() => _GalleryWalletItemState();
}

class _GalleryWalletItemState extends State<_GalleryWalletItem>
    with TickerProviderStateMixin {
  late final _size = AnimationController(
    vsync: this,
    value: widget.inserted && !widget.reduceMotion ? 0 : 1,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 220),
  );
  late final _sizeCurve = CurvedAnimation(
    parent: _size,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInOutCubic,
  );
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    if (_size.value < 1) _size.forward();
  }

  @override
  void didUpdateWidget(_GalleryWalletItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduceMotion && !oldWidget.reduceMotion) {
      _size.value = _deleting ? 0 : 1;
    }
  }

  void _delete() {
    if (_deleting) return;
    setState(() => _deleting = true);
    final commit = widget.onDelete;
    _size.reverseDuration = widget.reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 220);
    _size.reverse().whenCompleteOrCancel(commit);
  }

  @override
  void dispose() {
    _sizeCurve.dispose();
    _size.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GalleryTokens>()!;
    return SizeTransition(
      sizeFactor: _sizeCurve,
      axisAlignment: -1,
      child: FadeTransition(
        opacity: _sizeCurve,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _GallerySwipeReveal(
            reduceMotion: widget.reduceMotion,
            enabled: !_deleting,
            actions: [
              _GallerySwipeAction(
                key: ValueKey('wallet-face-${widget.id}'),
                icon: Icons.palette_outlined,
                label: '更换卡面',
                semanticsLabel: '更换${widget.name}的卡面',
                background: tokens.tone,
                foreground: tokens.onTone,
                onTap: widget.onFace,
              ),
              _GallerySwipeAction(
                key: ValueKey('wallet-delete-${widget.id}'),
                icon: Icons.delete_outline_rounded,
                label: '删除',
                semanticsLabel: '删除${widget.name}',
                background: tokens.dangerContainer,
                foreground: tokens.onDangerContainer,
                onTap: _delete,
              ),
            ],
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
