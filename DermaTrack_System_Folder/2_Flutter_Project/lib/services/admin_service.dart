import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import 'auth_service.dart';

/// A user row as seen by the admin console (from `public.profiles`).
@immutable
class AdminUser {
  const AdminUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
    required this.isActive,
    required this.sharedWithDoctor,
    required this.messagingRestricted,
    this.createdAt,
  });

  final String id;
  final String username;
  final String displayName;
  final UserRole role;
  final bool isActive;
  final bool sharedWithDoctor;
  final bool messagingRestricted;
  final DateTime? createdAt;

  static AdminUser fromRow(Map<String, dynamic> r) => AdminUser(
        id: r['id'] as String,
        username: (r['username'] as String?) ?? '(no username)',
        displayName: (r['display_name'] as String?) ?? '',
        role: userRoleFromString(r['role'] as String?),
        isActive: (r['is_active'] as bool?) ?? true,
        sharedWithDoctor: (r['shared_with_doctor'] as bool?) ?? false,
        messagingRestricted: (r['messaging_restricted'] as bool?) ?? false,
        createdAt: DateTime.tryParse((r['created_at'] as String?) ?? ''),
      );
}

/// A chat thread summary for the admin moderation view.
@immutable
class MessageThread {
  const MessageThread({
    required this.patientId,
    required this.lastBody,
    required this.lastAt,
    required this.count,
  });
  final String patientId;
  final String lastBody;
  final DateTime lastAt;
  final int count;
}

/// An audit-log entry.
@immutable
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.actorRole,
    required this.action,
    required this.detail,
    required this.targetUserId,
    required this.createdAt,
  });

  final String id;
  final String actorRole;
  final String action;
  final String detail;
  final String? targetUserId;
  final DateTime createdAt;

  static AuditEntry fromRow(Map<String, dynamic> r) => AuditEntry(
        id: r['id'] as String,
        actorRole: (r['actor_role'] as String?) ?? '',
        action: (r['action'] as String?) ?? '',
        detail: (r['detail'] as String?) ?? '',
        targetUserId: r['target_user_id'] as String?,
        createdAt:
            DateTime.tryParse((r['created_at'] as String?) ?? '') ?? DateTime.now(),
      );
}

/// An emergency break-glass access session.
@immutable
class BreakGlassSession {
  const BreakGlassSession({
    required this.id,
    required this.adminId,
    required this.targetPatientId,
    required this.reason,
    required this.durationMinutes,
    required this.grantedAt,
    required this.expiresAt,
    required this.revoked,
  });

  final String id;
  final String adminId;
  final String targetPatientId;
  final String reason;
  final int durationMinutes;
  final DateTime grantedAt;
  final DateTime expiresAt;
  final bool revoked;

  bool get isActive => !revoked && expiresAt.isAfter(DateTime.now());
  Duration get remaining => expiresAt.difference(DateTime.now());

  static BreakGlassSession fromRow(Map<String, dynamic> r) => BreakGlassSession(
        id: r['id'] as String,
        adminId: r['admin_id'] as String,
        targetPatientId: r['target_patient_id'] as String,
        reason: (r['reason'] as String?) ?? '',
        durationMinutes: (r['duration_minutes'] as num?)?.toInt() ?? 0,
        grantedAt:
            DateTime.tryParse((r['granted_at'] as String?) ?? '') ?? DateTime.now(),
        expiresAt:
            DateTime.tryParse((r['expires_at'] as String?) ?? '') ?? DateTime.now(),
        revoked: (r['revoked'] as bool?) ?? false,
      );
}

/// Admin console data layer. All writes are gated server-side by the RLS
/// policies in migration 0011 (admin-only), and every state change is written
/// to `audit_log` so admin/break-glass activity is reviewable.
class AdminService extends ChangeNotifier {
  AdminService._internal();
  static final AdminService instance = AdminService._internal();

  supa.SupabaseClient get _client => supa.Supabase.instance.client;
  String? get _uid => _client.auth.currentUser?.id;

  List<AdminUser> _users = [];
  List<AuditEntry> _audit = [];
  List<BreakGlassSession> _breakGlass = [];
  List<MessageThread> _threads = [];
  bool _loading = false;
  Object? _error;

  List<MessageThread> get messageThreads => List.unmodifiable(_threads);

  List<AdminUser> get users => List.unmodifiable(_users);
  List<AuditEntry> get audit => List.unmodifiable(_audit);
  List<BreakGlassSession> get breakGlass => List.unmodifiable(_breakGlass);
  bool get isLoading => _loading;
  Object? get error => _error;

  List<AdminUser> get patients =>
      _users.where((u) => u.role == UserRole.patient).toList();

  // ----- Monitoring counts -----
  int get totalUsers => _users.length;
  int countByRole(UserRole r) => _users.where((u) => u.role == r).length;
  int get deactivatedCount => _users.where((u) => !u.isActive).length;
  int get activeBreakGlassCount => _breakGlass.where((b) => b.isActive).length;

  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await Future.wait([_loadUsers(), _loadAudit(), _loadBreakGlass()]);
    } catch (e) {
      _error = e;
      debugPrint('AdminService.refresh failed: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _loadUsers() async {
    final rows = await _client
        .from('profiles')
        .select('id, username, display_name, role, is_active, shared_with_doctor, messaging_restricted, created_at')
        .order('created_at', ascending: true);
    _users = [
      for (final r in rows as List)
        AdminUser.fromRow((r as Map).cast<String, dynamic>())
    ];
  }

  Future<void> _loadAudit() async {
    final rows = await _client
        .from('audit_log')
        .select()
        .order('created_at', ascending: false)
        .limit(100);
    _audit = [
      for (final r in rows as List)
        AuditEntry.fromRow((r as Map).cast<String, dynamic>())
    ];
  }

  Future<void> _loadBreakGlass() async {
    final rows = await _client
        .from('break_glass_sessions')
        .select()
        .order('granted_at', ascending: false)
        .limit(50);
    _breakGlass = [
      for (final r in rows as List)
        BreakGlassSession.fromRow((r as Map).cast<String, dynamic>())
    ];
  }

  /// Writes an audit entry for the current admin. Best-effort (logging must
  /// never block the action it records).
  Future<void> _audited(String action,
      {String? targetUserId, String? detail}) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _client.from('audit_log').insert({
        'actor_id': uid,
        'actor_role': 'admin',
        'action': action,
        if (targetUserId != null) 'target_user_id': targetUserId,
        if (detail != null) 'detail': detail,
      });
    } catch (e) {
      debugPrint('AdminService audit insert failed: $e');
    }
  }

  Future<void> setRole(AdminUser user, UserRole role) async {
    await _client
        .from('profiles')
        .update({'role': role.name}).eq('id', user.id);
    await _audited('role_change',
        targetUserId: user.id,
        detail: 'Set ${user.username} role to ${role.name}.');
    await refresh();
  }

  Future<void> setActive(AdminUser user, bool active) async {
    await _client
        .from('profiles')
        .update({'is_active': active}).eq('id', user.id);
    await _audited(active ? 'account_activate' : 'account_deactivate',
        targetUserId: user.id,
        detail:
            '${active ? 'Activated' : 'Deactivated'} account ${user.username}.');
    await refresh();
  }

  /// Opens a time-limited, read-only break-glass session for [patient].
  /// Logged to the audit trail (the "super admin is notified / reviewed"
  /// record). Returns the created session.
  Future<BreakGlassSession> openBreakGlass({
    required AdminUser patient,
    required String reason,
    required int durationMinutes,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in.');
    final expires = DateTime.now().add(Duration(minutes: durationMinutes));
    final row = await _client
        .from('break_glass_sessions')
        .insert({
          'admin_id': uid,
          'target_patient_id': patient.id,
          'reason': reason.trim(),
          'duration_minutes': durationMinutes,
          'expires_at': expires.toUtc().toIso8601String(),
        })
        .select()
        .single();
    await _audited('break_glass_opened',
        targetUserId: patient.id,
        detail:
            'Emergency access to ${patient.username} for $durationMinutes min. Reason: ${reason.trim()}');
    await refresh();
    return BreakGlassSession.fromRow(row.cast<String, dynamic>());
  }

  Future<void> revokeBreakGlass(BreakGlassSession session) async {
    await _client
        .from('break_glass_sessions')
        .update({'revoked': true}).eq('id', session.id);
    await _audited('break_glass_revoked',
        targetUserId: session.targetPatientId,
        detail: 'Revoked emergency access session.');
    await refresh();
  }

  // ----- Chat moderation -----

  /// Restricts / unrestricts a user from sending chat messages (behavior-based
  /// moderation). Enforced server-side by the RESTRICTIVE insert policy.
  Future<void> setMessagingRestricted(AdminUser user, bool restricted) async {
    await _client
        .from('profiles')
        .update({'messaging_restricted': restricted}).eq('id', user.id);
    await _audited(restricted ? 'messaging_restrict' : 'messaging_unrestrict',
        targetUserId: user.id,
        detail:
            '${restricted ? 'Restricted' : 'Unrestricted'} messaging for ${user.username}.');
    await refresh();
  }

  /// Loads every chat thread (admin reads all messages via RLS), summarized by
  /// patient with the latest message + count. Newest thread first.
  Future<void> loadMessageThreads() async {
    final rows = await _client
        .from('messages')
        .select('patient_id, body, created_at, deleted_at, removed_by_admin')
        .order('created_at', ascending: false);
    final byPatient = <String, List<Map<String, dynamic>>>{};
    for (final r in rows as List) {
      final m = (r as Map).cast<String, dynamic>();
      byPatient.putIfAbsent(m['patient_id'] as String, () => []).add(m);
    }
    _threads = byPatient.entries.map((e) {
      final newest = e.value.first; // ordered desc
      final unsent =
          newest['deleted_at'] != null || (newest['removed_by_admin'] as bool? ?? false);
      return MessageThread(
        patientId: e.key,
        lastBody: unsent ? '(message removed)' : (newest['body'] as String? ?? ''),
        lastAt: DateTime.tryParse(newest['created_at'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
        count: e.value.length,
      );
    }).toList()
      ..sort((a, b) => b.lastAt.compareTo(a.lastAt));
    notifyListeners();
  }

  /// Moderator removal of a message (soft delete + removed_by_admin flag).
  Future<void> removeMessage(
      {required String messageId, required String patientId}) async {
    await _client.from('messages').update({
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
      'removed_by_admin': true,
    }).eq('id', messageId);
    await _audited('message_removed',
        targetUserId: patientId, detail: 'Removed a message in a chat thread.');
  }

  /// Read-only fetch of a patient's scan records during a break-glass session.
  /// Succeeds only while an active session exists (enforced by RLS in 0011).
  /// Returns lightweight maps (no images) — emergency review of the trend, not
  /// full clinical access.
  Future<List<Map<String, dynamic>>> loadPatientScans(String patientId) async {
    final rows = await _client
        .from('scans')
        .select(
            'taken_at, region, severity_label, cook_grade, inflammatory_count, non_inflammatory_count, post_acne_count')
        .eq('user_id', patientId)
        .order('taken_at', ascending: false)
        .limit(100);
    return [
      for (final r in rows as List) (r as Map).cast<String, dynamic>()
    ];
  }

  String usernameFor(String userId) {
    for (final u in _users) {
      if (u.id == userId) return u.username;
    }
    return userId.substring(0, 8);
  }
}
