import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../gallery/gallery_app.dart';
import '../gallery/gallery_preferences.dart';
import '../platform/browser/feedback_browser.dart';
import '../platform/storage/settings_store.dart';
import 'app_dependencies.dart';
import 'beta_ui_scope.dart';
import 'trafarch_app.dart';

/// Recreates each UI on switching, disposing the previous session and timers.
class InternalPreviewApp extends StatefulWidget {
  const InternalPreviewApp({
    super.key,
    this.createDependencies,
    this.previewSettingsStore,
  });
  final AppDependencies Function()? createDependencies;
  final SettingsStore? previewSettingsStore;
  @override
  State<InternalPreviewApp> createState() => _InternalPreviewAppState();
}

class _InternalPreviewAppState extends State<InternalPreviewApp> {
  bool _enabled = false;
  late final GalleryPreferences _preferences;
  late final SettingsStore _settingsStore;

  @override
  void initState() {
    super.initState();
    final store = _settingsStore =
        widget.previewSettingsStore ?? FileSettingsStore();
    _preferences = GalleryPreferences(
      readEnabled: () async =>
          await store.read(SettingsKeys.galleryPredictiveBackEnabled) !=
          'false',
      writeEnabled: (value) =>
          store.write(SettingsKeys.galleryPredictiveBackEnabled, '$value'),
    )..load();
  }

  @override
  void dispose() {
    _preferences.dispose();
    super.dispose();
  }

  void _switch(bool enabled) => setState(() => _enabled = enabled);
  @override
  Widget build(BuildContext context) => BetaUiScope(
    enabled: _enabled,
    onChanged: _switch,
    child: _enabled
        ? GalleryApp(
            key: const ValueKey('new-ui'),
            preferences: _preferences,
            onDisableBeta: () => _switch(false),
            openWebLink: const MethodChannelFeedbackBrowser().open,
            openEmail: (address) => launchUrl(
              Uri(scheme: 'mailto', path: address),
              mode: LaunchMode.externalApplication,
            ),
          )
        : TransitCardAnalyzerApp(
            key: const ValueKey('current-ui'),
            createDependencies:
                widget.createDependencies ??
                () => AppDependencies(settingsStore: _settingsStore),
            enableUpdateChecks: false,
          ),
  );
}
