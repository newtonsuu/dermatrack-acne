import 'package:flutter/material.dart';

import '../models/scan.dart';
import '../services/scan_service.dart';
import '../theme/app_theme.dart';
import '../widgets/facial_summary_card.dart';
import '../widgets/user_avatar_action.dart';
import 'scan_detail_screen.dart';

/// Monthly calendar showing scan history. Each day either renders a small
/// scan thumbnail (with severity color and Cook grade chip) or an empty
/// bordered cell. Inspired by Instagram's archive view from the UI doc.
///
/// Data source: ScanService.scans (live, from `public.scans`).
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
    ScanService.instance.addListener(_onScansChanged);
  }

  @override
  void dispose() {
    ScanService.instance.removeListener(_onScansChanged);
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

  /// Returns ALL scans grouped by day, each list sorted newest-first. The
  /// previous behavior collapsed multiple scans on the same day into one —
  /// quietly losing data. We now keep the full list so _DayDetailSheet can
  /// surface every scan in the drill-down.
  Map<DateTime, List<Scan>> _indexScansByDay(List<Scan> scans) {
    final result = <DateTime, List<Scan>>{};
    for (final scan in scans) {
      final key =
          DateTime(scan.takenAt.year, scan.takenAt.month, scan.takenAt.day);
      (result[key] ??= <Scan>[]).add(scan);
    }
    for (final list in result.values) {
      list.sort((a, b) => b.takenAt.compareTo(a.takenAt));
    }
    return result;
  }

  /// Counts the TOTAL number of scans in the displayed month (across all
  /// days). Previously this counted unique days with scans, which under-
  /// reports activity once multi-scan days exist.
  int _countScansInMonth(
    Map<DateTime, List<Scan>> scansByDay,
    DateTime month,
  ) {
    int total = 0;
    for (final entry in scansByDay.entries) {
      if (entry.key.year == month.year && entry.key.month == month.month) {
        total += entry.value.length;
      }
    }
    return total;
  }

  void _handleDayTap(DateTime date, List<Scan> dayScans) {
    if (dayScans.isEmpty) return;
    if (dayScans.length == 1) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ScanDetailScreen(scan: dayScans.first),
        ),
      );
      return;
    }
    _showDaySheet(date, dayScans);
  }

  Future<void> _showDaySheet(DateTime date, List<Scan> dayScans) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => _DayDetailSheet(
        date: date,
        scans: dayScans,
        onScanTap: (scan) {
          Navigator.of(sheetCtx).pop();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ScanDetailScreen(scan: scan),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scansByDay = _indexScansByDay(ScanService.instance.scans);
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
                  onDayTap: _handleDayTap,
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
  final Map<DateTime, List<Scan>> scansByDay;
  final DateTime today;
  final void Function(DateTime date, List<Scan> dayScans) onDayTap;

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
        final dayScans = scansByDay[dateKey] ?? const <Scan>[];
        // The cell displays one "representative" scan per day; when extras
        // exist, a "+N" badge tells the user there's more behind the tap.
        final rep = dayScans.isEmpty ? null : _pickRepresentative(dayScans);
        return _CalendarCell(
          date: date,
          representative: rep,
          extrasCount: dayScans.isEmpty ? 0 : dayScans.length - 1,
          inMonth: inMonth,
          isToday: dateKey == today,
          onTap: () => onDayTap(date, dayScans),
        );
      },
    );
  }
}

/// Picks the scan to "represent" a day on the calendar grid.
///
/// Policy: worst severity wins (higher cookGrade) so the calendar honestly
/// surfaces bad days; tiebreak by most-recent takenAt so the latest
/// scan-of-the-day wins among equals. Trend visibility matters more than
/// chronological accuracy here — the bottom sheet shows everyone.
Scan _pickRepresentative(List<Scan> dayScans) {
  return dayScans.reduce((a, b) {
    if (a.cookGrade != b.cookGrade) {
      return a.cookGrade > b.cookGrade ? a : b;
    }
    return a.takenAt.isAfter(b.takenAt) ? a : b;
  });
}

// ===== Single cell =====

class _CalendarCell extends StatelessWidget {
  const _CalendarCell({
    required this.date,
    required this.representative,
    required this.extrasCount,
    required this.inMonth,
    required this.isToday,
    required this.onTap,
  });

  final DateTime date;

  /// The scan visually represented in this cell (worst-grade of the day).
  /// Null when the day has no scans.
  final Scan? representative;

  /// Number of scans on this day BEYOND the representative. When > 0, a
  /// small "+N" badge appears in the cell's top-right corner.
  final int extrasCount;

  final bool inMonth;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasScan = representative != null;
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
                    ? _ScanCellBackground(scan: representative!)
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
              // Multi-scan badge (top-right) — only when extras exist.
              if (hasScan && extrasCount > 0)
                Positioned(
                  top: 4,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      '+$extrasCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
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
                      'G${representative!.cookGrade}',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: representative!.severityColor,
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

// ===== Day-detail bottom sheet =====

/// Modal sheet shown when a calendar cell with 2+ scans is tapped. Lists
/// every scan from that day in newest-first order; each row taps through
/// to the full ScanDetailScreen.
class _DayDetailSheet extends StatelessWidget {
  const _DayDetailSheet({
    required this.date,
    required this.scans,
    required this.onScanTap,
  });

  final DateTime date;
  final List<Scan> scans;
  final void Function(Scan scan) onScanTap;

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String _formattedDate() =>
      '${_monthNames[date.month - 1]} ${date.day}, ${date.year}';

  /// The day's scans that belong to a guided per-region session (non-null
  /// session_id). When there are 2+, we surface a consolidated facial
  /// summary so the day's overall result is viewable after the fact, not
  /// only at capture time.
  List<Scan> get _sessionScans =>
      scans.where((s) => s.sessionId != null).toList();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle.
            Center(
              child: Container(
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: AppTheme.border(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      _formattedDate(),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Text(
                    '${scans.length} scan${scans.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: AppTheme.textSecondary(context),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Consolidated facial summary for the day's guided session — the
            // same overall result the patient saw at capture time, now
            // viewable later from the calendar.
            if (_sessionScans.length >= 2) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FacialSummaryCard(scans: _sessionScans),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'SCANS THIS DAY',
                  style: TextStyle(
                    color: AppTheme.textSecondary(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(height: 4),
            ],
            // shrinkWrap keeps the sheet tight to its content; Flexible
            // caps the height when there are many scans so the sheet
            // doesn't push past the top of the screen.
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: scans.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final scan = scans[index];
                  return _DaySheetRow(
                    scan: scan,
                    onTap: () => onScanTap(scan),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DaySheetRow extends StatelessWidget {
  const _DaySheetRow({required this.scan, required this.onTap});
  final Scan scan;
  final VoidCallback onTap;

  String _formatTime(DateTime d) {
    final hour12 = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    final minute = d.minute.toString().padLeft(2, '0');
    return '$hour12:$minute $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = scan.imageUrl;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Severity-colored "frame" around the image — uses padding +
              // a child ClipRRect rather than BoxDecoration.border so the
              // image's rounded corners aren't clipped against a hard edge.
              Container(
                width: 56,
                height: 56,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: scan.severityColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: imageUrl != null
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _DaySheetThumbPlaceholder(
                            color: scan.severityColor,
                          ),
                        )
                      : _DaySheetThumbPlaceholder(color: scan.severityColor),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatTime(scan.takenAt),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${scan.severityLabel} • Cook ${scan.cookGrade}',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: AppTheme.textSecondary(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DaySheetThumbPlaceholder extends StatelessWidget {
  const _DaySheetThumbPlaceholder({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color.withValues(alpha: 0.35),
      alignment: Alignment.center,
      child: const Icon(Icons.face_outlined, color: Colors.white, size: 28),
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
