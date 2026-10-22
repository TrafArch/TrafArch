import 'package:flutter/material.dart';

import '../../shared/presentation/ui_constants.dart';

abstract final class AppTheme {
  /// Android 转场统一为 FadeForwards（Android 14+ 系统同款：水平滑入 +
  /// 交叉淡化，450ms）：显式覆盖新版 Flutter 的默认值
  /// （PredictiveBackPageTransitionsBuilder），避免"手势返回=缩小圆角、
  /// 按键返回=水平甩出"两种样式混杂；相比 Zoom 的整页缩放 + 压暗，
  /// 连续返回时页面统一水平滑出，方向感清晰、观感更稳。
  /// 备选：CupertinoPageTransitionsBuilder（iOS 式整页视差滑动，500ms）。
  static const pageTransitionsTheme = PageTransitionsTheme(
    builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()},
  );

  /// SnackBar 统一样式：默认的 fixed 贴底黑条会压住悬浮底栏，改为浮动式
  /// 钉在底栏上方（底栏高 + 底边距 + 12 间隙），左右与底栏对齐、圆角
  /// 与整体卡片风格统一，保证任何页面弹出的提示都不遮挡底栏。
  static const snackBarTheme = SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    insetPadding: EdgeInsets.fromLTRB(
      UiConstants.floatingNavBarInset,
      0,
      UiConstants.floatingNavBarInset,
      UiConstants.snackBarBottomInset,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    ),
  );

  static final fallbackLight = ColorScheme.fromSeed(
    seedColor: Colors.teal,
    brightness: Brightness.light,
  );
  static final fallbackDark = ColorScheme.fromSeed(
    seedColor: Colors.teal,
    brightness: Brightness.dark,
  );

  static ThemeData light(ColorScheme? dynamic) => ThemeData(
    colorScheme: dynamic ?? fallbackLight,
    pageTransitionsTheme: pageTransitionsTheme,
    snackBarTheme: snackBarTheme,
  );
  static ThemeData dark(ColorScheme? dynamic) => ThemeData(
    colorScheme: dynamic ?? fallbackDark,
    pageTransitionsTheme: pageTransitionsTheme,
    snackBarTheme: snackBarTheme,
  );
}
