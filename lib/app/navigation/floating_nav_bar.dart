import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/presentation/ui_constants.dart';

/// 悬浮底栏：未选中仅图标，选中项为「图标 + 文字」的胶囊。
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.index,
    required this.onSelect,
  });

  final int index;
  final ValueChanged<int> onSelect;

  static const List<({IconData icon, String label})> _tabs = [
    (icon: Icons.home_outlined, label: '首页'),
    (icon: Icons.directions_transit_outlined, label: '行程'),
    (icon: Icons.credit_card_outlined, label: '卡片'),
    (icon: Icons.science_outlined, label: '专家'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final selection = List<double>.generate(4, (i) => i == index ? 1 : 0);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(UiConstants.floatingNavBarRadius),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black54 : Colors.black26,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(UiConstants.floatingNavBarRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: TweenAnimationBuilder<List<double>>(
            tween: _SelectionTween(begin: selection, end: selection),
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            builder: (context, progress, child) => Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  _NavItem(
                    icon: _tabs[i].icon,
                    label: _tabs[i].label,
                    selected: i == index,
                    progress: progress[i],
                    onTap: () {
                      if (i != index) HapticFeedback.selectionClick();
                      onSelect(i);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 共享插值让快速改选时展开量之和仍为 1，避免多项标签同时撑宽底栏。
class _SelectionTween extends Tween<List<double>> {
  _SelectionTween({required super.begin, required super.end});

  @override
  List<double> lerp(double t) => List<double>.generate(
    end!.length,
    (i) => begin![i] + (end![i] - begin![i]) * t,
  );
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.progress,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final double progress;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final progress = widget.progress;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.label,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: widget.onTap,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: AnimatedScale(
          scale: !reduceMotion && _pressed ? 0.95 : 1,
          duration: reduceMotion
              ? Duration.zero
              : Duration(milliseconds: _pressed ? 90 : 140),
          curve: Curves.easeOutCubic,
          child: Container(
            height: 44,
            padding: EdgeInsets.symmetric(horizontal: 12 + 4 * progress),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.16 * progress),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  size: 24,
                  color: Color.lerp(
                    scheme.onSurfaceVariant,
                    scheme.primary,
                    progress,
                  ),
                ),
                ClipRect(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: progress,
                    child: Opacity(
                      opacity: progress,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(start: 8),
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            color: scheme.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
