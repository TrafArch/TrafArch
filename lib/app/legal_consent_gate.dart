import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../features/settings/presentation/legal_document_links.dart';
import '../features/settings/presentation/firebase_analytics_tile.dart';
import '../platform/analytics/firebase_collection.dart';
import '../platform/browser/feedback_browser.dart';
import '../platform/storage/settings_store.dart';
import 'app_info.dart';
import 'theme/app_theme.dart';

class LegalConsentGate extends StatefulWidget {
  const LegalConsentGate({
    super.key,
    required this.child,
    this.settingsStore,
    this.screenBuilder,
  });

  final Widget child;
  final SettingsStore? settingsStore;
  final Widget Function(LegalConsentPrompt?)? screenBuilder;

  @override
  State<LegalConsentGate> createState() => _LegalConsentGateState();
}

class _LegalConsentGateState extends State<LegalConsentGate> {
  late final _store = widget.settingsStore ?? FileSettingsStore();
  bool? _accepted;
  bool _saving = false;
  String? _error;
  bool _analyticsAvailable = false;
  bool _analyticsEnabled = false;
  static const _withAnalytics = 'v2:analytics-on';
  static const _withoutAnalytics = 'v2:analytics-off';

  String _receipt(bool enabled) => enabled ? _withAnalytics : _withoutAnalytics;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _analyticsAvailable = await FirebaseCollection.available();
      _analyticsEnabled = _analyticsAvailable;
      final receipt = await _store.read(SettingsKeys.legalConsent);
      final hasChoice =
          receipt == _withAnalytics || receipt == _withoutAnalytics;
      final accepted = hasChoice || (receipt == 'true' && !_analyticsAvailable);
      _analyticsEnabled =
          _analyticsAvailable && (!hasChoice || receipt == _withAnalytics);
      if (_analyticsAvailable) {
        await FirebaseCollection.setEnabled(accepted && _analyticsEnabled);
      }
      if (mounted) setState(() => _accepted = accepted);
    } catch (_) {
      if (_analyticsAvailable) {
        await FirebaseCollection.setEnabled(false).catchError((Object _) {});
      }
      if (!mounted) return;
      setState(() {
        _accepted = false;
        _error = '无法读取同意记录，请重新确认。';
      });
    }
  }

  void _selectAnalytics(bool enabled) =>
      setState(() => _analyticsEnabled = enabled);

  Future<void> _saveConsent(bool enabled) async {
    await _store.write(
      SettingsKeys.legalConsent,
      _analyticsAvailable ? _receipt(enabled) : 'true',
    );
    if (!_analyticsAvailable) return;
    try {
      await FirebaseCollection.setEnabled(enabled);
    } catch (_) {
      if (enabled) {
        await _store.write(SettingsKeys.legalConsent, _withoutAnalytics);
        await FirebaseCollection.setEnabled(false);
      }
      rethrow;
    }
  }

  Future<void> _updateAnalytics(bool enabled) async {
    if (_saving || !_analyticsAvailable || enabled == _analyticsEnabled) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _saveConsent(enabled);
      if (mounted) setState(() => _analyticsEnabled = enabled);
    } catch (_) {
      if (mounted) setState(() => _error = '未能更新 Firebase 分析，请重试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _accept(Future<void> Function()? afterSave) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _saveConsent(_analyticsEnabled);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '未能保存同意记录，请重试。';
      });
      return;
    }
    if (!mounted) return;
    await afterSave?.call();
    if (mounted) {
      setState(() {
        _accepted = true;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_accepted == true) return _scope(widget.child, _updateAnalytics);
    final prompt = _accepted == null
        ? null
        : LegalConsentPrompt._(_saving ? null : _accept, _error);
    final screenBuilder = widget.screenBuilder;
    if (screenBuilder != null) {
      return _scope(screenBuilder(prompt), _selectAnalytics);
    }
    return _scope(
      MaterialApp(
        title: AppInfo.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(null),
        darkTheme: AppTheme.dark(null),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh'), Locale('en')],
        home: Scaffold(
          body: prompt == null
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  children: [
                    const ModalBarrier(
                      dismissible: false,
                      color: Colors.black54,
                    ),
                    SafeArea(
                      child: AlertDialog(
                        scrollable: true,
                        title: const Text(LegalConsentPrompt.title),
                        content: prompt.content(),
                        actions: prompt.actions(),
                      ),
                    ),
                  ],
                ),
        ),
      ),
      _selectAnalytics,
    );
  }

  Widget _scope(Widget child, ValueChanged<bool> onChanged) =>
      AnalyticsPreferenceScope(
        enabled: _analyticsEnabled,
        available: _analyticsAvailable,
        error: _accepted == true ? _error : null,
        onChanged: _analyticsAvailable && !_saving ? onChanged : null,
        child: child,
      );
}

class LegalConsentPrompt {
  const LegalConsentPrompt._(this._accept, this._error);

  static const title = '使用 TrafArch 前请确认';
  final Future<void> Function(Future<void> Function()?)? _accept;
  final String? _error;

  Widget content({LegalLinkNotice? onLinkNotice}) => Builder(
    builder: (context) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('请阅读以下两份文件。点按名称可查看全文，同意两者后才能继续使用。'),
        LegalDocumentLinks(
          inline: true,
          openWebLink: const MethodChannelFeedbackBrowser().open,
          onNotice: onLinkNotice,
        ),
        const FirebaseAnalyticsTile(compact: true),
        if (_error case final message?)
          Semantics(
            liveRegion: true,
            child: Text(
              message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
  );

  List<Widget> actions({Future<void> Function()? afterSave}) => [
    TextButton(
      onPressed: _accept == null ? null : SystemNavigator.pop,
      child: const Text('不同意并退出'),
    ),
    FilledButton(
      onPressed: _accept == null ? null : () => _accept(afterSave),
      child: const Text('同意并继续'),
    ),
  ];
}
