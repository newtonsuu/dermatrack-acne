-- DermaTrack — treatment plans (doctor-authored, per patient)
-- ============================================
-- One-row-per-patient treatment plan written by the dermatologist. Unlike
-- doctor_notes (which are per-scan clinical observations), a treatment plan
-- is the patient-level standing guidance: the regimen, products, and
-- follow-up cadence the doctor wants the patient to follow between visits.
--
-- Why a separate table (not a column on profiles):
--   - profiles is patient-owned and patient-writable. A plan column there
--     would fall under the patient's own UPDATE policy, letting them edit
--     the doctor's plan. A dedicated table keeps write authority with the
--     doctor (same reasoning as doctor_notes in 0003).
--
-- Visibility (mirrors doctor_notes):
--   • Patient can SELECT their own plan — always, even after toggling
--     sharing off, so guidance the doctor already gave doesn't vanish.
--   • Doctor can SELECT/INSERT/UPDATE/DELETE plans for patients whose
--     profiles.shared_with_doctor = true. Turning sharing off freezes the
--     doctor's write access; the existing plan stays visible to the patient.
--   • Patient cannot write — the plan is doctor-authored.
--
-- Run AFTER 0005_patient_histories.sql. Safe to re-run.
-- ============================================


-- ============================================
-- Table
-- ============================================
CREATE TABLE IF NOT EXISTS public.treatment_plans (
    -- PK == auth.users(id). One plan row per patient, max. Cascade delete so
    -- removing an account wipes their plan cleanly.
    user_id     uuid        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    plan        text        NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT treatment_plans_not_blank CHECK (length(btrim(plan)) > 0)
);

COMMENT ON TABLE public.treatment_plans
    IS 'Dermatologist-authored, patient-level treatment plan. PK is user_id so each patient has at most one current plan.';
COMMENT ON COLUMN public.treatment_plans.plan
    IS 'Free-text regimen / follow-up guidance from the demo doctor account. NOT NULL + non-blank check — delete the row to clear a plan.';


-- ============================================
-- updated_at trigger (re-use existing helper from 0001)
-- ============================================
DROP TRIGGER IF EXISTS treatment_plans_updated_at ON public.treatment_plans;
CREATE TRIGGER treatment_plans_updated_at
    BEFORE UPDATE ON public.treatment_plans
    FOR EACH ROW EXECUTE PROCEDURE public.update_updated_at();


-- ============================================
-- RLS
-- ============================================
ALTER TABLE public.treatment_plans ENABLE ROW LEVEL SECURITY;

-- ---- Patient read ----
-- The patient can always read their own plan (so revocation of sharing
-- doesn't make past guidance disappear).
DROP POLICY IF EXISTS "Patient can read own treatment plan" ON public.treatment_plans;
CREATE POLICY "Patient can read own treatment plan"
    ON public.treatment_plans FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

-- ---- Doctor read ----
DROP POLICY IF EXISTS "Demo doctor can read consenting patients' plan" ON public.treatment_plans;
CREATE POLICY "Demo doctor can read consenting patients' plan"
    ON public.treatment_plans FOR SELECT
    TO authenticated
    USING (
        public.is_demo_doctor()
        AND EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = public.treatment_plans.user_id
              AND p.shared_with_doctor = true
        )
    );

-- ---- Doctor write (insert) ----
DROP POLICY IF EXISTS "Demo doctor can add plan for consenting patients" ON public.treatment_plans;
CREATE POLICY "Demo doctor can add plan for consenting patients"
    ON public.treatment_plans FOR INSERT
    TO authenticated
    WITH CHECK (
        public.is_demo_doctor()
        AND EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = public.treatment_plans.user_id
              AND p.shared_with_doctor = true
        )
    );

-- ---- Doctor write (update) ----
-- USING gates which existing rows are updatable; WITH CHECK re-validates the
-- post-update row so the consent/identity invariant can't be written away.
DROP POLICY IF EXISTS "Demo doctor can edit plan for consenting patients" ON public.treatment_plans;
CREATE POLICY "Demo doctor can edit plan for consenting patients"
    ON public.treatment_plans FOR UPDATE
    TO authenticated
    USING (
        public.is_demo_doctor()
        AND EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = public.treatment_plans.user_id
              AND p.shared_with_doctor = true
        )
    )
    WITH CHECK (
        public.is_demo_doctor()
        AND EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = public.treatment_plans.user_id
              AND p.shared_with_doctor = true
        )
    );

-- ---- Doctor write (delete) ----
DROP POLICY IF EXISTS "Demo doctor can delete plan for consenting patients" ON public.treatment_plans;
CREATE POLICY "Demo doctor can delete plan for consenting patients"
    ON public.treatment_plans FOR DELETE
    TO authenticated
    USING (
        public.is_demo_doctor()
        AND EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = public.treatment_plans.user_id
              AND p.shared_with_doctor = true
        )
    );

-- Patient deliberately has NO insert/update/delete policies — the plan is
-- doctor-authored. PostgREST denies by default.


-- ============================================
-- Sanity-check queries
-- ============================================
-- Table present:
--   SELECT table_name FROM information_schema.tables
--   WHERE table_schema = 'public' AND table_name = 'treatment_plans';
--
-- RLS enabled:
--   SELECT relrowsecurity FROM pg_class WHERE relname = 'treatment_plans';
--
-- Policies present (expect five — one patient read + four doctor CRUD):
--   SELECT polname FROM pg_policy WHERE polrelid = 'public.treatment_plans'::regclass;
