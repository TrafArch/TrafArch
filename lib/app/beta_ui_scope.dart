import 'package:flutter/widgets.dart';

class BetaUiScope extends InheritedWidget {
  const BetaUiScope({
    super.key,
    required this.enabled,
    required this.onChanged,
    this.live = false,
    this.switching = false,
    this.switchError,
    required super.child,
  });
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final bool live;
  final bool switching;
  final String? switchError;
  static BetaUiScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BetaUiScope>();
  @override
  bool updateShouldNotify(BetaUiScope oldWidget) =>
      enabled != oldWidget.enabled ||
      live != oldWidget.live ||
      switching != oldWidget.switching ||
      switchError != oldWidget.switchError;
}
