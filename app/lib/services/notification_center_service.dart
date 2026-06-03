import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import '../data/severity_guidance.dart';
import '../models/app_notification.dart';
import '../models/scan.dart';
import 'chat_service.dart';
import 'notification_prefs_service.dart';
import 'prescription_service.dart';
import 'scan_reminder_service.dart';
import 'scan_service.dart';
import 'security_activity_service.dart';

/// Builds the in-app Notification Center feed by **synthesizing real events**
/// from the data the app already has — scans (doctor reviews, severity
/// changes, follow-ups), prescriptions, chat messages, and the daily-reminder
/// state (reminder due / missed scan) — plus a product announcement.
///
/// There is intentionally no `notifications` table: every item is derived
/// from an existing source row, with a deterministic [AppNotification.id]
/// (e.g. `review:<scanId>`) so read-state persists across rebuilds. Read ids
/// are stored in SharedPreferences.
///
/// The service rebuilds synchronously from cached data whenever any source
/// service changes (keeps the bell badge fresh), and [refresh] pulls the
/// patient's prescriptions + chat thread over the network on demand.
class NotificationCenterService extends ChangeNotifier {
  NotificationCenterService._internal();
  static final NotificationCenterService instance =
      NotificationCenterService._internal();

  static const _kReadIds = 'notif_read_ids';
  static const int _maxReadIds = 300;

  supa.SupabaseClient get _client => supa.Supabase.instance.client;
  String? get _uid => _client.auth.currentUser?.id;

  bool _initialized = false;
  final Set<String> _readIds = {};
  List<AppNotification> _items = const [];

  /// The synthesized feed, newest first, already filtered by preferences.
  List<AppNotification> get notifications => _items;

  /// Count of unread items (drives the bell badge). 0 when the master
  /// notification switch is off (the feed is muted).
  int get unreadCount => _items.where((n) => !n.read).length;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    _readIds
      ..clear()
      ..addAll(prefs.getStringList(_kReadIds) ?? const []);

    // Rebuild synchronously from cached data on any source change.
    ScanService.instance.addListener(_rebuild);
    PrescriptionService.instance.addListener(_rebuild);
    ChatService.instance.addListener(_rebuild);
    ScanReminderService.instance.addListener(_rebuild);
    NotificationPrefsService.instance.addListener(_rebuild);
    SecurityActivityService.instance.addListener(_rebuild);

    _rebuild();
    // Fire-and-forget network pull of prescriptions + messages.
    refresh();
  }

  /// Pulls the current patient's prescriptions + chat thread (cached after
  /// first call) then rebuilds. Call on Notification Center open.
  Future<void> refresh() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await Future.wait([
        PrescriptionService.instance.loadForPatient(uid),
        ChatService.instance.loadThread(uid),
      ]);
    } catch (e) {
      debugPrint('NotificationCenterService.refresh load failed: $e');
    }
    _rebuild();
  }

  void markAllRead() {
    for (final n in _items) {
      _readIds.add(n.id);
    }
    _persistReadIds();
    _rebuild();
  }

  void markRead(String id) {
    if (_readIds.add(id)) {
      _persistReadIds();
      _rebuild();
    }
  }

  Future<void> _persistReadIds() async {
    // Cap growth: keep the most recent ids only.
    if (_readIds.length > _maxReadIds) {
      final trimmed = _readIds.toList().sublist(_readIds.length - _maxReadIds);
      _readIds
        ..clear()
        ..addAll(trimmed);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kReadIds, _readIds.toList());
  }

  // ----- Synthesis -----

  void _rebuild() {
    final prefs = NotificationPrefsService.instance;
    final raw = <AppNotification>[];

    final uid = _uid;
    final scans = List<Scan>.from(ScanService.instance.scans)
      ..sort((a, b) => b.takenAt.compareTo(a.takenAt));

    // 1) Doctor reviews — scans carrying a dermatologist note.
    for (final s in scans.take(30)) {
      final note = s.doctorNote?.trim();
      if (note != null && note.isNotEmpty) {
        raw.add(AppNotification(
          id: 'review:${s.id}',
          kind: NotificationKind.doctorReview,
          title: 'Your scan was reviewed',
          body:
              'Your dermatologist reviewed your ${_shortDate(s.takenAt)} scan. '
              'Open it to read their note.',
          timestamp: s.takenAt,
        ));
      }
    }

    // 2) Severity change — compare the two most recent full-face scans.
    final fullFace = scans.where((s) => s.region == ScanRegion.fullFace).toList();
    if (fullFace.length >= 2) {
      final curr = _tier(fullFace[0]);
      final prev = _tier(fullFace[1]);
      if (curr != prev) {
        raw.add(AppNotification(
          id: 'severity:${fullFace[0].id}',
          kind: NotificationKind.severityChange,
          title: 'Severity update',
          body:
              'Your latest scan changed from ${prev.label} to ${curr.label}.',
          timestamp: fullFace[0].takenAt,
        ));
      }
    }

    // 3) Follow-up — most recent scan reads Moderate/Severe.
    if (scans.isNotEmpty) {
      final latest = scans.first;
      final tier = _tier(latest);
      if (tier == SeverityTier.moderate || tier == SeverityTier.severe) {
        raw.add(AppNotification(
          id: 'followup:${latest.id}',
          kind: NotificationKind.followUp,
          title: 'Follow-up suggested',
          body:
              'Your most recent result read ${tier.label}. Consider a '
              'dermatologist review and keep scanning to track changes.',
          timestamp: latest.takenAt,
        ));
      }
    }

    // 4) Daily reminder due / 5) missed scan — only when the reminder is on.
    if (ScanReminderService.instance.enabled) {
      final now = DateTime.now();
      final today = _dayKey(now);
      final yesterday = today.subtract(const Duration(days: 1));
      final scanDays = scans.map((s) => _dayKey(s.takenAt)).toSet();

      if (!scanDays.contains(today)) {
        raw.add(AppNotification(
          id: 'reminder:${_dayKeyStr(today)}',
          kind: NotificationKind.dailyReminder,
          title: 'Daily scan reminder',
          body: 'It is time to complete your scheduled acne scan today.',
          timestamp: DateTime(now.year, now.month, now.day,
              ScanReminderService.instance.hour,
              ScanReminderService.instance.minute),
        ));
      }
      if (!scanDays.contains(yesterday)) {
        raw.add(AppNotification(
          id: 'missed:${_dayKeyStr(yesterday)}',
          kind: NotificationKind.missedScan,
          title: 'You missed yesterday\'s scan',
          body: 'A quick scan each day keeps your severity trend accurate.',
          timestamp: yesterday.add(const Duration(hours: 21)),
        ));
      }
    }

    // 6) Prescriptions from the dermatologist.
    if (uid != null) {
      for (final p in PrescriptionService.instance.forPatient(uid)) {
        raw.add(AppNotification(
          id: 'rx:${p.id}',
          kind: NotificationKind.doctorReview,
          title: 'New prescription',
          body: 'Your dermatologist sent you a prescription. Open Prescriptions '
              'to view it.',
          timestamp: p.createdAt,
        ));
      }
      // 7) Doctor chat messages.
      for (final m in ChatService.instance.messagesFor(uid)) {
        if (m.senderRole == 'doctor') {
          raw.add(AppNotification(
            id: 'msg:${m.id}',
            kind: NotificationKind.doctorReview,
            title: 'New message from your dermatologist',
            body: m.body.length > 90 ? '${m.body.substring(0, 90)}…' : m.body,
            timestamp: m.createdAt,
          ));
        }
      }
    }

    // 8) Security & account alerts — from the on-device activity log.
    for (final e in SecurityActivityService.instance.events.take(10)) {
      String? title;
      switch (e.type) {
        case SecurityEventType.signIn:
          title = 'New sign-in to your account';
          break;
        case SecurityEventType.passwordChange:
        case SecurityEventType.profileUpdate:
          title = 'Security alert';
          break;
        case SecurityEventType.consentChange:
          title = 'Sharing setting changed';
          break;
        case SecurityEventType.deletionRequest:
          title = 'Account deletion requested';
          break;
        case SecurityEventType.dataExport:
        case SecurityEventType.dataDelete:
          title = null; // user-initiated data actions — not surfaced as alerts
          break;
      }
      if (title != null) {
        raw.add(AppNotification(
          id: 'sec:${e.timestamp.millisecondsSinceEpoch}',
          kind: NotificationKind.security,
          title: title,
          body: e.description,
          timestamp: e.timestamp,
        ));
      }
    }

    // 9) Product announcement (honest, static).
    raw.add(AppNotification(
      id: 'announce:v0.3',
      kind: NotificationKind.announcement,
      title: 'What\'s new in DermaTrack',
      body: 'Per-region facial scanning, clearer Mild/Moderate/Severe '
          'results with guidance, and this Notification Center are now here.',
      timestamp: DateTime(2026, 6, 3),
    ));

    // Filter by preferences, apply read-state, sort newest-first.
    final filtered = raw
        .where((n) => prefs.allows(n.kind))
        .map((n) => n.copyWith(read: _readIds.contains(n.id)))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    _items = List.unmodifiable(filtered);
    notifyListeners();
  }

  SeverityTier _tier(Scan s) =>
      SeverityGuidance.tierFor(cookGrade: s.cookGrade, severityLabel: s.severityLabel);

  DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);
  String _dayKeyStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _shortDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}';
  }
}
