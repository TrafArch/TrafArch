import 'package:flutter/material.dart';

import '../app_dependencies.dart';

/// Named recoverable screens only. Transient dialogs keep their parent screen.
class RecoveryRouteObserver extends RouteObserver<PageRoute<dynamic>> {
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
