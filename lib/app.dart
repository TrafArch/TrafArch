import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_floating_bottom_bar/flutter_floating_bottom_bar.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import 'core/ui_constants.dart';
import 'core/app_info.dart';
import 'state/app_state.dart';
import 'features/home/home_page.dart';
import 'features/trips/trips_page.dart';
import 'features/expert/expert_page.dart';

class TransitCardAnalyzerApp extends StatelessWidget {
  const TransitCardAnalyzerApp({super.key});

  static final _fallbackLight = ColorScheme.fromSeed(
    seedColor: Colors.teal,
    brightness: Brightness.light,
  );
  static final _fallbackDark = ColorScheme.fromSeed(
    seedColor: Colors.teal,
    brightness: Brightness.dark,
  );

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return MaterialApp(
          title: AppInfo.appName,
          debugShowCheckedModeBanner: false,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('zh'),
            Locale('en'),
          ],
          theme: ThemeData(
            colorScheme: lightDynamic ?? _fallbackLight,
          ),
          darkTheme: ThemeData(
            colorScheme: darkDynamic ?? _fallbackDark,
          ),
          themeMode: ThemeMode.system,
          home: const AppShell(),
        );
      },
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;
  late final AppState app;

  @override
  void initState() {
    super.initState();
    app = AppState();
    // 启动即加载知识库（assets/data/*.json），失败自动降级为空库
    app.init();
  }

  @override
  void dispose() {
    app.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 参考 flutter_floating_bottom_bar：底栏悬浮于内容之上，滚动时自动隐藏/
    // 回显（弹簧动画），底栏隐藏时提供“回到顶部”快捷按钮；
    // 底栏本体参考 google_nav_bar（Telegram 式展开）：
    // 未选中仅显示图标，选中项胶囊高亮 + 文字从图标旁展开/收起。
    return Scaffold(
      body: BottomBar(
        layout: BottomBarLayout.adaptive(
          maxWidth: 520,
          offset: UiConstants.floatingNavBarInset,
          borderRadius:
              BorderRadius.circular(UiConstants.floatingNavBarRadius),
        ),
        scrollBehavior: BottomBarScrollBehavior(
          hideOnScroll: true,
          deltaThreshold: 12.0,
          showAtStart: true,
          showOnScrollEnd: true,
          // 专家页为 NestedScrollView：外层（depth 0）负责收起标题栏，正文
          // 长列表（depth ≥ 1）才是主要滑动来源，两者都要驱动底栏隐藏，
          // 拦截规则见 _bottomBarScrollPredicate。
          predicate: _bottomBarScrollPredicate,
        ),
        iconTooltip: '回到顶部',
        iconSemanticLabel: '回到顶部',
        // 3.0.0 起 child（悬浮栏本体）与 body 同为必填参数
        child: _FloatingNavBar(
          index: index,
          onSelect: (i) {
            if (i != index) setState(() => index = i);
          },
        ),
        body: IndexedStack(
          index: index,
          children: [
            HomePage(app: app, active: index == 0),
            TripsPage(app: app),
            ExpertPage(app: app),
          ],
        ),
      ),
    );
  }
}

/// 悬浮底栏滚动显隐过滤器。
///
/// - 普通页面（首页/行程页）的直接滚动通知 depth 为 0，总是放行；
/// - 专家页为 NestedScrollView：正文 ListView 经 TabBarView 的 PageView 与
///   外层两个视口，通知 depth ≥ 1，同样放行以驱动长滑动时的隐藏/回显，
///   但有两类通知需拦截：
///   1) 正文的 ScrollStart：正文停在顶部（pixels == minScrollExtent）时会
///      命中 showAtStart 的强制回显，与"收起标题栏时隐藏底栏"的动作相悖；
///   2) 外层的 ScrollEnd：fling 起手瞬间外层会先结算出一条"伪结束"通知
///      （此时正文仍在惯性滚动），放行会让底栏提前回显，故正文未停时忽略。
bool _bottomBarScrollPredicate(ScrollNotification notification) {
  if (notification.depth > 0) {
    return notification is! ScrollStartNotification;
  }
  if (notification is ScrollEndNotification) {
    final nested = notification.context
        ?.findAncestorStateOfType<NestedScrollViewState>();
    if (nested != null &&
        nested.innerController.positions
            .any((position) => position.isScrollingNotifier.value)) {
      return false;
    }
  }
  return true;
}

/// 悬浮底栏本体：GNav（Telegram 式展开：未选中仅图标，选中项胶囊 +
/// 文字展开）+ 圆角阴影容器，视觉高度与 [UiConstants.floatingNavBarHeight] 一致。
class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({required this.index, required this.onSelect});

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
            GButton(
              icon: Icons.home_outlined,
              text: '首页',
              semanticLabel: '首页',
            ),
            GButton(
              icon: Icons.directions_transit_outlined,
              text: '行程',
              semanticLabel: '行程',
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
