import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'change_password_screen.dart';
import 'edit_profile_screen.dart';

/// Settings screen — reached from the user avatar menu in the top-right of
/// each main tab's AppBar.
///
/// Most entries are still placeholders. The Appearance section is wired up:
/// it drives the app-wide [ThemeController] (Light / Dark / System) and
/// persists the choice across launches.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    ThemeController.instance.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    ThemeController.instance.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  void _comingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Coming soon')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const _SectionLabel('Account'),
          const SizedBox(height: 8),
          _SettingsCard(
            children: [
              _SettingsTile(
                icon: Icons.person_outline,
                title: 'Edit profile',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const EditProfileScreen(),
                  ),
                ),
              ),
              const _Divider(),
              _SettingsTile(
                icon: Icons.lock_outline,
                title: 'Change password',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ChangePasswordScreen(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const _SectionLabel('Appearance'),
          const SizedBox(height: 8),
          _SettingsCard(
            children: [
              const _ThemeModeTile(),
            ],
          ),
          const SizedBox(height: 20),
          const _SectionLabel('Preferences'),
          const SizedBox(height: 8),
          _SettingsCard(
            children: [
              _SettingsTile(
                icon: Icons.notifications_outlined,
                title: 'Notifications',
                onTap: _comingSoon,
              ),
              const _Divider(),
              _SettingsTile(
                icon: Icons.schedule,
                title: 'Scan reminders',
                onTap: _comingSoon,
              ),
            ],
          ),
          const SizedBox(height: 20),
          const _SectionLabel('About'),
          const SizedBox(height: 8),
          _SettingsCard(
            children: [
              _SettingsTile(
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy & data',
                onTap: _comingSoon,
              ),
              const _Divider(),
              _SettingsTile(
                icon: Icons.help_outline,
                title: 'Help & support',
                onTap: _comingSoon,
              ),
              const _Divider(),
              _SettingsTile(
                icon: Icons.info_outline,
                title: 'App version',
                trailing: Text(
                  '0.1.0',
                  style: TextStyle(color: AppTheme.textSecondary(context)),
                ),
                onTap: null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Inline theme-mode picker. Uses a SegmentedButton so all three options
/// (Light / Dark / System) are visible at a glance and switching takes one tap.
class _ThemeModeTile extends StatelessWidget {
  const _ThemeModeTile();

  @override
  Widget build(BuildContext context) {
    final currentMode = ThemeController.instance.mode;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.color_lens_outlined, color: AppTheme.primary),
              const SizedBox(width: 12),
              Text(
                'Theme',
                style: TextStyle(
                  color: AppTheme.textPrimary(context),
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: Text(
              _modeDescription(currentMode),
              style: TextStyle(
                color: AppTheme.textSecondary(context),
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.light,
                label: Text('Light'),
                icon: Icon(Icons.light_mode_outlined),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                label: Text('Dark'),
                icon: Icon(Icons.dark_mode_outlined),
              ),
              ButtonSegment(
                value: ThemeMode.system,
                label: Text('System'),
                icon: Icon(Icons.brightness_auto_outlined),
              ),
            ],
            selected: {currentMode},
            onSelectionChanged: (selection) {
              if (selection.isNotEmpty) {
                ThemeController.instance.setMode(selection.first);
              }
            },
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor:
                  AppTheme.primary.withValues(alpha: 0.15),
              selectedForegroundColor: AppTheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  static String _modeDescription(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Always use the light theme.';
      case ThemeMode.dark:
        return 'Always use the dark theme.';
      case ThemeMode.system:
        return 'Match your device setting.';
    }
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: AppTheme.textSecondary(context),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(child: Column(children: children));
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: AppTheme.primary),
      title: Text(
        title,
        style: TextStyle(
          color: AppTheme.textPrimary(context),
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: trailing ??
          (onTap != null
              ? Icon(Icons.chevron_right,
                  color: AppTheme.textSecondary(context))
              : null),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 56,
      color: AppTheme.border(context),
    );
  }
}
