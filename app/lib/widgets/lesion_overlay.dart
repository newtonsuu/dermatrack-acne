import 'package:flutter/material.dart';

import '../models/scan.dart';

/// Renders a scan's image with lesion bounding boxes drawn on top.
///
/// Locks the container to the image's natural aspect ratio (read from
/// `lesions.first.imageSize`) so `BoxFit.cover` fills it exactly — no
/// letterboxing, no need to do letterbox-aware coordinate math in the
/// painter. Each bbox is drawn in the color associated with its bucket
/// (red = inflammatory, amber = non-inflammatory, grey = post-acne).
///
/// If [lesions] is empty, the overlay layer is skipped entirely and only
/// the image is shown.
class LesionOverlay extends StatelessWidget {
  const LesionOverlay({
    super.key,
    required this.imageUrl,
    required this.lesions,
    this.borderRadius = 16,
    this.strokeWidth = 2.5,
    this.fallbackAspectRatio = 1.0,
  });

  /// Signed URL to the scan image. Null while loading.
  final String? imageUrl;

  final List<Lesion> lesions;
  final double borderRadius;
  final double strokeWidth;

  /// Used when no lesions are present and we can't read the natural size
  /// from one. Square is a reasonable default for selfies.
  final double fallbackAspectRatio;

  @override
  Widget build(BuildContext context) {
    // The natural image size lives on each lesion. Reading from the first
    // is fine — every detection from a given scan was made against the
    // same image, so all of them share dimensions.
    final natural = lesions.isNotEmpty ? lesions.first.imageSize : null;
    final aspectRatio = (natural != null && natural.h > 0)
        ? natural.w / natural.h
        : fallbackAspectRatio;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _ImageLayer(imageUrl: imageUrl),
            if (lesions.isNotEmpty && natural != null)
              CustomPaint(
                painter: _LesionOverlayPainter(
                  lesions: lesions,
                  naturalSize: Size(natural.w, natural.h),
                  strokeWidth: strokeWidth,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ImageLayer extends StatelessWidget {
  const _ImageLayer({required this.imageUrl});
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null) {
      return Container(
        color: Colors.black12,
        alignment: Alignment.center,
        child: const Icon(
          Icons.image_outlined,
          size: 48,
          color: Colors.white70,
        ),
      );
    }
    return Image.network(
      imageUrl!,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: Colors.black12,
        alignment: Alignment.center,
        child: const Icon(
          Icons.broken_image_outlined,
          size: 48,
          color: Colors.white70,
        ),
      ),
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return Container(
          color: Colors.black12,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(strokeWidth: 2),
        );
      },
    );
  }
}

/// CustomPainter that scales each lesion's bbox from the image's natural
/// pixel space into the canvas's render space. Because the parent
/// [AspectRatio] guarantees canvas:image aspect ratios match, the scale is
/// uniform — `scaleX == scaleY` in practice, but we compute both
/// independently to stay safe against floating-point drift.
class _LesionOverlayPainter extends CustomPainter {
  _LesionOverlayPainter({
    required this.lesions,
    required this.naturalSize,
    required this.strokeWidth,
  });

  final List<Lesion> lesions;
  final Size naturalSize;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (naturalSize.width <= 0 || naturalSize.height <= 0) return;

    final scaleX = size.width / naturalSize.width;
    final scaleY = size.height / naturalSize.height;

    for (final lesion in lesions) {
      final paint = Paint()
        ..color = lesion.bucketColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;

      final rect = Rect.fromLTWH(
        lesion.bbox.x * scaleX,
        lesion.bbox.y * scaleY,
        lesion.bbox.w * scaleX,
        lesion.bbox.h * scaleY,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LesionOverlayPainter old) =>
      old.lesions != lesions ||
      old.naturalSize != naturalSize ||
      old.strokeWidth != strokeWidth;
}
