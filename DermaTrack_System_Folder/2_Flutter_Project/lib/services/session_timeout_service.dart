import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'security_activity_service.dart';

/// Automatically signs out an inactive user after [idleTimeout] of no
/// interaction — a basic session-timeout control for a health app holding
/// sensitive data. The app wraps its UI in a pointer [Listener] that calls
/// [notifyActivity] on every touch; the timer re-arms on each interaction and
/// is only active while signed in.
class SessionTimeoutService {
  SessionTimeoutService._internal();
  static final SessionTimeoutService instance =
      SessionTimeoutService._internal();

  /// Idle window before auto sign-out.
  static const Duration idleTimeout = Duration(minutes: 15);

  Timer? _timer;
  bool _initialized = false;

  void init() {
    if (_initialized) return;
    _initialized = true;
    AuthService.instance.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  void _onAuthChanged() {
    if (AuthService.instance.isSignedIn) {
      _arm();
    } else {
      _cancel();
    }
  }

  /// Called on user interaction to reset the idle timer.
  void notifyActivity() {
    if (AuthService.instance.isSignedIn) _arm();
  }

  void _arm() {
    _timer?.cancel();
    _timer = Timer(idleTimeout, _expire);
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void _expire() {
    if (!AuthService.instance.isSignedIn) return;
    debugPrint('SessionTimeoutService: idle timeout — signing out.');
    SecurityActivityService.instance.record(
      SecurityEventType.signIn,
      'Signed out automatically after ${idleTimeout.inMinutes} minutes of inactivity.',
    );
    AuthService.instance.signOut();
  }
}
