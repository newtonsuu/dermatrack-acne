import 'package:flutter/material.dart';

import '../../models/scan.dart';
import '../../theme/app_theme.dart';
import '../../widgets/facial_summary_card.dart';
import '../../widgets/scan_thumbnail.dart';
import '../scan_detail_screen.dart';

/// End-of-session summary shown when the guided 5-step scan finishes (or
/// when the patient aborts after capturing at least one region).
///
/// Per-region card with thumbnail + grade chip. Tap any card to open the
/// patient-side ScanDetailScreen for that region. "Done" returns to the
/// dashboard, where the new scans are already visible because ScanService
/// prepended them to the in-memory list as they were captured.
///
/// Intentionally minimal: this is a confirmation, not a primary surface.
/// The dashboard remains the home for ongoing engagement.
class ScanSessionCompleteScreen extends StatelessWidget {
  const ScanSessionCompleteScreen({super.key, required this.scans});

  final List<Scan> scans;

  @override
  Widget build(BuildContext context) {
    final regionsCaptured = scans.length;
    final regionsTotal = kScanSessionRegions.length;
    final isFullSession = regionsCaptured == regionsTotal;

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        title: const Text('Daily scan complete'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          _SummaryHeader(
            regionsCaptured: regionsCaptured,
            regionsTotal: regionsTotal,
            isFullSession: isFullSession,
          ),
          const SizedBox(height: 20),
          if (scans.isEmpty)
            _EmptyCard()
          else ...[
            FacialSummaryCard(scans: scans),
            const SizedBox(height: 20),
            const _SectionLabel('Region breakdown'),
            const SizedBox(height: 10),
            _RegionGrid(scans: scans),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({
    required this.regionsCaptured,
    required this.regionsTotal,
    required this.isFullSession,
  });

  final int regionsCaptured;
  final int regionsTotal;
  final bool isFullSession;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isFullSession
                    ? Icons.check_circle_outline
                    : Icons.timelapse_outlined,
                color: AppTheme.primary,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isFullSession
                        ? "Today's scan complete"
                        : 'Session saved',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isFullSession
                        ? 'All $regionsTotal regions captured. Your trend chart and calendar now include these scans.'
                        : '$regionsCaptured of $regionsTotal regions captured. You can run another session whenever you want to fill in the rest.',
                    style: TextStyle(
                      color: AppTheme.textSecondary(context),
                      fontSize: 13,
                      height: 1.4,
                    ),
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

class _RegionGrid extends StatelessWidget {
  const _RegionGrid({required this.scans});
  final List<Scan> scans;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final scan in scans) ...[
          _RegionTile(scan: scan),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _RegionTile extends StatelessWidget {
  const _RegionTile({required this.scan});
  final Scan scan;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ScanDetailScreen(scan: scan),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              ScanThumbnail(scan: scan, width: 72),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            scan.region.label,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary(context),
                            ),
                          ),
                        ),
                        SeverityTierChip(
                          cookGrade: scan.cookGrade,
                          severityLabel: scan.severityLabel,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Inflammatory ${scan.inflammatoryCount} · '
                      'Non-inflam. ${scan.nonInflammatoryCount} · '
                      'Post-acne ${scan.postAcneCount}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: AppTheme.textSecondary(context), size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: AppTheme.textSecondary(context)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No regions were captured in this session.',
                style: TextStyle(color: AppTheme.textSecondary(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: AppTheme.textSecondary(context),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
      ),
    );
  }
}
