import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'update_service.dart';

class UpdatePrompt extends StatefulWidget {
  const UpdatePrompt({
    super.key,
    required this.service,
    required this.child,
    this.openUrl,
    this.shouldShow,
  });
  final UpdateService service;
  final Widget child;
  final Future<bool> Function(Uri)? openUrl;
  final bool Function()? shouldShow;
  @override
  State<UpdatePrompt> createState() => _UpdatePromptState();
}

class _UpdatePromptState extends State<UpdatePrompt> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    final manifest = await widget.service.checkOnce();
    if (!mounted ||
        manifest == null ||
        !manifest.isNewerThan(widget.service.currentBuild) ||
        widget.shouldShow?.call() == false) {
      return;
    }
    await showUpdateDialog(context, manifest, openUrl: widget.openUrl);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class UpdateCheckButton extends StatefulWidget {
  const UpdateCheckButton({
    super.key,
    required this.service,
    this.openUrl,
    this.onFeedback,
  });

  final UpdateService service;
  final Future<bool> Function(Uri)? openUrl;
  final void Function(String message, bool isError)? onFeedback;

  @override
  State<UpdateCheckButton> createState() => _UpdateCheckButtonState();
}

class _UpdateCheckButtonState extends State<UpdateCheckButton>
    with AutomaticKeepAliveClientMixin<UpdateCheckButton> {
  bool _checking = false;

  @override
  bool get wantKeepAlive => true;

  Future<void> _checkUpdates() async {
    if (_checking || !widget.service.isConfigured) return;
    setState(() => _checking = true);
    try {
      final manifest = await widget.service.checkNow();
      if (!mounted || manifest == null) return;
      setState(() => _checking = false);
      if (manifest.isNewerThan(widget.service.currentBuild)) {
        await showUpdateDialog(
          context,
          manifest,
          openUrl: widget.openUrl,
          onDownloadFailure: (message) => _feedback(message, isError: true),
        );
      } else {
        _feedback('暂无更新', isError: false);
      }
    } catch (_) {
      if (mounted) _feedback('检查更新失败，请稍后重试', isError: true);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _feedback(String message, {required bool isError}) {
    if (widget.onFeedback case final onFeedback?) {
      onFeedback(message, isError);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return OutlinedButton.icon(
      onPressed: _checking ? null : _checkUpdates,
      icon: _checking
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.system_update_outlined),
      label: Text(_checking ? '正在检查…' : '检查更新'),
    );
  }
}

Future<void> showUpdateDialog(
  BuildContext context,
  UpdateManifest manifest, {
  Future<bool> Function(Uri)? openUrl,
  ValueChanged<String>? onDownloadFailure,
}) => showDialog<void>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    title: Text('发现新版本 ${manifest.version}'),
    content: SingleChildScrollView(child: Text(manifest.notes)),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: const Text('暂不更新'),
      ),
      TextButton(
        onPressed: () async {
          var opened = false;
          try {
            opened =
                await (openUrl?.call(manifest.downloadUrl) ??
                    launchUrl(
                      manifest.downloadUrl,
                      mode: LaunchMode.externalApplication,
                    ));
          } catch (_) {
            /* Report launch failure without crashing the app. */
          }
          if (!context.mounted || !dialogContext.mounted) return;
          if (opened) {
            Navigator.pop(dialogContext);
          } else if (onDownloadFailure != null) {
            onDownloadFailure('无法打开下载链接，请稍后重试');
          } else {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('无法打开下载链接，请稍后重试')));
          }
        },
        child: const Text('前往下载'),
      ),
    ],
  ),
);
