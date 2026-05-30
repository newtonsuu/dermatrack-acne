-- DermaTrack — patient histories (clinical intake)
-- ============================================
-- One-row-per-user clinical intake form, modeled directly on the OPD
-- Medical Record form Dr. Christine Ann Olivete-Agdamag uses at her
-- aesthetic dermatology clinic (the dermatologist who's consulting on
-- this thesis). All fields are optional from the patient's perspective —
-- the goal is to give the dermatologist context when she has it, not to
-- force disclosure when she doesn't.
--
-- Visibility:
--   • Patient can read + write their own row.
--   • The demo doctor account can read rows for patients who have
--     toggled shared_with_doctor = true (see 0002_doctor_demo.sql).
--   • The doctor cannot write — patient history is patient-authored.
--
-- Run AFTER 0004_scan_regions.sql. Safe to re-run.
-- ============================================


-- ============================================
-- Table
-- ============================================
CREATE TABLE IF NOT EXISTS public.patient_histories (
    -- PK == auth.users(id). One history row per user, max. Cascade delete
    -- so removing an account wipes their clinical record cleanly.
    user_id                       uuid        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,

    -- ----- Demographics (top half of the OPD form) -----
    full_name                     text,
    address                       text,
    birthday                      date,
    sex                           text,    -- 'male' | 'female' | 'other' | 'prefer_not_to_say'
    occupation                    text,
    contact_no                    text,

    -- ----- Past medical history -----
    -- Array of canonical condition keys. Source of truth for the allowed
    -- values lives in app/lib/models/patient_history.dart
    -- (kPastMedicalConditions). Free-text "Others" and the surgery/
    -- hospitalization detail get their own columns.
    past_medical_conditions       text[]      NOT NULL DEFAULT '{}'::text[],
    past_medical_others           text,
    previous_surgery_detail       text,
    allergies_detail              text,

    -- ----- Family history -----
    family_history_conditions     text[]      NOT NULL DEFAULT '{}'::text[],
    family_history_others         text,

    -- ----- Personal and social history -----
    -- pack_years: NULL → non-smoker, 0+ → smoker with that pack-year count
    -- (the form has "Smoker: ___ Pack Years" with a numeric blank).
    smoker_pack_years             numeric,
    uses_prohibited_drugs         boolean     NOT NULL DEFAULT false,
    is_alcohol_drinker            boolean     NOT NULL DEFAULT false,
    social_others                 text,

    -- ----- Current medications (right column on the form) -----
    current_medications           text,

    -- ----- Bookkeeping -----
    created_at                    timestamptz NOT NULL DEFAULT now(),
    updated_at                    timestamptz NOT NULL DEFAULT now(),

    -- Sanity constraints
    CONSTRAINT patient_histories_sex_valid CHECK (
        sex IS NULL OR sex IN ('male', 'female', 'other', 'prefer_not_to_say')
    ),
    CONSTRAINT patient_histories_pack_years_nonneg CHECK (
        smoker_pack_years IS NULL OR smoker_pack_years >= 0
    )
);

COMMENT ON TABLE public.patient_histories
    IS 'Clinical intake form, one row per user. Mirrors Dr. Olivete-Agdamag''s OPD Medical Record. All fields optional from the patient side.';
COMMENT ON COLUMN public.patient_histories.past_medical_conditions
    IS 'Canonical keys (e.g., hypertension, diabetes). Allowed values live in patient_history.dart on the Flutter side.';
COMMENT ON COLUMN public.patient_histories.smoker_pack_years
    IS 'NULL = non-smoker, otherwise pack-years (numeric). Matches the "Smoker: ___ Pack Years" field on the OPD form.';


-- ============================================
-- updated_at trigger (re-use existing helper from 0001)
-- ============================================
DROP TRIGGER IF EXISTS patient_histories_updated_at ON public.patient_histories;
CREATE TRIGGER patient_histories_updated_at
    BEFORE UPDATE ON public.patient_histories
    FOR EACH ROW EXECUTE PROCEDURE public.update_updated_at();


-- ============================================
-- RLS
-- ============================================
ALTER TABLE public.patient_histories ENABLE ROW LEVEL SECURITY;

-- ---- Owner: full read/write on their own row ----
DROP POLICY IF EXISTS "Users can read own patient history" ON public.patient_histories;
CREATE POLICY "Users can read own patient history"
    ON public.patient_histories FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own patient history" ON public.patient_histories;
CREATE POLICY "Users can insert own patient history"
    ON public.patient_histories FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own patient history" ON public.patient_histories;
CREATE POLICY "Users can update own patient history"
    ON public.patient_histories FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own patient history" ON public.patient_histories;
CREATE POLICY "Users can delete own patient history"
    ON public.patient_histories FOR DELETE
    TO authenticated
    USING (auth.uid() = user_id);


-- ---- Demo doctor: read-only access to consenting patients' histories ----
-- Doctor cannot INSERT/UPDATE/DELETE — patient history is patient-authored.
-- Sharing flag lives on profiles.shared_with_doctor (0002_doctor_demo.sql).
DROP POLICY IF EXISTS "Demo doctor can read consenting patients' history" ON public.patient_histories;
CREATE POLICY "Demo doctor can read consenting patients' history"
    ON public.patient_histories FOR SELECT
    TO authenticated
    USING (
        public.is_demo_doctor()
        AND EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = public.patient_histories.user_id
              AND p.shared_with_doctor = true
        )
    );


-- ============================================
-- Sanity-check queries
-- ============================================
-- Table present:
--   SELECT table_name FROM information_schema.tables
--   WHERE table_schema = 'public' AND table_name = 'patient_histories';
--
-- RLS enabled:
--   SELECT relrowsecurity FROM pg_class WHERE relname = 'patient_histories';
--
-- Policies present (expect five — four owner CRUD + one doctor read):
--   SELECT polname FROM pg_policy WHERE polrelid = 'public.patient_histories'::regclass;
