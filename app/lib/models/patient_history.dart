import 'package:flutter/foundation.dart';

// ============================================
// Canonical checkbox values
// ============================================
//
// These const lists are the single source of truth for the allowed values
// in `public.patient_histories.past_medical_conditions`,
// `family_history_conditions`, and `personal_social_history`. They mirror
// the OPD Medical Record form Dr. Christine Ann Olivete-Agdamag uses at
// her aesthetic dermatology clinic.
//
// Wire format (the strings actually written to Postgres) is intentionally
// snake_case and stable forever — don't rename without a migration.
//
// Human-readable labels are paired here so the form widget can render
// "Cardiovascular Disease" while storing "cardiovascular_disease".

/// Past medical history (multi-select). Order matches the OPD form's
/// left-to-right reading order — left column first, then right.
const Map<String, String> kPastMedicalConditions = {
  'hypertension': 'Hypertension',
  'diabetes': 'Diabetes',
  'cardiovascular_disease': 'Cardiovascular Disease',
  'cancer': 'Cancer',
  'thyroid_disease': 'Thyroid Disease',
  'asthma': 'Asthma',
  'allergies': 'Allergies',
};

/// Family history (multi-select). Kidney disease appears here on the form
/// but not in past medical history — that's faithful to the original.
const Map<String, String> kFamilyHistoryConditions = {
  'hypertension': 'Hypertension',
  'diabetes': 'Diabetes',
  'cardiovascular_disease': 'Cardiovascular Disease',
  'cancer': 'Cancer',
  'thyroid_disease': 'Thyroid Disease',
  'asthma': 'Asthma',
  'kidney_disease': 'Kidney Disease',
};

/// Sex options. 'prefer_not_to_say' is added on top of the form's
/// male/female because the patient profile screen should be non-coercive.
const Map<String, String> kSexOptions = {
  'male': 'Male',
  'female': 'Female',
  'other': 'Other',
  'prefer_not_to_say': 'Prefer not to say',
};

// ============================================
// Model
// ============================================

/// Patient's clinical intake history. One row per user, mirroring
/// `public.patient_histories`. All fields are optional from the patient's
/// perspective — the form lets them save with zero fields filled.
///
/// `null` for a scalar field means "not provided". An empty list for the
/// multi-select fields means "nothing ticked" (NOT `null`, because the
/// SQL column is NOT NULL DEFAULT '{}'::text[]).
///
/// Use [PatientHistoryService.upsert] to persist changes.
@immutable
class PatientHistory {
  const PatientHistory({
    this.fullName,
    this.address,
    this.birthday,
    this.sex,
    this.occupation,
    this.contactNo,
    this.pastMedicalConditions = const [],
    this.pastMedicalOthers,
    this.previousSurgeryDetail,
    this.allergiesDetail,
    this.familyHistoryConditions = const [],
    this.familyHistoryOthers,
    this.smokerPackYears,
    this.usesProhibitedDrugs = false,
    this.isAlcoholDrinker = false,
    this.socialOthers,
    this.currentMedications,
    this.createdAt,
    this.updatedAt,
  });

  /// An entirely blank history. Used as the starting point when the
  /// patient first opens the form on an account with no row yet.
  static const PatientHistory empty = PatientHistory();

  // ----- Demographics -----
  final String? fullName;
  final String? address;
  final DateTime? birthday;

  /// One of [kSexOptions] keys or null.
  final String? sex;
  final String? occupation;
  final String? contactNo;

  // ----- Past medical history -----
  /// Selected keys from [kPastMedicalConditions]. Order is meaningless;
  /// the form widget renders by the canonical order in the const map.
  final List<String> pastMedicalConditions;
  final String? pastMedicalOthers;
  final String? previousSurgeryDetail;
  final String? allergiesDetail;

  // ----- Family history -----
  /// Selected keys from [kFamilyHistoryConditions].
  final List<String> familyHistoryConditions;
  final String? familyHistoryOthers;

  // ----- Personal and social history -----
  /// NULL = non-smoker. Otherwise pack-years (numeric).
  final double? smokerPackYears;
  final bool usesProhibitedDrugs;
  final bool isAlcoholDrinker;
  final String? socialOthers;

  // ----- Current medications -----
  final String? currentMedications;

  // ----- Server timestamps (read-only; set by Postgres on upsert) -----
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // ----- Completion state for the profile-card badge -----

  /// Whether the patient has filled in any field at all. Used to drive
  /// the "Not started" vs "Demographics only" vs "Complete" badge on
  /// the profile screen.
  PatientHistoryCompletion get completion {
    final hasDemographics = (fullName ?? '').trim().isNotEmpty ||
        (address ?? '').trim().isNotEmpty ||
        birthday != null ||
        sex != null ||
        (occupation ?? '').trim().isNotEmpty ||
        (contactNo ?? '').trim().isNotEmpty;
    final hasClinical = pastMedicalConditions.isNotEmpty ||
        familyHistoryConditions.isNotEmpty ||
        (pastMedicalOthers ?? '').trim().isNotEmpty ||
        (previousSurgeryDetail ?? '').trim().isNotEmpty ||
        (allergiesDetail ?? '').trim().isNotEmpty ||
        (familyHistoryOthers ?? '').trim().isNotEmpty ||
        smokerPackYears != null ||
        usesProhibitedDrugs ||
        isAlcoholDrinker ||
        (socialOthers ?? '').trim().isNotEmpty ||
        (currentMedications ?? '').trim().isNotEmpty;

    if (!hasDemographics && !hasClinical) {
      return PatientHistoryCompletion.notStarted;
    }
    if (hasDemographics && !hasClinical) {
      return PatientHistoryCompletion.demographicsOnly;
    }
    if (!hasDemographics && hasClinical) {
      return PatientHistoryCompletion.clinicalOnly;
    }
    return PatientHistoryCompletion.complete;
  }

  // ----- Serialization -----

  factory PatientHistory.fromRow(Map<String, dynamic> row) {
    DateTime? parseDate(dynamic v) =>
        v is String && v.isNotEmpty ? DateTime.parse(v) : null;

    List<String> parseStringList(dynamic v) {
      if (v is List) {
        return v.whereType<String>().toList(growable: false);
      }
      return const [];
    }

    return PatientHistory(
      fullName: row['full_name'] as String?,
      address: row['address'] as String?,
      birthday: parseDate(row['birthday']),
      sex: row['sex'] as String?,
      occupation: row['occupation'] as String?,
      contactNo: row['contact_no'] as String?,
      pastMedicalConditions: parseStringList(row['past_medical_conditions']),
      pastMedicalOthers: row['past_medical_others'] as String?,
      previousSurgeryDetail: row['previous_surgery_detail'] as String?,
      allergiesDetail: row['allergies_detail'] as String?,
      familyHistoryConditions: parseStringList(row['family_history_conditions']),
      familyHistoryOthers: row['family_history_others'] as String?,
      smokerPackYears: (row['smoker_pack_years'] as num?)?.toDouble(),
      usesProhibitedDrugs:
          (row['uses_prohibited_drugs'] as bool?) ?? false,
      isAlcoholDrinker: (row['is_alcohol_drinker'] as bool?) ?? false,
      socialOthers: row['social_others'] as String?,
      currentMedications: row['current_medications'] as String?,
      createdAt: parseDate(row['created_at']),
      updatedAt: parseDate(row['updated_at']),
    );
  }

  /// Payload for `INSERT … ON CONFLICT` against `patient_histories`. The
  /// caller adds `user_id` separately (the service knows the current
  /// auth.uid()). Blank strings are stored as NULL so the UI can render
  /// "not provided" cleanly.
  Map<String, dynamic> toUpsertJson() {
    String? blank(String? s) {
      if (s == null) return null;
      final t = s.trim();
      return t.isEmpty ? null : t;
    }

    return {
      'full_name': blank(fullName),
      'address': blank(address),
      'birthday': birthday?.toIso8601String().split('T').first,
      'sex': sex,
      'occupation': blank(occupation),
      'contact_no': blank(contactNo),
      'past_medical_conditions': pastMedicalConditions,
      'past_medical_others': blank(pastMedicalOthers),
      'previous_surgery_detail': blank(previousSurgeryDetail),
      'allergies_detail': blank(allergiesDetail),
      'family_history_conditions': familyHistoryConditions,
      'family_history_others': blank(familyHistoryOthers),
      'smoker_pack_years': smokerPackYears,
      'uses_prohibited_drugs': usesProhibitedDrugs,
      'is_alcohol_drinker': isAlcoholDrinker,
      'social_others': blank(socialOthers),
      'current_medications': blank(currentMedications),
    };
  }

  // ----- copyWith -----
  //
  // Field overrides use a sentinel object (`_Unset`) so the caller can
  // explicitly pass `null` to clear a field. This is the cleanest pattern
  // for nullable copyWith in Dart without a code generator.

  PatientHistory copyWith({
    Object? fullName = _unset,
    Object? address = _unset,
    Object? birthday = _unset,
    Object? sex = _unset,
    Object? occupation = _unset,
    Object? contactNo = _unset,
    List<String>? pastMedicalConditions,
    Object? pastMedicalOthers = _unset,
    Object? previousSurgeryDetail = _unset,
    Object? allergiesDetail = _unset,
    List<String>? familyHistoryConditions,
    Object? familyHistoryOthers = _unset,
    Object? smokerPackYears = _unset,
    bool? usesProhibitedDrugs,
    bool? isAlcoholDrinker,
    Object? socialOthers = _unset,
    Object? currentMedications = _unset,
  }) {
    return PatientHistory(
      fullName: identical(fullName, _unset) ? this.fullName : fullName as String?,
      address: identical(address, _unset) ? this.address : address as String?,
      birthday: identical(birthday, _unset) ? this.birthday : birthday as DateTime?,
      sex: identical(sex, _unset) ? this.sex : sex as String?,
      occupation:
          identical(occupation, _unset) ? this.occupation : occupation as String?,
      contactNo:
          identical(contactNo, _unset) ? this.contactNo : contactNo as String?,
      pastMedicalConditions:
          pastMedicalConditions ?? this.pastMedicalConditions,
      pastMedicalOthers: identical(pastMedicalOthers, _unset)
          ? this.pastMedicalOthers
          : pastMedicalOthers as String?,
      previousSurgeryDetail: identical(previousSurgeryDetail, _unset)
          ? this.previousSurgeryDetail
          : previousSurgeryDetail as String?,
      allergiesDetail: identical(allergiesDetail, _unset)
          ? this.allergiesDetail
          : allergiesDetail as String?,
      familyHistoryConditions:
          familyHistoryConditions ?? this.familyHistoryConditions,
      familyHistoryOthers: identical(familyHistoryOthers, _unset)
          ? this.familyHistoryOthers
          : familyHistoryOthers as String?,
      smokerPackYears: identical(smokerPackYears, _unset)
          ? this.smokerPackYears
          : smokerPackYears as double?,
      usesProhibitedDrugs: usesProhibitedDrugs ?? this.usesProhibitedDrugs,
      isAlcoholDrinker: isAlcoholDrinker ?? this.isAlcoholDrinker,
      socialOthers: identical(socialOthers, _unset)
          ? this.socialOthers
          : socialOthers as String?,
      currentMedications: identical(currentMedications, _unset)
          ? this.currentMedications
          : currentMedications as String?,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

/// Sentinel for `copyWith` so explicit `null` is distinguishable from
/// "omitted" without a generated builder.
const Object _unset = Object();

/// Drives the profile-card badge. Order matches "least filled → most".
enum PatientHistoryCompletion {
  notStarted,
  demographicsOnly,
  clinicalOnly,
  complete,
}
