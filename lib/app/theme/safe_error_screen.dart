import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Debug/profile retain Flutter's normal reporting and ErrorWidget. Release
/// diagnostics omit exception messages, stack traces, card data and file paths.
void installReleaseErrorPresentation() {
  if (!kReleaseMode) return;
  FlutterError.onError = (details) {
    developer.log(
      'UI_RENDER_FAILED (${details.exception.runtimeType})',
      name: 'TrafArch.ui',
      level: 1000,
    );
  };
  ErrorWidget.builder = (_) => const SafeErrorScreen();
}

/// Basic widgets also work when the failing tree has no MaterialApp ancestor.
class SafeErrorScreen extends StatelessWidget {
  const SafeErrorScreen({super.key});
  @override
  Widget build(BuildContext context) => const Directionality(
    textDirection: TextDirection.ltr,
    child: ColoredBox(
      color: Color(0xFFF5F7F7),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '暂时无法显示此页面\n\n请返回上一页后重试；若仍无法恢复，请重新打开应用。\n\n问题代码：UI_RENDER_FAILED',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF243737),
              fontSize: 16,
              height: 1.5,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    ),
  );
}
