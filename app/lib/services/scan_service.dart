import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:uuid/uuid.dart';

import '../models/scan.dart';
import 'auth_service.dart';

/// Owns the user's scan history and the scan-submission pipeline.
///
/// Three responsibilities:
///   1. Load scans from `public.scans` and resolve signed URLs so the UI can
///      display the images. Re-runs on sign-in; clears on sign-out.
///   2. `submitScan(bytes)` — uploads the JPEG, invokes the `analyze-scan`
///      Edge Function, and prepends the returned scan to the in-memory list.
///   3. `deleteScan(id)` — removes the storage object and the row.
///
/// Listen via [ChangeNotifier] (or wrap in `ListenableBuilder`) to react to
/// scan list updates. Replaces the old `ProfileService.scans` mock data.
class ScanService extends ChangeNotifier {
  ScanService._internal() {
    AuthService.instance.addListener(_onAuthChanged);
    // If the app launches with an already-restored session, kick off a load.
    // Fire-and-forget — listeners get notified when it finishes.
    if (AuthService.instance.isSignedIn) {
      loadScans();
    }
  }
  static final ScanService instance = ScanService._internal();

  // Late guard so unit tests that don't init Supabase don't crash on access.
  supa.SupabaseClient get _client => supa.Supabase.instance.client;

  List<Scan> _scans = const [];
  bool _isLoading = false;
  bool _isSubmitting = false;
  Object? _lastLoadError;

  /// All scans, most recent first. Unmodifiable view — call [submitScan] /
  /// [deleteScan] to mutate.
  List<Scan> get scans => List.unmodifiable(_scans);

  /// True while [loadScans] is in flight.
  bool get isLoading => _isLoading;

  /// True while [submitScan] is in flight. Camera screen uses this to lock
  /// the "Use this photo" button.
  bool get isSubmitting => _isSubmitting;

  /// The error from the most recent failed load, if any. Cleared on the
  /// next successful load.
  Object? get lastLoadError => _lastLoadError;

  /// Most recent [count] scans, newest first. Replaces the old
  /// `ProfileService.recentScans()` so existing UI keeps working.
  List<Scan> recentScans({int count = 6}) =>
      _scans.take(count).toList(growable: false);

  // ----- Internals -----

  /// Supabase signed URLs default to 1 hour. Long enough for a typical
  /// scrolling session; short enough that a leaked URL doesn't expose
  /// a scan image indefinitely.
  static const int _signedUrlTtlSeconds = 60 * 60;

  void _onAuthChanged() {
    if (AuthService.instance.isSignedIn) {
      loadScans();
    } else if (_scans.isNotEmpty) {
      _scans = const [];
      _lastLoadError = null;
      notifyListeners();
    }
  }

  // Generate a signed URL for [path]. Returns null on failure so the caller
  // can still surface the scan with a fallback placeholder.
  Future<String?> _signedUrlFor(String path) async {
    try {
      return await _client.storage
          .from('scan-images')
          .createSignedUrl(path, _signedUrlTtlSeconds);
    } catch (e) {
      debugPrint('ScanService._signedUrlFor($path) failed: $e');
      return null;
    }
  }

  // ----- Loads -----

  /// Fetches the user's scans and refreshes the in-memory list.
  ///
  /// Safe to call multiple times — concurrent calls coalesce via the
  /// _isLoading flag (the second call is a no-op while the first is in
  /// flight). Errors are stored on [lastLoadError] and the list keeps its
  /// previous value (i.e. we don't blow away good data on a transient
  /// network failure).
  Future<void> loadScans() async {
    if (_isLoading) return;
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      // PostgREST embed brings the doctor_notes row (if any) along for the
      // ride so the patient's scan detail can show "From your dermatologist"
      // without a second query. RLS on doctor_notes confines the embed to
      // notes on the user's own scans.
      final rows = await _client
          .from('scans')
          .select('*, doctor_notes(note)')
          .order('taken_at', ascending: false);

      final parsed = <Scan>[];
      for (final row in rows as List) {
        try {
          parsed.add(Scan.fromRow((row as Map).cast<String, dynamic>()));
        } catch (e) {
          // Skip malformed rows rather than failing the whole load.
          debugPrint('ScanService.loadScans: skipping malformed row: $e');
        }
      }

      // Resolve signed URLs concurrently rather than one-at-a-time. A user
      // with many scans previously waited for N serial round-trips; running
      // them in parallel collapses that to roughly a single round-trip of
      // latency. _signedUrlFor swallows per-item errors (returns null), so a
      // single bad path can't fail the batch.
      final urls =
          await Future.wait(parsed.map((s) => _signedUrlFor(s.imagePath)));
      final withUrls = <Scan>[
        for (var i = 0; i < parsed.length; i++)
          parsed[i].copyWith(imageUrl: urls[i]),
      ];

      _scans = List.unmodifiable(withUrls);
      _lastLoadError = null;
    } catch (e) {
      debugPrint('ScanService.loadScans: $e');
      _lastLoadError = e;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ----- Submit -----

  /// Uploads [bytes] (a JPEG selfie) to Supabase Storage, runs analysis via
  /// the `analyze-scan` Edge Function, and returns the resulting Scan.
  ///
  /// Throws on failure with a user-readable message. The caller — typically
  /// `camera_screen._useThisPhoto` — should wrap in try/catch and surface
  /// via a SnackBar.
  ///
  /// Optional parameters:
  ///   [region]    — anatomical zone the scan represents. Defaults to
  ///                 [ScanRegion.fullFace] so legacy single-scan callers
  ///                 keep working without changes. Guided-session callers
  ///                 pass the matching region for each of the five steps.
  ///   [sessionId] — UUID linking this scan to the other four from a
  ///                 guided session. The caller generates it once at
  ///                 session start and reuses it for all five submissions.
  ///                 Pass null for standalone scans.
  ///   [faceBbox]  — face bounding box from the ML Kit preflight, in the
  ///                 same pixel space as the uploaded image. The Edge
  ///                 Function uses this to filter Roboflow detections
  ///                 whose center falls outside the face — solves the
  ///                 "comedone detected on the background" problem the
  ///                 dermatologist flagged on 2026-05-25.
  ///                 Shape: {'x', 'y', 'w', 'h', 'image_w', 'image_h'}.
  ///
  /// Side effects on success:
  ///   - A new row in `public.scans`.
  ///   - A new object at `scan-images/{user_id}/{scan_id}.jpg`.
  ///   - The new Scan prepended to [scans] and listeners notified.
  Future<Scan> submitScan(
    Uint8List bytes, {
    ScanRegion region = ScanRegion.fullFace,
    String? sessionId,
    Map<String, dynamic>? faceBbox,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('You need to be signed in to submit a scan.');
    }

    _isSubmitting = true;
    notifyListeners();

    final scanId = const Uuid().v4();
    final imagePath = '$userId/$scanId.jpg';
    var imageUploaded = false;

    try {
      // 1. Upload. Storage RLS guarantees the path's first segment must
      //    equal auth.uid(); we construct it that way above.
      await _client.storage.from('scan-images').uploadBinary(
            imagePath,
            bytes,
            fileOptions: const supa.FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );
      imageUploaded = true;

      // 2. Run analysis. supabase_flutter automatically attaches the JWT.
      //    region + session_id + face_bbox are forwarded to the Edge
      //    Function so it can (a) persist them on the scan row and
      //    (b) filter out Roboflow detections whose center falls outside
      //    the face bbox — solving the background-false-positive issue.
      //    All three are optional from the server's perspective: omitting
      //    region defaults to full_face on insert, omitting session_id
      //    keeps the row standalone, omitting face_bbox skips the filter.
      // Hard timeout so a slow/hung analysis can't lock the capture button
      // indefinitely. The Edge Function itself bounds its Roboflow/HF calls,
      // but this is the client-side backstop (network stalls, cold starts).
      final response = await _client.functions.invoke(
        'analyze-scan',
        body: {
          'scan_id': scanId,
          'image_path': imagePath,
          'region': region.wireName,
          if (sessionId != null) 'session_id': sessionId,
          if (faceBbox != null) 'face_bbox': faceBbox,
        },
      ).timeout(
        const Duration(seconds: 45),
        onTimeout: () => throw Exception(
            'Analysis timed out. Please check your connection and try again.'),
      );

      if (response.status != 200) {
        final body = response.data;
        String message = 'Analysis failed (status ${response.status}).';
        if (body is Map && body['error'] != null) {
          message = body['error'].toString();
        }
        throw Exception(message);
      }

      final data = response.data;
      if (data is! Map || data['scan'] is! Map) {
        throw Exception('Unexpected response shape from analyze-scan.');
      }
      final scanRow = (data['scan'] as Map).cast<String, dynamic>();

      // 3. Generate the signed URL up front so the detail screen can render
      //    the image without an extra round trip.
      final url = await _signedUrlFor(imagePath);
      final scan = Scan.fromRow(scanRow, imageUrl: url);

      // 4. Prepend to local list. (Server-side, the row's taken_at defaults
      //    to now(), so it's the newest scan and belongs at the top.)
      _scans = List.unmodifiable([scan, ..._scans]);
      return scan;
    } catch (e) {
      // If the function failed AFTER the upload succeeded, the storage
      // object is orphaned. Best-effort cleanup so we don't leak space.
      if (imageUploaded) {
        try {
          await _client.storage.from('scan-images').remove([imagePath]);
        } catch (cleanupErr) {
          debugPrint('ScanService.submitScan cleanup failed: $cleanupErr');
        }
      }
      rethrow;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  // ----- Update notes -----

  /// Replaces the `notes` column for [scanId] with [notes] (or NULL when
  /// [notes] is null or blank). Updates the in-memory copy and notifies
  /// listeners so the scan-detail screen reflects the change immediately.
  ///
  /// Returns the refreshed Scan. RLS confines the update to the caller's
  /// own rows; no need for an extra user_id check here.
  Future<Scan> updateScanNotes(String scanId, String? notes) async {
    final trimmed = notes?.trim();
    // Treat empty-string and whitespace-only as a clear → store NULL.
    final value = (trimmed == null || trimmed.isEmpty) ? null : trimmed;

    // Embed doctor_notes in the returning row so the refreshed Scan keeps
    // its dermatologist-note alongside the new patient note.
    final row = await _client
        .from('scans')
        .update({'notes': value})
        .eq('id', scanId)
        .select('*, doctor_notes(note)')
        .single();

    final existing = _scans.firstWhere(
      (s) => s.id == scanId,
      orElse: () => throw StateError(
        'Cannot update notes — scan $scanId is not in the local list.',
      ),
    );

    final refreshed = Scan.fromRow(
      (row).cast<String, dynamic>(),
      imageUrl: existing.imageUrl,
    );
    _scans = List.unmodifiable(
      _scans.map((s) => s.id == scanId ? refreshed : s),
    );
    notifyListeners();
    return refreshed;
  }

  // ----- Delete -----

  /// Removes the storage object and the row. No-op if [scanId] isn't in the
  /// local list (which means we wouldn't know the image_path anyway).
  Future<void> deleteScan(String scanId) async {
    Scan? target;
    for (final s in _scans) {
      if (s.id == scanId) {
        target = s;
        break;
      }
    }
    if (target == null) return;

    // Storage delete first. RLS confines us to our own folder.
    try {
      await _client.storage.from('scan-images').remove([target.imagePath]);
    } catch (e) {
      debugPrint('ScanService.deleteScan storage failed: $e');
    }

    // Row delete. RLS confines us to our own user_id, so we just match on id.
    await _client.from('scans').delete().eq('id', scanId);

    _scans = List.unmodifiable(_scans.where((s) => s.id != scanId));
    notifyListeners();
  }
}
