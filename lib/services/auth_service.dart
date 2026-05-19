import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

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
    }

    // React to future auth state changes (sign-in, sign-out, token refresh).
    _client.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      final next = session == null ? null : _userFromSession(session);
      if (next != _currentUser) {
        _currentUser = next;
        notifyListeners();
      }
    });
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
      return null;
    } on supa.AuthException catch (e) {
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
    return RegExp(r'^[\w.\-]+@[\w\-]+\.[a-zA-Z]{2,}$').hasMatch(email);
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
