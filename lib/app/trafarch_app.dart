import 'dart:async';

import 'package:flutter/widgets.dart';

import '../gallery/gallery_app.dart';
import '../gallery/gallery_preferences.dart';
import '../platform/storage/settings_store.dart';
import 'app_dependencies.dart';

class TransitCardAnalyzerApp extends StatefulWidget {
  const TransitCardAnalyzerApp({
    super.key,
    this.createDependencies,
    this.enableUpdateChecks = true,
  });

  /// The root widget owns the returned state's initialization and disposal.
  final AppDependencies Function()? createDependencies;
  final bool enableUpdateChecks;

  @override
  State<TransitCardAnalyzerApp> createState() => _TransitCardAnalyzerAppState();
}

class _TransitCardAnalyzerAppState extends State<TransitCardAnalyzerApp>
    with WidgetsBindingObserver {
  late final AppDependencies _app;
  late final GalleryPreferences _preferences;
  bool _startupUpdateShown = false;

  @override
  void initState() {
    super.initState();
    _app = widget.createDependencies?.call() ?? AppDependencies();
    final store = _app.settings.store;
    _preferences = GalleryPreferences(
      readEnabled: () async =>
          await store.read(SettingsKeys.galleryPredictiveBackEnabled) !=
          'false',
      writeEnabled: (value) =>
          store.write(SettingsKeys.galleryPredictiveBackEnabled, '$value'),
    )..load();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_app.init());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _preferences.dispose();
    _app.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached) &&
        _app.scanning) {
      unawaited(_app.stop());
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_app.flushDiagnostics());
    }
  }

  @override
  void didHaveMemoryPressure() {
    unawaited(_app.handleMemoryPressure(false));
  }

  bool _claimStartupUpdatePrompt() {
    if (_startupUpdateShown) return false;
    _startupUpdateShown = true;
    return true;
  }

  @override
  Widget build(BuildContext context) => GalleryApp(
    liveApp: _app,
    preferences: _preferences,
    claimStartupUpdatePrompt: widget.enableUpdateChecks
        ? _claimStartupUpdatePrompt
        : null,
    openWebLink: _app.openWebLink,
    openEmail: _app.openFeedbackEmail,
  );
}
