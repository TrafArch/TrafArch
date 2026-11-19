import 'package:flutter/material.dart';

import '../../../platform/browser/feedback_browser.dart';
import '../../../shared/app_support.dart';

typedef LegalLinkNotice = void Function(
  BuildContext context,
  String message, {
  required bool copied,
});

class LegalDocumentLinks extends StatefulWidget {
  const LegalDocumentLinks({
    super.key,
    required this.openWebLink,
    this.inline = false,
    this.onNotice,
  });

  final Future<void> Function(Uri) openWebLink;
  final bool inline;
  final LegalLinkNotice? onNotice;

  @override
  State<LegalDocumentLinks> createState() => _LegalDocumentLinksState();
}

class _LegalDocumentLinksState extends State<LegalDocumentLinks> {
  bool _opening = false;

  Future<void> _open(String url, String label) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.openWebLink(Uri.parse(url));
    } catch (error) {
      if (!mounted) return;
      final message = error is FeedbackBrowserException
          ? error.message
          : '无法打开$label，请稍后重试。';
      final notice = widget.onNotice;
      if (notice == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      } else {
        notice(
          context,
          message,
          copied: error is FeedbackBrowserException && error.copiedToClipboard,
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget link(String label, String url, IconData icon) {
      final onTap = _opening ? null : () => _open(url, label);
      return widget.inline
          ? TextButton(onPressed: onTap, child: Text(label))
          : Card(
              child: ListTile(
                leading: Icon(icon),
                title: Text(label),
                enabled: !_opening,
                onTap: onTap,
              ),
            );
    }

    final eula = link(
      AppSupport.eulaLabel,
      AppSupport.eula,
      Icons.description_outlined,
    );
    final privacy = link(
      '隐私政策',
      AppSupport.privacy,
      Icons.privacy_tip_outlined,
    );
    return widget.inline
        ? Wrap(children: [eula, privacy])
        : Column(children: [privacy, const SizedBox(height: 8), eula]);
  }
}
