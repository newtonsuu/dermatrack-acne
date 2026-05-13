import 'dart:io';

import 'package:flutter/material.dart';

import '../models/scan.dart';
import '../theme/app_theme.dart';

/// Compact card representing a single scan in the profile preview row or in
/// the full gallery grid.
///
/// If [scan.imagePath] is set, the image fills the top portion; otherwise a
/// gradient placeholder in the severity color is shown. A grade chip is pinned
/// to the top-right and the date label sits below.
class ScanThumbnail extends StatelessWidget {
  const ScanThumbnail({
    super.key,
    required this.scan,
    this.width = 100,
    this.onTap,
  });

  final Scan scan;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: scan.imagePath != null
                        ? Image.file(File(scan.imagePath!), fit: BoxFit.cover)
                        : _PlaceholderTile(color: scan.severityColor),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: _GradeChip(
                      grade: scan.cookGrade,
                      color: scan.severityColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _formatDate(scan.takenAt),
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final scanDay = DateTime(date.year, date.month, date.day);
    final diff = today.difference(scanDay).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return '${diff}d ago';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }
}

class _PlaceholderTile extends StatelessWidget {
  const _PlaceholderTile({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.35),
            color.withValues(alpha: 0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.face_outlined,
        color: Colors.white,
        size: 36,
      ),
    );
  }
}

class _GradeChip extends StatelessWidget {
  const _GradeChip({required this.grade, required this.color});
  final int grade;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Text(
        'G$grade',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
