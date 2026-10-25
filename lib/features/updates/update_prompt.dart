import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'update_service.dart';

class UpdatePrompt extends StatefulWidget {
  const UpdatePrompt({
    super.key,
    required this.service,
    required this.child,
    this.openUrl,
  });
  final UpdateService service;
  final Widget child;
  final Future<bool> Function(Uri)? openUrl;
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
        !manifest.isNewerThan(widget.service.currentBuild)) {
      return;
    }
    await showUpdateDialog(context, manifest, openUrl: widget.openUrl);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> showUpdateDialog(
  BuildContext context,
  UpdateManifest manifest, {
  Future<bool> Function(Uri)? openUrl,
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
