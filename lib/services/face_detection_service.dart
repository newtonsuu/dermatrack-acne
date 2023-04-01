import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';

/// Reasons a preflight face check might fail. The camera screen turns each
/// into a user-friendly message.
enum FaceCheckFailure {
  noFace,
  multipleFaces,
  faceTooSmall,
  faceTooTilted,
}

/// Outcome of running [FaceDetectionService.check] on a captured image.
/// Three terminal states:
///   * passed → a single, well-framed face was detected.
///   * failed → some guard fired; `failure` and `userMessage` say which.
///   * skipped → ML Kit isn't available on this platform (Flutter Web).
///     Treated as a pass so the survey-demo flow keeps working — flagged
///     as a phase-1 limitation in methodology.
class FaceCheckResult {
  const FaceCheckResult._({
    required this.passed,
    required this.skipped,
    this.failure,
    this.userMessage,
    this.face,
    this.imageWidth,
    this.imageHeight,
  });

  factory FaceCheckResult.ok({
    required Face face,
    required int imageWidth,
    required int imageHeight,
  }) =>
      FaceCheckResult._(
        passed: true,
        skipped: false,
        face: face,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );

  factory FaceCheckResult.failed(FaceCheckFailure reason, String message) =>
      FaceCheckResult._(
        passed: false,
        skipped: false,
        failure: reason,
        userMessage: message,
      );

  factory FaceCheckResult.skipped() => const FaceCheckResult._(
        passed: true,
        skipped: true,
      );

  final bool passed;
  final bool skipped;
  final FaceCheckFailure? failure;
  final String? userMessage;

  /// Raw face object — present when [passed] is true and [skipped] is
  /// false. Phase B will partition lesion bboxes into anatomical regions
  /// using `face.contours` (face oval + per-feature outlines).
  final Face? face;

  /// Decoded image dimensions captured alongside the face object. Phase B
  /// needs these so it can scale ML Kit's image-pixel landmark coordinates
  /// against Roboflow's image-pixel bbox coordinates.
  final int? imageWidth;
  final int? imageHeight;
}

/// On-device face detection used as a preflight gate before the camera
/// screen submits a scan. Wraps Google ML Kit's `FaceDetector` with a
/// typed pass/fail API. Singleton so the detector model loads once per
/// app session (model load is expensive; per-call detection is cheap).
class FaceDetectionService {
  static final FaceDetectionService instance = FaceDetectionService._();
  FaceDetectionService._();

  FaceDetector? _detector;

  // ----- Tunable thresholds -----
  //
  // Starting values informed by AcneCheck's methodology + the 25–35 cm
  // distance recommendation. Worth revisiting after the dermatologist
  // meeting on Monday — she may want stricter framing or different angles.

  /// Minimum face bbox area ÷ image area. Below this, the face is too far
  /// from the camera. 8% is conservative — a typical selfie at 25–35 cm
  /// produces 15-25% face coverage.
  static const double _minBoundingBoxRatio = 0.08;

  /// Maximum absolute head yaw (`headEulerAngleY`) in degrees. Above this,
  /// the face is turned too far sideways for reliable lesion detection on
  /// the visible cheek.
  static const double _maxHeadYawDegrees = 20.0;

  /// Maximum absolute head roll (`headEulerAngleZ`) in degrees. Above
  /// this, the face is tilted enough that day-to-day comparisons become
  /// apples-to-oranges.
  static const double _maxHeadRollDegrees = 20.0;

  FaceDetector _getDetector() {
    return _detector ??= FaceDetector(
      options: FaceDetectorOptions(
        // Per-feature contours (face oval, eyes, brows, lips, nose, cheeks)
        // — needed for phase B region partitioning. ~30 KB extra model
        // weight; worth it.
        enableContours: true,
        // The 8-10 well-known landmark points (eye centers, ear tips,
        // nose, mouth corners). Phase B uses them as anchors when contours
        // are missing on partial-profile captures.
        enableLandmarks: true,
        // We don't care about smiling / eyes-open right now.
        enableClassification: false,
        // No frame-to-frame tracking — each call is independent.
        enableTracking: false,
        // Accurate mode is ~200ms vs ~80ms on a Pixel 7, but materially
        // better on edge cases. Worth it for a one-shot preflight.
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
  }

  /// Runs face detection on a freshly-captured image. Returns a typed
  /// pass/fail result. On Flutter Web (ML Kit unsupported), returns
  /// [FaceCheckResult.skipped] so the camera flow keeps working.
  Future<FaceCheckResult> check(Uint8List imageBytes) async {
    if (kIsWeb) {
      return FaceCheckResult.skipped();
    }

    // Decode image dimensions for the bbox-area-ratio check. ui.Image must
    // be disposed to avoid leaking the GPU texture.
    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    final imageWidth = frame.image.width;
    final imageHeight = frame.image.height;
    frame.image.dispose();

    // ML Kit's InputImage doesn't accept arbitrary JPEG bytes directly —
    // raw NV21/YUV/BGRA only via `fromBytes`. Workaround: write the JPEG
    // to a temp file and use `fromFilePath`. The detector reads it once;
    // we clean up in `finally`.
    final tempDir = await getTemporaryDirectory();
    final tempFile = File(
      '${tempDir.path}/face_check_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await tempFile.writeAsBytes(imageBytes);

    try {
      final detector = _getDetector();
      final inputImage = InputImage.fromFilePath(tempFile.path);
      final faces = await detector.processImage(inputImage);

      if (faces.isEmpty) {
        return FaceCheckResult.failed(
          FaceCheckFailure.noFace,
          "We couldn't find a face in this photo. "
          'Try better lighting or framing your whole face in the shot.',
        );
      }
      if (faces.length > 1) {
        return FaceCheckResult.failed(
          FaceCheckFailure.multipleFaces,
          'Multiple faces detected. Make sure only your face is in frame.',
        );
      }

      final face = faces.first;

      // Bounding box ratio = face area / image area.
      final bboxArea = face.boundingBox.width * face.boundingBox.height;
      final imageArea = imageWidth * imageHeight;
      final ratio = bboxArea / imageArea;
      if (ratio < _minBoundingBoxRatio) {
        return FaceCheckResult.failed(
          FaceCheckFailure.faceTooSmall,
          'Move closer — your face looks small in the frame. '
          'Aim for arm\'s length (about 25–35 cm).',
        );
      }

      // Head pose: yaw (Y) and roll (Z). Pitch (X) we let through because
      // looking slightly up/down doesn't change visible-cheek geometry.
      final yaw = face.headEulerAngleY ?? 0;
      final roll = face.headEulerAngleZ ?? 0;
      if (yaw.abs() > _maxHeadYawDegrees ||
          roll.abs() > _maxHeadRollDegrees) {
        return FaceCheckResult.failed(
          FaceCheckFailure.faceTooTilted,
          'Face the camera directly — your head looks tilted. '
          'Keep your phone parallel to your face.',
        );
      }

      return FaceCheckResult.ok(
        face: face,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );
    } finally {
      // Best-effort cleanup. Failure ignored — temp dir auto-cleans on
      // some platforms anyway.
      try {
        await tempFile.delete();
      } catch (_) {/* ignore */}
    }
  }

  /// Lightweight face detection for live camera stream frames.
  ///
  /// Unlike [check] (which does the heavy JPEG-decode preflight before
  /// submission), this method takes an already-constructed [InputImage]
  /// from the camera plugin's image stream and returns the *first* face
  /// (or null if none/multiple detected). No bbox-area / pose validation —
  /// the per-region [RegionAlignmentEvaluator] handles those checks
  /// because they vary per region.
  ///
  /// Returns null when:
  ///   - ML Kit isn't available (Web / desktop) — falls through silently.
  ///   - The detector found zero or two-plus faces.
  ///   - The InputImage was malformed (rare; usually a format mismatch
  ///     between camera + ML Kit on first stream frame).
  Future<Face?> detectFromInputImage(InputImage inputImage) async {
    if (kIsWeb) return null;
    try {
      final detector = _getDetector();
      final faces = await detector.processImage(inputImage);
      if (faces.length == 1) return faces.first;
      return null;
    } catch (e) {
      debugPrint('FaceDetectionService.detectFromInputImage failed: $e');
      return null;
    }
  }

  /// Releases the detector model. App currently never calls this — the
  /// detector lives for the process lifetime, which is fine for an
  /// interactive long-running app. Wired for completeness if we ever
  /// respond to low-memory pressure.
  Future<void> close() async {
    await _detector?.close();
    _detector = null;
  }
}
