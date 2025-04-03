// Unit tests for SeverityGuidance — the patient-facing Mild/Moderate/Severe
// classification + guidance derived from the Cook 0-8 grade. This is the core
// decision logic behind the full-face result and the per-region overall
// summary, so the tier boundaries are pinned here.

import 'package:flutter_test/flutter_test.dart';
import 'package:dermatrack/data/severity_guidance.dart';

void main() {
  group('SeverityGuidance.tierFor (Cook grade boundaries)', () {
    SeverityTier tier(int cook, [String label = '']) =>
        SeverityGuidance.tierFor(cookGrade: cook, severityLabel: label);

    test('Cook 0 → Clear', () => expect(tier(0), SeverityTier.clear));
    test('Cook 1 → Mild', () => expect(tier(1), SeverityTier.mild));
    test('Cook 2 → Mild', () => expect(tier(2), SeverityTier.mild));
    test('Cook 3 → Moderate', () => expect(tier(3), SeverityTier.moderate));
    test('Cook 4 → Moderate', () => expect(tier(4), SeverityTier.moderate));
    test('Cook 5 → Severe', () => expect(tier(5), SeverityTier.severe));
    test('Cook 8 → Severe', () => expect(tier(8), SeverityTier.severe));

    test('negative Cook falls back to the label', () {
      expect(tier(-1, 'Clear'), SeverityTier.clear);
      expect(tier(-1, 'Mild'), SeverityTier.mild);
      expect(tier(-1, 'Moderate'), SeverityTier.moderate);
      expect(tier(-1, 'Severe'), SeverityTier.severe);
      // "Very Severe" collapses into Severe via the substring match.
      expect(tier(-1, 'Very Severe'), SeverityTier.severe);
      // Unknown/empty label defaults to Clear when there's no grade.
      expect(tier(-1, ''), SeverityTier.clear);
    });
  });

  group('SeverityGuidance.forTier (content + doctor nudge)', () {
    test('tier label matches the enum label', () {
      for (final t in SeverityTier.values) {
        expect(SeverityGuidance.forTier(t).tierLabel, t.label);
        expect(SeverityGuidance.forTier(t).tier, t);
      }
    });

    test('Moderate and Severe urge a doctor review; Mild and Clear do not', () {
      expect(SeverityGuidance.forTier(SeverityTier.clear).urgeDoctorReview,
          isFalse);
      expect(
          SeverityGuidance.forTier(SeverityTier.mild).urgeDoctorReview, isFalse);
      expect(SeverityGuidance.forTier(SeverityTier.moderate).urgeDoctorReview,
          isTrue);
      expect(SeverityGuidance.forTier(SeverityTier.severe).urgeDoctorReview,
          isTrue);
    });

    test('every tier provides non-empty headline + body + recommendation', () {
      for (final t in SeverityTier.values) {
        final g = SeverityGuidance.forTier(t);
        expect(g.headline, isNotEmpty);
        expect(g.body, isNotEmpty);
        expect(g.recommendation, isNotEmpty);
      }
    });
  });

  group('SeverityTier.rank (drives worst-region overall summary)', () {
    test('ranks strictly increase clear < mild < moderate < severe', () {
      expect(SeverityTier.clear.rank, lessThan(SeverityTier.mild.rank));
      expect(SeverityTier.mild.rank, lessThan(SeverityTier.moderate.rank));
      expect(SeverityTier.moderate.rank, lessThan(SeverityTier.severe.rank));
    });
  });

  group('SeverityGuidance.fromScan', () {
    test('delegates to tierFor + forTier consistently', () {
      final g = SeverityGuidance.fromScan(cookGrade: 4, severityLabel: 'Moderate');
      expect(g.tier, SeverityTier.moderate);
      expect(g.urgeDoctorReview, isTrue);
    });
  });
}
