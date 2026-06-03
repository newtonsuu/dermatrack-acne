import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_notification.dart';

/// User preferences for in-app notifications, persisted in SharedPreferences.
///
/// These gate which categories surface in the Notification Center and count
/// toward the unread badge. The daily-scan-reminder *scheduling* itself lives
/// in ScanReminderService; this service only governs the in-app feed +
/// the non-reminder category toggles. The master [enabled] switch mutes the
/// whole feed (history stays visible, but nothing counts as unread).
class NotificationPrefsService extends ChangeNotifier {
  NotificationPrefsService._internal();
  static final NotificationPrefsService instance =
      NotificationPrefsService._internal();

  static const _kEnabled = 'notif_enabled';
  static const _kDoctorUpdates = 'notif_doctor_updates';
  static const _kSeverityChanges = 'notif_severity_changes';
  static const _kSecurityAlerts = 'notif_security_alerts';

  bool _initialized = false;
  bool _enabled = true;
  bool _doctorUpdates = true;
  bool _severityChanges = true;
  bool _securityAlerts = true;

  /// Master switch. When off, the feed is muted (unread count is 0).
  bool get enabled => _enabled;
  bool get doctorUpdates => _doctorUpdates;
  bool get severityChanges => _severityChanges;
  bool get securityAlerts => _securityAlerts;
  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_kEnabled) ?? true;
    _doctorUpdates = prefs.getBool(_kDoctorUpdates) ?? true;
    _severityChanges = prefs.getBool(_kSeverityChanges) ?? true;
    _securityAlerts = prefs.getBool(_kSecurityAlerts) ?? true;
    _initialized = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool v) => _set(_kEnabled, v, (x) => _enabled = x);
  Future<void> setDoctorUpdates(bool v) =>
      _set(_kDoctorUpdates, v, (x) => _doctorUpdates = x);
  Future<void> setSeverityChanges(bool v) =>
      _set(_kSeverityChanges, v, (x) => _severityChanges = x);
  Future<void> setSecurityAlerts(bool v) =>
      _set(_kSecurityAlerts, v, (x) => _securityAlerts = x);

  Future<void> _set(String key, bool value, void Function(bool) apply) async {
    apply(value);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  /// Whether a given notification category should be surfaced, given the
  /// master switch + per-category toggles. Reminder/missed/follow-up/
  /// announcement are always allowed when the master switch is on.
  bool allows(NotificationKind kind) {
    if (!_enabled) return false;
    switch (kind) {
      case NotificationKind.doctorReview:
        return _doctorUpdates;
      case NotificationKind.severityChange:
        return _severityChanges;
      case NotificationKind.security:
        return _securityAlerts;
      case NotificationKind.dailyReminder:
      case NotificationKind.missedScan:
      case NotificationKind.followUp:
      case NotificationKind.announcement:
        return true;
    }
  }
}
