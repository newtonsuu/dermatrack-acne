import 'package:flutter/material.dart';

import '../data/severity_guidance.dart';
import '../models/scan.dart';
import '../theme/app_theme.dart';

/// Reusable card that summarizes a set of per-region scans into a per-region
/// tier list plus an **overall facial acne severity**.
///
/// The overall tier is the **worst** region's tier (the most-affected zone
/// drives the headline) — a conservative monitoring heuristic that never
/// understates what the patient should watch. Used by the guided session's
/// completion screen and by the calendar day sheet, so a past session's
/// overall result stays viewable later, not just at capture time.
///
/// Robust to duplicate regions (e.g. two sessions in one day): it keeps the
/// worst scan per region and orders rows by [kScanSessionRegions].
class FacialSummaryCard extends StatelessWidget {
  const FacialSummaryCard({
    super.key,
    required this.scans,
    this.showDisclaimer = true,
    this.title = 'Facial acne summary',
  });

  /// The region scans to summarize. Typically the 5 zones of one session.
  final List<Scan> scans;

  /// Whether to show the "monitoring support only" footer line.
  final bool showDisclaimer;

  /// Card header label.
  final String title;

  @override
  Widget build(BuildContext context) {
    final perRegion = _worstPerRegion(scans);
    final tier = _overallTier(perRegion.values);
    final guidance = SeverityGuidance.forTier(tier);
    final overallText = tier == SeverityTier.clear
        ? 'Clear — no active acne detected'
        : '${tier.label} Acne Severity';

    // Order rows by the canonical capture order, then any extra regions
    // (e.g. a full_face quick scan) last.
    final ordered = <Scan>[
      for (final r in kScanSessionRegions)
        if (perRegion.containsKey(r)) perRegion[r]!,
      for (final entry in perRegion.entries)
        if (!kScanSessionRegions.contains(entry.key)) entry.value,
    ];

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
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final scan in ordered)
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
                  SeverityTierChip(
                    cookGrade: scan.cookGrade,
                    severityLabel: scan.severityLabel,
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(
                height: 1, color: guidance.color.withValues(alpha: 0.25)),
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
          if (showDisclaimer) ...[
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
        ],
      ),
    );
  }

  /// Keeps the worst scan (highest Cook grade) for each region.
  static Map<ScanRegion, Scan> _worstPerRegion(List<Scan> scans) {
    final map = <ScanRegion, Scan>{};
    for (final s in scans) {
      final existing = map[s.region];
      if (existing == null || s.cookGrade > existing.cookGrade) {
        map[s.region] = s;
      }
    }
    return map;
  }

  static SeverityTier _overallTier(Iterable<Scan> scans) {
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
/// Severe), derived from its Cook grade. Shared across the session summary and
/// the per-region breakdown.
class SeverityTierChip extends StatelessWidget {
  const SeverityTierChip({
    super.key,
    required this.cookGrade,
    required this.severityLabel,
  });

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
