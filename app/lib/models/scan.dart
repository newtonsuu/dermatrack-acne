import 'package:flutter/material.dart';

/// Anatomical zone captured by a scan. Mirrors the CHECK constraint on
/// `public.scans.region` (see migration 0004_scan_regions.sql). The five
/// values are the basis of the daily guided capture (forehead → left
/// cheek → right cheek → chin → full face) that came out of the
/// dermatologist consult.
///
/// String values are the canonical wire format — they match the SQL
/// constraint exactly, so a region passes round-trip through the Edge
/// Function and the database without any translation layer in between.
enum ScanRegion {
  forehead('forehead', 'Forehead'),
  leftCheek('left_cheek', 'Left cheek'),
  rightCheek('right_cheek', 'Right cheek'),
  chin('chin', 'Chin'),
  fullFace('full_face', 'Full face');

  const ScanRegion(this.wireName, this.label);

  /// SQL string written to `public.scans.region`. Stable forever — don't
  /// rename without a migration.
  final String wireName;

  /// Human-readable label for the scan detail screen, the calendar
  /// day-sheet, and the guided-capture progress UI.
  final String label;

  /// Parses a wire-format string back to its enum. Falls back to
  /// [ScanRegion.fullFace] for unknown values so the UI degrades
  /// gracefully on a row written by a newer schema.
  static ScanRegion fromWire(String? wire) {
    if (wire == null) return ScanRegion.fullFace;
    for (final r in ScanRegion.values) {
      if (r.wireName == wire) return r;
    }
    return ScanRegion.fullFace;
  }
}

/// A single skin scan record.
///
/// Maps 1:1 to a row in `public.scans` plus a lazily-resolved signed URL for
/// display. `imagePath` is the canonical storage path (`user_id/scan_id.jpg`);
/// `imageUrl` is a short-lived signed URL ScanService generates so widgets
/// can pass it directly to `Image.network`.
///
/// Severity follows the Cook 0–8 acne grading scale, extended with -1 for
/// "Clear Skin" (from the Hugging Face skintelligent classifier). Higher =
/// more severe. `severityLabel` is what the analyze-scan Edge Function
/// derived at scan time and is the authoritative human-readable label —
/// don't recompute it client-side, just display it.
@immutable
class Scan {
  const Scan({
    required this.id,
    required this.takenAt,
    required this.imagePath,
    this.imageUrl,
    required this.cookGrade,
    required this.severityLabel,
    required this.inflammatoryCount,
    required this.nonInflammatoryCount,
    required this.postAcneCount,
    required this.lesions,
    this.notes,
    required this.createdAt,
    this.analysisDetails,
    this.doctorNote,
    this.region = ScanRegion.fullFace,
    this.sessionId,
  });

  final String id;
  final DateTime takenAt;

  /// Storage path inside the `scan-images` bucket. Used for deletes and
  /// signed-URL regeneration. Not directly displayable.
  final String imagePath;

  /// Signed URL pointing at the storage object. Pass to `Image.network`.
  /// Null while loading or if the URL couldn't be generated.
  final String? imageUrl;

  /// -1 = Clear, 0–8 = Cook-style severity.
  final int cookGrade;

  /// Human-readable label from the Edge Function (e.g. "Clear", "Mild",
  /// "Moderate", "Severe", "Very Severe").
  final String severityLabel;

  final int inflammatoryCount;
  final int nonInflammatoryCount;
  final int postAcneCount;

  /// Detected lesions with bounding boxes, ready to render as an overlay
  /// via `lesion_overlay.dart` (coming in the scan-detail screen).
  final List<Lesion> lesions;

  final String? notes;
  final DateTime createdAt;

  /// Per-model breakdown of how this scan's grade was derived. Parsed from
  /// the row's `source_metadata` JSONB. Null for scans inserted before the
  /// phase 2 schema fields were populated (so the UI can fall back to its
  /// pre-phase-2 layout gracefully).
  final AnalysisDetails? analysisDetails;

  /// Dermatologist's note for this scan, authored from the doctor-side view.
  /// Null when no note has been left yet. Read on both the patient and
  /// doctor sides via the `doctor_notes` PostgREST embed in their respective
  /// load methods. RLS (0003_doctor_notes.sql) gates who can write it.
  final String? doctorNote;

  /// Anatomical zone this scan captured. Defaults to [ScanRegion.fullFace]
  /// for back-compat — every scan written before 0004 was a full-face
  /// capture, so the schema DEFAULT and this Dart default agree.
  final ScanRegion region;

  /// Links this scan to the other four in the same guided-capture session,
  /// so the UI can render the five regions of one daily sitting as a
  /// coherent snapshot. Null on standalone single-region scans and on
  /// legacy rows. UUID string from `public.scans.session_id`.
  final String? sessionId;

  /// Color used in thumbnails / chips / calendar cells to communicate
  /// severity at a glance.
  Color get severityColor {
    if (cookGrade < 0) return const Color(0xFF4CAF50); // Clear → green
    if (cookGrade <= 1) return const Color(0xFF4CAF50); // green
    if (cookGrade <= 3) return const Color(0xFF8BC34A); // lime
    if (cookGrade <= 5) return const Color(0xFFFFC107); // amber
    if (cookGrade <= 7) return const Color(0xFFFF9800); // orange
    return const Color(0xFFF44336); // red
  }

  /// Parse a row coming from Supabase (`public.scans` SELECT) or from the
  /// analyze-scan Edge Function's `{scan: ...}` envelope.
  ///
  /// Forgiving about missing optional fields so we don't crash on
  /// half-populated rows (e.g., a scan inserted before classifier_model
  /// was wired in).
  factory Scan.fromRow(Map<String, dynamic> row, {String? imageUrl}) {
    final lesionsRaw = row['lesions'];
    final lesionList = lesionsRaw is List
        ? lesionsRaw
            .whereType<Map>()
            .map((m) => Lesion.fromJson(m.cast<String, dynamic>()))
            .toList(growable: false)
        : const <Lesion>[];

    // source_metadata is a JSONB column populated by analyze-scan. May be
    // absent on legacy rows; the UI handles `analysisDetails == null` by
    // hiding the per-model breakdown section.
    final smRaw = row['source_metadata'];
    final analysis = smRaw is Map
        ? AnalysisDetails.fromJson(smRaw.cast<String, dynamic>())
        : null;

    // Doctor note arrives via PostgREST embed when the caller selects
    // `*, doctor_notes(note)`. The shape can be:
    //   - a Map  → 1:1 embed (PostgREST sometimes emits this for PK FK)
    //   - a List → 1:many embed (one element when a note exists, empty when not)
    //   - null   → not selected at all (e.g., legacy callers)
    // Handle all three so the model stays forgiving.
    final dnRaw = row['doctor_notes'];
    String? doctorNoteText;
    if (dnRaw is Map) {
      doctorNoteText = (dnRaw['note'] as String?)?.trim();
    } else if (dnRaw is List && dnRaw.isNotEmpty) {
      final first = dnRaw.first;
      if (first is Map) {
        doctorNoteText = (first['note'] as String?)?.trim();
      }
    }
    if (doctorNoteText != null && doctorNoteText.isEmpty) {
      doctorNoteText = null;
    }

    return Scan(
      id: row['id'] as String,
      takenAt: DateTime.parse(row['taken_at'] as String).toLocal(),
      imagePath: row['image_path'] as String,
      imageUrl: imageUrl,
      cookGrade: (row['cook_grade'] as num?)?.toInt() ?? 0,
      severityLabel: (row['severity_label'] as String?) ?? 'Unknown',
      inflammatoryCount: (row['inflammatory_count'] as num?)?.toInt() ?? 0,
      nonInflammatoryCount:
          (row['non_inflammatory_count'] as num?)?.toInt() ?? 0,
      postAcneCount: (row['post_acne_count'] as num?)?.toInt() ?? 0,
      lesions: lesionList,
      notes: row['notes'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      analysisDetails: analysis,
      doctorNote: doctorNoteText,
      // Region defaults to full_face for any pre-0004 row that lacks the
      // column (theoretically impossible since the migration backfills via
      // DEFAULT, but defensive parsing keeps the model forgiving).
      region: ScanRegion.fromWire(row['region'] as String?),
      sessionId: row['session_id'] as String?,
    );
  }

  /// Returns a copy of this scan with [imageUrl] replaced, and optionally
  /// [doctorNote] replaced.
  ///
  /// [setDoctorNote] is a sentinel flag: when `true`, the [doctorNote]
  /// argument is taken literally (including `null`, which represents
  /// "doctor cleared their note"). When `false` (the default), [doctorNote]
  /// is ignored and the existing value is preserved. Dart copyWith methods
  /// can't otherwise distinguish "omit" from "set to null" with a single
  /// nullable parameter.
  Scan copyWith({
    String? imageUrl,
    String? doctorNote,
    bool setDoctorNote = false,
  }) =>
      Scan(
        id: id,
        takenAt: takenAt,
        imagePath: imagePath,
        imageUrl: imageUrl ?? this.imageUrl,
        cookGrade: cookGrade,
        severityLabel: severityLabel,
        inflammatoryCount: inflammatoryCount,
        nonInflammatoryCount: nonInflammatoryCount,
        postAcneCount: postAcneCount,
        lesions: lesions,
        notes: notes,
        createdAt: createdAt,
        analysisDetails: analysisDetails,
        doctorNote: setDoctorNote ? doctorNote : this.doctorNote,
        region: region,
        sessionId: sessionId,
      );
}

/// Provenance fields recorded by the analyze-scan Edge Function so the UI
/// can show *how* a scan's final grade was reached. Mirrors the shape of
/// the JSONB stored in `public.scans.source_metadata`.
///
/// The classifier_* fields are nullable because the HF Space call is a
/// soft-fail in the Edge Function — if HF was down at scan time, the
/// detection-only grade still ships and these fields stay null.
@immutable
class AnalysisDetails {
  const AnalysisDetails({
    required this.detectionModel,
    required this.detectionCookGrade,
    this.detectionLatencyMs,
    required this.confidenceThreshold,
    this.classifierModel,
    this.classifierCookGrade,
    this.classifierTopLabel,
    this.classifierTopConfidence,
    this.classifierLatencyMs,
    required this.combinerRationale,
  });

  /// e.g. "acne-detection-zukbx/4"
  final String detectionModel;
  final int detectionCookGrade;
  final int? detectionLatencyMs;

  /// The confidence threshold applied to the detection model on this scan,
  /// captured at scan time so historical scans stay interpretable even if
  /// we tune the threshold later.
  final double confidenceThreshold;

  /// e.g. "imfarzanansari/skintelligent-acne". Null = HF call failed.
  final String? classifierModel;
  final int? classifierCookGrade;

  /// e.g. "level -1", "level 3". Raw label as emitted by the classifier.
  final String? classifierTopLabel;

  /// 0.0–1.0 — confidence of the top label.
  final double? classifierTopConfidence;
  final int? classifierLatencyMs;

  /// One of: "agreement", "minor_disagreement_kept", "hf_override",
  /// "roboflow_only". Drives the user-facing "Final grade" explanation.
  final String combinerRationale;

  /// Convenience — was a classifier reading available on this scan?
  bool get hasClassifier => classifierModel != null;

  factory AnalysisDetails.fromJson(Map<String, dynamic> json) {
    return AnalysisDetails(
      detectionModel: (json['detection_model'] as String?) ?? 'unknown',
      detectionCookGrade: (json['detection_cook_grade'] as num?)?.toInt() ?? 0,
      detectionLatencyMs: (json['detection_latency_ms'] as num?)?.toInt(),
      confidenceThreshold:
          (json['confidence_threshold'] as num?)?.toDouble() ?? 0,
      classifierModel: json['classifier_model'] as String?,
      classifierCookGrade: (json['classifier_cook_grade'] as num?)?.toInt(),
      classifierTopLabel: json['classifier_top_label'] as String?,
      classifierTopConfidence:
          (json['classifier_top_confidence'] as num?)?.toDouble(),
      classifierLatencyMs: (json['classifier_latency_ms'] as num?)?.toInt(),
      combinerRationale:
          (json['combiner_rationale'] as String?) ?? 'roboflow_only',
    );
  }
}

/// One detected lesion from the detection model (Roboflow). Stored as JSONB
/// in `public.scans.lesions`; parsed back out by `Scan.fromRow`.
@immutable
class Lesion {
  const Lesion({
    required this.className,
    required this.bucket,
    required this.confidence,
    required this.bbox,
    required this.imageSize,
  });

  /// Raw class name from the detection model (e.g. "papules", "comedone").
  final String className;

  /// Coarse bucket the Edge Function assigned: "inflammatory",
  /// "non_inflammatory", "post_acne", or "unknown".
  final String bucket;

  final double confidence;

  /// Bounding box in absolute pixel coordinates, **top-left** origin.
  /// (The Edge Function converts Roboflow's center coords for us.)
  final BBox bbox;

  /// Pixel dimensions of the image the bbox was drawn on. Required for
  /// scaling when rendering the overlay on a different display size.
  final ImageSize imageSize;

  factory Lesion.fromJson(Map<String, dynamic> json) {
    final bboxRaw = (json['bbox'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final sizeRaw = (json['image_size'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return Lesion(
      className: (json['class'] as String?) ?? 'unknown',
      bucket: (json['bucket'] as String?) ?? 'unknown',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      bbox: BBox.fromJson(bboxRaw),
      imageSize: ImageSize.fromJson(sizeRaw),
    );
  }

  /// Color used by the overlay painter to communicate the bucket at a glance.
  Color get bucketColor {
    switch (bucket) {
      case 'inflammatory':
        return const Color(0xFFF44336); // red
      case 'non_inflammatory':
        return const Color(0xFFFFC107); // amber
      case 'post_acne':
        return const Color(0xFF9E9E9E); // grey
      default:
        return const Color(0xFF607D8B); // blue-grey (unknown)
    }
  }
}

@immutable
class BBox {
  const BBox({required this.x, required this.y, required this.w, required this.h});

  /// Top-left x in pixels.
  final double x;

  /// Top-left y in pixels.
  final double y;
  final double w;
  final double h;

  factory BBox.fromJson(Map<String, dynamic> json) => BBox(
        x: (json['x'] as num?)?.toDouble() ?? 0,
        y: (json['y'] as num?)?.toDouble() ?? 0,
        w: (json['w'] as num?)?.toDouble() ?? 0,
        h: (json['h'] as num?)?.toDouble() ?? 0,
      );
}

@immutable
class ImageSize {
  const ImageSize({required this.w, required this.h});
  final double w;
  final double h;

  factory ImageSize.fromJson(Map<String, dynamic> json) => ImageSize(
        w: (json['w'] as num?)?.toDouble() ?? 0,
        h: (json['h'] as num?)?.toDouble() ?? 0,
      );
}
