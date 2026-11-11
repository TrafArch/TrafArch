import 'package:flutter/material.dart';

import '../app_dependencies.dart';

/// Named recoverable screens only. Transient dialogs keep their parent screen.
///
/// 泛型取 [ModalRoute] 而非 [PageRoute]：保存卡片等对话框是 [DialogRoute]
/// （非 PageRoute），若只观察 PageRoute，关闭对话框时 [RouteObserver.didPop]
/// 的 `route is R` 判定不成立，壳页收不到 didPopNext，悬浮底栏会卡在隐藏态。
/// 恢复路由栈仍只收录 PageRoute（见 [_sync]），对话框不影响恢复目标。
class RecoveryRouteObserver extends RouteObserver<ModalRoute<dynamic>> {
  RecoveryRouteObserver(this.app);
  final AppDependencies app;
  final List<Route<dynamic>> _stack = [];

  void _sync() {
    app.recoveryRoute = _stack.reversed
        .whereType<PageRoute<dynamic>>()
        .map((route) => route.settings.name)
        .whereType<String>()
        .firstOrNull;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _stack.add(route);
    _sync();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _stack.remove(route);
    _sync();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _stack.remove(route);
    _sync();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    final index = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _stack.removeAt(index);
      } else {
        _stack[index] = newRoute;
      }
    }
    _sync();
  }
}
