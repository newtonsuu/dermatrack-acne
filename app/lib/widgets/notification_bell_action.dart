import 'package:flutter/material.dart';

import '../screens/notification_center_screen.dart';
import '../services/notification_center_service.dart';
import '../theme/app_theme.dart';

/// AppBar action: the notification bell with an unread-count badge. Opens the
/// [NotificationCenterScreen]. Listens to [NotificationCenterService] so the
/// badge updates live as notifications are read or new ones synthesize.
class NotificationBellAction extends StatefulWidget {
  const NotificationBellAction({super.key});

  @override
  State<NotificationBellAction> createState() => _NotificationBellActionState();
}

class _NotificationBellActionState extends State<NotificationBellAction> {
  final _service = NotificationCenterService.instance;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onChange);
  }

  @override
  void dispose() {
    _service.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final count = _service.unreadCount;
    return IconButton(
      tooltip: 'Notifications',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const NotificationCenterScreen()),
      ),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_outlined),
          if (count > 0)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: AppTheme.surface(context), width: 1.5),
                ),
                child: Text(
                  count > 9 ? '9+' : '$count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
