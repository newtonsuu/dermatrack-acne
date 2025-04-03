import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// How often the user wants the scan reminder to fire. Persisted as the
/// enum name so adding values later stays backward-compatible.
enum ReminderFrequency {
  /// Every day at the chosen time (the default, and what the fixed midday +
  /// evening streak nudges are tuned for).
  daily('daily', 'Every day'),

  /// Every other day at the chosen time. flutter_local_notifications has no
  /// native 2-day repeat, so this is scheduled as the next single instance and
  /// re-armed each time the app launches (see [ScanReminderService.initialize]).
  everyTwoDays('every_2_days', 'Every 2 days'),

  /// Once a week, on the same weekday as when it was set, at the chosen time.
  weekly('weekly', 'Weekly');

  const ReminderFrequency(this.storageValue, this.label);

  /// Stable string persisted to SharedPreferences.
  final String storageValue;

  /// Human-readable label for the settings UI.
  final String label;

  static ReminderFrequency fromStorage(String? value) {
    return ReminderFrequency.values.firstWhere(
      (f) => f.storageValue == value,
      orElse: () => ReminderFrequency.daily,
    );
  }
}

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
/// Notification ID 1001 is reserved exclusively for this reminder so we can
/// cancel and re-schedule cleanly. The two fixed nudges use 1002/1003. If a
/// future feature needs more local notifications, use IDs ≥ 1100 to leave
/// headroom.
class ScanReminderService extends ChangeNotifier {
  ScanReminderService._internal();
  static final ScanReminderService instance = ScanReminderService._internal();

  static const String _kEnabledKey = 'scan_reminder_enabled';
  static const String _kHourKey = 'scan_reminder_hour';
  static const String _kMinuteKey = 'scan_reminder_minute';
  static const String _kFrequencyKey = 'scan_reminder_frequency';

  /// One-shot migration flag. flutter_local_notifications caches scheduled
  /// notifications as Gson-serialized JSON on Android; a cache written by an
  /// older plugin/app version (or stripped of generic type info by R8) makes
  /// `cancel()` throw `RuntimeException: Missing type parameter` the next time
  /// we try to update a reminder. We clear that cache exactly once with
  /// `cancelAll()` after upgrading, gated by this key so we don't wipe the
  /// user's reminder on every launch.
  static const String _kCachePurgedKey = 'scan_reminder_cache_purged_v2';

  /// Single notification ID used by the user-set daily scan reminder. Stable
  /// forever — bumping it would create a second notification instead of
  /// replacing the first.
  static const int _reminderNotificationId = 1001;

  /// Fixed midday nudge ("have you scanned yet?") and an evening
  /// streak-deadline nudge ("only a few hours left today"). Both fire daily and
  /// are gated by the same [enabled] opt-in as the user-set reminder.
  static const int _middayNotificationId = 1002;
  static const int _deadlineNotificationId = 1003;

  /// Wall-clock times for the two fixed nudges. Midday = 12:00; the evening
  /// deadline nudge fires at 21:00 so there's still time to scan before
  /// midnight (the daily cut-off the dashboard countdown ticks down to).
  static const int _middayHour = 12;
  static const int _deadlineHour = 21;

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
  ReminderFrequency _frequency = ReminderFrequency.daily;
  bool? _permissionGranted; // null = not asked yet; true/false after request

  /// Guards against running the corrupted-cache `cancelAll()` recovery more
  /// than once per process (it's a heavy, last-resort wipe).
  bool _cachePurgeAttempted = false;

  /// Whether the patient has opted in to the daily scan reminder.
  bool get enabled => _enabled;

  /// Reminder fires at this hour (24h, 0-23). Defaults to 9 if unset.
  int get hour => _hour;

  /// Reminder fires at this minute (0-59). Defaults to 0 if unset.
  int get minute => _minute;

  /// How often the reminder repeats. Defaults to [ReminderFrequency.daily].
  ReminderFrequency get frequency => _frequency;

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
    // Point tz.local at a zone matching the device's current UTC offset so
    // zonedSchedule fires at the right WALL-CLOCK time. Without this, tz.local
    // defaults to UTC and the reminder would fire offset-hours early/late.
    _configureLocalTimezone();

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

    // Create the Android notification channel up front so it exists with the
    // correct importance even before the first reminder is scheduled, and so
    // its ID matches the AndroidNotificationDetails used when scheduling. The
    // OS ignores a second create for an existing channel, so this is a no-op
    // on later launches.
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      try {
        await androidImpl.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            'Daily scan reminders',
            description:
                'Reminds you to take your daily DermaTrack scan at the time you chose.',
            importance: Importance.high,
          ),
        );
      } catch (e) {
        debugPrint('ScanReminderService.createNotificationChannel failed: $e');
      }
    }

    await _loadFromPrefs();

    // One-time recovery from a corrupted scheduled-notification cache (the
    // "Missing type parameter" PlatformException). Runs before any
    // cancel/schedule so the bad entries are gone before we touch them.
    await _maybePurgeCorruptCache();

    // Mark initialized before the defensive re-schedule so the public mutators'
    // _ensureInitialized() guard treats us as ready if one races in.
    _isInitialized = true;

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

    notifyListeners();
  }

  /// Lazily boots the service if a mutator is called before [initialize] has
  /// finished. Without this, a fast tap on the reminder toggle right after
  /// launch could schedule/cancel against an uninitialized plugin and throw.
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  /// Sets `tz.local` to a timezone whose CURRENT offset matches the device's,
  /// so scheduled wall-clock times are correct. Dependency-free: scans the tz
  /// database for the first location with the same current UTC offset (good
  /// for zones without DST, e.g. Asia/Manila where the app's users are). Falls
  /// back to leaving tz.local at its default on any error.
  void _configureLocalTimezone() {
    try {
      final offset = DateTime.now().timeZoneOffset;
      for (final name in tz.timeZoneDatabase.locations.keys) {
        final loc = tz.getLocation(name);
        if (tz.TZDateTime.now(loc).timeZoneOffset == offset) {
          tz.setLocalLocation(loc);
          return;
        }
      }
    } catch (e) {
      debugPrint('ScanReminderService._configureLocalTimezone failed: $e');
    }
  }

  /// Clears the plugin's scheduled-notification cache exactly once after this
  /// fix ships. flutter_local_notifications stores scheduled notifications as
  /// Gson-serialized JSON on Android; a cache written by an older plugin/app
  /// version (or with generic type info stripped) makes a later `cancel()`
  /// throw `RuntimeException: Missing type parameter`. Wiping it once with
  /// `cancelAll()` clears the bad entries. Guarded by a persisted flag so a
  /// healthy schedule is never nuked on every launch.
  Future<void> _maybePurgeCorruptCache() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kCachePurgedKey) ?? false) return;
    try {
      await _plugin.cancelAll();
      // Mark done ONLY on success — if cancelAll threw (e.g. the cache itself
      // is unreadable), leave the flag unset so we retry on the next launch
      // instead of permanently giving up.
      await prefs.setBool(_kCachePurgedKey, true);
    } catch (e) {
      debugPrint('ScanReminderService one-time cache purge failed '
          '(will retry next launch): $e');
    }
  }

  /// Cancels a single notification, swallowing the corrupted-cache
  /// "Missing type parameter" failure. If cancel throws, falls back to a
  /// one-time `cancelAll()` so a poisoned cache can't block re-scheduling.
  /// Callers must treat cancel as best-effort and always proceed to
  /// (re-)schedule afterwards — zonedSchedule with the same ID overwrites.
  Future<void> _safeCancel(int id) async {
    try {
      await _plugin.cancel(id);
    } catch (e) {
      debugPrint('ScanReminderService.cancel($id) failed: $e');
      await _recoverCacheOnce();
    }
  }

  // ----- Public mutators -----

  /// Turns the reminder on or off. When enabling for the first time,
  /// requests OS notification permission; if denied, stores enabled=false
  /// and surfaces the denied state via [permissionGranted] so the UI can
  /// tell the user to grant the permission in system settings.
  Future<void> setEnabled(bool value) async {
    await _ensureInitialized();
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
      // Schedule FIRST, persist the "enabled" setting only after scheduling
      // succeeds (spec requirement). If scheduling genuinely fails we leave
      // the toggle off and surface the error to the caller.
      await _scheduleReminder();
      _enabled = true;
      await _saveToPrefs();
    } else {
      _enabled = false;
      await _saveToPrefs();
      await _safeCancel(_reminderNotificationId);
      await _safeCancel(_middayNotificationId);
      await _safeCancel(_deadlineNotificationId);
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
    await _ensureInitialized();
    if (hour24 == _hour && minuteVal == _minute) return;
    final prevHour = _hour;
    final prevMinute = _minute;
    _hour = hour24;
    _minute = minuteVal;
    // Re-schedule before persisting so a scheduling failure doesn't leave a
    // saved time that the OS never actually armed.
    if (_enabled) {
      try {
        await _scheduleReminder();
      } catch (e) {
        _hour = prevHour;
        _minute = prevMinute;
        rethrow;
      }
    }
    await _saveToPrefs();
    notifyListeners();
  }

  /// Updates how often the reminder repeats (daily / every 2 days / weekly).
  /// Re-schedules immediately when enabled so the change takes effect now.
  Future<void> setFrequency(ReminderFrequency value) async {
    await _ensureInitialized();
    if (value == _frequency) return;
    final prev = _frequency;
    _frequency = value;
    if (_enabled) {
      try {
        await _scheduleReminder();
      } catch (e) {
        _frequency = prev;
        rethrow;
      }
    }
    await _saveToPrefs();
    notifyListeners();
  }

  // ----- Internals -----

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_kEnabledKey) ?? false;
    _hour = prefs.getInt(_kHourKey) ?? 9;
    _minute = prefs.getInt(_kMinuteKey) ?? 0;
    _frequency = ReminderFrequency.fromStorage(prefs.getString(_kFrequencyKey));
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabledKey, _enabled);
    await prefs.setInt(_kHourKey, _hour);
    await prefs.setInt(_kMinuteKey, _minute);
    await prefs.setString(_kFrequencyKey, _frequency.storageValue);
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
    // Validate the reminder time before touching the OS scheduler (req: never
    // schedule with a null/invalid time). _hour/_minute are non-nullable ints
    // loaded from prefs; this guards against an out-of-range value.
    if (_hour < 0 || _hour > 23 || _minute < 0 || _minute > 59) {
      throw StateError('Reminder time invalid ($_hour:$_minute) — not scheduling.');
    }
    final match = _matchComponentsFor(_frequency);

    // The user-set reminder at the chosen time, repeating per the chosen
    // frequency.
    await _scheduleDaily(
      id: _reminderNotificationId,
      hour: _hour,
      minute: _minute,
      title: "Time for today's scan",
      body:
          'Open DermaTrack and capture your scan to keep your trend up to date.',
      match: match,
    );

    // The fixed midday + evening streak nudges only make sense for a daily
    // cadence. For every-2-days / weekly we cancel them so the app doesn't
    // nag every single day when the user asked for a lighter rhythm.
    if (_frequency == ReminderFrequency.daily) {
      await _scheduleDaily(
        id: _middayNotificationId,
        hour: _middayHour,
        minute: 0,
        title: 'Midday skin check',
        body:
            "Have you taken today's DermaTrack scan yet? Scanning around the same time keeps your trend accurate.",
        match: DateTimeComponents.time,
      );
      await _scheduleDaily(
        id: _deadlineNotificationId,
        hour: _deadlineHour,
        minute: 0,
        title: "Don't break your scan streak",
        body:
            'Only a few hours left to log today\'s scan. Open DermaTrack to keep your streak going.',
        match: DateTimeComponents.time,
      );
    } else {
      await _safeCancel(_middayNotificationId);
      await _safeCancel(_deadlineNotificationId);
    }
  }

  /// Maps a [ReminderFrequency] to the `matchDateTimeComponents` value that
  /// gives the OS the right repeat rule. Returns null for every-2-days, which
  /// has no native repeat and is scheduled as a single next-instance that
  /// [initialize] re-arms on each launch.
  DateTimeComponents? _matchComponentsFor(ReminderFrequency f) {
    switch (f) {
      case ReminderFrequency.daily:
        return DateTimeComponents.time;
      case ReminderFrequency.weekly:
        return DateTimeComponents.dayOfWeekAndTime;
      case ReminderFrequency.everyTwoDays:
        return null;
    }
  }

  /// Schedules (or re-schedules) a single daily notification at [hour]:[minute].
  /// Cancels any existing notification under [id] first so we never accumulate
  /// duplicates, then arms a daily-repeating one.
  Future<void> _scheduleDaily({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
    DateTimeComponents? match = DateTimeComponents.time,
  }) async {
    // Best-effort cancel: never let a corrupted cache block re-scheduling.
    await _safeCancel(id);

    final scheduled = _nextInstanceOf(hour, minute);

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

    try {
      await _zonedScheduleOnce(
          id, title, body, scheduled, details,
          AndroidScheduleMode.exactAllowWhileIdle, match);
    } catch (e) {
      // The "Missing type parameter" failure originates from a corrupted
      // scheduled-notification cache that zonedSchedule reads before writing.
      // Clear the cache once, then retry; if the exact alarm is denied
      // (Android 14+), fall back to an inexact alarm so the reminder still
      // fires instead of surfacing "Couldn't update reminder".
      debugPrint('ScanReminderService schedule($id) failed: $e '
          '— recovering cache and retrying.');
      await _recoverCacheOnce();
      try {
        await _zonedScheduleOnce(
            id, title, body, scheduled, details,
            AndroidScheduleMode.exactAllowWhileIdle, match);
      } catch (e2) {
        debugPrint('ScanReminderService exact retry failed, using inexact: $e2');
        await _zonedScheduleOnce(
            id, title, body, scheduled, details,
            AndroidScheduleMode.inexactAllowWhileIdle, match);
      }
    }
  }

  /// Single zonedSchedule call with the standard interpretation + repeat rule.
  Future<void> _zonedScheduleOnce(
    int id,
    String title,
    String body,
    tz.TZDateTime when,
    NotificationDetails details,
    AndroidScheduleMode mode,
    DateTimeComponents? match,
  ) {
    return _plugin.zonedSchedule(
      id,
      title,
      body,
      when,
      details,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: mode,
      matchDateTimeComponents: match,
    );
  }

  /// Clears the plugin's scheduled-notification cache once per process — the
  /// recovery path for a corrupted cache ("Missing type parameter"). Guarded
  /// so the heavy wipe runs at most once even if several schedules fail.
  Future<void> _recoverCacheOnce() async {
    if (_cachePurgeAttempted) return;
    _cachePurgeAttempted = true;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('ScanReminderService cache recovery (cancelAll) failed: $e');
    }
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
