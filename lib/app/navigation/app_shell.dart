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
import '../../features/settings/presentation/settings_page.dart';
import '../../features/qr/presentation/qr_page.dart';
import '../../features/archive/presentation/card_detail_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.app,
    this.routeObserver,
    this.bottomBarController,
  });

  final AppDependencies app;

  /// 用于感知本壳页被其他页面（扫码解析、设置等）覆盖后再回显。
  final RouteObserver<PageRoute<dynamic>>? routeObserver;

  /// 可选的底栏控制器；缺省时由壳页自建并负责释放。
  final BottomBarController? bottomBarController;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with RouteAware {
  int index = 0;
  late final BottomBarController _barController =
      widget.bottomBarController ?? BottomBarController();
  PageRoute<dynamic>? _subscribedRoute;
  AppDependencies get app => widget.app;
  bool _restored = false;

  @override
  void initState() {
    super.initState();
    app.addListener(_restorePage);
    _restorePage();
  }

  void _restorePage() {
    if (_restored || !app.recoveryReady) return;
    _restored = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => index = app.recoveryTab);
      final name = app.pendingRecoveryRoute;
      app.pendingRecoveryRoute = null;
      final Widget? page = switch (name) {
        '/settings' => SettingsPage(app: app),
        '/qr' => QrPage(app: app),
        final String path when path.startsWith('/card/') => CardDetailPage(
          repository: app.cardRepository,
          cardId: Uri.decodeComponent(path.substring(6)),
          settings: app.settings,
          recoveryFilters: app.recoveryFilters,
        ),
        _ => null,
      };
      if (page != null) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: RouteSettings(name: name),
            builder: (_) => page,
          ),
        );
      }
    });
  }

  void _select(int value) {
    app.recoveryTab = value;
    setState(() => index = value);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && route != _subscribedRoute) {
      widget.routeObserver?.subscribe(this, route);
      _subscribedRoute = route;
    }
  }

  /// 从扫码解析等页面返回时恢复底栏。
  ///
  /// 底栏的弹簧显隐由 motor 驱动，其 Ticker 在壳页被不透明路由覆盖时会被
  /// Route 的 TickerMode 静音：遮挡期间启动的动画要等恢复后才有首帧，
  /// 若进入前底栏正处于“已隐藏”的终态，返回后会停留在隐藏状态、
  /// 只剩“回到顶部”圆钮，看起来就是底栏动画没了。回到壳页时统一回显，
  /// 让滚动静显动画从可见态重新开始。
  @override
  void didPopNext() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _barController.show();
    });
  }

  @override
  void dispose() {
    app.removeListener(_restorePage);
    widget.routeObserver?.unsubscribe(this);
    if (widget.bottomBarController == null) _barController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 参考 flutter_floating_bottom_bar：底栏悬浮于内容之上，滚动时自动隐藏/
    // 回显（弹簧动画），底栏隐藏时提供“回到顶部”快捷按钮；
    // 底栏本体为自绘的胶囊栏：未选中仅图标，选中项显示图标 + 文字，
    // 点按后无过渡动画。
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
        if (index != 0) _select(0);
      },
      child: Scaffold(
        body: BottomBar(
          controller: _barController,
          layout: BottomBarLayout(
            width: UiConstants.floatingNavBarWidth,
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
              if (i != index) _select(i);
            },
          ),
        ),
      ),
    );
  }
}
