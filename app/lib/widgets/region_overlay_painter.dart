import 'package:flutter/material.dart';

import '../models/scan.dart';
import '../theme/app_theme.dart';

/// Paints a semi-transparent guide on top of the live camera preview that
/// shows where the patient should aim the phone for the current
/// [ScanRegion]. Color shifts from red (not aligned) through amber to teal
/// (aligned) — the green/red feedback common to ID-verification flows the
/// dermatologist referenced on 2026-05-25.
///
/// The painter is geometric-only: it draws the target template (a region-
/// specific oval positioned in the relevant part of the frame) plus a thin
/// scrim and corner brackets. The caller decides the color by passing
/// [aligned] and [score] from a [RegionAlignmentResult].
///
/// The Y-axis is the long phone dimension, X is the short — matches the
/// portrait orientation the scan session always runs in.
class RegionOverlayPainter extends CustomPainter {
  RegionOverlayPainter({
    required this.region,
    required this.aligned,
    required this.score,
    required this.noFace,
  });

  final ScanRegion region;
  final bool aligned;

  /// 0.0–1.0 alignment confidence from the evaluator. Drives the color
  /// interpolation between the "off" red and the "locked" teal.
  final double score;

  /// True when no face is detected. Painter dims the overlay further in
  /// this state to signal "we don't see you yet".
  final bool noFace;

  // ----- Tunables -----

  static const Color _offColor = Color(0xFFE53935); // red
  static const Color _onColor = AppTheme.primary;   // teal
  static const double _strokeWidth = 3.0;
  static const double _cornerLength = 28.0;
  static const double _cornerStrokeWidth = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    // Compute the current color by lerping between off and on based on
    // alignment score. When aligned=true we snap fully to teal so the
    // visual transition to "locked" is clean.
    final color = aligned
        ? _onColor
        : Color.lerp(
            _offColor,
            _onColor,
            score.clamp(0.0, 1.0).toDouble(),
          )!;
    final overlayAlpha = noFace ? 0.45 : 1.0;
    final activeColor = color.withValues(alpha: 0.9 * overlayAlpha);

    // 1) Region-specific target rectangle (the oval lives inside this).
    //    All values are relative to the [size] passed in by the framework
    //    so the painter naturally scales to any preview dimensions.
    final target = _targetRectFor(region, size);

    // 2) Outer scrim — slight dimming everywhere except inside the oval,
    //    so attention focuses on the target region. Skipped on noFace so
    //    the patient can see *why* alignment isn't working (e.g., they're
    //    not in frame at all).
    if (!noFace) {
      final scrimPath = Path()..addRect(Offset.zero & size);
      final ovalPath = Path()..addOval(target);
      final scrimEvenOdd = Path.combine(PathOperation.difference, scrimPath, ovalPath);
      final scrimPaint = Paint()
        ..color = Colors.black.withValues(alpha: aligned ? 0.20 : 0.35);
      canvas.drawPath(scrimEvenOdd, scrimPaint);
    }

    // 3) The oval target itself.
    final ovalPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..color = activeColor;
    canvas.drawOval(target, ovalPaint);

    // 4) Corner brackets just outside the oval's bounding rect.
    //    Helps the patient see the target as a *frame* rather than just an
    //    oval — matches the ID-verification visual language.
    _drawCornerBrackets(canvas, target.inflate(8), activeColor);

    // 5) Region label chip at top center of the frame.
    _drawRegionLabel(canvas, size, region, activeColor);
  }

  /// Returns the Rect inside which the oval target should be drawn for
  /// [region]. Tuned per-region so the patient's adjustment instruction
  /// matches what the alignment evaluator is looking for:
  ///   • forehead → oval in upper portion of frame
  ///   • chin     → oval in lower portion of frame
  ///   • left/right cheek → oval pushed to the side
  ///   • full_face → centered oval
  Rect _targetRectFor(ScanRegion region, Size size) {
    final w = size.width;
    final h = size.height;
    switch (region) {
      case ScanRegion.fullFace:
        // Centered oval taking ~70% width × 80% height.
        final ovalW = w * 0.70;
        final ovalH = h * 0.55;
        return Rect.fromCenter(
          center: Offset(w / 2, h / 2),
          width: ovalW,
          height: ovalH,
        );
      case ScanRegion.forehead:
        // Oval in the top third — phone is angled up, so forehead fills
        // top of frame. Slightly wider than tall.
        final ovalW = w * 0.75;
        final ovalH = h * 0.30;
        return Rect.fromCenter(
          center: Offset(w / 2, h * 0.27),
          width: ovalW,
          height: ovalH,
        );
      case ScanRegion.chin:
        // Oval in the bottom third — phone angled down, chin fills bottom.
        final ovalW = w * 0.70;
        final ovalH = h * 0.30;
        return Rect.fromCenter(
          center: Offset(w / 2, h * 0.73),
          width: ovalW,
          height: ovalH,
        );
      case ScanRegion.leftCheek:
        // Patient's left cheek fills the right side of the frame (camera
        // is to their left). Oval pushed right.
        final ovalW = w * 0.55;
        final ovalH = h * 0.55;
        return Rect.fromCenter(
          center: Offset(w * 0.65, h / 2),
          width: ovalW,
          height: ovalH,
        );
      case ScanRegion.rightCheek:
        // Mirror — oval pushed left.
        final ovalW = w * 0.55;
        final ovalH = h * 0.55;
        return Rect.fromCenter(
          center: Offset(w * 0.35, h / 2),
          width: ovalW,
          height: ovalH,
        );
    }
  }

  void _drawCornerBrackets(Canvas canvas, Rect rect, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = _cornerStrokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Each corner is two lines forming an L.
    final l = _cornerLength;

    // Top-left
    canvas.drawLine(rect.topLeft, rect.topLeft.translate(l, 0), paint);
    canvas.drawLine(rect.topLeft, rect.topLeft.translate(0, l), paint);
    // Top-right
    canvas.drawLine(rect.topRight, rect.topRight.translate(-l, 0), paint);
    canvas.drawLine(rect.topRight, rect.topRight.translate(0, l), paint);
    // Bottom-left
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft.translate(l, 0), paint);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft.translate(0, -l), paint);
    // Bottom-right
    canvas.drawLine(rect.bottomRight, rect.bottomRight.translate(-l, 0), paint);
    canvas.drawLine(rect.bottomRight, rect.bottomRight.translate(0, -l), paint);
  }

  void _drawRegionLabel(
      Canvas canvas, Size size, ScanRegion region, Color color) {
    // Small label chip at top showing which region is being captured.
    // Uses TextPainter (CustomPainter has no widget context).
    final label = region.label.toUpperCase();
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final padding = 12.0;
    final chipW = tp.width + 2 * padding;
    final chipH = tp.height + 12.0;
    final chipRect = Rect.fromCenter(
      center: Offset(size.width / 2, 36),
      width: chipW,
      height: chipH,
    );
    final chipRRect =
        RRect.fromRectAndRadius(chipRect, const Radius.circular(20));

    final bgPaint = Paint()..color = color.withValues(alpha: 0.92);
    canvas.drawRRect(chipRRect, bgPaint);

    tp.paint(
      canvas,
      Offset(chipRect.left + padding, chipRect.top + (chipH - tp.height) / 2),
    );
  }

  @override
  bool shouldRepaint(covariant RegionOverlayPainter old) {
    // Only repaint when something visually changes — saves a few frames
    // of CPU when the alignment state holds steady.
    return old.region != region ||
        old.aligned != aligned ||
        old.noFace != noFace ||
        (old.score - score).abs() > 0.02;
  }
}

