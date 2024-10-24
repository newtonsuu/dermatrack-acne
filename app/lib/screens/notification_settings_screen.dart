import 'package:flutter/material.dart';

import '../services/notification_prefs_service.dart';
import '../services/scan_reminder_service.dart';
import '../theme/app_theme.dart';
import '../widgets/settings_widgets.dart';
import 'scan_reminder_screen.dart';

/// Notification preferences: a master switch, per-category toggles, and a
/// quick reminder time control. Persisted via [NotificationPrefsService] and
/// [ScanReminderService].
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final _prefs = NotificationPrefsService.instance;
  final _reminder = ScanReminderService.instance;

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onChange);
    _reminder.addListener(_onChange);
  }

  @override
  void dispose() {
    _prefs.removeListener(_onChange);
    _reminder.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _toggleReminder(bool value) async {
    try {
      await _reminder.setEnabled(value);
      if (value && _reminder.permissionGranted == false) {
        _snack('Enable notifications for DermaTrack in your phone settings '
            'to receive reminders.');
      } else {
        _snack(value ? 'Daily scan reminder on.' : 'Daily scan reminder off.');
      }
    } catch (e) {
      _snack("Couldn't update reminder. Please try again.");
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _reminder.hour, minute: _reminder.minute),
    );
    if (picked == null) return;
    try {
      await _reminder.setTime(picked.hour, picked.minute);
      _snack('Daily scan reminder updated.');
    } catch (e) {
      _snack("Couldn't update reminder time. Please try again.");
    }
  }

  String _formatTime(int hour, int minute) {
    final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final ampm = hour < 12 ? 'AM' : 'PM';
    return '$h12:${minute.toString().padLeft(2, '0')} $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final on = _prefs.enabled;
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(title: const Text('Notification settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          SettingsCard(children: [
            SettingsSwitchTile(
              icon: Icons.notifications_active_outlined,
              title: 'Allow notifications',
              subtitle: 'Master switch for all in-app notifications.',
              value: on,
              onChanged: (v) => _prefs.setEnabled(v),
            ),
          ]),
          const SizedBox(height: 20),
          const SettingsSectionLabel('Alert types'),
          const SizedBox(height: 8),
          SettingsCard(children: [
            SettingsSwitchTile(
              icon: Icons.medical_services_outlined,
              title: 'Doctor updates',
              subtitle: 'Reviews, prescriptions, and messages from your '
                  'dermatologist.',
              value: _prefs.doctorUpdates,
              onChanged: on ? (v) => _prefs.setDoctorUpdates(v) : null,
            ),
            const SettingsDivider(),
            SettingsSwitchTile(
              icon: Icons.trending_up,
              title: 'Severity change alerts',
              subtitle: 'When your latest scan moves between Mild / Moderate / '
                  'Severe.',
              value: _prefs.severityChanges,
              onChanged: on ? (v) => _prefs.setSeverityChanges(v) : null,
            ),
            const SettingsDivider(),
            SettingsSwitchTile(
              icon: Icons.shield_outlined,
              title: 'Security & account alerts',
              subtitle: 'Sign-ins, password and profile changes.',
              value: _prefs.securityAlerts,
              onChanged: on ? (v) => _prefs.setSecurityAlerts(v) : null,
            ),
          ]),
          const SizedBox(height: 20),
          const SettingsSectionLabel('Daily scan reminder'),
          const SizedBox(height: 8),
          SettingsCard(children: [
            SettingsSwitchTile(
              icon: Icons.alarm,
              title: 'Daily scan reminder',
              subtitle: 'A nudge to take your scan each day.',
              value: _reminder.enabled,
              onChanged: (v) => _toggleReminder(v),
            ),
            if (_reminder.enabled) ...[
              const SettingsDivider(),
              SettingsTile(
                icon: Icons.schedule,
                title: 'Reminder time',
                onTap: _pickTime,
                trailing: Text(
                  _formatTime(_reminder.hour, _reminder.minute),
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SettingsDivider(),
              SettingsTile(
                icon: Icons.tune,
                title: 'Frequency & more options',
                subtitle: 'Daily, every 2 days, or weekly.',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ScanReminderScreen(),
                  ),
                ),
              ),
            ],
          ]),
        ],
      ),
    );
  }
}
