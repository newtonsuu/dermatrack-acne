import 'package:flutter/material.dart';

/// Coarse, patient-facing severity tier.
///
/// The analysis pipeline produces a 0–8 Cook grade and a 5-label severity
/// string (Clear / Mild / Moderate / Severe / Very Severe). For the
/// patient-facing result and the per-region summary we collapse that to the
/// three actionable tiers the product speaks in — **Mild, Moderate, Severe** —
/// plus a Clear state for no active acne. This keeps the result legible
/// ("Moderate Acne Severity") while the precise Cook grade stays available as
/// a detail.
enum SeverityTier {
  clear('Clear', 0),
  mild('Mild', 1),
  moderate('Moderate', 2),
  severe('Severe', 3);

  const SeverityTier(this.label, this.rank);

  /// Display label.
  final String label;

  /// Monotonic rank used to pick the worst tier across regions (higher =
  /// more severe).
  final int rank;
}

/// Patient-facing guidance derived from a scan's severity.
///
/// Deliberately supportive and non-prescriptive — DermaTrack is a
/// monitoring-support tool, not a diagnostic device — so guidance points to
/// self-care habits and, for the higher tiers, to consulting a licensed
/// dermatologist. It never recommends specific medication.
class SeverityGuidance {
  const SeverityGuidance({
    required this.tier,
    required this.headline,
    required this.body,
    required this.recommendation,
    required this.urgeDoctorReview,
    required this.color,
  });

  final SeverityTier tier;

  /// One-line plain-language read of the result.
  final String headline;

  /// 1–2 sentence explanation of what the tier means for monitoring.
  final String body;

  /// Short, actionable next-step (self-care, or "consider a dermatologist").
  final String recommendation;

  /// True for moderate/severe — the UI nudges toward doctor review/sharing.
  final bool urgeDoctorReview;

  /// Tier accent color, consistent with the severity badge palette.
  final Color color;

  String get tierLabel => tier.label;

  /// Maps a Cook grade (-1..8) and the pipeline's severity label to a tier +
  /// guidance. The Cook grade is the primary signal; the label is the
  /// fallback when no grade is present (cookGrade < 0).
  factory SeverityGuidance.fromScan({
    required int cookGrade,
    required String severityLabel,
  }) {
    return SeverityGuidance.forTier(
      tierFor(cookGrade: cookGrade, severityLabel: severityLabel),
    );
  }

  /// Guidance content for a given tier.
  factory SeverityGuidance.forTier(SeverityTier tier) {
    switch (tier) {
      case SeverityTier.clear:
        return const SeverityGuidance(
          tier: SeverityTier.clear,
          headline: 'No active acne detected',
          body: 'This scan looks clear. Keeping a consistent daily scan habit '
              'is the best way to catch changes early.',
          recommendation: 'Keep up your current routine and keep scanning '
              'regularly to track your skin over time.',
          urgeDoctorReview: false,
          color: Color(0xFF4CAF50),
        );
      case SeverityTier.mild:
        return const SeverityGuidance(
          tier: SeverityTier.mild,
          headline: 'Mild acne severity',
          body: 'A small number of lesions were detected. Mild changes are '
              'common and often respond well to a gentle, consistent routine.',
          recommendation: 'Cleanse gently twice a day, avoid picking, and keep '
              'scanning. If it steadily worsens over a week or two, consider '
              'seeing a dermatologist.',
          urgeDoctorReview: false,
          color: Color(0xFF8BC34A),
        );
      case SeverityTier.moderate:
        return const SeverityGuidance(
          tier: SeverityTier.moderate,
          headline: 'Moderate acne severity',
          body: 'Several lesions were detected in this scan. Tracking how this '
              'trends over the next few days shows whether it is settling or '
              'building.',
          recommendation: 'Keep scanning every 2–3 days to monitor the trend. '
              'If it persists or increases, a dermatologist review is a good '
              'next step — you can share your scans from Privacy & Data.',
          urgeDoctorReview: true,
          color: Color(0xFFFFB300),
        );
      case SeverityTier.severe:
        return const SeverityGuidance(
          tier: SeverityTier.severe,
          headline: 'Severe acne severity',
          body: 'A high number of lesions were detected. Monitoring on its own '
              'may not be enough at this level.',
          recommendation: 'Consider consulting a licensed dermatologist soon. '
              'Turn on “Share with dermatologist” so your doctor can review '
              'your scan history, and keep scanning to document changes.',
          urgeDoctorReview: true,
          color: Color(0xFFF44336),
        );
    }
  }

  /// Collapses the Cook grade / severity label into a [SeverityTier].
  static SeverityTier tierFor({
    required int cookGrade,
    required String severityLabel,
  }) {
    if (cookGrade >= 0) {
      // Cook 0 = clear, 1–2 = mild, 3–4 = moderate, 5–8 = severe
      // (collapsing "Severe" and "Very Severe").
      if (cookGrade == 0) return SeverityTier.clear;
      if (cookGrade <= 2) return SeverityTier.mild;
      if (cookGrade <= 4) return SeverityTier.moderate;
      return SeverityTier.severe;
    }
    // cookGrade < 0 → no numeric grade; fall back to the label.
    final l = severityLabel.toLowerCase();
    if (l.contains('moderate')) return SeverityTier.moderate;
    if (l.contains('severe')) return SeverityTier.severe;
    if (l.contains('mild')) return SeverityTier.mild;
    return SeverityTier.clear;
  }
}
