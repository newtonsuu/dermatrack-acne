import 'package:flutter/material.dart';

import '../data/severity_guidance.dart';
import '../services/scan_reminder_service.dart';
import '../services/scan_service.dart';
import '../theme/app_theme.dart';
import '../widgets/settings_widgets.dart';

/// Scan reminder controls: enable/disable, time, repeat frequency (daily /
/// every 2 days / weekly), plus a severity-based cadence suggestion derived
/// from the patient's most recent scan. Backed by [ScanReminderService].
class ScanReminderScreen extends StatefulWidget {
  const ScanReminderScreen({super.key});

  @override
  State<ScanReminderScreen> createState() => _ScanReminderScreenState();
}

class _ScanReminderScreenState extends State<ScanReminderScreen> {
  final _reminder = ScanReminderService.instance;

  @override
  void initState() {
    super.initState();
    _reminder.addListener(_onChange);
    ScanService.instance.addListener(_onChange);
  }

  @override
  void dispose() {
    _reminder.removeListener(_onChange);
    ScanService.instance.removeListener(_onChange);
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

  Future<void> _toggle(bool v) async {
    try {
      await _reminder.setEnabled(v);
      if (v && _reminder.permissionGranted == false) {
        _snack('Enable notifications for DermaTrack in your phone settings '
            'to receive reminders.');
      } else {
        _snack('Daily scan reminder updated.');
      }
    } catch (_) {
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
    } catch (_) {
      _snack("Couldn't update reminder time. Please try again.");
    }
  }

  Future<void> _setFrequency(ReminderFrequency f) async {
    try {
      await _reminder.setFrequency(f);
      _snack('Daily scan reminder updated.');
    } catch (_) {
      _snack("Couldn't update reminder. Please try again.");
    }
  }

  /// Latest scan's tier, or null if there are no scans yet.
  SeverityTier? get _latestTier {
    final scans = ScanService.instance.scans;
    if (scans.isEmpty) return null;
    final latest = scans.reduce((a, b) => a.takenAt.isAfter(b.takenAt) ? a : b);
    return SeverityGuidance.tierFor(
      cookGrade: latest.cookGrade,
      severityLabel: latest.severityLabel,
    );
  }

  ReminderFrequency _suggestedFor(SeverityTier tier) {
    switch (tier) {
      case SeverityTier.clear:
      case SeverityTier.mild:
        return ReminderFrequency.weekly;
      case SeverityTier.moderate:
        return ReminderFrequency.everyTwoDays;
      case SeverityTier.severe:
        return ReminderFrequency.daily;
    }
  }

  String _formatTime(int hour, int minute) {
    final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final ampm = hour < 12 ? 'AM' : 'PM';
    return '$h12:${minute.toString().padLeft(2, '0')} $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _reminder.enabled;
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(title: const Text('Scan reminders')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          SettingsCard(children: [
            SettingsSwitchTile(
              icon: Icons.alarm,
              title: 'Daily scan reminder',
              subtitle: 'Get a reminder to take your scan.',
              value: enabled,
              onChanged: (v) => _toggle(v),
            ),
            if (enabled) ...[
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
            ],
          ]),
          if (enabled) ...[
            const SizedBox(height: 20),
            const SettingsSectionLabel('Frequency'),
            const SizedBox(height: 8),
            SettingsCard(
              children: [
                for (final f in ReminderFrequency.values) ...[
                  RadioListTile<ReminderFrequency>(
                    value: f,
                    groupValue: _reminder.frequency,
                    onChanged: (v) {
                      if (v != null) _setFrequency(v);
                    },
                    activeColor: AppTheme.primary,
                    title: Text(
                      f.label,
                      style: TextStyle(
                        color: AppTheme.textPrimary(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  if (f != ReminderFrequency.values.last)
                    const SettingsDivider(),
                ],
              ],
            ),
          ],
          const SizedBox(height: 20),
          _SeveritySuggestionCard(
            latestTier: _latestTier,
            suggestedFor: _suggestedFor,
            currentFrequency: _reminder.frequency,
            onApply: (f) async {
              if (!_reminder.enabled) await _toggle(true);
              if (_reminder.enabled) await _setFrequency(f);
            },
          ),
        ],
      ),
    );
  }
}

/// Explains the optional severity-based cadence and offers to apply the
/// suggestion for the patient's most recent result.
class _SeveritySuggestionCard extends StatelessWidget {
  const _SeveritySuggestionCard({
    required this.latestTier,
    required this.suggestedFor,
    required this.currentFrequency,
    required this.onApply,
  });

  final SeverityTier? latestTier;
  final ReminderFrequency Function(SeverityTier) suggestedFor;
  final ReminderFrequency currentFrequency;
  final Future<void> Function(ReminderFrequency) onApply;

  @override
  Widget build(BuildContext context) {
    final tier = latestTier;
    final color = tier == null
        ? AppTheme.primary
        : SeverityGuidance.forTier(tier).color;
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_outlined, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                'Suggested cadence',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'A simple rule of thumb:\n'
            '• Mild — a weekly check is usually enough\n'
            '• Moderate — every 2–3 days to watch the trend\n'
            '• Severe — scan daily and consider a dermatologist review',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 12),
          if (tier == null)
            Text(
              'Take your first scan to get a tailored suggestion.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.textSecondary(context),
              ),
            )
          else ...[
            Text(
              'Your latest result reads ${tier.label}. '
              'Suggested: ${suggestedFor(tier).label}.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary(context),
              ),
            ),
            if (tier == SeverityTier.severe) ...[
              const SizedBox(height: 6),
              Text(
                'At this level, monitoring alone may not be enough — consider '
                'booking a dermatologist review.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textSecondary(context),
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: suggestedFor(tier) == currentFrequency
                    ? null
                    : () => onApply(suggestedFor(tier)),
                child: Text(
                  suggestedFor(tier) == currentFrequency
                      ? 'Already on ${suggestedFor(tier).label.toLowerCase()}'
                      : 'Apply ${suggestedFor(tier).label.toLowerCase()}',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
