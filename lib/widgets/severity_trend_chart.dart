import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/scan.dart';
import '../theme/app_theme.dart';

/// 30-day severity trend line chart for the dashboard.
///
/// Plots two series: the daily worst cook_grade (one point per scan day),
/// and a 7-day rolling-average overlay when the trailing window has ≥2
/// scan days (otherwise the average would just duplicate the raw line and
/// add visual noise).
///
/// Aggregation policy mirrors the calendar — worst-of-day wins as the
/// representative, so an unusually-good late scan doesn't visually
/// "rescue" an otherwise-bad day. Honest about the worst rather than
/// optimistic about the latest.
class SeverityTrendChart extends StatelessWidget {
  const SeverityTrendChart({super.key, required this.scans});
  final List<Scan> scans;

  static const _windowDays = 30;
  static const _rollingWindow = 7;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(const Duration(days: _windowDays - 1));

    // Aggregate scans into per-day worst cook grade, keyed by day index
    // (0 = `start`, 29 = today) so chart math stays in integer-x space.
    final dailyWorst = <int, int>{};
    for (final s in scans) {
      final day = DateTime(s.takenAt.year, s.takenAt.month, s.takenAt.day);
      if (day.isBefore(start) || day.isAfter(today)) continue;
      final idx = day.difference(start).inDays;
      final existing = dailyWorst[idx];
      if (existing == null || s.cookGrade > existing) {
        dailyWorst[idx] = s.cookGrade;
      }
    }

    final sortedIdx = dailyWorst.keys.toList()..sort();
    final rawSpots = <FlSpot>[
      for (final i in sortedIdx)
        FlSpot(i.toDouble(), dailyWorst[i]!.toDouble()),
    ];

    // 7-day rolling average: emitted at each day that has a scan, averaged
    // over the trailing 7-day window. Skipped when the window contains
    // fewer than 2 scans — duplicating the raw value adds nothing.
    final rollingSpots = <FlSpot>[];
    for (final i in sortedIdx) {
      var sum = 0;
      var count = 0;
      for (var j = i - _rollingWindow + 1; j <= i; j++) {
        final v = dailyWorst[j];
        if (v != null) {
          sum += v;
          count++;
        }
      }
      if (count >= 2) {
        rollingSpots.add(FlSpot(i.toDouble(), sum / count));
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ChartHeader(hasRolling: rollingSpots.length >= 2),
            const SizedBox(height: 14),
            SizedBox(
              height: 180,
              child: rawSpots.isEmpty
                  ? const _EmptyState()
                  : _TrendLineChart(
                      rawSpots: rawSpots,
                      rollingSpots: rollingSpots,
                      windowDays: _windowDays,
                      start: start,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== Header + legend =====

class _ChartHeader extends StatelessWidget {
  const _ChartHeader({required this.hasRolling});
  final bool hasRolling;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Severity trend',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                'Last 30 days',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary(context),
                ),
              ),
            ],
          ),
        ),
        if (hasRolling)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _LegendItem(color: AppTheme.primary, label: 'Daily'),
              const SizedBox(width: 10),
              _LegendItem(
                color: AppTheme.accent,
                label: '7-day avg',
                dashed: true,
              ),
            ],
          ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    this.dashed = false,
  });
  final Color color;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(14, 2),
          painter: _LinePainter(color: color, dashed: dashed),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppTheme.textSecondary(context),
          ),
        ),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  const _LinePainter({required this.color, required this.dashed});
  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    if (dashed) {
      const dash = 3.0;
      const gap = 2.0;
      var x = 0.0;
      while (x < size.width) {
        canvas.drawLine(
          Offset(x, size.height / 2),
          Offset((x + dash).clamp(0, size.width), size.height / 2),
          paint,
        );
        x += dash + gap;
      }
    } else {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.color != color || old.dashed != dashed;
}

// ===== Empty state =====

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.show_chart,
            size: 36,
            color: AppTheme.textSecondary(context),
          ),
          const SizedBox(height: 8),
          Text(
            'No scans in this window yet.',
            style: TextStyle(color: AppTheme.textSecondary(context)),
          ),
          const SizedBox(height: 2),
          Text(
            'Take regular scans to see your trend here.',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ===== The actual chart =====

class _TrendLineChart extends StatelessWidget {
  const _TrendLineChart({
    required this.rawSpots,
    required this.rollingSpots,
    required this.windowDays,
    required this.start,
  });

  final List<FlSpot> rawSpots;
  final List<FlSpot> rollingSpots;
  final int windowDays;
  final DateTime start;

  /// Severity-bucket label per cook grade. Short forms keep the y-axis
  /// gutter narrow enough that the chart area stays wide.
  String _yLabel(double v) {
    if (v == 0) return 'Clear';
    if (v == 2) return 'Mild';
    if (v == 4) return 'Mod';
    if (v == 6) return 'Sev';
    if (v == 8) return 'V.Sev';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (windowDays - 1).toDouble(),
        minY: 0,
        maxY: 8,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 2,
          getDrawingHorizontalLine: (value) => FlLine(
            color: AppTheme.border(context).withValues(alpha: 0.4),
            strokeWidth: 1,
            dashArray: const [4, 4],
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              interval: 2,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  _yLabel(v),
                  style: TextStyle(
                    fontSize: 9,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 5,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= windowDays) return const SizedBox.shrink();
                final day = start.add(Duration(days: i));
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${day.month}/${day.day}',
                    style: TextStyle(
                      fontSize: 9,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          // Rolling-average drawn UNDER the raw line so the daily points
          // and dots stay visually dominant.
          if (rollingSpots.length >= 2)
            LineChartBarData(
              spots: rollingSpots,
              isCurved: true,
              curveSmoothness: 0.3,
              color: AppTheme.accent,
              barWidth: 2,
              dashArray: const [5, 4],
              dotData: const FlDotData(show: false),
            ),
          LineChartBarData(
            spots: rawSpots,
            isCurved: false,
            color: AppTheme.primary,
            barWidth: 2.5,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                radius: 3,
                color: AppTheme.primary,
                strokeWidth: 0,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: AppTheme.primary.withValues(alpha: 0.12),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppTheme.surface(context),
            getTooltipItems: (spots) => spots.map((s) {
              final day = start.add(Duration(days: s.x.toInt()));
              return LineTooltipItem(
                '${day.month}/${day.day}\nCook ${s.y.toStringAsFixed(1)}',
                TextStyle(
                  color: AppTheme.textPrimary(context),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
