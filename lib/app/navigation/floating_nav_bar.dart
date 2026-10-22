import 'package:flutter/material.dart';
import 'package:google_nav_bar/google_nav_bar.dart';

import '../../shared/presentation/ui_constants.dart';

/// 悬浮底栏本体：GNav（Telegram 式展开：未选中仅图标，选中项胶囊 +
/// 文字展开）+ 圆角阴影容器，视觉高度与 [UiConstants.floatingNavBarHeight] 一致。
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.index,
    required this.onSelect,
  });

  final int index;
  final ValueChanged<int> onSelect;

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
        child: GNav(
          selectedIndex: index,
          onTabChange: onSelect,
          // 采用库默认的 google 样式（即演示的 Telegram 式展开效果）：
          // 未选中仅显示图标；选中项胶囊高亮，文字从图标右侧展开/收起
          backgroundColor: Colors.transparent,
          color: scheme.onSurfaceVariant,
          activeColor: scheme.primary,
          tabBackgroundColor: scheme.primary.withValues(alpha: 0.16),
          rippleColor: scheme.primary.withValues(alpha: 0.08),
          hoverColor: scheme.primary.withValues(alpha: 0.04),
          // 图标与展开文字之间的水平间距
          gap: 8,
          iconSize: 24,
          // google 样式下文字样式由 textStyle 控制（textSize 仅对 oldSchool 生效）
          textStyle: TextStyle(
            color: scheme.primary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          // 胶囊内边距：图标 24 + 垂直内边距 12×2 = 48 高胶囊
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          // 胶囊上下各留白 10：底栏总高 48 + 10×2 = 68，与 UiConstants 一致
          tabMargin: const EdgeInsets.symmetric(vertical: 10),
          tabBorderRadius: 100,
          curve: Curves.easeOutExpo,
          // 切换过渡速度（文字展开/收起与胶囊背景同步，保持快速切换）
          duration: const Duration(milliseconds: 200),
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          haptic: true,
          tabs: const [
            GButton(icon: Icons.home_outlined, text: '首页', semanticLabel: '首页'),
            GButton(
              icon: Icons.directions_transit_outlined,
              text: '行程',
              semanticLabel: '行程',
            ),
            GButton(
              icon: Icons.credit_card_outlined,
              text: '卡片',
              semanticLabel: '卡片',
            ),
            GButton(
              icon: Icons.science_outlined,
              text: '专家',
              semanticLabel: '专家',
            ),
          ],
        ),
      ),
    );
  }
}
