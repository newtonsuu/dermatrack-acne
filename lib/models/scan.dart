import 'package:flutter/material.dart';

/// A single skin scan record.
///
/// `cookGrade` follows the Cook 0-8 acne grading scale (Cook 1979), the same
/// scale used by Dr. Bell Eapen's Acne Grading API and AcneCheck. Higher = more
/// severe. Specific grades are defined at 0, 2, 4, 6, 8 but the API may emit
/// any integer in between.
@immutable
class Scan {
  const Scan({
    required this.id,
    required this.takenAt,
    required this.cookGrade,
    this.imagePath,
  });

  final String id;
  final DateTime takenAt;
  final int cookGrade;

  /// Local file path (or storage URL after Supabase). Null for placeholders.
  final String? imagePath;

  /// Coarse three-bucket label inspired by the Cook scale ranges.
  String get severityLabel {
    if (cookGrade <= 2) return 'Mild';
    if (cookGrade <= 5) return 'Moderate';
    return 'Severe';
  }

  /// Color used in thumbnails / chips to communicate severity at a glance.
  Color get severityColor {
    if (cookGrade <= 1) return const Color(0xFF4CAF50); // green
    if (cookGrade <= 3) return const Color(0xFF8BC34A); // lime
    if (cookGrade <= 5) return const Color(0xFFFFC107); // amber
    if (cookGrade <= 7) return const Color(0xFFFF9800); // orange
    return const Color(0xFFF44336); // red
  }
}
