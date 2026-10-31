import 'package:flutter/widgets.dart';

import '../gallery/gallery_app.dart';
import 'app_dependencies.dart';
import 'beta_ui_scope.dart';
import 'trafarch_app.dart';

/// Recreates each UI on switching, disposing the previous session and timers.
class InternalPreviewApp extends StatefulWidget {
  const InternalPreviewApp({super.key, this.createDependencies});
  final AppDependencies Function()? createDependencies;
  @override
  State<InternalPreviewApp> createState() => _InternalPreviewAppState();
}

class _InternalPreviewAppState extends State<InternalPreviewApp> {
  bool _enabled = false;
  void _switch(bool enabled) => setState(() => _enabled = enabled);
  @override
  Widget build(BuildContext context) => BetaUiScope(
    enabled: _enabled,
    onChanged: _switch,
    child: _enabled
        ? GalleryApp(
            key: const ValueKey('new-ui'),
            onDisableBeta: () => _switch(false),
          )
        : TransitCardAnalyzerApp(
            key: const ValueKey('current-ui'),
            createDependencies: widget.createDependencies,
            enableUpdateChecks: false,
          ),
  );
}
