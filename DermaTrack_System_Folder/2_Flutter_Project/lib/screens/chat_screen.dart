import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import '../models/message.dart';
import '../services/chat_service.dart';
import '../theme/app_theme.dart';

/// Two-way chat thread between a patient and the dermatologist. Used by both
/// sides: the doctor opens it from a patient's detail screen; the patient
/// opens it from their dashboard. [patientId] identifies the thread.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.patientId, required this.title});

  final String patientId;

  /// AppBar title — the other party's name ("Dr. Demo" for the patient, the
  /// patient's name for the doctor).
  final String title;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _sending = false;

  String? get _uid => supa.Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    ChatService.instance.addListener(_onChanged);
    ChatService.instance.loadThread(widget.patientId);
    ChatService.instance.subscribe(widget.patientId);
  }

  @override
  void dispose() {
    ChatService.instance.removeListener(_onChanged);
    ChatService.instance.unsubscribe(widget.patientId);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    _scrollToBottomSoon();
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showMessageActions(Message m) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () {
                Navigator.of(ctx).pop();
                _editMessage(m);
              },
            ),
            ListTile(
              leading: Icon(Icons.undo, color: Colors.red.shade600),
              title: Text('Unsend',
                  style: TextStyle(color: Colors.red.shade600)),
              onTap: () {
                Navigator.of(ctx).pop();
                _unsendMessage(m);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editMessage(Message m) async {
    final controller = TextEditingController(text: m.body);
    final newBody = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          minLines: 1,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (newBody == null || newBody.isEmpty || newBody == m.body) return;
    try {
      await ChatService.instance
          .editMessage(patientId: widget.patientId, messageId: m.id, body: newBody);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Couldn't edit: $e")));
      }
    }
  }

  Future<void> _unsendMessage(Message m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsend message?'),
        content: const Text(
            'This removes the message for everyone in the conversation.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Unsend'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ChatService.instance
          .unsendMessage(patientId: widget.patientId, messageId: m.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Couldn't unsend: $e")));
      }
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _input.clear();
    try {
      await ChatService.instance.send(patientId: widget.patientId, body: text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Couldn't send: $e")));
        _input.text = text; // restore so the user doesn't lose it
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = ChatService.instance;
    final messages = svc.messagesFor(widget.patientId);
    final loading =
        svc.isLoadingFor(widget.patientId) && !svc.hasLoadedFor(widget.patientId);
    final uid = _uid;

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty
                    ? _EmptyThread()
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        itemCount: messages.length,
                        itemBuilder: (_, i) {
                          final m = messages[i];
                          final mine = m.senderId == uid;
                          return _Bubble(
                            message: m,
                            mine: mine,
                            onLongPress: (mine && !m.isUnsent)
                                ? () => _showMessageActions(m)
                                : null,
                          );
                        },
                      ),
          ),
          _Composer(
            controller: _input,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine, this.onLongPress});
  final Message message;
  final bool mine;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = message.createdAt;
    final time = '${_2(t.hour)}:${_2(t.minute)}';
    final unsent = message.isUnsent;
    final bg = unsent
        ? Theme.of(context).cardColor
        : (mine ? AppTheme.primary : Theme.of(context).cardColor);
    final fg = (mine && !unsent) ? Colors.white : AppTheme.textPrimary(context);

    final tombstone = message.removedByAdmin
        ? 'Message removed by a moderator'
        : 'Message unsent';
    final metaText = message.isEdited ? '$time · edited' : time;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.76,
          ),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(mine ? 14 : 4),
              bottomRight: Radius.circular(mine ? 4 : 14),
            ),
            border: (mine && !unsent)
                ? null
                : Border.all(
                    color: AppTheme.textSecondary(context).withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (unsent)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(message.removedByAdmin ? Icons.gavel : Icons.do_not_disturb_on_outlined,
                        size: 14, color: AppTheme.textSecondary(context)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        tombstone,
                        style: TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ),
                  ],
                )
              else
                Text(message.body, style: TextStyle(fontSize: 14, color: fg)),
              const SizedBox(height: 2),
              Text(
                metaText,
                style: TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _2(int n) => n.toString().padLeft(2, '0');
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: 'Message…',
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: sending ? null : onSend,
              icon: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyThread extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined,
                size: 48, color: AppTheme.textSecondary(context)),
            const SizedBox(height: 12),
            Text(
              'No messages yet',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Say hello to start the conversation.',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
