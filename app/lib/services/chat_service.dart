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

  /// Subscribes to live inserts on [patientId]'s thread. Idempotent.
  void subscribe(String patientId) {
    if (_channels.containsKey(patientId)) return;
    final channel = _client.channel('messages:$patientId');
    channel.onPostgresChanges(
      event: supa.PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      filter: supa.PostgresChangeFilter(
        type: supa.PostgresChangeFilterType.eq,
        column: 'patient_id',
        value: patientId,
      ),
      callback: (payload) {
        try {
          final msg = Message.fromRow(payload.newRecord);
          _appendIfNew(patientId, msg);
        } catch (e) {
          debugPrint('ChatService realtime parse failed: $e');
        }
      },
    ).subscribe();
    _channels[patientId] = channel;
  }

  /// Tears down the live subscription for [patientId] (call when leaving the
  /// chat screen).
  void unsubscribe(String patientId) {
    final ch = _channels.remove(patientId);
    if (ch != null) _client.removeChannel(ch);
  }

  void _appendIfNew(String patientId, Message msg) {
    final list = List<Message>.from(_byThread[patientId] ?? const []);
    if (list.any((m) => m.id == msg.id)) return; // dedupe (e.g. our own echo)
    list.add(msg);
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
      _appendIfNew(patientId, Message.fromRow(row.cast<String, dynamic>()));
    } catch (e) {
      debugPrint('ChatService.send failed: $e');
      rethrow;
    }
  }
}
