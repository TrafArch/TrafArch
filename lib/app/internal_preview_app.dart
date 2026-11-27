import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../gallery/gallery_app.dart';
import '../gallery/gallery_preferences.dart';
import '../platform/browser/feedback_browser.dart';
import '../platform/storage/settings_store.dart';

class InternalPreviewApp extends StatefulWidget {
  const InternalPreviewApp({super.key, this.previewSettingsStore});
  final SettingsStore? previewSettingsStore;
  @override
  State<InternalPreviewApp> createState() => _InternalPreviewAppState();
}

class _InternalPreviewAppState extends State<InternalPreviewApp> {
  late final GalleryPreferences _preferences;

  @override
  void initState() {
    super.initState();
    final store = widget.previewSettingsStore ?? FileSettingsStore();
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

  @override
  Widget build(BuildContext context) => GalleryApp(
    preferences: _preferences,
    openWebLink: const MethodChannelFeedbackBrowser().open,
    openEmail: (address) => launchUrl(
      Uri(scheme: 'mailto', path: address),
      mode: LaunchMode.externalApplication,
    ),
  );
}
