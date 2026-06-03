import 'package:flutter/material.dart';

/// Category of an in-app notification. Drives the icon/color shown in the
/// Notification Center and which preference toggle (if any) gates it.
enum NotificationKind {
  dailyReminder,
  missedScan,
  doctorReview,
  severityChange,
  followUp,
  security,
  announcement;

  /// Short category label shown as a chip in the feed.
  String get label {
    switch (this) {
      case NotificationKind.dailyReminder:
        return 'Reminder';
      case NotificationKind.missedScan:
        return 'Missed scan';
      case NotificationKind.doctorReview:
        return 'Doctor';
      case NotificationKind.severityChange:
        return 'Severity';
      case NotificationKind.followUp:
        return 'Follow-up';
      case NotificationKind.security:
        return 'Security';
      case NotificationKind.announcement:
        return 'Announcement';
    }
  }

  IconData get icon {
    switch (this) {
      case NotificationKind.dailyReminder:
        return Icons.alarm;
      case NotificationKind.missedScan:
        return Icons.warning_amber_rounded;
      case NotificationKind.doctorReview:
        return Icons.medical_services_outlined;
      case NotificationKind.severityChange:
        return Icons.trending_up;
      case NotificationKind.followUp:
        return Icons.event_repeat_outlined;
      case NotificationKind.security:
        return Icons.shield_outlined;
      case NotificationKind.announcement:
        return Icons.campaign_outlined;
    }
  }

  Color get color {
    switch (this) {
      case NotificationKind.dailyReminder:
        return const Color(0xFF1F8A8A); // teal (brand)
      case NotificationKind.missedScan:
        return const Color(0xFFFF9800); // orange
      case NotificationKind.doctorReview:
        return const Color(0xFF5C6BC0); // indigo (accent-ish)
      case NotificationKind.severityChange:
        return const Color(0xFFFFB300); // amber
      case NotificationKind.followUp:
        return const Color(0xFF26A69A); // teal variant
      case NotificationKind.security:
        return const Color(0xFFE53935); // red
      case NotificationKind.announcement:
        return const Color(0xFF7E57C2); // purple
    }
  }
}

/// A single in-app notification shown in the Notification Center.
///
/// Notifications are **synthesized from real data** (scans, doctor notes,
/// prescriptions, messages, reminder state, security activity) rather than
/// stored in a dedicated table — see NotificationCenterService. The [id] is
/// deterministic per source event (e.g. `review:<scanId>`) so read-state
/// persists across rebuilds.
@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.timestamp,
    this.read = false,
  });

  /// Deterministic, stable id derived from the source event.
  final String id;
  final NotificationKind kind;
  final String title;
  final String body;
  final DateTime timestamp;

  /// Whether the user has seen this (tracked by the service via persisted
  /// read-id set). Copied onto the instance for convenient rendering.
  final bool read;

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        kind: kind,
        title: title,
        body: body,
        timestamp: timestamp,
        read: read ?? this.read,
      );
}
