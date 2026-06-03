import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../models/scan.dart';
import '../services/notification_center_service.dart';
import '../services/scan_service.dart';
import '../theme/app_theme.dart';
import 'scan_detail_screen.dart';

/// The in-app Notification Center, opened from the home-page bell.
///
/// Lists notifications synthesized by [NotificationCenterService] (daily scan
/// reminders, missed scans, doctor reviews, severity changes, follow-ups,
/// prescriptions, messages, and announcements), newest first. Tapping an
/// item marks it read and, when it references a scan, opens that scan.
class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  final _service = NotificationCenterService.instance;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onChange);
    // Pull prescriptions + chat over the network, then rebuild.
    _service.refresh();
  }

  @override
  void dispose() {
    _service.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _handleTap(AppNotification n) {
    _service.markRead(n.id);
    // Scan-referencing notifications open the relevant scan.
    final scanId = _scanIdFor(n.id);
    if (scanId != null) {
      Scan? match;
      for (final s in ScanService.instance.scans) {
        if (s.id == scanId) {
          match = s;
          break;
        }
      }
      if (match != null) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ScanDetailScreen(scan: match!)),
        );
      }
    }
  }

  /// Extracts the scan id from a `review:<id>` / `severity:<id>` /
  /// `followup:<id>` notification id; null for non-scan notifications.
  String? _scanIdFor(String id) {
    for (final prefix in const ['review:', 'severity:', 'followup:']) {
      if (id.startsWith(prefix)) return id.substring(prefix.length);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final items = _service.notifications;
    final hasUnread = _service.unreadCount > 0;

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: () => _service.markAllRead(),
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: items.isEmpty
          ? const _EmptyState()
          : RefreshIndicator(
              onRefresh: _service.refresh,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _NotificationTile(
                  notification: items[i],
                  onTap: () => _handleTap(items[i]),
                ),
              ),
            ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final unread = !n.read;
    return Material(
      color: unread
          ? n.kind.color.withValues(alpha: 0.06)
          : AppTheme.surface(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: unread
                  ? n.kind.color.withValues(alpha: 0.35)
                  : AppTheme.border(context),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: n.kind.color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(n.kind.icon, size: 20, color: n.kind.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            n.title,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight:
                                  unread ? FontWeight.w700 : FontWeight.w600,
                              color: AppTheme.textPrimary(context),
                            ),
                          ),
                        ),
                        if (unread)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 6, top: 4),
                            decoration: BoxDecoration(
                              color: n.kind.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      n.body,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _CategoryChip(kind: n.kind),
                        const Spacer(),
                        Text(
                          _relativeTime(n.timestamp),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[t.month - 1]} ${t.day}';
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.kind});
  final NotificationKind kind;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: kind.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        kind.label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: kind.color,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none_rounded,
                size: 56, color: AppTheme.textSecondary(context)),
            const SizedBox(height: 16),
            Text(
              "You're all caught up",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Scan reminders, doctor reviews, and severity updates will show '
              'up here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppTheme.textSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
