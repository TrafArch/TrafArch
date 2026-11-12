part of 'gallery_app.dart';

/// A swipe only reveals the action. Even a full-width fling cannot delete.
/// Collapse before removing the keyed row so its neighbours move continuously.
class _GalleryWalletItem extends StatefulWidget {
  const _GalleryWalletItem({
    super.key,
    required this.id,
    required this.name,
    required this.reduceMotion,
    required this.onDelete,
    required this.child,
    this.inserted = false,
  });
  final String id, name;
  final bool reduceMotion, inserted;
  final VoidCallback onDelete;
  final Widget child;

  @override
  State<_GalleryWalletItem> createState() => _GalleryWalletItemState();
}

class _GalleryWalletItemState extends State<_GalleryWalletItem>
    with TickerProviderStateMixin {
  late final _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
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
      _reveal.value = _reveal.value >= .35 ? 1 : 0;
      _size.value = _deleting ? 0 : 1;
    }
  }

  void _settle(bool open) => _reveal.animateTo(
    open ? 1 : 0,
    duration: widget.reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 200),
    curve: Curves.easeOutCubic,
  );

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
    _reveal.dispose();
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final actionWidth = math.min(
                constraints.maxWidth * .55,
                math.max(
                  80.0,
                  MediaQuery.textScalerOf(context).scale(14) * 2 + 32,
                ),
              );
              return AnimatedBuilder(
                animation: _reveal,
                builder: (context, _) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _reveal.value > 0 ? () => _settle(false) : null,
                  onHorizontalDragUpdate: _deleting
                      ? null
                      : (details) {
                          _reveal.value =
                              (_reveal.value - details.delta.dx / actionWidth)
                                  .clamp(0.0, 1.0);
                        },
                  onHorizontalDragEnd: _deleting
                      ? null
                      : (details) {
                          final velocity = details.primaryVelocity ?? 0;
                          _settle(
                            velocity < -250 ||
                                velocity <= 250 && _reveal.value >= .35,
                          );
                        },
                  onHorizontalDragCancel: _deleting
                      ? null
                      : () => _settle(_reveal.value >= .35),
                  child: ClipRect(
                    clipBehavior: _reveal.value == 0
                        ? Clip.none
                        : Clip.hardEdge,
                    child: Stack(
                      children: [
                        if (_reveal.value > 0)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                color: tokens.dangerContainer,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              alignment: Alignment.centerRight,
                              child: SizedBox(
                                width: actionWidth,
                                height: double.infinity,
                                child: TextButton(
                                  key: ValueKey('wallet-delete-${widget.id}'),
                                  onPressed: _deleting ? null : _delete,
                                  style: TextButton.styleFrom(
                                    foregroundColor: tokens.onDangerContainer,
                                    shape: GalleryGeometry.buttonShape,
                                    padding: const EdgeInsets.all(8),
                                  ),
                                  child: Semantics(
                                    label: '删除${widget.name}',
                                    excludeSemantics: true,
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.delete_outline_rounded,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '删除',
                                          style: GalleryTypography.feedback,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Transform.translate(
                          offset: Offset(-actionWidth * _reveal.value, 0),
                          child: AbsorbPointer(
                            absorbing: _reveal.value > 0 || _deleting,
                            child: widget.child,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
