import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../features/settings/presentation/legal_document_links.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final accepted = await _store.read(SettingsKeys.legalConsent) == 'true';
      if (mounted) setState(() => _accepted = accepted);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _accepted = false;
        _error = '无法读取同意记录，请重新确认。';
      });
    }
  }

  Future<void> _accept(Future<void> Function()? afterSave) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _store.write(SettingsKeys.legalConsent, 'true');
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
    if (mounted) setState(() => _accepted = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_accepted == true) return widget.child;
    final prompt = _accepted == null
        ? null
        : LegalConsentPrompt._(_saving ? null : _accept, _error);
    final screenBuilder = widget.screenBuilder;
    if (screenBuilder != null) return screenBuilder(prompt);
    return MaterialApp(
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
                  const ModalBarrier(dismissible: false, color: Colors.black54),
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
    );
  }
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
