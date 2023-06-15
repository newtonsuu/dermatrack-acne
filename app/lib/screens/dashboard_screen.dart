import 'package:flutter/material.dart';

import '../models/scan.dart';
import '../services/auth_service.dart';
import '../services/scan_service.dart';
import '../theme/app_theme.dart';
import '../widgets/scan_thumbnail.dart';
import '../widgets/severity_trend_chart.dart';
import '../widgets/user_avatar_action.dart';
import 'camera_screen.dart';
import 'gallery_screen.dart';
import 'scan_detail_screen.dart';
import 'scan_session/scan_session_screen.dart';

/// Home/dashboard. The first surface a logged-in user sees.
///
/// Listens to ScanService so the progress stats and recent-scans row stay
/// fresh — newly-submitted scans pop in without the user having to back
/// out and re-enter the tab.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    final firstName = (user?.displayName ?? 'there').split(' ').first;
    final scans = ScanService.instance.scans;
    final recent = ScanService.instance.recentScans();

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        title: const Text('DermaTrack'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Notifications — coming soon')),
              );
            },
          ),
          const UserAvatarAction(),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            'Hi, $firstName',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Ready for today’s skin check?',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          // Primary CTA — the guided 5-region daily scan session, which is
          // what the dermatologist confirmed on 2026-05-25 is the right
          // basis for longitudinal acne tracking.
          _DailySessionCard(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ScanSessionScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          // Secondary — the existing single-shot flow remains available
          // for quick spot-checks. De-emphasized via TextButton + smaller
          // type so the daily session feels like the canonical path.
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CameraScreen()),
                );
              },
              icon: const Icon(Icons.camera_alt_outlined, size: 16),
              label: const Text('Quick single scan'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Your progress',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          _StatsRow(
            totalScans: scans.length,
            dayStreak: _computeDayStreak(scans),
            lastGrade: scans.isEmpty ? null : scans.first.severityLabel,
          ),
          // Trend chart only renders once the user has scans at all — no
          // point showing an empty chart card on a brand-new account when
          // the "Recent scans" section below already explains the empty
          // state. After the first scan, the chart card shows the user's
          // data taking shape.
          if (scans.isNotEmpty) ...[
            const SizedBox(height: 16),
            SeverityTrendChart(scans: scans),
          ],
          const SizedBox(height: 24),
          _SectionHeaderWithAction(
            title: 'Recent scans',
            actionLabel: scans.isEmpty ? null : 'View all',
            onAction: scans.isEmpty
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const GalleryScreen(),
                      ),
                    ),
          ),
          const SizedBox(height: 12),
          if (recent.isEmpty)
            const _EmptyRecentScans()
          else
            _RecentScansRow(scans: recent),
          const SizedBox(height: 24),
          Text(
            'Tips for you',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          for (final tip in _selectTips(scans)) ...[
            _TipCard(
              icon: tip.icon,
              title: tip.title,
              body: tip.body,
              accentColor: tip.accentColor,
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

/// Days-in-a-row of scanning, ending at the most recent scan day.
///
/// Forgiving: counts the run of consecutive days ending on the most-recent
/// scan day, as long as that day is today *or* yesterday. If the user
/// hasn't scanned in 2+ days the streak resets to zero. This way the
/// streak doesn't drop from 5 → 0 just because the user hasn't taken
/// today's scan yet at 9 AM — matches how habit-tracker apps usually feel.
int _computeDayStreak(List<Scan> scans) {
  if (scans.isEmpty) return 0;

  // Collect unique scan dates (midnight-keyed) so multiple scans per day
  // don't double-count.
  final dates = <DateTime>{};
  for (final s in scans) {
    dates.add(DateTime(s.takenAt.year, s.takenAt.month, s.takenAt.day));
  }
  if (dates.isEmpty) return 0;

  final mostRecent = dates.reduce((a, b) => a.isAfter(b) ? a : b);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final daysSinceLast = today.difference(mostRecent).inDays;

  // Streak broken if the latest scan was 2+ days ago.
  if (daysSinceLast > 1) return 0;

  // Walk backward day-by-day from the most recent scan day; stop at the
  // first gap.
  int streak = 0;
  DateTime cursor = mostRecent;
  while (dates.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

/// Primary dashboard CTA. Launches the guided 5-step daily scan session
/// (forehead → left cheek → right cheek → chin → full face). Designed to
/// look prominent against the rest of the dashboard so the patient's eye
/// lands on it first.
class _DailySessionCard extends StatelessWidget {
  const _DailySessionCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppTheme.primary, AppTheme.primaryDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.center_focus_strong,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Start daily scan',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "5 quick captures — forehead, cheeks, chin, full face.",
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                color: Colors.white70, size: 18),
          ],
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.totalScans,
    required this.dayStreak,
    required this.lastGrade,
  });

  final int totalScans;
  final int dayStreak;

  /// Most-recent scan's severity_label (e.g. "Clear", "Mild", "Very Severe").
  /// Null when the user has no scans yet — _StatCard renders "—" in that case.
  final String? lastGrade;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(label: 'Total scans', value: '$totalScans'),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(label: 'Day streak', value: '$dayStreak'),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(label: 'Last grade', value: lastGrade ?? '—'),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Column(
          children: [
            // FittedBox shrinks longer values (like "Very Severe") to fit
            // the card width — three-card row on narrow phones can be tight.
            SizedBox(
              height: 28,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// "Recent scans" header with an optional trailing "View all" link. Hides
/// the link when the user has no scans (no gallery to navigate to).
class _SectionHeaderWithAction extends StatelessWidget {
  const _SectionHeaderWithAction({
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

/// Horizontal scan-thumbnail strip mirroring the one on the profile screen.
/// Kept local rather than extracted because the empty-state styling differs.
class _RecentScansRow extends StatelessWidget {
  const _RecentScansRow({required this.scans});
  final List<Scan> scans;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 138,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: scans.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final scan = scans[index];
          return ScanThumbnail(
            scan: scan,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ScanDetailScreen(scan: scan),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyRecentScans extends StatelessWidget {
  const _EmptyRecentScans();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.history,
                  color: AppTheme.primary, size: 28),
            ),
            const SizedBox(height: 12),
            const Text(
              'No scans yet',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              'Take your first scan to start tracking your progress.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({
    required this.icon,
    required this.title,
    required this.body,
    this.accentColor,
  });

  final IconData icon;
  final String title;
  final String body;

  /// Override for the icon tint + tile color. Lets safety-prompt tips
  /// stand out from routine-advice tips. Falls back to AppTheme.accent.
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? AppTheme.accent;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== Personalized tip selection =====

/// Data for one tip card. Bundled-tip catalog at the bottom of the file
/// generates these dynamically based on the user's scan history.
class _TipData {
  const _TipData({
    required this.icon,
    required this.title,
    required this.body,
    this.accentColor,
    required this.priority,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color? accentColor;

  /// Higher = surfaced ahead of lower-priority tips. Used to rank when
  /// many candidates apply at once. 100 = safety, 80 = habit, 60 = trend,
  /// 40 = pattern, 10 = generic fallback.
  final int priority;
}

/// Pick the top tips for the dashboard from the user's scan history.
/// Returns up to 3 tips, sorted highest-priority first.
List<_TipData> _selectTips(List<Scan> scans) {
  final candidates = <_TipData>[];

  // ----- Safety tier (priority 100) -----
  // Highest-priority — surfaces when the most recent reading is in the
  // Severe / Very Severe range. Encourages professional consultation
  // without being prescriptive. Suppress on the very first scan since a
  // single noisy detection isn't enough to motivate this kind of nudge.
  if (scans.length >= 2 && scans.first.cookGrade >= 7) {
    candidates.add(const _TipData(
      icon: Icons.medical_services_outlined,
      title: 'Worth a dermatologist consult?',
      body:
          'Your last scan read as Very Severe. Persistent severe acne usually '
          'responds best to professional treatment.',
      accentColor: Color(0xFFE53935),
      priority: 100,
    ));
  } else if (scans.length >= 2 && scans.first.cookGrade >= 5) {
    candidates.add(const _TipData(
      icon: Icons.medical_services_outlined,
      title: 'Consider professional care',
      body:
          'Your last scan read as Severe. If grades stay elevated, a '
          'dermatologist can help you find a treatment that sticks.',
      accentColor: Color(0xFFEF6C00),
      priority: 100,
    ));
  }

  // ----- Habit tier (priority 80) -----
  // Reminds the user to scan when they've gone quiet. The day-streak
  // logic in the stats row uses 2-day reset; tip threshold is more
  // generous (3+ days) so we don't nag too often.
  if (scans.isNotEmpty) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastDay = DateTime(
      scans.first.takenAt.year,
      scans.first.takenAt.month,
      scans.first.takenAt.day,
    );
    final daysSince = today.difference(lastDay).inDays;
    if (daysSince >= 3) {
      candidates.add(_TipData(
        icon: Icons.alarm_outlined,
        title: 'Worth a scan today?',
        body:
            "It's been $daysSince days since your last check. Regular scans "
            'keep the trend chart honest.',
        priority: 80,
      ));
    }
  }

  // ----- Trend tier (priority 60) -----
  // Echoes the skin-summary card's trend logic (first-half vs second-half
  // avg, 0.5 cook-step delta). Only fires when we have 4+ scan days so a
  // single outlier doesn't trigger a false "trend".
  final trend = _computeShortTrend(scans);
  if (trend == _TrendDirection.improving) {
    candidates.add(const _TipData(
      icon: Icons.trending_down,
      title: "You're trending better",
      body:
          "Your last few scans average lower than the ones before — keep "
          'doing what you\'re doing.',
      accentColor: Color(0xFF43A047),
      priority: 60,
    ));
  } else if (trend == _TrendDirection.worsening) {
    candidates.add(const _TipData(
      icon: Icons.trending_up,
      title: 'Trend climbing',
      body:
          'Recent scans average higher than earlier ones. Worth thinking '
          'about what might have changed — products, sleep, diet, stress.',
      accentColor: Color(0xFFFF8F00),
      priority: 60,
    ));
  }

  // ----- Pattern tier (priority 40) -----
  // Looks at the lesion-bucket mix on the most recent scan. The advice
  // is intentionally light — we don't diagnose subtypes, just nudge in a
  // direction that matches the visible lesion type.
  if (scans.isNotEmpty) {
    final s = scans.first;
    final totalLesions =
        s.inflammatoryCount + s.nonInflammatoryCount + s.postAcneCount;
    if (totalLesions > 0) {
      // High post-acne share (≥ half the visible lesions).
      if (s.postAcneCount >= 2 && s.postAcneCount * 2 >= totalLesions) {
        candidates.add(const _TipData(
          icon: Icons.wb_sunny_outlined,
          title: 'SPF helps marks fade',
          body:
              'Your last scan showed several post-acne marks. Daily '
              'SPF 30+ keeps them from darkening as they heal.',
          priority: 40,
        ));
      }
      // Mostly inflammatory.
      if (s.inflammatoryCount >= 2 &&
          s.inflammatoryCount * 2 >= totalLesions) {
        candidates.add(const _TipData(
          icon: Icons.spa_outlined,
          title: 'Be gentle while it heals',
          body:
              'Inflammatory lesions respond best to gentle cleansing and '
              'non-comedogenic moisturizer — harsh scrubbing makes them '
              'worse.',
          priority: 40,
        ));
      }
      // Mostly comedonal (non-inflammatory).
      if (s.nonInflammatoryCount >= 2 &&
          s.nonInflammatoryCount * 2 >= totalLesions) {
        candidates.add(const _TipData(
          icon: Icons.refresh,
          title: 'Comedones love consistency',
          body:
              'Clogged pores tend to respond to consistent gentle '
              'exfoliation more than aggressive one-off treatments.',
          priority: 40,
        ));
      }
    }
  }

  // ----- Generic fallbacks (priority 10) -----
  // Always-applicable advice for when the user has thin or unremarkable
  // data — keeps the Tips section from looking empty on a brand-new
  // account or a steady-state user with no patterns to call out.
  candidates.add(const _TipData(
    icon: Icons.wb_sunny_outlined,
    title: 'Use sunscreen daily',
    body:
        'SPF 30+ helps prevent post-acne dark spots from getting worse.',
    priority: 10,
  ));
  candidates.add(const _TipData(
    icon: Icons.water_drop_outlined,
    title: 'Stay hydrated',
    body: "Drinking enough water supports your skin's barrier.",
    priority: 10,
  ));

  // Sort by priority desc, then take up to 3 to avoid a wall of tips.
  candidates.sort((a, b) => b.priority.compareTo(a.priority));
  return candidates.take(3).toList(growable: false);
}

enum _TrendDirection { improving, steady, worsening, insufficient }

/// Same first-half-vs-second-half-average logic the skin-summary card
/// uses, just simplified to return a direction tag. Need 4+ scan-days
/// to fire; below that returns insufficient and the trend-tier tips
/// don't appear.
_TrendDirection _computeShortTrend(List<Scan> scans) {
  if (scans.length < 4) return _TrendDirection.insufficient;

  // Aggregate by day, worst-of-day wins (matches the rest of the app).
  final dayWorst = <DateTime, int>{};
  for (final s in scans) {
    final day = DateTime(s.takenAt.year, s.takenAt.month, s.takenAt.day);
    final v = dayWorst[day];
    if (v == null || s.cookGrade > v) {
      dayWorst[day] = s.cookGrade;
    }
  }
  if (dayWorst.length < 4) return _TrendDirection.insufficient;

  final sorted = dayWorst.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  final mid = sorted.length ~/ 2;
  final firstAvg = sorted.sublist(0, mid).map((e) => e.value).reduce(
        (a, b) => a + b,
      ) /
      mid;
  final secondAvg = sorted.sublist(mid).map((e) => e.value).reduce(
        (a, b) => a + b,
      ) /
      (sorted.length - mid);
  final delta = secondAvg - firstAvg;
  if (delta < -0.5) return _TrendDirection.improving;
  if (delta > 0.5) return _TrendDirection.worsening;
  return _TrendDirection.steady;
}
