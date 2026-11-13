import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'gallery_design.dart';
import 'gallery_layout.dart';
import 'gallery_theme.dart';

enum GalleryFeedbackType { success, error, info }

/// One window-level queue keeps feedback visible when a dialog or page closes.
class GalleryFeedbackHost extends StatefulWidget {
  const GalleryFeedbackHost({
    super.key,
    required this.mainPage,
    required this.docked,
    required this.child,
  });

  final bool mainPage, docked;
  final Widget child;

  static void show(
    BuildContext context,
    String message, {
    GalleryFeedbackType type = GalleryFeedbackType.info,
    String? title,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    assert((actionLabel == null) == (onAction == null));
    context.findAncestorStateOfType<_GalleryFeedbackHostState>()!._show((
      type: type,
      title: title,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
    ));
  }

  @override
  State<GalleryFeedbackHost> createState() => _GalleryFeedbackHostState();
}

typedef _Message = ({
  GalleryFeedbackType type,
  String? title,
  String message,
  String? actionLabel,
  VoidCallback? onAction,
});

class _GalleryFeedbackHostState extends State<GalleryFeedbackHost>
    with SingleTickerProviderStateMixin {
  static const _motion = Duration(milliseconds: 240);
  static const _exitMotion = Duration(milliseconds: 180);
  late final _animation = AnimationController(
    vsync: this,
    duration: _motion,
    reverseDuration: _exitMotion,
  );
  late final _curve = CurvedAnimation(
    parent: _animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  late final _position = Tween(
    begin: const Offset(1.08, 0),
    end: Offset.zero,
  ).animate(_curve);
  final _pending = <_Message>[];
  _Message? _current;
  Timer? _timer;
  bool _dismissing = false;

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  void _show(_Message message) {
    if (message.message.trim().isEmpty ||
        message == _current ||
        _pending.contains(message)) {
      return;
    }
    // Finish the current message; errors precede other waiting feedback.
    if (message.type == GalleryFeedbackType.error) {
      final index = _pending.indexWhere(
        (item) => item.type != GalleryFeedbackType.error,
      );
      _pending.insert(index < 0 ? _pending.length : index, message);
    } else {
      _pending.add(message);
    }
    if (_current == null) _showNext();
  }

  void _showNext() {
    if (_pending.isEmpty) return;
    final message = _pending.removeAt(0);
    _dismissing = false;
    setState(() => _current = message);
    if (_reduceMotion) {
      _animation.value = 1;
    } else {
      _animation.forward(from: 0);
    }
    final textLength =
        message.message.runes.length + (message.title?.runes.length ?? 0);
    final duration = MediaQuery.accessibleNavigationOf(context)
        ? math.max(10000, textLength * 180)
        : math.max(
            message.onAction != null
                ? 6000
                : message.type == GalleryFeedbackType.error
                ? 3000
                : 2500,
            textLength * 100,
          );
    _timer = Timer(
      Duration(milliseconds: duration) +
          (_reduceMotion ? Duration.zero : _motion),
      _dismiss,
    );
  }

  void _dismiss() {
    if (_current == null || _dismissing) return;
    _dismissing = true;
    _timer?.cancel();
    _animation.reverseDuration = _reduceMotion ? Duration.zero : _exitMotion;
    _animation.reverse().whenCompleteOrCancel(() {
      if (!mounted) return;
      setState(() => _current = null);
      _showNext();
    });
  }

  void _performAction(_Message message) {
    if (_current != message || _dismissing) return;
    _dismiss();
    message.onAction?.call();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _curve.dispose();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final navigation = GalleryNavigationLayout(media, docked: widget.docked);
    final top = math.max(media.padding.top, media.viewPadding.top) + 12;
    final bottom =
        media.viewInsets.bottom +
        (widget.mainPage ? navigation.toastBottom : 16 + navigation.safeBottom);
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_current case final message?)
          Positioned(
            left: math.max(16, media.padding.left + 16),
            right: math.max(16, media.padding.right + 16),
            top: top,
            child: Align(
              alignment: Alignment.topRight,
              child: FadeTransition(
                opacity: _reduceMotion
                    ? const AlwaysStoppedAnimation(1)
                    : _curve,
                child: SlideTransition(
                  position: _reduceMotion
                      ? const AlwaysStoppedAnimation(Offset.zero)
                      : _position,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 560,
                      maxHeight: math.max(0, media.size.height - top - bottom),
                    ),
                    child: _FeedbackSurface(
                      message: message,
                      onAction: _dismissing || message.onAction == null
                          ? null
                          : () => _performAction(message),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FeedbackSurface extends StatelessWidget {
  const _FeedbackSurface({required this.message, this.onAction});
  final _Message message;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GalleryTokens>()!;
    final (icon, background, foreground, status) = switch (message.type) {
      GalleryFeedbackType.success => (
        Icons.check_rounded,
        tokens.successContainer,
        tokens.onSuccessContainer,
        '操作成功',
      ),
      GalleryFeedbackType.error => (
        Icons.close_rounded,
        tokens.dangerContainer,
        tokens.onDangerContainer,
        '操作失败',
      ),
      GalleryFeedbackType.info => (
        Icons.info_outline_rounded,
        tokens.tone,
        tokens.onTone,
        '提示',
      ),
    };
    final title = message.title;
    return Semantics(
      container: true,
      liveRegion: true,
      explicitChildNodes: true,
      label: '${title ?? status}，${message.message}',
      child: DefaultTextStyle(
        style: Theme.of(context).textTheme.bodyMedium!,
        child: IntrinsicWidth(
          child: DecoratedBox(
            key: const ValueKey('gallery-feedback'),
            decoration: BoxDecoration(
              color: tokens.feedbackSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: tokens.line.withValues(alpha: .5),
                width: .5,
              ),
              boxShadow: tokens.shadows(GalleryElevation.card),
            ),
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: message.actionLabel == null ? 6 : 2,
                  ),
                  child: Row(
                    children: [
                      ExcludeSemantics(
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: background,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(icon, color: foreground, size: 18),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: ExcludeSemantics(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (title != null)
                                Text(
                                  title,
                                  style: GalleryTypography.feedback.copyWith(
                                    color: tokens.text,
                                  ),
                                ),
                              Text(
                                message.message,
                                style:
                                    (title == null
                                            ? GalleryTypography.feedback
                                            : GalleryTypography.caption)
                                        .copyWith(
                                          color: title == null
                                              ? tokens.text
                                              : tokens.muted,
                                        ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (message.actionLabel != null) ...[
                        const SizedBox(width: 4),
                        TextButton(
                          key: const ValueKey('gallery-feedback-action'),
                          onPressed: onAction,
                          style: TextButton.styleFrom(
                            foregroundColor: tokens.action,
                            minimumSize: const Size(48, 44),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            shape: GalleryGeometry.buttonShape,
                            textStyle: GalleryTypography.feedback,
                          ),
                          child: Text(message.actionLabel!),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
