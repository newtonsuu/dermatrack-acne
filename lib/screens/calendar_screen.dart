import 'package:flutter/material.dart';

import '../models/scan.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/user_avatar_action.dart';

/// Monthly calendar showing scan history. Each day either renders a small
/// scan thumbnail (with severity color and Cook grade chip) or an empty
/// bordered cell. Inspired by Instagram's archive view from the UI doc.
///
/// Data source: ProfileService.scans (currently mocked). When ScanService
/// comes online and writes to Supabase, the data source swaps but this
/// widget doesn't change.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _displayedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _displayedMonth = DateTime(now.year, now.month, 1);
    ProfileService.instance.addListener(_onScansChanged);
  }

  @override
  void dispose() {
    ProfileService.instance.removeListener(_onScansChanged);
    super.dispose();
  }

  void _onScansChanged() {
    if (mounted) setState(() {});
  }

  void _goToPrevMonth() {
    setState(() {
      _displayedMonth =
          DateTime(_displayedMonth.year, _displayedMonth.month - 1, 1);
    });
  }

  void _goToNextMonth() {
    setState(() {
      _displayedMonth =
          DateTime(_displayedMonth.year, _displayedMonth.month + 1, 1);
    });
  }

  /// Returns the most-recent scan keyed by its midnight DateTime so the grid
  /// can do O(1) lookups. If a day has multiple scans, the one later in the
  /// list wins — fine for the mock data; we'll likely want a smarter rule
  /// (e.g., highest severity, or last of the day) when real data lands.
  Map<DateTime, Scan> _indexScansByDay(List<Scan> scans) {
    final result = <DateTime, Scan>{};
    for (final scan in scans) {
      final key =
          DateTime(scan.takenAt.year, scan.takenAt.month, scan.takenAt.day);
      result[key] = scan;
    }
    return result;
  }

  int _countScansInMonth(Map<DateTime, Scan> scansByDay, DateTime month) {
    return scansByDay.keys
        .where((d) => d.year == month.year && d.month == month.month)
        .length;
  }

  void _openScanDetail(Scan scan) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Scan detail for ${scan.id} — coming soon.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scansByDay = _indexScansByDay(ProfileService.instance.scans);
    final today = DateTime.now();
    final todayKey = DateTime(today.year, today.month, today.day);
    final scansThisMonth = _countScansInMonth(scansByDay, _displayedMonth);

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: const [UserAvatarAction()],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MonthHeader(
                displayed: _displayedMonth,
                onPrev: _goToPrevMonth,
                onNext: _goToNextMonth,
              ),
              const SizedBox(height: 12),
              const _DayOfWeekRow(),
              const SizedBox(height: 8),
              Expanded(
                child: _CalendarGrid(
                  displayedMonth: _displayedMonth,
                  scansByDay: scansByDay,
                  today: todayKey,
                  onDayTap: (date, scan) {
                    if (scan != null) _openScanDetail(scan);
                  },
                ),
              ),
              const SizedBox(height: 12),
              _MonthSummary(
                month: _displayedMonth,
                scansInMonth: scansThisMonth,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===== Header =====

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.displayed,
    required this.onPrev,
    required this.onNext,
  });

  final DateTime displayed;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Previous month',
        ),
        Expanded(
          child: Text(
            '${_monthNames[displayed.month - 1]} ${displayed.year}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Next month',
        ),
      ],
    );
  }
}

// ===== Day-of-week row =====

class _DayOfWeekRow extends StatelessWidget {
  const _DayOfWeekRow();

  @override
  Widget build(BuildContext context) {
    // Monday-first. If we ever want Sunday-first as a setting, reorder here
    // AND update _CalendarGrid's `leadingDays` calculation.
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Row(
      children: [
        for (final d in days)
          Expanded(
            child: Center(
              child: Text(
                d.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary(context),
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ===== Grid =====

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({
    required this.displayedMonth,
    required this.scansByDay,
    required this.today,
    required this.onDayTap,
  });

  final DateTime displayedMonth;
  final Map<DateTime, Scan> scansByDay;
  final DateTime today;
  final void Function(DateTime date, Scan? scan) onDayTap;

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(displayedMonth.year, displayedMonth.month, 1);
    // DateTime.weekday: Mon=1 ... Sun=7. We want leading offset from Monday.
    final leadingDays = firstOfMonth.weekday - 1;
    final gridStart = firstOfMonth.subtract(Duration(days: leadingDays));

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 1,
      ),
      itemCount: 42, // fixed 6 rows keeps grid height stable across months
      itemBuilder: (context, index) {
        final date = gridStart.add(Duration(days: index));
        final dateKey = DateTime(date.year, date.month, date.day);
        final inMonth = date.month == displayedMonth.month;
        return _CalendarCell(
          date: date,
          scan: scansByDay[dateKey],
          inMonth: inMonth,
          isToday: dateKey == today,
          onTap: () => onDayTap(date, scansByDay[dateKey]),
        );
      },
    );
  }
}

// ===== Single cell =====

class _CalendarCell extends StatelessWidget {
  const _CalendarCell({
    required this.date,
    required this.scan,
    required this.inMonth,
    required this.isToday,
    required this.onTap,
  });

  final DateTime date;
  final Scan? scan;
  final bool inMonth;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasScan = scan != null;
    final opacityForOutOfMonth = inMonth ? 1.0 : 0.35;

    final borderColor = isToday
        ? AppTheme.primary
        : AppTheme.border(context);

    return Opacity(
      opacity: opacityForOutOfMonth,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: hasScan ? onTap : null,
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            children: [
              // Background: scan thumbnail (severity-colored placeholder) OR
              // empty surface with border.
              Positioned.fill(
                child: hasScan
                    ? _ScanCellBackground(scan: scan!)
                    : Container(
                        decoration: BoxDecoration(
                          color: AppTheme.surface(context),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: borderColor,
                            width: isToday ? 2 : 1,
                          ),
                        ),
                      ),
              ),
              // Today border overlay (drawn on top of scan background too).
              if (hasScan && isToday)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppTheme.primary,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              // Day number (top-left).
              Positioned(
                top: 4,
                left: 6,
                child: Text(
                  '${date.day}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: hasScan
                        ? Colors.white
                        : AppTheme.textPrimary(context),
                    shadows: hasScan
                        ? const [
                            Shadow(
                              color: Color(0x55000000),
                              blurRadius: 2,
                              offset: Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
              // Grade chip (bottom-right).
              if (hasScan)
                Positioned(
                  bottom: 4,
                  right: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'G${scan!.cookGrade}',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: scan!.severityColor,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Severity-colored gradient placeholder for a scan cell. When real scan
/// images land, swap this for an Image.network(signedUrl) of the actual
/// selfie thumbnail; the layout around it stays the same.
class _ScanCellBackground extends StatelessWidget {
  const _ScanCellBackground({required this.scan});
  final Scan scan;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scan.severityColor.withValues(alpha: 0.45),
            scan.severityColor.withValues(alpha: 0.95),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.face_outlined,
        color: Colors.white,
        size: 24,
      ),
    );
  }
}

// ===== Footer summary =====

class _MonthSummary extends StatelessWidget {
  const _MonthSummary({required this.month, required this.scansInMonth});

  final DateTime month;
  final int scansInMonth;

  @override
  Widget build(BuildContext context) {
    final label = scansInMonth == 0
        ? 'No scans this month yet.'
        : '$scansInMonth scan${scansInMonth == 1 ? '' : 's'} this month';
    return Center(
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: AppTheme.textSecondary(context),
        ),
      ),
    );
  }
}
