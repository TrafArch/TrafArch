import 'package:flutter/material.dart';

class AnalyticsPreferenceScope extends InheritedWidget {
  const AnalyticsPreferenceScope({
    super.key,
    required this.enabled,
    required this.available,
    required this.onChanged,
    this.error,
    required super.child,
  });

  final bool enabled, available;
  final String? error;
  final ValueChanged<bool>? onChanged;

  static AnalyticsPreferenceScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AnalyticsPreferenceScope>();

  @override
  bool updateShouldNotify(AnalyticsPreferenceScope oldWidget) =>
      enabled != oldWidget.enabled ||
      available != oldWidget.available ||
      onChanged != oldWidget.onChanged ||
      error != oldWidget.error;
}

class FirebaseAnalyticsTile extends StatelessWidget {
  const FirebaseAnalyticsTile({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final preference = AnalyticsPreferenceScope.maybeOf(context);
    return SwitchListTile(
      contentPadding: compact ? EdgeInsets.zero : null,
      secondary: compact ? null : const Icon(Icons.analytics_outlined),
      title: const Text('Firebase 分析'),
      subtitle: Text(
        preference?.error ??
            (preference?.available != true
                ? '此版本未启用 Firebase 分析。'
                : compact
                ? '同意后向 Google Firebase 发送应用使用统计。关闭也可继续使用。'
                : '向 Google Firebase 发送应用使用统计。关闭不影响读卡。'),
      ),
      value: preference?.enabled ?? false,
      onChanged: preference?.onChanged,
    );
  }
}
