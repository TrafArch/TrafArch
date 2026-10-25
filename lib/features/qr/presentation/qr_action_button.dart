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
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.app.stop();
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => QrPage(app: widget.app)),
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
