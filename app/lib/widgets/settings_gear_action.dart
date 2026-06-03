import 'package:flutter/material.dart';

import '../screens/settings_screen.dart';

/// AppBar action: a Settings gear that opens [SettingsScreen]. Replaces the
/// duplicate profile avatar that used to sit in tab headers (the profile blade
/// lives on the home page and the Profile tab; the header just needs quick
/// access to settings).
class SettingsGearAction extends StatelessWidget {
  const SettingsGearAction({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Settings',
      icon: const Icon(Icons.settings_outlined),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      ),
    );
  }
}
