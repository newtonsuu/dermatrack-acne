import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared building blocks for the Settings screens (the main Settings list and
/// its sub-screens: Notifications, Scan reminder, Privacy & data, Help &
/// support). Keeps the visual language consistent and avoids re-declaring the
/// same private tile widgets in every file.

/// Uppercase section label above a [SettingsCard].
class SettingsSectionLabel extends StatelessWidget {
  const SettingsSectionLabel(this.text, {super.key});
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

/// Rounded card wrapping a column of settings rows.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(child: Column(children: children));
  }
}

/// Hairline divider between rows inside a [SettingsCard].
class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, indent: 56, color: AppTheme.border(context));
  }
}

/// Tappable row with a leading icon, title, optional subtitle + trailing.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
    this.titleColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: iconColor ?? AppTheme.primary),
      title: Text(
        title,
        style: TextStyle(
          color: titleColor ?? AppTheme.textPrimary(context),
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: TextStyle(
                color: AppTheme.textSecondary(context),
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
      trailing: trailing ??
          (onTap != null
              ? Icon(Icons.chevron_right, color: AppTheme.textSecondary(context))
              : null),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}

/// Row with a trailing [Switch]. The whole row toggles when tapped.
class SettingsSwitchTile extends StatelessWidget {
  const SettingsSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeColor: AppTheme.primary,
      secondary: Icon(
        icon,
        color: onChanged == null
            ? AppTheme.textSecondary(context)
            : AppTheme.primary,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: AppTheme.textPrimary(context),
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: TextStyle(
                color: AppTheme.textSecondary(context),
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}

/// A simple paragraph block used for privacy notices, disclaimers, etc.
class SettingsProse extends StatelessWidget {
  const SettingsProse(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Text(
        text,
        style: TextStyle(
          color: AppTheme.textSecondary(context),
          fontSize: 13.5,
          height: 1.5,
        ),
      ),
    );
  }
}
