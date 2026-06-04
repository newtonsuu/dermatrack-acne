import 'package:flutter/material.dart';

import '../../models/message.dart';
import '../../services/admin_service.dart';
import '../../services/chat_service.dart';
import '../../theme/app_theme.dart';

/// Admin "Chats" moderation tab: lists every chat thread (admin reads all via
/// RLS). Tapping a thread opens the moderator view where messages can be
/// removed and the user can be restricted from messaging.
class AdminChatsTab extends StatefulWidget {
  const AdminChatsTab({super.key});

  @override
  State<AdminChatsTab> createState() => _AdminChatsTabState();
}

class _AdminChatsTabState extends State<AdminChatsTab> {
  final _admin = AdminService.instance;

  @override
  void initState() {
    super.initState();
    _admin.addListener(_onChange);
    _admin.loadMessageThreads();
  }

  @override
  void dispose() {
    _admin.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final threads = _admin.messageThreads;
    if (threads.isEmpty) {
      return Center(
        child: Text('No chat threads yet.',
            style: TextStyle(color: AppTheme.textSecondary(context))),
      );
    }
    return RefreshIndicator(
      onRefresh: _admin.loadMessageThreads,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        itemCount: threads.length,
        separatorBuilder: (_, __) => const SizedBox(height: 2),
        itemBuilder: (context, i) {
          final t = threads[i];
          final username = _admin.usernameFor(t.patientId);
          final restricted = _admin.users
              .where((u) => u.id == t.patientId)
              .map((u) => u.messagingRestricted)
              .firstWhere((_) => true, orElse: () => false);
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
              child: Icon(Icons.forum_outlined, color: AppTheme.primary),
            ),
            title: Row(
              children: [
                Expanded(
                    child: Text(username,
                        style: const TextStyle(fontWeight: FontWeight.w600))),
                if (restricted)
                  const Icon(Icons.block, size: 16, color: Color(0xFFE53935)),
              ],
            ),
            subtitle: Text('${t.lastBody}\n${t.count} message(s)',
                maxLines: 2, overflow: TextOverflow.ellipsis),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  AdminThreadScreen(patientId: t.patientId, title: username),
            )),
          );
        },
      ),
    );
  }
}

/// Moderator view of a single thread: read every message, remove any message,
/// and restrict/unrestrict the patient from messaging.
class AdminThreadScreen extends StatefulWidget {
  const AdminThreadScreen(
      {super.key, required this.patientId, required this.title});
  final String patientId;
  final String title;

  @override
  State<AdminThreadScreen> createState() => _AdminThreadScreenState();
}

class _AdminThreadScreenState extends State<AdminThreadScreen> {
  final _chat = ChatService.instance;
  final _admin = AdminService.instance;

  @override
  void initState() {
    super.initState();
    _chat.addListener(_onChange);
    _admin.addListener(_onChange);
    _chat.loadThread(widget.patientId, force: true);
    _chat.subscribe(widget.patientId);
  }

  @override
  void dispose() {
    _chat.removeListener(_onChange);
    _admin.removeListener(_onChange);
    _chat.unsubscribe(widget.patientId);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  AdminUser? get _patient {
    for (final u in _admin.users) {
      if (u.id == widget.patientId) return u;
    }
    return null;
  }

  Future<void> _toggleRestrict() async {
    final u = _patient;
    if (u == null) return;
    try {
      await _admin.setMessagingRestricted(u, !u.messagingRestricted);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(u.messagingRestricted
                ? 'Messaging unrestricted for ${u.username}.'
                : 'Messaging restricted for ${u.username}.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Action failed: $e')));
      }
    }
  }

  Future<void> _remove(Message m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove message?'),
        content: const Text(
            'This removes the message for both participants and flags it as removed by a moderator.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _admin.removeMessage(messageId: m.id, patientId: widget.patientId);
      await _chat.loadThread(widget.patientId, force: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Remove failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = _chat.messagesFor(widget.patientId);
    final restricted = _patient?.messagingRestricted ?? false;
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        title: Text('Moderate: ${widget.title}'),
        actions: [
          TextButton.icon(
            onPressed: _toggleRestrict,
            icon: Icon(restricted ? Icons.lock_open : Icons.block,
                color: restricted ? Colors.green : Colors.red.shade600),
            label: Text(restricted ? 'Unrestrict' : 'Restrict',
                style: TextStyle(
                    color: restricted ? Colors.green : Colors.red.shade600)),
          ),
        ],
      ),
      body: messages.isEmpty
          ? Center(
              child: Text('No messages.',
                  style: TextStyle(color: AppTheme.textSecondary(context))))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
              itemCount: messages.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, i) {
                final m = messages[i];
                return Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    title: Text(m.isUnsent
                        ? (m.removedByAdmin
                            ? '[removed by moderator]'
                            : '[unsent]')
                        : m.body),
                    subtitle: Text(
                        '${m.senderRole} · ${m.createdAt.hour.toString().padLeft(2, '0')}:${m.createdAt.minute.toString().padLeft(2, '0')}'
                        '${m.isEdited ? ' · edited' : ''}'),
                    trailing: m.isUnsent
                        ? null
                        : IconButton(
                            tooltip: 'Remove',
                            icon: Icon(Icons.delete_outline,
                                color: Colors.red.shade600),
                            onPressed: () => _remove(m),
                          ),
                  ),
                );
              },
            ),
    );
  }
}
