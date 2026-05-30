import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import '../models/patient_history.dart';
import 'auth_service.dart';

/// Owns the patient's clinical intake history.
///
/// Mirrors the [ProfileService] singleton pattern: listens to
/// [AuthService] for sign-in/out, eagerly loads the row when the user
/// signs in, exposes a [ChangeNotifier] surface so widgets can rebuild
/// when the history changes.
///
/// `null` after [load] means "the user has not filled in their history
/// yet" (no row in the table). Distinct from `PatientHistory.empty`,
/// which is a fully-blank-but-saved row.
class PatientHistoryService extends ChangeNotifier {
  PatientHistoryService._internal() {
    AuthService.instance.addListener(_onAuthChanged);
    if (AuthService.instance.isSignedIn) {
      // Fire-and-forget — listeners get notified when it lands.
      load();
    }
  }
  static final PatientHistoryService instance =
      PatientHistoryService._internal();

  supa.SupabaseClient get _client => supa.Supabase.instance.client;

  PatientHistory? _history;
  bool _isLoading = false;
  Object? _lastError;

  /// The saved history, or null if the patient hasn't filled in any
  /// fields yet.
  PatientHistory? get history => _history;
  bool get isLoading => _isLoading;
  Object? get lastError => _lastError;

  /// True when a saved row exists (even if all fields are blank). Lets
  /// the profile card distinguish "never opened" from "intentionally
  /// saved blank".
  bool get hasSavedRow => _history != null;

  void _onAuthChanged() {
    if (AuthService.instance.isSignedIn) {
      load();
    } else if (_history != null) {
      _history = null;
      _lastError = null;
      notifyListeners();
    }
  }

  // ----- Load -----

  /// Fetches the patient's history row. Idempotent — concurrent calls
  /// coalesce via the [_isLoading] flag. Errors land on [lastError] but
  /// don't clobber the previous [history] value, so a transient network
  /// hiccup doesn't blow away good in-memory data.
  Future<void> load() async {
    if (_isLoading) return;
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      final row = await _client
          .from('patient_histories')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (row == null) {
        _history = null; // no row yet
      } else {
        _history = PatientHistory.fromRow(row.cast<String, dynamic>());
      }
      _lastError = null;
    } catch (e) {
      debugPrint('PatientHistoryService.load: $e');
      _lastError = e;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ----- Upsert -----

  /// Persists [updated] for the current user. Uses Postgres UPSERT (the
  /// table's PK is user_id, so duplicates collapse). Optimistically
  /// updates the local copy first so the UI feels instant, and rolls
  /// back on failure.
  ///
  /// Throws on failure with a user-readable message so the caller can
  /// surface a SnackBar.
  Future<void> upsert(PatientHistory updated) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('You need to be signed in to save your history.');
    }

    final previous = _history;
    _history = updated;
    notifyListeners();

    try {
      final payload = updated.toUpsertJson();
      payload['user_id'] = userId;

      final row = await _client
          .from('patient_histories')
          .upsert(payload, onConflict: 'user_id')
          .select()
          .single();

      // Refresh from the returned row so server-side timestamps land.
      _history = PatientHistory.fromRow(row.cast<String, dynamic>());
      _lastError = null;
      notifyListeners();
    } catch (e) {
      _history = previous;
      _lastError = e;
      notifyListeners();
      debugPrint('PatientHistoryService.upsert: $e');
      rethrow;
    }
  }
}
