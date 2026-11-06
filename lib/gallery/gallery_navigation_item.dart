part of 'gallery_app.dart';

/// Paint glyphs once with an explicit color. Material's inherited animated text
/// and icon themes must not add a second state transition around these items.
class _GalleryNavigationItem extends StatefulWidget {
  const _GalleryNavigationItem({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.docked,
    required this.tokens,
    required this.reduceMotion,
    required this.onTap,
    required this.showLabel,
  });
  final String label;
  final IconData icon;
  final bool selected, docked, reduceMotion;
  final bool showLabel;
  final GalleryTokens tokens;
  final VoidCallback onTap;
  @override
  State<_GalleryNavigationItem> createState() => _GalleryNavigationItemState();
}

class _GalleryNavigationItemState extends State<_GalleryNavigationItem> {
  bool _showFocus = false;
  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final color = widget.selected ? t.onTone : t.muted;
    return Semantics(
      label: widget.label,
      excludeSemantics: true,
      button: true,
      selected: widget.selected,
      onTap: widget.onTap,
      child: Tooltip(
        message: widget.label,
        child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.click,
          onShowFocusHighlight: (value) => setState(() => _showFocus = value),
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onTap();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: widget.onTap,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.docked ? 16 : 25),
                border: _showFocus ? Border.all(color: t.onTone) : null,
              ),
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: color),
                duration: widget.reduceMotion
                    ? Duration.zero
                    : _GalleryMotion.capsule,
                curve: _GalleryMotion.curve,
                builder: (context, foreground, _) => Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration: widget.reduceMotion
                          ? Duration.zero
                          : _GalleryMotion.capsule,
                      curve: _GalleryMotion.curve,
                      width: widget.docked ? 56 : 20,
                      height: widget.docked ? 28 : 20,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween<double>(
                              end: widget.docked && widget.selected ? 1 : 0,
                            ),
                            duration: widget.reduceMotion
                                ? Duration.zero
                                : _GalleryMotion.capsule,
                            curve: _GalleryMotion.curve,
                            builder: (context, opacity, _) => DecoratedBox(
                              decoration: BoxDecoration(
                                // Fade only alpha: transparent black would
                                // darken the capsule during color interpolation.
                                color: t.tone.withValues(alpha: opacity),
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                          ),
                          Icon(
                            widget.icon,
                            size: widget.docked ? 22 : 20,
                            color: foreground,
                            shadows: const [],
                          ),
                        ],
                      ),
                    ),
                    if (widget.showLabel) ...[
                      SizedBox(height: widget.docked ? 2 : 3),
                      Text(
                        widget.label,
                        maxLines: 1,
                        style: GalleryTypography.navigation.copyWith(
                          inherit: false,
                          height: widget.docked ? 16 / 12 : 1,
                          color: foreground,
                          shadows: const [],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
