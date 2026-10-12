import 'package:flutter/material.dart';
import '../../state/app_state.dart';
import 'settings_page.dart';

class SettingsActionButton extends StatelessWidget {
  final AppState app;
  const SettingsActionButton({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '设置',
      icon: const Icon(Icons.settings_outlined),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SettingsPage(app: app)),
      ),
    );
  }
}