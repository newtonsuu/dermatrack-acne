import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:uuid/uuid.dart';

import '../models/prescription.dart';
import 'auth_service.dart';

/// Data layer for doctor-authored prescriptions.
///
/// Used by both sides — RLS (migration 0008) is the real gate:
///   • The doctor calls [loadForPatient]/[addPrescription]/[deletePrescription]
///     with a target patient id (writes succeed only for consenting patients).
///   • The patient calls [loadForPatient] with their own id to read theirs.
///
/// Prescriptions are cached per patient id so re-opening a patient (doctor)
/// or re-entering the screen (patient) is instant. Signed image URLs are
/// resolved on load for display.
class PrescriptionService extends ChangeNotifier {
  PrescriptionService._internal() {
    AuthService.instance.addListener(_onAuthChanged);
  }
  static final PrescriptionService instance = PrescriptionService._internal();

  static const _uuid = Uuid();
  static const String _bucket = 'prescription-images';
  static const int _signedUrlTtlSeconds = 60 * 60;

  supa.SupabaseClient get _client => supa.Supabase.instance.client;

  // Keyed by patient user_id.
  final Map<String, List<Prescription>> _byPatient = {};
  final Map<String, Object?> _error = {};
  final Set<String> _loading = {};

  List<Prescription> forPatient(String patientId) =>
      List.unmodifiable(_byPatient[patientId] ?? const []);
  bool hasLoadedFor(String patientId) => _byPatient.containsKey(patientId);
  bool isLoadingFor(String patientId) => _loading.contains(patientId);
  Object? errorFor(String patientId) => _error[patientId];

  void _onAuthChanged() {
    if (!AuthService.instance.isSignedIn) {
      if (_byPatient.isNotEmpty || _error.isNotEmpty) {
        _byPatient.clear();
        _error.clear();
        _loading.clear();
        notifyListeners();
      }
    }
  }

  /// Loads prescriptions for [patientId] (newest first), resolving signed
  /// image URLs. Cached; pass `force: true` to bypass.
  Future<void> loadForPatient(String patientId, {bool force = false}) async {
    if (_loading.contains(patientId)) return;
    if (!force && _byPatient.containsKey(patientId)) return;

    _loading.add(patientId);
    notifyListeners();
    try {
      final rows = await _client
          .from('prescriptions')
          .select()
          .eq('user_id', patientId)
          .order('created_at', ascending: false);

      final parsed = <Prescription>[];
      for (final row in rows as List) {
        try {
          parsed.add(
              Prescription.fromRow((row as Map).cast<String, dynamic>()));
        } catch (e) {
          debugPrint('PrescriptionService: skipping bad row: $e');
        }
      }

      // Resolve signed URLs for each prescription's images.
      final withUrls = <Prescription>[];
      for (final p in parsed) {
        final urls = <String>[];
        for (final path in p.imagePaths) {
          try {
            urls.add(await _client.storage
                .from(_bucket)
                .createSignedUrl(path, _signedUrlTtlSeconds));
          } catch (e) {
            debugPrint('PrescriptionService: sign $path failed: $e');
          }
        }
        withUrls.add(p.copyWith(imageUrls: urls));
      }

      _byPatient[patientId] = List.unmodifiable(withUrls);
      _error[patientId] = null;
    } catch (e) {
      debugPrint('PrescriptionService.loadForPatient($patientId) failed: $e');
      _error[patientId] = e;
    } finally {
      _loading.remove(patientId);
      notifyListeners();
    }
  }

  /// Doctor-only: creates a prescription for [patientId] with [body] and
  /// optional [images] (raw JPEG/PNG bytes). Uploads images to
  /// `prescription-images/{patientId}/{prescriptionId}/{i}.jpg`, inserts the
  /// row, then refreshes the cache. RLS rejects non-doctors / non-consenting.
  Future<void> addPrescription({
    required String patientId,
    required String body,
    List<Uint8List> images = const [],
  }) async {
    if (!AuthService.instance.isDoctor) {
      throw StateError('Only the doctor account can create prescriptions.');
    }
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Prescription body cannot be empty.');
    }

    final id = _uuid.v4();
    final paths = <String>[];
    try {
      for (var i = 0; i < images.length; i++) {
        final path = '$patientId/$id/$i.jpg';
        await _client.storage.from(_bucket).uploadBinary(
              path,
              images[i],
              fileOptions: const supa.FileOptions(
                contentType: 'image/jpeg',
                upsert: true,
              ),
            );
        paths.add(path);
      }

      await _client.from('prescriptions').insert({
        'id': id,
        'user_id': patientId,
        'body': trimmed,
        'image_paths': paths,
      });

      await loadForPatient(patientId, force: true);
    } catch (e) {
      // Best-effort cleanup of any uploaded images if the insert failed.
      if (paths.isNotEmpty) {
        try {
          await _client.storage.from(_bucket).remove(paths);
        } catch (_) {}
      }
      debugPrint('PrescriptionService.addPrescription failed: $e');
      rethrow;
    }
  }

  /// Doctor-only: deletes a prescription and its images.
  Future<void> deletePrescription({
    required String patientId,
    required Prescription prescription,
  }) async {
    if (!AuthService.instance.isDoctor) {
      throw StateError('Only the doctor account can delete prescriptions.');
    }
    try {
      if (prescription.imagePaths.isNotEmpty) {
        try {
          await _client.storage.from(_bucket).remove(prescription.imagePaths);
        } catch (e) {
          debugPrint('PrescriptionService.delete: image remove failed: $e');
        }
      }
      await _client.from('prescriptions').delete().eq('id', prescription.id);
      await loadForPatient(patientId, force: true);
    } catch (e) {
      debugPrint('PrescriptionService.deletePrescription failed: $e');
      rethrow;
    }
  }
}
