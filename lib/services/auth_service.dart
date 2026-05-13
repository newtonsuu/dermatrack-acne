import 'package:flutter/foundation.dart';

/// Stub authentication service.
///
/// v1 — in-memory only. Tracks the users that have registered during this app
/// session and validates credentials against that store. Swap for Supabase in
/// week 2 while keeping the same public surface (signIn, signUp, signOut,
/// sendPasswordReset, currentUser).
class AuthService extends ChangeNotifier {
  AuthService._internal();
  static final AuthService instance = AuthService._internal();

  // Keyed by lowercased email so lookups are case-insensitive.
  final Map<String, _StoredUser> _users = {};
  final Set<String> _usernames = {}; // lowercased

  AppUser? _currentUser;
  AppUser? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;

  /// Returns null on success, or an [AuthError] with a [field] hint and a
  /// human-readable [message] on failure.
  Future<AuthError?> signIn({
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final emailKey = email.trim().toLowerCase();
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

    final stored = _users[emailKey];
    if (stored == null) {
      return const AuthError(
        field: AuthField.email,
        message: 'No account found with that email.',
      );
    }
    if (stored.password != password) {
      return const AuthError(
        field: AuthField.password,
        message: 'Incorrect password. Try again or reset it.',
      );
    }

    _currentUser = AppUser(email: stored.email, username: stored.username);
    notifyListeners();
    return null;
  }

  Future<AuthError?> signUp({
    required String email,
    required String username,
    required String password,
    required String confirmPassword,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final emailKey = email.trim().toLowerCase();
    final usernameKey = username.trim().toLowerCase();

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

    final missing = unmetPasswordRequirements(password);
    if (missing.isNotEmpty) {
      return const AuthError(
        field: AuthField.password,
        message: 'Password does not meet the requirements below.',
      );
    }
    if (password != confirmPassword) {
      return const AuthError(
        field: AuthField.confirmPassword,
        message: 'Passwords do not match.',
      );
    }
    if (_users.containsKey(emailKey)) {
      return const AuthError(
        field: AuthField.email,
        message: 'An account with this email already exists.',
      );
    }
    if (_usernames.contains(usernameKey)) {
      return const AuthError(
        field: AuthField.username,
        message: 'That username is already taken.',
      );
    }

    _users[emailKey] = _StoredUser(
      email: email.trim(),
      username: username.trim(),
      password: password,
    );
    _usernames.add(usernameKey);

    _currentUser = AppUser(email: email.trim(), username: username.trim());
    notifyListeners();
    return null;
  }

  Future<void> signOut() async {
    _currentUser = null;
    notifyListeners();
  }

  /// Stub — pretends to send a reset email and always reports success so we
  /// don't leak which emails are registered.
  Future<void> sendPasswordReset(String email) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

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
}

class _StoredUser {
  _StoredUser({
    required this.email,
    required this.username,
    required this.password,
  });
  final String email;
  final String username;
  final String password;
}
