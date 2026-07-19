import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import '../models/message.dart';
import 'auth_service.dart';

/// Chat data layer for the patient<->dermatologist thread.
///
/// One thread per patient (keyed by the patient's user_id). Used by both
/// sides — RLS (migration 0009) gates who can read/send. New messages stream
/// in live via a Supabase Realtime subscription per open thread.
class ChatService extends ChangeNotifier {
  ChatService._internal() {
    AuthService.instance.addListener(_onAuthChanged);
  }
  static final ChatService instance = ChatService._internal();

  supa.SupabaseClient get _client => supa.Supabase.instance.client;

  final Map<String, List<Message>> _byThread = {};
  final Map<String, Object?> _error = {};
  final Set<String> _loading = {};
  final Map<String, supa.RealtimeChannel> _channels = {};

  List<Message> messagesFor(String patientId) =>
      List.unmodifiable(_byThread[patientId] ?? const []);
  bool isLoadingFor(String patientId) => _loading.contains(patientId);
  bool hasLoadedFor(String patientId) => _byThread.containsKey(patientId);
  Object? errorFor(String patientId) => _error[patientId];

  void _onAuthChanged() {
    if (!AuthService.instance.isSignedIn) {
      for (final ch in _channels.values) {
        _client.removeChannel(ch);
      }
      _channels.clear();
      _byThread.clear();
      _error.clear();
      _loading.clear();
      notifyListeners();
    }
  }

  /// Loads the full thread for [patientId] (oldest first) and caches it.
  Future<void> loadThread(String patientId, {bool force = false}) async {
    if (_loading.contains(patientId)) return;
    if (!force && _byThread.containsKey(patientId)) return;

    _loading.add(patientId);
    notifyListeners();
    try {
      final rows = await _client
          .from('messages')
          .select()
          .eq('patient_id', patientId)
          .order('created_at', ascending: true);
      final msgs = <Message>[];
      for (final row in rows as List) {
        try {
          msgs.add(Message.fromRow((row as Map).cast<String, dynamic>()));
        } catch (e) {
          debugPrint('ChatService: bad message row: $e');
        }
      }
      _byThread[patientId] = msgs;
      _error[patientId] = null;
    } catch (e) {
      debugPrint('ChatService.loadThread($patientId) failed: $e');
      _error[patientId] = e;
    } finally {
      _loading.remove(patientId);
      notifyListeners();
    }
  }

  /// Subscribes to live inserts AND updates on [patientId]'s thread (updates
  /// carry edits / unsends / moderator removals). Idempotent.
  void subscribe(String patientId) {
    if (_channels.containsKey(patientId)) return;
    final filter = supa.PostgresChangeFilter(
      type: supa.PostgresChangeFilterType.eq,
      column: 'patient_id',
      value: patientId,
    );
    void handle(supa.PostgresChangePayload payload) {
      try {
        _upsert(patientId, Message.fromRow(payload.newRecord));
      } catch (e) {
        debugPrint('ChatService realtime parse failed: $e');
      }
    }

    final channel = _client.channel('messages:$patientId');
    channel
        .onPostgresChanges(
          event: supa.PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: filter,
          callback: handle,
        )
        .onPostgresChanges(
          event: supa.PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          filter: filter,
          callback: handle,
        )
        .subscribe();
    _channels[patientId] = channel;
  }

  /// Tears down the live subscription for [patientId] (call when leaving the
  /// chat screen).
  void unsubscribe(String patientId) {
    final ch = _channels.remove(patientId);
    if (ch != null) _client.removeChannel(ch);
  }

  /// Inserts the message, or replaces an existing one with the same id (used
  /// for both new messages and edit/unsend/moderation updates).
  void _upsert(String patientId, Message msg) {
    final list = List<Message>.from(_byThread[patientId] ?? const []);
    final idx = list.indexWhere((m) => m.id == msg.id);
    if (idx >= 0) {
      list[idx] = msg;
    } else {
      list.add(msg);
    }
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _byThread[patientId] = list;
    notifyListeners();
  }

  /// Sends a message into [patientId]'s thread. Role is derived from the
  /// signed-in account (doctor vs patient); RLS enforces it server-side.
  /// The inserted row is appended locally immediately so the sender sees it
  /// even before the realtime echo arrives.
  Future<void> send({required String patientId, required String body}) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw StateError('Not signed in.');
    final role = AuthService.instance.isDoctor ? 'doctor' : 'patient';

    try {
      final row = await _client
          .from('messages')
          .insert({
            'patient_id': patientId,
            'sender_id': uid,
            'sender_role': role,
            'body': trimmed,
          })
          .select()
          .single();
      _upsert(patientId, Message.fromRow(row.cast<String, dynamic>()));
    } on supa.PostgrestException catch (e) {
      debugPrint('ChatService.send failed: ${e.code} ${e.message}');
      // A RESTRICTIVE RLS policy blocks restricted users from inserting.
      if (e.code == '42501' ||
          e.message.toLowerCase().contains('row-level security')) {
        throw Exception(
            'Messaging is restricted for your account. Please contact support.');
      }
      rethrow;
    } catch (e) {
      debugPrint('ChatService.send failed: $e');
      rethrow;
    }
  }

  /// Edits the body of a message the current user sent (Messenger-style edit).
  /// RLS allows updating only your own, non-removed messages.
  Future<void> editMessage({
    required String patientId,
    required String messageId,
    required String body,
  }) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;
    final row = await _client
        .from('messages')
        .update({
          'body': trimmed,
          'edited_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', messageId)
        .select()
        .single();
    _upsert(patientId, Message.fromRow(row.cast<String, dynamic>()));
  }

  /// Unsends a message the current user sent (soft delete — body is hidden in
  /// the UI but retained for moderation). RLS allows only your own messages.
  Future<void> unsendMessage({
    required String patientId,
    required String messageId,
  }) async {
    final row = await _client
        .from('messages')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', messageId)
        .select()
        .single();
    _upsert(patientId, Message.fromRow(row.cast<String, dynamic>()));
  }
}
