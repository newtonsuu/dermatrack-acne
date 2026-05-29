import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../models/scan.dart';

/// Result of evaluating a live ML Kit face against a region's alignment
/// criteria. Three outcomes:
///   - aligned=true  → capture button should be enabled.
///   - aligned=false → button stays disabled, [hint] tells the patient what
///     to adjust ("move closer", "shift left", etc.).
///   - noFace=true   → ML Kit returned no face. Separate from "face present
///     but misaligned" so the overlay can say "no face detected" rather
///     than a region-specific adjustment hint.
@immutable
class RegionAlignmentResult {
  const RegionAlignmentResult({
    required this.aligned,
    required this.noFace,
    required this.score,
    required this.hint,
  });

  /// True when every criterion for the current region is satisfied. Hard
  /// gate for the capture button.
  final bool aligned;

  /// True when ML Kit returned zero (or more than one) face. UI treats this
  /// as the "show me a face" state — distinct from the "almost there"
  /// adjustment state.
  final bool noFace;

  /// Approximate confidence the patient is aligned, 0.0–1.0. Used to
  /// animate the overlay color (red → amber → green) before reaching the
  /// hard alignment threshold. Not the same as aligned: a score of 0.9
  /// might still be marked aligned=false if any *hard* criterion fails.
  final double score;

  /// Human-readable adjustment to show under the region template.
  final String hint;
}

/// Evaluates a freshly-detected ML Kit face against per-region geometric
/// criteria for the guided 5-step capture session.
///
/// Capture model is **camera position-driven** (the patient moves the
/// phone, not their head — confirmed with AJ and the dermatologist on
/// 2026-05-25):
///   • forehead    → phone held slightly below eye level pointing up at the
///                   forehead. Eyes appear in the lower portion of the
///                   frame, forehead fills the top.
///   • left_cheek  → phone positioned to the patient's left side. Face
///                   appears in profile or three-quarter, cheek on the
///                   right of the frame.
///   • right_cheek → mirror of left_cheek.
///   • chin        → phone held above pointing down at the chin. Mouth
///                   appears in the upper portion of the frame, chin and
///                   jawline fill the bottom.
///   • full_face   → phone held at arm's length, face centered, both eyes
///                   visible, near-zero head pose deltas.
///
/// All coordinates use the same pixel space ML Kit reports — top-left
/// origin, x increases right, y increases down — relative to the rotated
/// preview frame. The caller is responsible for passing the *displayed*
/// frame dimensions (width × height after rotation), not the raw sensor.
class RegionAlignmentEvaluator {
  RegionAlignmentEvaluator._();

  /// Singleton. The evaluator holds no state; the singleton just keeps the
  /// caller from constructing a new instance per frame.
  static final RegionAlignmentEvaluator instance =
      RegionAlignmentEvaluator._();

  // ----- Tunables -----
  //
  // Conservative starting values informed by ML Kit's typical bbox tightness
  // and the camera-position-driven capture model. Treat each as "what we'd
  // tune after a real-device session" — they're educated guesses, not
  // empirically validated yet.

  /// Minimum bbox area / frame area for full-face capture. Below this,
  /// the face is too small (phone too far away).
  static const double _fullFaceMinAreaRatio = 0.18;

  /// Maximum bbox area / frame area for full-face capture. Above this, the
  /// face crops out of frame.
  static const double _fullFaceMaxAreaRatio = 0.55;

  /// Allowable horizontal offset of face center from frame center, as a
  /// fraction of frame width. 0.15 = the face can be off-center by 15% of
  /// the frame and still count as full-face-aligned.
  static const double _fullFaceMaxHorizontalOffsetRatio = 0.15;

  /// Same idea for vertical centering on full-face.
  static const double _fullFaceMaxVerticalOffsetRatio = 0.15;

  /// Maximum |yaw| (headEulerAngleY) for full-face. Above this, the face is
  /// turned too sideways for "looks straight at the camera" framing.
  static const double _fullFaceMaxYawDegrees = 15.0;

  /// Maximum |roll| (headEulerAngleZ) for full-face. Same idea.
  static const double _fullFaceMaxRollDegrees = 15.0;

  /// For forehead capture, the *top* of the face bbox should be within
  /// this fraction of the frame top edge — face is being shot from below.
  /// Loosened from 0.10 → 0.30 after the 2026-05-25 real-device test:
  /// at 0.10 the hairline (which ML Kit includes in the bbox) sat outside
  /// the band and good captures were rejected.
  static const double _foreheadMaxBboxTopRatio = 0.30;

  /// For forehead capture, eyes should be in the lower portion of the
  /// frame (because the phone is angled up, the eyes are below the
  /// forehead in the camera's view). Loosened from 0.45 → 0.30 — at 0.45
  /// even correctly-framed forehead shots failed because eye landmarks
  /// in ML Kit's bbox tend to sit just above the bbox vertical center.
  static const double _foreheadMinEyeYRatio = 0.30;

  /// For cheek capture, the face center should be in the half of the
  /// frame that matches the cheek being captured. left_cheek = face
  /// appears on the right of the frame (camera is to patient's left,
  /// looking at the left cheek which fills the right of frame).
  /// Conversely for right_cheek. Lenient threshold — only enforced when
  /// ML Kit successfully detects a face (which is rare in profile).
  static const double _cheekFaceCenterXThreshold = 0.45;

  /// For chin capture, mouth should be in the upper portion of the frame
  /// (phone is angled down, so mouth sits above the chin in the image).
  /// Loosened from 0.45 → 0.60 to handle modest phone angles.
  static const double _chinMaxMouthYRatio = 0.60;

  /// For chin capture, the bbox bottom should be near the bottom of frame
  /// (chin fills out the lower edge). Loosened from 0.85 → 0.70 to
  /// accommodate the variation in how far down the chin patients angle
  /// the phone.
  static const double _chinMinBboxBottomRatio = 0.70;

  /// Universal minimum bbox area / frame area — below this, no region
  /// can be considered captured because we don't have enough pixels.
  static const double _universalMinBboxAreaRatio = 0.08;

  /// Universal maximum yaw/roll where ML Kit reliably finds landmarks.
  /// Above this, the detection itself becomes flaky, and we shouldn't
  /// trust any alignment claim.
  static const double _universalMaxAngleDegrees = 45.0;

  // ----- Main entry point -----

  /// Evaluates whether [face] satisfies the alignment criteria for
  /// [region] in a frame of dimensions [frameWidth] × [frameHeight].
  ///
  /// Returns a [RegionAlignmentResult] the camera screen can use to drive
  /// the overlay color, the hint text, and the capture button's enabled
  /// state.
  ///
  /// **Gate philosophy after the 2026-05-25 real-device test:**
  ///
  /// ML Kit's face detector is trained on near-frontal faces and degrades
  /// sharply on partial profiles / extreme camera angles. The
  /// camera-position-driven model (patient moves the phone around their
  /// still face) deliberately produces those extreme angles for four of
  /// the five regions. So "no face detected" should be interpreted very
  /// differently depending on the region:
  ///   • full_face → ML Kit *should* see a frontal face. No face = error.
  ///   • forehead, cheeks, chin → ML Kit failing is *evidence the patient
  ///     is correctly positioned* for a non-frontal capture. The gate
  ///     trusts them; the visible oval template gives them visual
  ///     guidance; the override is the backstop for when both fail.
  RegionAlignmentResult evaluate({
    required ScanRegion region,
    required Face? face,
    required int frameWidth,
    required int frameHeight,
  }) {
    // Frame must have valid dimensions before any ratio math.
    if (frameWidth <= 0 || frameHeight <= 0) {
      return const RegionAlignmentResult(
        aligned: false,
        noFace: true,
        score: 0,
        hint: 'Initializing camera…',
      );
    }

    // ----- full_face — strict gate, ML Kit is reliable here -----
    if (region == ScanRegion.fullFace) {
      if (face == null) {
        return const RegionAlignmentResult(
          aligned: false,
          noFace: true,
          score: 0,
          hint: 'Center your face in the oval.',
        );
      }
      final yaw = face.headEulerAngleY ?? 0;
      final roll = face.headEulerAngleZ ?? 0;
      if (yaw.abs() > _universalMaxAngleDegrees ||
          roll.abs() > _universalMaxAngleDegrees) {
        return const RegionAlignmentResult(
          aligned: false,
          noFace: false,
          score: 0.1,
          hint: 'Look straight at the camera.',
        );
      }
      final bboxArea = face.boundingBox.width * face.boundingBox.height;
      final frameArea = frameWidth * frameHeight;
      final areaRatio = bboxArea / frameArea;
      if (areaRatio < _universalMinBboxAreaRatio) {
        return const RegionAlignmentResult(
          aligned: false,
          noFace: false,
          score: 0.2,
          hint: 'Move the phone closer to your face.',
        );
      }
      return _evaluateFullFace(face, frameWidth, frameHeight, areaRatio,
          yaw: yaw, roll: roll);
    }

    // ----- non-frontal regions — soft gate -----
    // When ML Kit can't detect a face, that's the *expected* state for
    // these capture postures (phone angled up/down/sideways → face in
    // partial profile or extreme tilt). Auto-align with a low-confidence
    // score and a hint that points the user to the visual template.
    if (face == null) {
      return RegionAlignmentResult(
        aligned: true,
        noFace: true,
        score: 0.65,
        hint: 'Frame your ${region.label.toLowerCase()} in the oval, '
            'then tap to capture.',
      );
    }

    // ML Kit *did* detect a face — apply the region-specific lenient
    // checks. These never set aligned=false on noFace; they only refine
    // the hint when ML Kit gives us a signal we can use.
    switch (region) {
      case ScanRegion.fullFace:
        // Handled in the strict branch above. Unreachable here.
        throw StateError('full_face evaluated in non-frontal branch');
      case ScanRegion.forehead:
        return _evaluateForehead(face, frameWidth, frameHeight);
      case ScanRegion.leftCheek:
        return _evaluateLeftCheek(face, frameWidth, frameHeight);
      case ScanRegion.rightCheek:
        return _evaluateRightCheek(face, frameWidth, frameHeight);
      case ScanRegion.chin:
        return _evaluateChin(face, frameWidth, frameHeight);
    }
  }

  // ----- Per-region evaluators -----

  RegionAlignmentResult _evaluateFullFace(
    Face face,
    int frameW,
    int frameH,
    double areaRatio, {
    required double yaw,
    required double roll,
  }) {
    // Face must fill enough of the frame but not too much.
    if (areaRatio > _fullFaceMaxAreaRatio) {
      return const RegionAlignmentResult(
        aligned: false,
        noFace: false,
        score: 0.4,
        hint: 'Move the phone back a little.',
      );
    }
    if (areaRatio < _fullFaceMinAreaRatio) {
      return const RegionAlignmentResult(
        aligned: false,
        noFace: false,
        score: 0.4,
        hint: 'Move a bit closer.',
      );
    }

    // Centering — face center should be near frame center.
    final centerX = face.boundingBox.center.dx;
    final centerY = face.boundingBox.center.dy;
    final dx = (centerX - frameW / 2).abs() / frameW;
    final dy = (centerY - frameH / 2).abs() / frameH;
    if (dx > _fullFaceMaxHorizontalOffsetRatio) {
      final hint = centerX < frameW / 2
          ? 'Shift the phone a little to the right.'
          : 'Shift the phone a little to the left.';
      return RegionAlignmentResult(
        aligned: false,
        noFace: false,
        score: 0.55,
        hint: hint,
      );
    }
    if (dy > _fullFaceMaxVerticalOffsetRatio) {
      final hint = centerY < frameH / 2
          ? 'Lower the phone slightly.'
          : 'Raise the phone slightly.';
      return RegionAlignmentResult(
        aligned: false,
        noFace: false,
        score: 0.6,
        hint: hint,
      );
    }

    // Head pose — face should look straight at the camera.
    if (yaw.abs() > _fullFaceMaxYawDegrees) {
      return const RegionAlignmentResult(
        aligned: false,
        noFace: false,
        score: 0.7,
        hint: 'Look straight at the camera.',
      );
    }
    if (roll.abs() > _fullFaceMaxRollDegrees) {
      return const RegionAlignmentResult(
        aligned: false,
        noFace: false,
        score: 0.7,
        hint: 'Straighten your head — it looks tilted.',
      );
    }

    return const RegionAlignmentResult(
      aligned: true,
      noFace: false,
      score: 1.0,
      hint: 'Hold steady — capturing your full face.',
    );
  }

  // ---- Forehead / cheeks / chin — applied only when ML Kit *did* return
  // a face. All four return aligned=true unless they have a clear reason
  // to nudge the patient. The fail paths set aligned=false with a
  // specific hint; the success paths celebrate; ambiguous cases (no
  // landmarks, marginal pose) default to aligned=true because the
  // visible oval template is doing the work.

  RegionAlignmentResult _evaluateForehead(
    Face face,
    int frameW,
    int frameH,
  ) {
    // Forehead capture: phone is angled up at the brow. Lenient checks —
    // we only nudge when the patient is clearly mis-framing.
    final bboxTopRatio = face.boundingBox.top / frameH;
    if (bboxTopRatio > _foreheadMaxBboxTopRatio) {
      return const RegionAlignmentResult(
        aligned: false,
        noFace: false,
        score: 0.5,
        hint: 'Angle the phone up — point it at your forehead.',
      );
    }

    // Eye Y check is informational. If eyes are very high in the frame
    // (e.g., 0.10), the patient hasn't angled the phone up at all —
    // nudge them. Otherwise accept; the oval template handles fine
    // positioning.
    final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;
    final eyeY = leftEye != null && rightEye != null
        ? (leftEye.y + rightEye.y) / 2
        : (leftEye?.y ?? rightEye?.y);
    if (eyeY != null && eyeY / frameH < _foreheadMinEyeYRatio) {
      return const RegionAlignmentResult(
        aligned: false,
        noFace: false,
        score: 0.7,
        hint: 'Tilt the phone up a bit more.',
      );
    }

    return const RegionAlignmentResult(
      aligned: true,
      noFace: false,
      score: 1.0,
      hint: 'Forehead in frame — hold steady.',
    );
  }

  RegionAlignmentResult _evaluateLeftCheek(
    Face face,
    int frameW,
    int frameH,
  ) {
    // Patient's LEFT cheek. Camera on the patient's left side. The face
    // is in partial profile — ML Kit's yaw value is unreliable in this
    // range, so we don't gate on it (early versions did; the
    // 2026-05-25 real-device test showed yaw was as often wrong as right
    // in profile). We only check whether the face is in the correct
    // lateral half of the frame, and even that is informational.
    final centerXRatio = face.boundingBox.center.dx / frameW;
    if (centerXRatio < _cheekFaceCenterXThreshold) {
      return const RegionAlignmentResult(
        aligned: false,
        noFace: false,
        score: 0.6,
        hint: 'Move the phone to your left side.',
      );
    }
    return const RegionAlignmentResult(
      aligned: true,
      noFace: false,
      score: 1.0,
      hint: 'Left cheek in frame — hold steady.',
    );
  }

  RegionAlignmentResult _evaluateRightCheek(
    Face face,
    int frameW,
    int frameH,
  ) {
    // Mirror of _evaluateLeftCheek.
    final centerXRatio = face.boundingBox.center.dx / frameW;
    if (centerXRatio > (1.0 - _cheekFaceCenterXThreshold)) {
      return const RegionAlignmentResult(
        aligned: false,
        noFace: false,
        score: 0.6,
        hint: 'Move the phone to your right side.',
      );
    }
    return const RegionAlignmentResult(
      aligned: true,
      noFace: false,
      score: 1.0,
      hint: 'Right cheek in frame — hold steady.',
    );
  }

  RegionAlignmentResult _evaluateChin(
    Face face,
    int frameW,
    int frameH,
  ) {
    // Chin capture: phone angled down at jawline. Lenient version —
    // only nudge when the patient is clearly mis-framing.
    final mouth = face.landmarks[FaceLandmarkType.bottomMouth]?.position ??
        face.landmarks[FaceLandmarkType.leftMouth]?.position ??
        face.landmarks[FaceLandmarkType.rightMouth]?.position;
    if (mouth != null) {
      final mouthYRatio = mouth.y / frameH;
      if (mouthYRatio > _chinMaxMouthYRatio) {
        return const RegionAlignmentResult(
          aligned: false,
          noFace: false,
          score: 0.6,
          hint: 'Tilt the phone down a bit more — aim at your chin.',
        );
      }
    }

    // Bbox-bottom check is informational. If the chin isn't anywhere
    // near the bottom of the frame, ask the patient to get closer or
    // tilt more aggressively.
    final bboxBottomRatio = face.boundingBox.bottom / frameH;
    if (bboxBottomRatio < _chinMinBboxBottomRatio) {
      return const RegionAlignmentResult(
        aligned: false,
        noFace: false,
        score: 0.7,
        hint: 'Get a little closer — your chin should fill the bottom.',
      );
    }

    return const RegionAlignmentResult(
      aligned: true,
      noFace: false,
      score: 1.0,
      hint: 'Chin in frame — hold steady.',
    );
  }
}
