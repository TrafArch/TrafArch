import 'package:flutter/widgets.dart';

/// Available only in the internal preview host. The flag is session-local.
class BetaUiScope extends InheritedWidget {
  const BetaUiScope({
    super.key,
    required this.enabled,
    required this.onChanged,
    required super.child,
  });
  final bool enabled;
  final ValueChanged<bool> onChanged;
  static BetaUiScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BetaUiScope>();
  @override
  bool updateShouldNotify(BetaUiScope oldWidget) =>
      enabled != oldWidget.enabled;
}
