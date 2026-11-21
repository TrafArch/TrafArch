import 'package:flutter/material.dart';

import '../../../app/app_dependencies.dart';
import 'qr_page.dart';

class QrActionButton extends StatefulWidget {
  const QrActionButton({super.key, required this.app});

  final AppDependencies app;

  @override
  State<QrActionButton> createState() => _QrActionButtonState();
}

class _QrActionButtonState extends State<QrActionButton> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening || widget.app.qrAcquiring) return;
    setState(() => _opening = true);
    try {
      await widget.app.stop();
      if (!mounted) return;
      if (widget.app.nfcReleaseFailed) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(const SnackBar(content: Text('NFC 尚未关闭，请重试。')));
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/qr'),
          builder: (_) => QrPage(app: widget.app),
        ),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: '扫码',
    icon: const Icon(Icons.qr_code_scanner),
    onPressed: _opening ? null : _open,
  );
}
