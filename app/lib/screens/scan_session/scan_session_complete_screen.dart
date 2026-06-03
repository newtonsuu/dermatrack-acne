import 'package:flutter/material.dart';

import '../../data/severity_guidance.dart';
import '../../models/scan.dart';
import '../../theme/app_theme.dart';
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
            _OverallSummaryCard(scans: scans),
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
                        _TierChip(
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

/// Computes the overall facial severity from the captured region scans and
/// presents it as a per-region list + headline "Overall Result", plus the
/// guidance for that tier.
///
/// The overall tier is the **worst** region's tier (the most affected zone
/// drives the headline) — a conservative monitoring heuristic that matches
/// how a clinician reads regional distribution, and never *understates*
/// what the patient should keep an eye on.
class _OverallSummaryCard extends StatelessWidget {
  const _OverallSummaryCard({required this.scans});
  final List<Scan> scans;

  @override
  Widget build(BuildContext context) {
    final tier = _overallTier(scans);
    final guidance = SeverityGuidance.forTier(tier);
    final overallText = tier == SeverityTier.clear
        ? 'Clear — no active acne detected'
        : '${tier.label} Acne Severity';

    return Container(
      decoration: BoxDecoration(
        color: guidance.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: guidance.color.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.assessment_outlined, size: 18, color: guidance.color),
              const SizedBox(width: 8),
              Text(
                'Facial acne summary',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Per-region tiers (Forehead: Moderate, Left cheek: Mild, …).
          for (final scan in scans)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      scan.region.label,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                  ),
                  _TierChip(
                    cookGrade: scan.cookGrade,
                    severityLabel: scan.severityLabel,
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: guidance.color.withValues(alpha: 0.25)),
          ),
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: guidance.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Overall Result: $overallText',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            guidance.recommendation,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'For monitoring support only — not a medical diagnosis.',
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: AppTheme.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }

  static SeverityTier _overallTier(List<Scan> scans) {
    var worst = SeverityTier.clear;
    for (final s in scans) {
      final t = SeverityGuidance.tierFor(
        cookGrade: s.cookGrade,
        severityLabel: s.severityLabel,
      );
      if (t.rank > worst.rank) worst = t;
    }
    return worst;
  }
}

/// Small colored pill showing a scan's coarse tier (Clear / Mild / Moderate /
/// Severe), derived from its Cook grade.
class _TierChip extends StatelessWidget {
  const _TierChip({required this.cookGrade, required this.severityLabel});
  final int cookGrade;
  final String severityLabel;

  @override
  Widget build(BuildContext context) {
    final tier = SeverityGuidance.tierFor(
      cookGrade: cookGrade,
      severityLabel: severityLabel,
    );
    final guidance = SeverityGuidance.forTier(tier);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: guidance.color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: guidance.color.withValues(alpha: 0.5)),
      ),
      child: Text(
        tier.label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: guidance.color,
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
