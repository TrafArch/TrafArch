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
  });
  final String label;
  final IconData icon;
  final bool selected, docked, reduceMotion;
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
      button: true,
      selected: widget.selected,
      onTap: widget.onTap,
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
                    decoration: BoxDecoration(
                      color: widget.docked && widget.selected
                          ? t.tone
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Icon(
                      widget.icon,
                      size: widget.docked ? 22 : 20,
                      color: foreground,
                      shadows: const [],
                    ),
                  ),
                  SizedBox(height: widget.docked ? 2 : 3),
                  Text(
                    widget.label,
                    maxLines: 1,
                    style: TextStyle(
                      inherit: false,
                      fontFamily: 'sans-serif',
                      fontSize: 12,
                      height: widget.docked ? 16 / 12 : 1,
                      fontWeight: FontWeight.w600,
                      color: foreground,
                      shadows: const [],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
