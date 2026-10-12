/// 全局 UI 尺寸常量，保证悬浮底栏与各页面底部留白保持一致。
class UiConstants {
  UiConstants._();

  /// 悬浮底栏视觉高度
  /// （GNav google 展开式：胶囊 48 = 图标 24 + 垂直内边距 12×2，tabMargin 上下预留 10×2 → 总高 68）。
  static const double floatingNavBarHeight = 68;

  /// 悬浮底栏与屏幕左、右、下边缘的间距。
  static const double floatingNavBarInset = 12;

  /// 悬浮底栏圆角半径。
  static const double floatingNavBarRadius = 24;

  /// 页面滚动内容底部为悬浮底栏预留的留白
  /// （底栏高度 + 底边距 + 16 呼吸留白）。
  static const double floatingNavBarClearance =
      floatingNavBarHeight + floatingNavBarInset + 16;
}