import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Settings screen — reached from the user avatar menu in the top-right of
/// each main tab's AppBar.
///
/// All entries are placeholders for now. They'll be wired to real screens
/// (edit profile, change password, notification preferences, etc.) as the
/// product fills in.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _comingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Coming soon')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
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
                onTap: () => _comingSoon(context),
              ),
              const _Divider(),
              _SettingsTile(
                icon: Icons.lock_outline,
                title: 'Change password',
                onTap: () => _comingSoon(context),
              ),
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
                onTap: () => _comingSoon(context),
              ),
              const _Divider(),
              _SettingsTile(
                icon: Icons.schedule,
                title: 'Scan reminders',
                onTap: () => _comingSoon(context),
              ),
              const _Divider(),
              _SettingsTile(
                icon: Icons.color_lens_outlined,
                title: 'Appearance',
                onTap: () => _comingSoon(context),
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
                onTap: () => _comingSoon(context),
              ),
              const _Divider(),
              _SettingsTile(
                icon: Icons.help_outline,
                title: 'Help & support',
                onTap: () => _comingSoon(context),
              ),
              const _Divider(),
              _SettingsTile(
                icon: Icons.info_outline,
                title: 'App version',
                trailing: const Text(
                  '0.1.0',
                  style: TextStyle(color: AppTheme.textSecondary),
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: AppTheme.textSecondary,
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
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: trailing ??
          (onTap != null
              ? const Icon(Icons.chevron_right, color: AppTheme.textSecondary)
              : null),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, indent: 56, color: Color(0xFFEDF1F3));
  }
}
