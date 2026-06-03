import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Type of a recorded security/account activity event.
enum SecurityEventType {
  signIn,
  passwordChange,
  profileUpdate,
  consentChange,
  dataExport,
  dataDelete,
  deletionRequest;

  String get storage => name;

  String get label {
    switch (this) {
      case SecurityEventType.signIn:
        return 'Signed in';
      case SecurityEventType.passwordChange:
        return 'Password changed';
      case SecurityEventType.profileUpdate:
        return 'Profile updated';
      case SecurityEventType.consentChange:
        return 'Doctor sharing changed';
      case SecurityEventType.dataExport:
        return 'Records exported';
      case SecurityEventType.dataDelete:
        return 'Records deleted';
      case SecurityEventType.deletionRequest:
        return 'Account deletion requested';
    }
  }

  static SecurityEventType fromStorage(String? s) =>
      SecurityEventType.values.firstWhere((e) => e.name == s,
          orElse: () => SecurityEventType.signIn);
}

@immutable
class SecurityEvent {
  const SecurityEvent({
    required this.type,
    required this.description,
    required this.timestamp,
  });

  final SecurityEventType type;
  final String description;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'type': type.storage,
        'description': description,
        'ts': timestamp.toIso8601String(),
      };

  static SecurityEvent fromJson(Map<String, dynamic> j) => SecurityEvent(
        type: SecurityEventType.fromStorage(j['type'] as String?),
        description: (j['description'] as String?) ?? '',
        timestamp:
            DateTime.tryParse(j['ts'] as String? ?? '') ?? DateTime.now(),
      );
}

/// A lightweight, on-device log of account/security activity — sign-ins,
/// password and profile changes, sharing-consent changes, and data
/// export/delete actions. Surfaced in Privacy & Data and used by the
/// Notification Center's "Security & account alerts" category.
///
/// Stored locally (SharedPreferences) rather than server-side; a full audit
/// trail with server enforcement comes with the later audit-log work.
class SecurityActivityService extends ChangeNotifier {
  SecurityActivityService._internal();
  static final SecurityActivityService instance =
      SecurityActivityService._internal();

  static const _kKey = 'security_activity_log';
  static const int _max = 50;

  bool _initialized = false;
  List<SecurityEvent> _events = [];

  /// Events, newest first.
  List<SecurityEvent> get events => List.unmodifiable(_events);
  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = (jsonDecode(raw) as List)
            .map((e) => SecurityEvent.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
        _events = list;
      } catch (e) {
        debugPrint('SecurityActivityService: bad log, resetting: $e');
      }
    }
    notifyListeners();
  }

  /// Records an event (newest first) and persists. Safe to call before
  /// [init]; it initializes lazily.
  Future<void> record(SecurityEventType type, String description) async {
    if (!_initialized) await init();
    _events.insert(
      0,
      SecurityEvent(
          type: type, description: description, timestamp: DateTime.now()),
    );
    if (_events.length > _max) {
      _events = _events.sublist(0, _max);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kKey,
      jsonEncode(_events.map((e) => e.toJson()).toList()),
    );
  }
}
