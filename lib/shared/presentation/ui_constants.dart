/// 全局 UI 尺寸常量，保证悬浮底栏与各页面底部留白保持一致。
class UiConstants {
  UiConstants._();

  /// 悬浮底栏视觉高度（胶囊 44 + 上下留白 6×2）。
  static const double floatingNavBarHeight = 56;

  /// 悬浮底栏宽度：固定为屏宽以内的小胶囊，居中悬浮，图标间距随宽度收紧。
  static const double floatingNavBarWidth = 280;

  /// 悬浮底栏与屏幕左、右、下边缘的间距（数值越大，底栏上浮越高）。
  static const double floatingNavBarInset = 20;

  /// 悬浮底栏圆角半径（等于高度的一半，两端呈完整半圆形）。
  static const double floatingNavBarRadius = 28;

  /// 页面滚动内容底部为悬浮底栏预留的留白
  /// （底栏高度 + 底边距 + 16 呼吸留白）。
  static const double floatingNavBarClearance =
      floatingNavBarHeight + floatingNavBarInset + 16;

  /// SnackBar 浮动提示距屏幕底部的间距：悬浮在底栏上方，不遮挡底栏
  /// （底栏高度 + 底边距 + 与底栏之间 12 呼吸留白）。
  static const double snackBarBottomInset =
      floatingNavBarHeight + floatingNavBarInset + 12;
}
