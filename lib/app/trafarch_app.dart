import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:dynamic_color/dynamic_color.dart';

import 'app_info.dart';
import 'app_dependencies.dart';
import 'theme/app_theme.dart';
import 'navigation/app_shell.dart';
import '../features/updates/update_prompt.dart';
import '../shared/presentation/adaptive_layout.dart';
import 'navigation/recovery_route_observer.dart';
import '../gallery/gallery_app.dart';
import '../gallery/gallery_preferences.dart';
import '../platform/storage/settings_store.dart';
import 'beta_ui_scope.dart';

export 'navigation/app_shell.dart' show AppShell;

class TransitCardAnalyzerApp extends StatefulWidget {
  const TransitCardAnalyzerApp({
    super.key,
    this.createDependencies,
    this.enableUpdateChecks = true,
    this.enableLiveBeta = false,
    this.initialLiveUi = false,
  });

  /// The root widget owns the returned state's initialization and disposal.
  final AppDependencies Function()? createDependencies;
  final bool enableUpdateChecks;
  final bool enableLiveBeta;
  final bool initialLiveUi;

  @override
  State<TransitCardAnalyzerApp> createState() => _TransitCardAnalyzerAppState();
}

class _TransitCardAnalyzerAppState extends State<TransitCardAnalyzerApp>
    with WidgetsBindingObserver {
  /// 应用级状态在根部创建，向下传递给 [AppShell] 与各功能页；
  /// 由本 Widget 负责 init/dispose。
  late final AppDependencies _app;

  /// 仅镜像 [AppDependencies.monetEnabled] 的独立通知器：
  /// AppDependencies 的 notifyListeners 会在读卡/扫码/日志等高频场景触发，
  /// 若直接监听会让 MaterialApp 反复重建；此处只在莫奈开关翻转时
  /// 才通知上层重建主题。
  final ValueNotifier<bool> _monetEnabled = ValueNotifier<bool>(true);

  /// AppShell 需要感知”被其他页面或对话框覆盖后再回显”：扫码解析、设置等
  /// 页面以及保存卡片对话框 pop 回来时靠它恢复悬浮底栏的显隐动画。
  late final RouteObserver<ModalRoute<dynamic>> _routeObserver;
  GalleryPreferences? _livePreferences;
  bool _live = false;
  bool _switching = false;
  String? _switchError;

  @override
  void initState() {
    super.initState();
    _app = widget.createDependencies?.call() ?? AppDependencies();
    _live = widget.enableLiveBeta && widget.initialLiveUi;
    if (_live) _ensureLivePreferences();
    _routeObserver = RecoveryRouteObserver(_app);
    WidgetsBinding.instance.addObserver(this);
    _monetEnabled.value = _app.monetEnabled;
    _app.addListener(_syncMonetFromDependencies);
    // 根组件拥有设置和本地参考数据的初始化与释放；加载问题由各功能页展示。
    _app.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _app.removeListener(_syncMonetFromDependencies);
    _livePreferences?.dispose();
    _app.dispose();
    _monetEnabled.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_live &&
        (state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached) &&
        _app.scanning) {
      unawaited(_app.stop());
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _app.flushDiagnostics();
    }
  }

  @override
  void didHaveMemoryPressure() {
    _app.handleMemoryPressure(false);
  }

  void _syncMonetFromDependencies() {
    if (_monetEnabled.value != _app.monetEnabled) {
      _monetEnabled.value = _app.monetEnabled;
    }
  }

  void _ensureLivePreferences() {
    final store = _app.settings.store;
    _livePreferences ??= GalleryPreferences(
      readEnabled: () async =>
          await store.read(SettingsKeys.galleryPredictiveBackEnabled) !=
          'false',
      writeEnabled: (value) =>
          store.write(SettingsKeys.galleryPredictiveBackEnabled, '$value'),
    )..load();
  }

  Future<void> _switchLiveUi(bool enabled) async {
    if (_switching || enabled == _live || _app.qrAcquiring) return;
    setState(() {
      _switching = true;
      _switchError = null;
    });
    await _app.stop();
    if (!mounted) return;
    if (_app.nfcReleaseFailed) {
      setState(() {
        _switching = false;
        _switchError = 'NFC 尚未关闭，无法切换。请重试。';
      });
      return;
    }
    _app.scan.autoScanConsumed = true;
    _ensureLivePreferences();
    setState(() {
      _switching = false;
      _live = enabled;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enableLiveBeta) return _legacyUi();
    return BetaUiScope(
      enabled: _live,
      live: true,
      switching: _switching,
      switchError: _switchError,
      onChanged: _switchLiveUi,
      child: _live
          ? GalleryApp(
              liveApp: _app,
              preferences: _livePreferences,
              onDisableBeta: () => _switchLiveUi(false),
              openWebLink: _app.openWebLink,
              openEmail: _app.openFeedbackEmail,
            )
          : _legacyUi(),
    );
  }

  Widget _legacyUi() {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return ValueListenableBuilder<bool>(
          valueListenable: _monetEnabled,
          // AppShell 作为 child 传入，避免莫奈开关翻转时重建整棵子树
          child: widget.enableUpdateChecks
              ? UpdatePrompt(
                  service: _app.updates,
                  child: AppShell(app: _app, routeObserver: _routeObserver),
                )
              : AppShell(app: _app, routeObserver: _routeObserver),
          builder: (context, monet, child) {
            return MaterialApp(
              title: AppInfo.appName,
              debugShowCheckedModeBanner: false,
              navigatorObservers: [_routeObserver],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('zh'), Locale('en')],
              // 莫奈取色开关关闭时忽略 dynamic_color 提供的系统色，
              // 回落到内置蓝色 seed（取自应用图标的卡片图形 #4E7098）；
              // 开关开启但系统不支持（Android 12 以下 / 非 Android 平台）
              // 时，dynamic 为 null 同样回落。
              theme: AppTheme.light(monet ? lightDynamic : null),
              darkTheme: AppTheme.dark(monet ? darkDynamic : null),
              themeMode: ThemeMode.system,
              builder: (context, child) => FoldableDisplayScope(
                child: AnnotatedRegion<SystemUiOverlayStyle>(
                  value: AppTheme.systemUiOverlayStyle(
                    Theme.of(context).scaffoldBackgroundColor,
                  ),
                  child: child!,
                ),
              ),
              home: child,
            );
          },
        );
      },
    );
  }
}
