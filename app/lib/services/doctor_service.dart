import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import '../models/patient_history.dart';
import '../models/scan.dart';
import 'auth_service.dart';

/// Doctor-side data layer for the demo doctor account.
///
/// Owns two pieces of state:
///   1. The list of patients who have toggled `shared_with_doctor = true`.
///   2. A per-patient scan list, fetched lazily when the doctor taps into a
///      patient detail screen.
///
/// Mirrors the shape of ScanService for the doctor's read-only view of a
/// patient — but where ScanService loads the *signed-in user's* scans,
/// DoctorService takes a target user_id and queries scans for that user. RLS
/// (0002_doctor_demo.sql) is what actually gates access: the doctor account
/// can only SELECT scans for users who have opted in.
///
/// Singleton because the patient list is shared across the patient-list and
/// patient-detail screens, and we want one auth listener for the whole
/// doctor session.
class DoctorService extends ChangeNotifier {
  DoctorService._internal() {
    AuthService.instance.addListener(_onAuthChanged);
    if (AuthService.instance.isSignedIn && AuthService.instance.isDoctor) {
      loadPatients();
    }
  }
  static final DoctorService instance = DoctorService._internal();

  supa.SupabaseClient get _client => supa.Supabase.instance.client;

  /// Signed URLs valid for 1 hour. Matches ScanService — long enough for
  /// a typical doctor browsing session, short enough that a leaked URL
  /// doesn't expose patient images indefinitely.
  static const int _signedUrlTtlSeconds = 60 * 60;

  // ===== Patient list =====

  List<DoctorPatient> _patients = const [];
  bool _isLoadingPatients = false;
  Object? _patientsError;

  /// All patients who have opted in to sharing. Sorted with most recent
  /// scan-haver first (so the active patients bubble up).
  List<DoctorPatient> get patients => List.unmodifiable(_patients);
  bool get isLoadingPatients => _isLoadingPatients;
  Object? get patientsError => _patientsError;

  // ===== Per-patient scans =====
  // Keyed by patient user_id so re-opening a patient is instant if their
  // scans are already cached. A simple `loadPatientScans` re-fetch will
  // refresh the cache.
  final Map<String, List<Scan>> _scansByPatient = {};
  final Map<String, Object?> _scansError = {};
  final Set<String> _scansLoading = {};

  List<Scan> scansFor(String patientId) =>
      List.unmodifiable(_scansByPatient[patientId] ?? const []);
  bool isLoadingScansFor(String patientId) => _scansLoading.contains(patientId);
  Object? scansErrorFor(String patientId) => _scansError[patientId];

  // ===== Per-patient medical history =====
  // Sentinel: a key present in [_historyByPatient] with a null value means
  // "we fetched and there was no row" (patient hasn't filled their history
  // yet). Absent key means "we haven't fetched yet". This lets the UI
  // distinguish loading from empty.
  final Map<String, PatientHistory?> _historyByPatient = {};
  final Map<String, Object?> _historyError = {};
  final Set<String> _historyLoading = {};

  bool hasHistoryFor(String patientId) =>
      _historyByPatient.containsKey(patientId);
  PatientHistory? historyFor(String patientId) =>
      _historyByPatient[patientId];
  bool isLoadingHistoryFor(String patientId) =>
      _historyLoading.contains(patientId);
  Object? historyErrorFor(String patientId) => _historyError[patientId];

  // ===== Auth wiring =====

  void _onAuthChanged() {
    final auth = AuthService.instance;
    if (auth.isSignedIn && auth.isDoctor) {
      loadPatients();
    } else {
      // Doctor signed out (or a non-doctor signed in via the same shared
      // singleton). Drop all cached data — we don't want patient scans
      // (or their histories) lingering in memory after the doctor session
      // ends.
      final hadAny = _patients.isNotEmpty ||
          _scansByPatient.isNotEmpty ||
          _historyByPatient.isNotEmpty ||
          _patientsError != null;
      _patients = const [];
      _scansByPatient.clear();
      _scansError.clear();
      _scansLoading.clear();
      _historyByPatient.clear();
      _historyError.clear();
      _historyLoading.clear();
      _patientsError = null;
      if (hadAny) notifyListeners();
    }
  }

  // ===== Loads =====

  /// Fetches the list of consenting patients plus, for each, their most
  /// recent scan summary (date + grade) so the list tile can show "last
  /// scan 3 days ago, currently Mild" without a second round-trip.
  ///
  /// Idempotent — concurrent calls coalesce via [_isLoadingPatients].
  Future<void> loadPatients() async {
    if (_isLoadingPatients) return;
    if (!AuthService.instance.isDoctor) return;

    _isLoadingPatients = true;
    notifyListeners();

    try {
      // 1) Profiles that have opted in. Username/display_name are needed for
      //    the patient list tile; the rest (avatars, etc.) are deferred.
      final profileRows = await _client
          .from('profiles')
          .select('id, username, display_name, shared_with_doctor')
          .eq('shared_with_doctor', true);

      final profiles = <DoctorPatient>[];
      for (final row in profileRows as List) {
        final map = (row as Map).cast<String, dynamic>();
        final id = map['id'] as String?;
        if (id == null) continue;
        profiles.add(DoctorPatient(
          id: id,
          username: (map['username'] as String?) ?? '',
          displayName: (map['display_name'] as String?)?.trim() ?? '',
        ));
      }

      // 2) Per patient, fetch their most recent scan (single row) so the
      //    list tile can show last-scan summary. Done sequentially because
      //    we typically have a handful of patients for the demo. Easy to
      //    parallelise with Future.wait if this ever grows.
      final withSummary = <DoctorPatient>[];
      for (final p in profiles) {
        DoctorScanSummary? summary;
        try {
          final scanRow = await _client
              .from('scans')
              .select(
                  'id, taken_at, cook_grade, severity_label, inflammatory_count, non_inflammatory_count, post_acne_count')
              .eq('user_id', p.id)
              .order('taken_at', ascending: false)
              .limit(1)
              .maybeSingle();
          if (scanRow != null) {
            summary = DoctorScanSummary(
              takenAt: DateTime.parse(scanRow['taken_at'] as String).toLocal(),
              cookGrade: (scanRow['cook_grade'] as num?)?.toInt() ?? 0,
              severityLabel:
                  (scanRow['severity_label'] as String?) ?? 'Unknown',
            );
          }
        } catch (e) {
          // Don't fail the whole patient list because one patient's
          // last-scan fetch hiccuped — surface the patient with no summary.
          debugPrint(
              'DoctorService.loadPatients: summary for ${p.id} failed: $e');
        }
        withSummary.add(p.copyWith(latestScan: summary));
      }

      // Sort: patients with a recent scan first, newest scan at the top.
      // Patients with no scans go to the bottom alphabetically so they're
      // still visible but de-emphasized.
      withSummary.sort((a, b) {
        final aDate = a.latestScan?.takenAt;
        final bDate = b.latestScan?.takenAt;
        if (aDate != null && bDate != null) return bDate.compareTo(aDate);
        if (aDate != null) return -1;
        if (bDate != null) return 1;
        return a.displayLabel.toLowerCase().compareTo(b.displayLabel.toLowerCase());
      });

      _patients = List.unmodifiable(withSummary);
      _patientsError = null;
    } catch (e) {
      debugPrint('DoctorService.loadPatients failed: $e');
      _patientsError = e;
    } finally {
      _isLoadingPatients = false;
      notifyListeners();
    }
  }

  /// Loads the full scan history for [patientId], resolves signed image URLs,
  /// and caches the result so re-opening the patient is instant.
  Future<void> loadPatientScans(String patientId) async {
    if (!AuthService.instance.isDoctor) return;
    if (_scansLoading.contains(patientId)) return;

    _scansLoading.add(patientId);
    notifyListeners();

    try {
      // Embed doctor_notes so each Scan carries its existing note in one
      // round-trip — the doctor's view pre-fills the edit dialog from this.
      // RLS lets the doctor read notes for consenting patients only.
      final rows = await _client
          .from('scans')
          .select('*, doctor_notes(note)')
          .eq('user_id', patientId)
          .order('taken_at', ascending: false);

      final parsed = <Scan>[];
      for (final row in rows as List) {
        try {
          parsed.add(Scan.fromRow((row as Map).cast<String, dynamic>()));
        } catch (e) {
          debugPrint(
              'DoctorService.loadPatientScans: skipping malformed row: $e');
        }
      }

      // Resolve signed URLs for each scan image. RLS allows the doctor to
      // read scan-images for consenting patients (see 0002_doctor_demo.sql).
      final withUrls = <Scan>[];
      for (final scan in parsed) {
        String? url;
        try {
          url = await _client.storage
              .from('scan-images')
              .createSignedUrl(scan.imagePath, _signedUrlTtlSeconds);
        } catch (e) {
          debugPrint(
              'DoctorService.loadPatientScans: signed URL for ${scan.imagePath} failed: $e');
        }
        withUrls.add(scan.copyWith(imageUrl: url));
      }

      _scansByPatient[patientId] = List.unmodifiable(withUrls);
      _scansError[patientId] = null;
    } catch (e) {
      debugPrint('DoctorService.loadPatientScans($patientId) failed: $e');
      _scansError[patientId] = e;
    } finally {
      _scansLoading.remove(patientId);
      notifyListeners();
    }
  }

  // ===== Patient medical history =====

  /// Fetches [patientId]'s medical history row from public.patient_histories.
  /// RLS (0005_patient_histories.sql) restricts the doctor to consenting
  /// patients only — if the patient has toggled sharing off, this returns
  /// no row.
  ///
  /// On success, the result is cached in [_historyByPatient] so re-opening
  /// the patient is instant. Pass `force: true` to bypass the cache.
  Future<void> loadPatientHistory(
    String patientId, {
    bool force = false,
  }) async {
    if (!AuthService.instance.isDoctor) return;
    if (_historyLoading.contains(patientId)) return;
    if (!force && _historyByPatient.containsKey(patientId)) return;

    _historyLoading.add(patientId);
    notifyListeners();

    try {
      final row = await _client
          .from('patient_histories')
          .select()
          .eq('user_id', patientId)
          .maybeSingle();

      if (row == null) {
        _historyByPatient[patientId] = null; // sentinel: fetched, no row
      } else {
        _historyByPatient[patientId] =
            PatientHistory.fromRow(row.cast<String, dynamic>());
      }
      _historyError[patientId] = null;
    } catch (e) {
      debugPrint('DoctorService.loadPatientHistory($patientId) failed: $e');
      _historyError[patientId] = e;
    } finally {
      _historyLoading.remove(patientId);
      notifyListeners();
    }
  }

  // ===== Doctor note write =====

  /// Sets (or clears) the dermatologist's note for [scanId]. Pass [note] as
  /// a non-empty string to upsert, or `null` / blank to delete.
  ///
  /// [patientId] is required so the local cache can be updated in place —
  /// notes live on Scans, which are keyed by patient in [_scansByPatient].
  ///
  /// Optimistic: the local cache is updated immediately so the UI feels
  /// instant. On failure we roll back and rethrow so the caller's snackbar
  /// can surface the error.
  ///
  /// RLS is the actual gate (see 0003_doctor_notes.sql): only the demo
  /// doctor account can write, and only for consenting patients. This
  /// method is a thin convenience wrapper.
  Future<void> setDoctorNote({
    required String patientId,
    required String scanId,
    required String? note,
  }) async {
    if (!AuthService.instance.isDoctor) {
      throw StateError('Only the doctor account can set doctor notes.');
    }

    final trimmed = note?.trim();
    final clearing = trimmed == null || trimmed.isEmpty;

    // Snapshot previous state so we can roll back on failure.
    final patientScans = _scansByPatient[patientId];
    Scan? previousScan;
    int? scanIndex;
    if (patientScans != null) {
      for (var i = 0; i < patientScans.length; i++) {
        if (patientScans[i].id == scanId) {
          previousScan = patientScans[i];
          scanIndex = i;
          break;
        }
      }
    }

    // Optimistic local update.
    if (previousScan != null && scanIndex != null && patientScans != null) {
      final updated = previousScan.copyWith(
        setDoctorNote: true,
        doctorNote: clearing ? null : trimmed,
      );
      final mutable = List<Scan>.from(patientScans);
      mutable[scanIndex] = updated;
      _scansByPatient[patientId] = List.unmodifiable(mutable);
      notifyListeners();
    }

    try {
      if (clearing) {
        await _client
            .from('doctor_notes')
            .delete()
            .eq('scan_id', scanId);
      } else {
        // Upsert on the PK (scan_id) so the doctor can edit an existing note
        // without first checking whether one exists. `updated_at` is set by
        // the BEFORE UPDATE trigger; we pass note + scan_id explicitly.
        await _client.from('doctor_notes').upsert({
          'scan_id': scanId,
          'note': trimmed,
        }, onConflict: 'scan_id');
      }
    } catch (e) {
      // Roll back to the prior cached value so the UI doesn't lie about the
      // server state.
      if (previousScan != null && scanIndex != null && patientScans != null) {
        final mutable = List<Scan>.from(_scansByPatient[patientId] ?? const []);
        if (scanIndex < mutable.length) {
          mutable[scanIndex] = previousScan;
          _scansByPatient[patientId] = List.unmodifiable(mutable);
          notifyListeners();
        }
      }
      debugPrint('DoctorService.setDoctorNote failed: $e');
      rethrow;
    }
  }
}

/// Minimal projection of `public.profiles` for the doctor's patient list,
/// plus an optional summary of the patient's most recent scan so list tiles
/// can render an at-a-glance status without a second fetch.
@immutable
class DoctorPatient {
  const DoctorPatient({
    required this.id,
    required this.username,
    required this.displayName,
    this.latestScan,
  });

  final String id;
  final String username;
  final String displayName;
  final DoctorScanSummary? latestScan;

  /// Best display string available — prefer display name, fall back to
  /// the username, then to a generic placeholder.
  String get displayLabel {
    if (displayName.isNotEmpty) return displayName;
    if (username.isNotEmpty) return username;
    return 'Patient';
  }

  /// Initials used for the patient avatar circle in the list.
  String get initials {
    final source = displayLabel;
    final parts = source.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  DoctorPatient copyWith({DoctorScanSummary? latestScan}) => DoctorPatient(
        id: id,
        username: username,
        displayName: displayName,
        latestScan: latestScan ?? this.latestScan,
      );
}

@immutable
class DoctorScanSummary {
  const DoctorScanSummary({
    required this.takenAt,
    required this.cookGrade,
    required this.severityLabel,
  });

  final DateTime takenAt;
  final int cookGrade;
  final String severityLabel;
}
