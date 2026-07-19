import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import 'auth_service.dart';

/// Profile store, backed by Supabase.
///
/// Owns the profile picture (in the `profile-pictures` storage bucket under
/// `{user_id}/avatar.jpg`, with the storage path persisted in
/// `public.profiles.profile_picture_path`) plus display-name/username updates.
///
/// Scan history used to live here as in-memory mocks; it's now owned by
/// [ScanService] which queries `public.scans` directly. Listen to
/// ScanService.instance for scan-list updates, not this class.
class ProfileService extends ChangeNotifier {
  ProfileService._internal() {
    AuthService.instance.addListener(_onAuthChanged);
    if (AuthService.instance.isSignedIn) {
      // Fire-and-forget — fine because listeners get notified when it lands.
      _loadProfile();
    }
  }
  static final ProfileService instance = ProfileService._internal();

  supa.SupabaseClient get _client => supa.Supabase.instance.client;

  // ===== Profile picture =====

  String? _profilePictureUrl;

  /// Signed URL for the user's avatar, or null if not set / not loaded yet.
  /// Pass directly to `Image.network(...)`.
  String? get profilePictureUrl => _profilePictureUrl;

  // ===== Doctor sharing flag =====

  bool _sharedWithDoctor = false;

  /// Whether the user has opted in to sharing their scans with the demo
  /// doctor account. Drives the toggle on the profile screen. Mirrors
  /// `public.profiles.shared_with_doctor` (see 0002_doctor_demo.sql).
  bool get sharedWithDoctor => _sharedWithDoctor;

  void _onAuthChanged() {
    if (AuthService.instance.isSignedIn) {
      _loadProfile();
    } else {
      var changed = false;
      if (_profilePictureUrl != null) {
        _profilePictureUrl = null;
        changed = true;
      }
      if (_sharedWithDoctor) {
        _sharedWithDoctor = false;
        changed = true;
      }
      if (changed) notifyListeners();
    }
  }

  /// Reads the profiles row for the current user and, if a picture path is
  /// stored, generates a signed URL for display.
  Future<void> _loadProfile() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final row = await _client
          .from('profiles')
          .select('profile_picture_path, shared_with_doctor')
          .eq('id', userId)
          .maybeSingle();

      var changed = false;

      // Profile picture URL — resolve a fresh signed URL if a path is set.
      final path = (row?['profile_picture_path'] as String?)?.trim();
      if (path != null && path.isNotEmpty) {
        final url = await _client.storage
            .from('profile-pictures')
            .createSignedUrl(path, _signedUrlTtlSeconds);
        if (_profilePictureUrl != url) {
          _profilePictureUrl = url;
          changed = true;
        }
      } else if (_profilePictureUrl != null) {
        _profilePictureUrl = null;
        changed = true;
      }

      // Doctor sharing flag. Defaults to false if the column was added by
      // the 0002 migration but the row predates it (Postgres backfills with
      // the default, so this is just belt-and-braces).
      final shared = (row?['shared_with_doctor'] as bool?) ?? false;
      if (_sharedWithDoctor != shared) {
        _sharedWithDoctor = shared;
        changed = true;
      }

      if (changed) notifyListeners();
    } catch (e) {
      debugPrint('ProfileService: failed to load profile — $e');
    }
  }

  /// Toggles whether the demo doctor account can read this user's scans.
  /// Writes `shared_with_doctor` on the profiles row, optimistically updates
  /// the local copy so the toggle UI feels instant, and rolls back on
  /// failure so the switch returns to its previous position.
  Future<void> setSharedWithDoctor(bool value) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('You need to be signed in to change sharing settings.');
    }

    final previous = _sharedWithDoctor;
    if (previous == value) return;

    _sharedWithDoctor = value;
    notifyListeners();

    try {
      await _client
          .from('profiles')
          .update({'shared_with_doctor': value})
          .eq('id', userId);
    } catch (e) {
      // Roll back so the switch UI reflects the actual server state.
      _sharedWithDoctor = previous;
      notifyListeners();
      debugPrint('ProfileService.setSharedWithDoctor failed: $e');
      rethrow;
    }
  }

  /// Uploads [bytes] as the user's avatar (JPEG). Overwrites any existing one.
  /// Throws on failure so the caller (which already has a try/catch with a
  /// snackbar) can surface the error to the user.
  ///
  /// The caller is responsible for reading the picked file into bytes — this
  /// keeps ProfileService cross-platform (dart:io's File class doesn't exist
  /// on Flutter Web, so we never touch it here). Use XFile.readAsBytes()
  /// from image_picker, which works on every platform.
  Future<void> setProfilePicture(Uint8List bytes) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('No signed-in user.');
    }

    final storagePath = '$userId/avatar.jpg';

    // Upload (upsert: true overwrites if the object already exists).
    await _client.storage.from('profile-pictures').uploadBinary(
          storagePath,
          bytes,
          fileOptions: const supa.FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );

    // Persist the path on the profile row.
    await _client
        .from('profiles')
        .update({'profile_picture_path': storagePath})
        .eq('id', userId);

    // Generate a fresh signed URL. Supabase caches uploads aggressively, but
    // we ask for a new URL anyway so any stale image cache gets bypassed.
    final url = await _client.storage
        .from('profile-pictures')
        .createSignedUrl(storagePath, _signedUrlTtlSeconds);

    _profilePictureUrl = url;
    notifyListeners();
  }

  /// Updates the user's display name and/or username. Returns null on
  /// success, or an [AuthError] with a field hint on failure (most commonly
  /// a username collision, which surfaces as a unique-violation).
  ///
  /// Touches three places in lock-step:
  ///   1. `public.profiles` row (the canonical store for these fields)
  ///   2. `auth.users.raw_user_meta_data` (so AuthService.currentUser stays
  ///      in sync without a full session reload)
  ///   3. notifyListeners(), so the dashboard/profile/settings UIs rebuild
  ///      with the new name immediately
  Future<AuthError?> updateProfile({
    required String displayName,
    required String username,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const AuthError(
        field: AuthField.email,
        message: 'You need to be signed in to update your profile.',
      );
    }

    final usernameKey = username.trim().toLowerCase();
    final displayTrim = displayName.trim();

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
    if (displayTrim.isEmpty) {
      return const AuthError(
        field: AuthField.username,
        message: 'Display name is required.',
      );
    }

    // Update profiles first — that's where the unique-username constraint
    // lives, so collision errors land here before we touch auth metadata.
    try {
      await _client.from('profiles').update({
        'username': usernameKey,
        'display_name': displayTrim,
      }).eq('id', userId);
    } on supa.PostgrestException catch (e) {
      if (e.code == '23505') {
        return const AuthError(
          field: AuthField.username,
          message: 'That username is already taken.',
        );
      }
      return AuthError(
        field: AuthField.username,
        message: 'Could not update profile: ${e.message}',
      );
    } catch (_) {
      return const AuthError(
        field: AuthField.username,
        message: 'Could not connect. Check your internet and try again.',
      );
    }

    // Mirror into auth metadata so AppUser (built from session.user) shows
    // the new name without waiting for a sign-out / sign-in cycle.
    try {
      await _client.auth.updateUser(
        supa.UserAttributes(data: {
          'username': usernameKey,
          'display_name': displayTrim,
        }),
      );
    } catch (_) {
      // Profiles row update already succeeded; metadata mirror is best-effort.
    }

    notifyListeners();
    return null;
  }

  /// Removes the user's avatar from storage and clears the profile column.
  Future<void> clearProfilePicture() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    final storagePath = '$userId/avatar.jpg';
    try {
      // remove() is a no-op if the object doesn't exist.
      await _client.storage.from('profile-pictures').remove([storagePath]);
    } catch (e) {
      debugPrint('ProfileService: failed to delete avatar object — $e');
    }
    try {
      await _client
          .from('profiles')
          .update({'profile_picture_path': null})
          .eq('id', userId);
    } catch (e) {
      debugPrint('ProfileService: failed to clear profile column — $e');
    }

    _profilePictureUrl = null;
    notifyListeners();
  }

  // ===== Constants =====

  /// Signed URLs valid for 1 hour. Long enough for any reasonable session;
  /// short enough that a leaked URL doesn't expose the avatar indefinitely.
  static const int _signedUrlTtlSeconds = 60 * 60;
}
