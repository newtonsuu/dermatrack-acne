import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Owns the on-device daily scan reminder.
///
/// Surfaces a single recurring local notification fired at a user-chosen
/// time every day ("Time for today's scan"). Uses
/// `flutter_local_notifications` for scheduling — no Firebase, no server,
/// no per-device tokens. The reminder lives entirely on the patient's
/// phone and survives reboots via the boot receiver declared in
/// `AndroidManifest.xml`.
///
/// State is persisted in [SharedPreferences] (three keys: `_kEnabledKey`,
/// `_kHourKey`, `_kMinuteKey`). The user opts in by toggling on the
/// reminder card on the profile screen; the service requests OS-level
/// notification permission as part of that opt-in.
///
/// Notification ID 1 is reserved exclusively for this reminder so we can
/// cancel and re-schedule cleanly. If a future feature (doctor-note
/// pushes, follow-up reminders, etc.) needs more local notifications,
/// use IDs ≥ 100 to leave headroom.
class ScanReminderService extends ChangeNotifier {
  ScanReminderService._internal();
  static final ScanReminderService instance = ScanReminderService._internal();

  static const String _kEnabledKey = 'scan_reminder_enabled';
  static const String _kHourKey = 'scan_reminder_hour';
  static const String _kMinuteKey = 'scan_reminder_minute';

  /// Single notification ID used by the daily scan reminder. Stable
  /// forever — bumping it would create a second notification instead of
  /// replacing the first.
  static const int _reminderNotificationId = 1;

  /// Android notification channel ID. Stable forever — the OS caches
  /// channel settings (sound, importance) per ID and changing it would
  /// lose any user-customized channel preferences.
  static const String _channelId = 'scan_reminders';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  bool _enabled = false;
  int _hour = 9; // default 9 a.m. — friendly morning slot
  int _minute = 0;
  bool? _permissionGranted; // null = not asked yet; true/false after request

  /// Whether the patient has opted in to the daily scan reminder.
  bool get enabled => _enabled;

  /// Reminder fires at this hour (24h, 0-23). Defaults to 9 if unset.
  int get hour => _hour;

  /// Reminder fires at this minute (0-59). Defaults to 0 if unset.
  int get minute => _minute;

  /// `true` if OS notification permission is known to be granted; `false`
  /// if known denied; `null` if not yet requested.
  bool? get permissionGranted => _permissionGranted;

  // ----- Lifecycle -----

  /// Boots the service. Safe to call multiple times — only the first call
  /// does any work. Should be invoked from `main()` before `runApp` so
  /// any scheduled reminder is registered as soon as the process is up.
  ///
  /// What this does:
  ///   1. Initializes the timezone database (required for zoned scheduling).
  ///   2. Initializes the notifications plugin with platform-specific
  ///      settings (Android icon, iOS request defaults).
  ///   3. Loads persisted reminder state from SharedPreferences.
  ///   4. If the reminder was enabled in a previous session, re-schedules
  ///      it (Android's alarm manager may have lost it on reboot; the
  ///      boot receiver handles most cases but defensive re-schedule on
  ///      app launch is cheap insurance).
  Future<void> initialize() async {
    if (_isInitialized) return;

    tz_data.initializeTimeZones();
    // We don't try to detect the device's local timezone here — the
    // matchDateTimeComponents: DateTimeComponents.time scheduling pattern
    // re-arms in the device's local time on each fire, so a tz_local
    // approximation via DateTime.now() is sufficient.

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      // Defer permission request until the user actively enables the
      // reminder, so first-launch doesn't show a confusing OS prompt
      // before the user has any context for what it's for.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _onTap,
    );

    await _loadFromPrefs();

    // Defensive re-schedule. If the OS dropped the alarm (rare but
    // happens with aggressive battery optimization), this re-arms it.
    // Cheap: cancel + schedule is a couple of millis, no-op if alarm
    // was already valid.
    if (_enabled) {
      try {
        await _scheduleReminder();
      } catch (e) {
        debugPrint('ScanReminderService.initialize re-schedule failed: $e');
      }
    }

    _isInitialized = true;
    notifyListeners();
  }

  // ----- Public mutators -----

  /// Turns the reminder on or off. When enabling for the first time,
  /// requests OS notification permission; if denied, stores enabled=false
  /// and surfaces the denied state via [permissionGranted] so the UI can
  /// tell the user to grant the permission in system settings.
  Future<void> setEnabled(bool value) async {
    if (value == _enabled) return;
    if (value) {
      final granted = await _requestPermissionIfNeeded();
      _permissionGranted = granted;
      if (!granted) {
        // Don't flip enabled on if we can't actually deliver the
        // notification — silently failing is worse than showing the
        // toggle stuck in off.
        _enabled = false;
        await _saveToPrefs();
        notifyListeners();
        return;
      }
      _enabled = true;
      await _saveToPrefs();
      await _scheduleReminder();
    } else {
      _enabled = false;
      await _saveToPrefs();
      await _plugin.cancel(_reminderNotificationId);
    }
    notifyListeners();
  }

  /// Updates the time of day the reminder fires. If currently enabled,
  /// re-schedules immediately so the change takes effect now (not after
  /// next app launch).
  Future<void> setTime(int hour24, int minuteVal) async {
    if (hour24 < 0 || hour24 > 23 || minuteVal < 0 || minuteVal > 59) {
      throw ArgumentError(
          'Invalid time $hour24:$minuteVal — expected 0–23, 0–59.');
    }
    if (hour24 == _hour && minuteVal == _minute) return;
    _hour = hour24;
    _minute = minuteVal;
    await _saveToPrefs();
    if (_enabled) {
      await _scheduleReminder();
    }
    notifyListeners();
  }

  // ----- Internals -----

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_kEnabledKey) ?? false;
    _hour = prefs.getInt(_kHourKey) ?? 9;
    _minute = prefs.getInt(_kMinuteKey) ?? 0;
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabledKey, _enabled);
    await prefs.setInt(_kHourKey, _hour);
    await prefs.setInt(_kMinuteKey, _minute);
  }

  Future<bool> _requestPermissionIfNeeded() async {
    // iOS: request via the iOS plugin. Returns true on grant, false on
    // deny / restricted.
    final iosImpl = _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    if (iosImpl != null) {
      final ok = await iosImpl.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return ok ?? false;
    }
    // Android 13+: POST_NOTIFICATIONS is a runtime permission. Below 13
    // notifications are granted by default.
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      final ok = await androidImpl.requestNotificationsPermission();
      // requestNotificationsPermission returns null on Android <13 (no
      // permission needed) — treat that as granted.
      return ok ?? true;
    }
    return true;
  }

  /// Schedules (or re-schedules) the daily reminder for the configured
  /// time. Cancels any existing reminder under the same notification ID
  /// first so we never accumulate duplicates.
  Future<void> _scheduleReminder() async {
    await _plugin.cancel(_reminderNotificationId);

    final scheduled = _nextInstanceOf(_hour, _minute);

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      'Daily scan reminders',
      channelDescription:
          'Reminds you to take your daily DermaTrack scan at the time you chose.',
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'DermaTrack reminder',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.zonedSchedule(
      _reminderNotificationId,
      'Time for today\'s scan',
      'Open DermaTrack and capture your daily scan to keep your trend up to date.',
      scheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      // matchDateTimeComponents: time → re-fires every day at the same
      // wall-clock time. We don't have to re-schedule from app code; the
      // OS handles the daily repeat for us.
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// Computes the next clock-time instance of [h]:[m] in the device's
  /// local timezone. If the configured time has already passed today,
  /// returns tomorrow at that time.
  tz.TZDateTime _nextInstanceOf(int h, int m) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, h, m);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// Handles a tap on the notification. Right now it's a no-op — the OS
  /// brings DermaTrack to the foreground and the user lands on whichever
  /// screen they were on. Wire deep-linking here (e.g., push directly to
  /// the scan tab) if a future iteration wants that.
  void _onTap(NotificationResponse response) {
    debugPrint('ScanReminder tapped: ${response.payload}');
  }
}
