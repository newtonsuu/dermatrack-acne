import 'package:flutter/foundation.dart';

/// Dermatologist-authored, patient-level treatment plan. Maps 1:1 to a row
/// in `public.treatment_plans` (see migration 0006). One current plan per
/// patient; the doctor edits it in place.
@immutable
class TreatmentPlan {
  const TreatmentPlan({
    required this.userId,
    required this.plan,
    this.updatedAt,
  });

  /// The patient this plan belongs to (`treatment_plans.user_id`).
  final String userId;

  /// Free-text regimen / follow-up guidance. Always non-empty for a row that
  /// exists (the table has a non-blank CHECK); absence of a row means "no
  /// plan yet".
  final String plan;

  /// When the plan was last edited. Null only if the row predates the column
  /// somehow; defensive.
  final DateTime? updatedAt;

  factory TreatmentPlan.fromRow(Map<String, dynamic> row) {
    final updatedRaw = row['updated_at'] as String?;
    return TreatmentPlan(
      userId: row['user_id'] as String,
      plan: (row['plan'] as String?)?.trim() ?? '',
      updatedAt:
          updatedRaw != null ? DateTime.parse(updatedRaw).toLocal() : null,
    );
  }
}
