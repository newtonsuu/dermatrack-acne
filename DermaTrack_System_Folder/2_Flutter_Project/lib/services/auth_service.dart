import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import 'security_activity_service.dart';

/// Email address that triggers doctor-mode routing in the app.
///
/// DEMO ONLY. The Supabase migration `0002_doctor_demo.sql` references this
/// same string from its RLS policy via the `is_demo_doctor()` function. If
/// you change it here, update that migration too (and re-apply it).
///
/// Post-thesis: replace with a proper `role` column on profiles + a
/// doctor↔patient linking table so multiple doctors are supported and
/// access is auditable.
const String kDoctorDemoEmail = 'doctor@dermatrack.demo';

/// All emails that route to the demo dermatologist view. The original demo
/// account plus any additional demo doctors created for testing. Mirror any
/// change here in the database `is_demo_doctor()` function (migration 0007)
/// so client routing and server-side RLS agree.
const Set<String> kDoctorDemoEmails = {
  kDoctorDemoEmail,
  'dr.demo@dermatrack.demo',
};

/// Access role for the signed-in user. Mirrors `public.profiles.role`
/// (migration 0011): patient | doctor | admin. The break-glass *admin* is the
/// same admin role acting through a logged, time-limited emergency session —
/// not a separate persistent role.
enum UserRole { patient, doctor, admin }

/// Parses the `role` text column into a [UserRole], defaulting to patient.
UserRole userRoleFromString(String? s) {
  switch (s) {
    case 'admin':
      return UserRole.admin;
    case 'doctor':
      return UserRole.doctor;
    default:
      return UserRole.patient;
  }
}

/// Authentication service backed by Supabase Auth.
///
/// Preserves the exact public surface of the previous in-memory stub so the
/// existing welcome / login / register / forgot-password screens compile
/// without changes. Adds Supabase-specific behavior internally:
///   - Listens to onAuthStateChange so sign-in / sign-out / token-refresh
///     update [currentUser] and fire listeners.
///   - Catches Supabase AuthException and translates it to AuthError values
///     with the right [AuthField] hint so the right form input lights up.
///   - Passes `username` and `display_name` in the signup metadata so the
///     `handle_new_user` Postgres trigger can populate the profiles row.
class AuthService extends ChangeNotifier {
  AuthService._internal() {
    _initialize();
  }
  static final AuthService instance = AuthService._internal();

  supa.SupabaseClient? _clientOrNull;
  supa.SupabaseClient get _client {
    final c = _clientOrNull;
    if (c == null) {
      throw StateError(
        'Supabase has not been initialized. Make sure main() calls '
        'Supabase.initialize() before any code touches AuthService.',
      );
    }
    return c;
  }

  AppUser? _currentUser;
  AppUser? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;

  // Role + account status, loaded from the profiles row once auth resolves.
  // The role is now authoritative from the database (migration 0011), not the
  // email allowlist — that allowlist remains only as a seed/back-compat hint.
  UserRole _role = UserRole.patient;
  bool _roleResolved = false;
  bool _accountActive = true;
  bool _canSwitchRoles = false;

  /// The signed-in user's role. Defaults to patient until [roleResolved].
  UserRole get role => _role;

  /// True once the role has been fetched after sign-in. The AuthGate waits on
  /// this so it never flashes the wrong shell (e.g. patient view for a doctor)
  /// while the role round-trips. Always true when signed out.
  bool get roleResolved => !isSignedIn || _roleResolved;

  /// False when an admin has deactivated this account.
  bool get accountActive => _accountActive;

  /// True for designated demo/dev accounts that may switch their own role
  /// between patient/doctor/admin (see [switchRole]).
  bool get canSwitchRoles => _canSwitchRoles;

  /// True when the signed-in user has the doctor role. The auth gate in
  /// main.dart uses this to route to DoctorShell.
  bool get isDoctor => _role == UserRole.doctor;

  /// True when the signed-in user has the admin role (routes to AdminShell).
  bool get isAdmin => _role == UserRole.admin;

  // Client-side brute-force guard. After [_maxAttempts] consecutive failed
  // sign-ins, sign-in is locked for [_lockoutDuration]. (Supabase also
  // rate-limits server-side; this gives immediate local feedback.)
  static const int _maxAttempts = 5;
  static const Duration _lockoutDuration = Duration(seconds: 60);
  int _failedAttempts = 0;
  DateTime? _lockoutUntil;

  void _initialize() {
    // Supabase.instance.client throws if initialize() wasn't called. Guard
    // so a misconfigured app gets a clearer error than a stack trace from
    // inside the Supabase SDK.
    try {
      _clientOrNull = supa.Supabase.instance.client;
    } catch (_) {
      return;
    }

    // Pick up an existing session restored from local storage.
    final session = _client.auth.currentSession;
    if (session != null) {
      _currentUser = _userFromSession(session);
      _loadRole();
    }

    // React to future auth state changes (sign-in, sign-out, token refresh).
    _client.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      final next = session == null ? null : _userFromSession(session);
      if (next != _currentUser) {
        _currentUser = next;
        if (next == null) {
          // Signed out — reset role state.
          _role = UserRole.patient;
          _roleResolved = false;
          _accountActive = true;
        } else {
          // Signed in (or switched account) — re-resolve the role.
          _roleResolved = false;
          _loadRole();
        }
        notifyListeners();
      }
    });
  }

  /// Loads the signed-in user's role + account status from the profiles row.
  /// Falls back to patient/active on any error so a transient failure can't
  /// lock someone out of their own data. Fires listeners when [roleResolved]
  /// flips true so the AuthGate can route.
  Future<void> _loadRole() async {
    final c = _clientOrNull;
    final uid = c?.auth.currentUser?.id;
    if (c == null || uid == null) {
      _role = UserRole.patient;
      _accountActive = true;
      _canSwitchRoles = false;
      _roleResolved = true;
      notifyListeners();
      return;
    }
    try {
      final row = await c
          .from('profiles')
          .select('role, is_active, can_switch_roles')
          .eq('id', uid)
          .maybeSingle();
      _role = userRoleFromString(row?['role'] as String?);
      _accountActive = (row?['is_active'] as bool?) ?? true;
      _canSwitchRoles = (row?['can_switch_roles'] as bool?) ?? false;
    } catch (e) {
      debugPrint('AuthService._loadRole failed: $e');
      _role = UserRole.patient;
      _accountActive = true;
      _canSwitchRoles = false;
    }
    _roleResolved = true;
    notifyListeners();
  }

  /// Switches the signed-in account's active role (only works for accounts
  /// flagged `can_switch_roles`; the DB trigger enforces it). Updates the
  /// `profiles.role`, re-resolves, and notifies so the AuthGate re-routes to
  /// the matching shell.
  Future<void> switchRole(UserRole target) async {
    final c = _clientOrNull;
    final uid = c?.auth.currentUser?.id;
    if (c == null || uid == null) return;
    if (target == _role) return;
    await c.from('profiles').update({'role': target.name}).eq('id', uid);
    await _loadRole();
  }

  /// Signs the user in. Returns null on success, or an [AuthError] with a
  /// [field] hint and a human-readable [message] on failure.
  Future<AuthError?> signIn({
    required String email,
    required String password,
  }) async {
    final emailKey = email.trim().toLowerCase();

    // Fast client-side validation so the user gets immediate feedback
    // without a network round-trip.
    if (emailKey.isEmpty) {
      return const AuthError(field: AuthField.email, message: 'Email is required.');
    }
    if (!_isValidEmail(emailKey)) {
      return const AuthError(
        field: AuthField.email,
        message: 'Please enter a valid email address.',
      );
    }
    if (password.isEmpty) {
      return const AuthError(
        field: AuthField.password,
        message: 'Password is required.',
      );
    }

    if (_clientOrNull == null) return _notInitializedError();

    // Brute-force lockout check.
    final nowTs = DateTime.now();
    if (_lockoutUntil != null && nowTs.isBefore(_lockoutUntil!)) {
      final secs = _lockoutUntil!.difference(nowTs).inSeconds + 1;
      return AuthError(
        field: AuthField.password,
        message: 'Too many attempts. Try again in ${secs}s.',
      );
    }

    try {
      final response = await _client.auth.signInWithPassword(
        email: emailKey,
        password: password,
      );
      if (response.session == null) {
        // Defensive: signInWithPassword normally returns a session when
        // successful; absence almost always means email-confirm is required.
        return const AuthError(
          field: AuthField.email,
          message: 'Please confirm your email before signing in.',
        );
      }
      // _currentUser is updated by the onAuthStateChange listener.
      _failedAttempts = 0;
      _lockoutUntil = null;
      SecurityActivityService.instance.record(
        SecurityEventType.signIn,
        'Signed in to your account on this device.',
      );
      return null;
    } on supa.AuthException catch (e) {
      // Count consecutive failures; lock briefly after too many.
      _failedAttempts++;
      if (_failedAttempts >= _maxAttempts) {
        _lockoutUntil = DateTime.now().add(_lockoutDuration);
        _failedAttempts = 0;
        return const AuthError(
          field: AuthField.password,
          message:
              'Too many failed attempts. Please wait a minute before trying again.',
        );
      }
      return _mapAuthException(e);
    } catch (_) {
      return const AuthError(
        field: AuthField.email,
        message: 'Could not connect. Check your internet and try again.',
      );
    }
  }

  /// Creates a new account. Returns null on success, or an [AuthError] on
  /// failure with the field hint and message.
  Future<AuthError?> signUp({
    required String email,
    required String username,
    required String password,
    required String confirmPassword,
  }) async {
    final emailKey = email.trim().toLowerCase();
    final usernameKey = username.trim().toLowerCase();
    final displayName = username.trim();

    if (emailKey.isEmpty) {
      return const AuthError(field: AuthField.email, message: 'Email is required.');
    }
    if (!_isValidEmail(emailKey)) {
      return const AuthError(
        field: AuthField.email,
        message: 'Please enter a valid email address.',
      );
    }
    if (usernameKey.isEmpty) {
      return const AuthError(
        field: AuthField.username,
        message: 'Username is required.',
      );
    }
    if (usernameKey.length < 3) {
      return const AuthError(
        field: AuthField.username,
        message: 'Username must be at least 3 characters.',
      );
    }
    if (unmetPasswordRequirements(password).isNotEmpty) {
      return const AuthError(
        field: AuthField.password,
        message: 'Password does not meet the requirements.',
      );
    }
    if (password != confirmPassword) {
      return const AuthError(
        field: AuthField.confirmPassword,
        message: 'Passwords do not match.',
      );
    }

    if (_clientOrNull == null) return _notInitializedError();

    try {
      final response = await _client.auth.signUp(
        email: emailKey,
        password: password,
        // These land in raw_user_meta_data and are read by the
        // handle_new_user Postgres trigger to populate the profiles row.
        data: {
          'username': usernameKey,
          'display_name': displayName,
        },
      );
      if (response.user == null) {
        return const AuthError(
          field: AuthField.email,
          message: 'Could not create account. Try again.',
        );
      }
      return null;
    } on supa.AuthException catch (e) {
      return _mapAuthException(e);
    } on supa.PostgrestException catch (e) {
      // The handle_new_user trigger inserts into public.profiles. If the
      // username collides with an existing one, Postgres raises a unique
      // violation (SQLSTATE 23505) which surfaces here.
      if (e.code == '23505') {
        return const AuthError(
          field: AuthField.username,
          message: 'That username is already taken.',
        );
      }
      return AuthError(
        field: AuthField.email,
        message: 'Could not create account: ${e.message}',
      );
    } catch (_) {
      return const AuthError(
        field: AuthField.email,
        message: 'Could not connect. Check your internet and try again.',
      );
    }
  }

  /// Changes the signed-in user's password. Returns null on success, or an
  /// [AuthError] on failure (most commonly the new password not meeting the
  /// strength requirements, or the session having expired).
  Future<AuthError?> changePassword({required String newPassword}) async {
    if (unmetPasswordRequirements(newPassword).isNotEmpty) {
      return const AuthError(
        field: AuthField.password,
        message: 'Password does not meet the requirements.',
      );
    }

    if (_clientOrNull == null) return _notInitializedError();

    try {
      final response = await _client.auth.updateUser(
        supa.UserAttributes(password: newPassword),
      );
      if (response.user == null) {
        return const AuthError(
          field: AuthField.password,
          message: 'Could not change password. Try signing in again.',
        );
      }
      SecurityActivityService.instance.record(
        SecurityEventType.passwordChange,
        'Your account password was changed.',
      );
      return null;
    } on supa.AuthException catch (e) {
      return _mapAuthException(e);
    } catch (_) {
      return const AuthError(
        field: AuthField.password,
        message: 'Could not connect. Check your internet and try again.',
      );
    }
  }

  Future<void> signOut() async {
    if (_clientOrNull == null) return;
    try {
      await _client.auth.signOut();
    } catch (_) {
      // If the server rejects the sign-out (e.g., token already expired),
      // still clear the local state so the UI swaps to the welcome screen.
      _currentUser = null;
      notifyListeners();
    }
  }

  /// Sends a password reset email. Always reports success so we don't leak
  /// which emails are registered.
  Future<void> sendPasswordReset(String email) async {
    final emailKey = email.trim().toLowerCase();
    if (emailKey.isEmpty || !_isValidEmail(emailKey)) return;
    if (_clientOrNull == null) return;
    try {
      await _client.auth.resetPasswordForEmail(emailKey);
    } catch (_) {
      // Intentionally silent.
    }
  }

  // ===== internals =====

  AppUser _userFromSession(supa.Session session) {
    final user = session.user;
    final meta = user.userMetadata ?? const <String, dynamic>{};
    final username = (meta['username'] as String?)?.trim();
    final display = (meta['display_name'] as String?)?.trim();
    final fallback = user.email?.split('@').first ?? 'user';
    return AppUser(
      email: user.email ?? '',
      username: display ?? username ?? fallback,
    );
  }

  AuthError _mapAuthException(supa.AuthException e) {
    final msg = e.message.toLowerCase();

    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid email or password')) {
      return const AuthError(
        field: AuthField.password,
        message: 'Incorrect email or password. Try again or reset it.',
      );
    }
    if (msg.contains('user already registered') ||
        msg.contains('already been registered') ||
        msg.contains('already exists')) {
      return const AuthError(
        field: AuthField.email,
        message: 'An account with this email already exists.',
      );
    }
    if (msg.contains('email not confirmed') ||
        msg.contains('confirm your email')) {
      return const AuthError(
        field: AuthField.email,
        message: 'Please confirm your email before signing in.',
      );
    }
    if (msg.contains('password')) {
      return AuthError(field: AuthField.password, message: e.message);
    }
    return AuthError(field: AuthField.email, message: e.message);
  }

  AuthError _notInitializedError() => const AuthError(
        field: AuthField.email,
        message:
            "Couldn't reach the server. Make sure the app was built with SUPABASE_URL and SUPABASE_ANON_KEY.",
      );

  bool _isValidEmail(String email) {
    // Accepts multi-label domains (e.g. user@mymail.mapua.edu.ph), not just
    // single-label ones like user@gmail.com.
    return RegExp(r'^[\w.\-]+@([\w\-]+\.)+[a-zA-Z]{2,}$').hasMatch(email);
  }
}

/// Returns the list of requirements [password] does *not* yet satisfy.
/// Empty list means the password is strong enough.
List<PasswordRequirement> unmetPasswordRequirements(String password) {
  final missing = <PasswordRequirement>[];
  if (password.length < 12) missing.add(PasswordRequirement.length);
  if (!RegExp(r'[A-Z]').hasMatch(password)) missing.add(PasswordRequirement.uppercase);
  if (!RegExp(r'[a-z]').hasMatch(password)) missing.add(PasswordRequirement.lowercase);
  if (!RegExp(r'\d').hasMatch(password)) missing.add(PasswordRequirement.number);
  if (!RegExp(r'[^a-zA-Z0-9]').hasMatch(password)) missing.add(PasswordRequirement.special);
  return missing;
}

enum PasswordRequirement {
  length('At least 12 characters'),
  uppercase('One uppercase letter (A–Z)'),
  lowercase('One lowercase letter (a–z)'),
  number('One number (0–9)'),
  special('One special character (!@#\$…)');

  const PasswordRequirement(this.label);
  final String label;
}

/// Identifies which input the auth error pertains to so the UI can highlight
/// that specific field.
enum AuthField { email, username, password, confirmPassword }

@immutable
class AuthError {
  const AuthError({required this.field, required this.message});
  final AuthField field;
  final String message;
}

@immutable
class AppUser {
  const AppUser({required this.email, required this.username});
  final String email;
  final String username;

  /// Kept as a getter so existing screens (dashboard, profile) that reference
  /// `displayName` keep working without changes.
  String get displayName => username;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppUser && other.email == email && other.username == username);

  @override
  int get hashCode => Object.hash(email, username);
}
