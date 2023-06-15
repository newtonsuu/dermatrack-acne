import 'package:flutter/material.dart';

import '../models/scan.dart';
import '../theme/app_theme.dart';

/// 30-day skin-summary card for the profile screen.
///
/// Aggregates the user's recent scan history into a glanceable status
/// report: the most common severity label (mode) with frequency, an
/// improving/steady/worsening trend signal, plus the user's best and worst
/// days in the window. Reads like the kind of summary a patient would
/// screenshot to send their dermatologist.
///
/// Aggregation policy mirrors the calendar and the dashboard trend chart —
/// worst-of-day wins as the day's representative scan. Same reason: an
/// isolated good evening scan shouldn't visually rescue a bad day, and
/// keeping the rule consistent across surfaces avoids three different
/// "best" stories for the same data.
class SkinSummaryCard extends StatelessWidget {
  const SkinSummaryCard({super.key, required this.scans});
  final List<Scan> scans;

  static const _windowDays = 30;
  // Need at least 4 scan days to split into halves of ≥2 each. Below that,
  // a "trend" would be one point vs one point — noise, not signal.
  static const _trendMinScanDays = 4;
  // How big a difference between first-half and second-half averages
  // counts as a real trend. 0.5 of a Cook step keeps low-amplitude noise
  // from being labelled improving/worsening.
  static const _trendDelta = 0.5;

  @override
  Widget build(BuildContext context) {
    final summary = _computeSummary(scans);
    if (summary == null) {
      // No scans in the 30-day window. Caller (profile_screen) already
      // guards on scans.isNotEmpty, so this is just defensive — if it
      // does fire, render nothing rather than a confusing empty card.
      return const SizedBox.shrink();
    }

    final showTrend = summary.trend != null;
    final showBest = summary.totalScanDays > 1 && summary.bestDay != null;
    // Only show "Worst day" when it differs from the best — otherwise the
    // two rows would point at the same data and just add clutter.
    final showWorst = showBest &&
        summary.worstDay != null &&
        summary.worstDay!.cookGrade > summary.bestDay!.cookGrade;

    final detailRows = <Widget>[];
    if (showTrend) {
      detailRows.add(_SummaryRow(
        icon: summary.trend!.icon,
        iconColor: summary.trend!.color,
        title: summary.trend!.label,
        subtitle: summary.trend!.detail,
      ));
    }
    if (showBest) {
      if (detailRows.isNotEmpty) detailRows.add(const SizedBox(height: 12));
      detailRows.add(_SummaryRow(
        icon: Icons.check_circle_outline,
        iconColor: const Color(0xFF4CAF50),
        title: 'Best day',
        subtitle:
            '${_formatDate(summary.bestDay!.date)} · ${summary.bestDay!.severityLabel}',
      ));
    }
    if (showWorst) {
      if (detailRows.isNotEmpty) detailRows.add(const SizedBox(height: 12));
      detailRows.add(_SummaryRow(
        icon: Icons.warning_amber_outlined,
        iconColor: const Color(0xFFFF9800),
        title: 'Worst day',
        subtitle:
            '${_formatDate(summary.worstDay!.date)} · ${summary.worstDay!.severityLabel}',
      ));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _CardHeader(),
            const SizedBox(height: 14),
            _ModalRow(summary: summary),
            if (detailRows.isNotEmpty) ...[
              const Divider(height: 26),
              ...detailRows,
            ],
          ],
        ),
      ),
    );
  }
}

// ===== Card subwidgets =====

class _CardHeader extends StatelessWidget {
  const _CardHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Skin summary',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        Text(
          'LAST 30 DAYS',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: AppTheme.textSecondary(context),
          ),
        ),
      ],
    );
  }
}

class _ModalRow extends StatelessWidget {
  const _ModalRow({required this.summary});
  final _SummaryData summary;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: summary.modalColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                summary.modalLabel,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${summary.modalCount} of ${summary.totalScanDays} scan day'
                '${summary.totalScanDays == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: iconColor, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ===== Data layer =====

class _SummaryData {
  const _SummaryData({
    required this.modalLabel,
    required this.modalColor,
    required this.modalCount,
    required this.totalScanDays,
    this.bestDay,
    this.worstDay,
    this.trend,
  });

  /// The severity label that appeared on the most scan days in the window.
  final String modalLabel;
  final Color modalColor;
  final int modalCount;
  final int totalScanDays;
  final _DayPoint? bestDay;
  final _DayPoint? worstDay;
  final _TrendInfo? trend;
}

class _DayPoint {
  const _DayPoint({
    required this.date,
    required this.severityLabel,
    required this.cookGrade,
  });
  final DateTime date;
  final String severityLabel;
  final int cookGrade;
}

class _TrendInfo {
  const _TrendInfo({
    required this.icon,
    required this.color,
    required this.label,
    required this.detail,
  });
  final IconData icon;
  final Color color;
  final String label;
  final String detail;
}

_SummaryData? _computeSummary(List<Scan> scans) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final start = today.subtract(
    const Duration(days: SkinSummaryCard._windowDays - 1),
  );

  // Worst-of-day representative scan (matches calendar + trend chart).
  final dayToRep = <DateTime, Scan>{};
  for (final s in scans) {
    final day = DateTime(s.takenAt.year, s.takenAt.month, s.takenAt.day);
    if (day.isBefore(start) || day.isAfter(today)) continue;
    final existing = dayToRep[day];
    if (existing == null || s.cookGrade > existing.cookGrade) {
      dayToRep[day] = s;
    }
  }
  if (dayToRep.isEmpty) return null;

  // Modal severity bucket — count by severity_label and pick the most common.
  final bucketCounts = <String, int>{};
  final bucketColors = <String, Color>{};
  for (final s in dayToRep.values) {
    bucketCounts[s.severityLabel] = (bucketCounts[s.severityLabel] ?? 0) + 1;
    bucketColors[s.severityLabel] = s.severityColor;
  }
  final modal =
      bucketCounts.entries.reduce((a, b) => a.value >= b.value ? a : b);

  // Best (lowest cookGrade) / worst (highest), oldest-wins on ties so the
  // user sees the *first* time they hit that milestone — feels more like
  // a journal entry than a perpetually-overwritten record.
  final sortedByDate = dayToRep.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  _DayPoint? best;
  _DayPoint? worst;
  for (final entry in sortedByDate) {
    final s = entry.value;
    final dp = _DayPoint(
      date: entry.key,
      severityLabel: s.severityLabel,
      cookGrade: s.cookGrade,
    );
    if (best == null || dp.cookGrade < best.cookGrade) best = dp;
    if (worst == null || dp.cookGrade > worst.cookGrade) worst = dp;
  }

  // Trend = first-half avg → second-half avg, applied only when we have
  // ≥4 scan days. Splitting by *scan order* rather than *time* keeps the
  // signal sensible when scans are bunched at one end of the window.
  _TrendInfo? trend;
  if (sortedByDate.length >= SkinSummaryCard._trendMinScanDays) {
    final mid = sortedByDate.length ~/ 2;
    final firstHalf =
        sortedByDate.sublist(0, mid).map((e) => e.value.cookGrade).toList();
    final secondHalf =
        sortedByDate.sublist(mid).map((e) => e.value.cookGrade).toList();
    final firstAvg = firstHalf.reduce((a, b) => a + b) / firstHalf.length;
    final secondAvg = secondHalf.reduce((a, b) => a + b) / secondHalf.length;
    final delta = secondAvg - firstAvg;

    if (delta < -SkinSummaryCard._trendDelta) {
      trend = _TrendInfo(
        icon: Icons.trending_down,
        color: const Color(0xFF4CAF50),
        label: 'Improving',
        detail:
            'Cook average dropped from ${firstAvg.toStringAsFixed(1)} to ${secondAvg.toStringAsFixed(1)}',
      );
    } else if (delta > SkinSummaryCard._trendDelta) {
      trend = _TrendInfo(
        icon: Icons.trending_up,
        color: const Color(0xFFF44336),
        label: 'Worsening',
        detail:
            'Cook average climbed from ${firstAvg.toStringAsFixed(1)} to ${secondAvg.toStringAsFixed(1)}',
      );
    } else {
      trend = _TrendInfo(
        icon: Icons.trending_flat,
        color: const Color(0xFF607D8B),
        label: 'Steady',
        detail: 'Cook average held around ${secondAvg.toStringAsFixed(1)}',
      );
    }
  }

  return _SummaryData(
    modalLabel: modal.key,
    modalColor: bucketColors[modal.key]!,
    modalCount: modal.value,
    totalScanDays: dayToRep.length,
    bestDay: best,
    worstDay: worst,
    trend: trend,
  );
}

String _formatDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}';
}
