import 'package:flutter/material.dart';
import 'package:flutter_floating_bottom_bar/flutter_floating_bottom_bar.dart';

import '../../shared/presentation/ui_constants.dart';
import '../app_dependencies.dart';
import '../../features/home/home_page.dart';
import '../../features/cards/cards_page.dart';
import '../../features/trips/trips_page.dart';
import '../../features/expert/expert_page.dart';
import 'floating_nav_bar.dart';
import 'navigation_scroll_policy.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.app});

  final AppDependencies app;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;
  AppDependencies get app => widget.app;

  @override
  Widget build(BuildContext context) {
    // 参考 flutter_floating_bottom_bar：底栏悬浮于内容之上，滚动时自动隐藏/
    // 回显（弹簧动画），底栏隐藏时提供“回到顶部”快捷按钮；
    // 底栏本体参考 google_nav_bar（Telegram 式展开）：
    // 未选中仅显示图标，选中项胶囊高亮 + 文字从图标旁展开/收起。
    //
    // PopScope：适配 Android 预测式返回（Predictive Back）并修正 Tab 返回逻辑。
    // canPop 必须提前确定（预测式返回在手势开始时就播放预览，无法事后拦截）：
    // - 首页：canPop = true，返回键/手势交还系统，Android 14+ 上左滑会预览
    //   “返回主屏幕”的系统动画，松手后退出应用；
    // - 行程/专家：canPop = false，手势被框架拦截（此时系统不播放预览动画），
    //   松手后在 onPopInvokedWithResult 中切回首页 Tab，避免直接退出应用。
    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        if (index != 0) setState(() => index = 0);
      },
      child: Scaffold(
        body: BottomBar(
          layout: BottomBarLayout.adaptive(
            maxWidth: 520,
            offset: UiConstants.floatingNavBarInset,
            borderRadius: BorderRadius.circular(
              UiConstants.floatingNavBarRadius,
            ),
          ),
          scrollBehavior: BottomBarScrollBehavior(
            hideOnScroll: true,
            deltaThreshold: 12.0,
            showAtStart: true,
            showOnScrollEnd: true,
            // 专家页为 NestedScrollView：外层（depth 0）负责收起标题栏，正文
            // 长列表（depth ≥ 1）才是主要滑动来源，两者都要驱动底栏隐藏，
            // 拦截规则见 bottomBarScrollPredicate。
            predicate: bottomBarScrollPredicate,
          ),
          iconTooltip: '回到顶部',
          iconSemanticLabel: '回到顶部',
          body: IndexedStack(
            index: index,
            children: [
              HomePage(app: app, active: index == 0),
              TripsPage(app: app),
              CardsPage(app: app),
              ExpertPage(app: app),
            ],
          ),
          // 3.0.0 起 child（悬浮栏本体）与 body 同为必填参数
          child: FloatingNavBar(
            index: index,
            onSelect: (i) {
              if (i != index) setState(() => index = i);
            },
          ),
        ),
      ),
    );
  }
}
