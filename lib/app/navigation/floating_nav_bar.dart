import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/presentation/ui_constants.dart';

/// 悬浮底栏：未选中仅图标，选中项为「图标 + 文字」的胶囊。
///
/// 选中状态直接由 [index] 计算，不挂任何隐式动画：点按即切换，
/// 没有涟漪、胶囊过渡或文字展开动画。
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < _tabs.length; i++)
                _NavItem(
                  icon: _tabs[i].icon,
                  label: _tabs[i].label,
                  selected: i == index,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onSelect(i);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          // 胶囊 44 高，配合外层上下 6 留白，底栏总高 56
          height: 44,
          padding: EdgeInsets.symmetric(horizontal: selected ? 16 : 12),
          decoration: selected
              ? BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(100),
                )
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 24,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: scheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
