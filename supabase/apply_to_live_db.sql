-- ============================================================
-- DermaTrack - catch-up script for an EXISTING database
-- ============================================================
-- Adds only the newer objects (migrations 0005-0009) to a database that
-- already has 0001-0004. Idempotent; does not touch existing tables/data.
-- For a brand-new project use full_schema.sql instead.
-- ============================================================

-- ####################### 0005_patient_histories.sql #######################
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


-- ####################### 0006_treatment_plans.sql #######################
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


-- ####################### 0007_doctor_demo_emails.sql #######################
-- DermaTrack — additional demo doctor email
-- ============================================
-- Widens is_demo_doctor() to recognize more than one demo dermatologist
-- account. Mirrors kDoctorDemoEmails in app/lib/services/auth_service.dart:
-- the client uses that set to route to the doctor shell; this function is the
-- server-side RLS gate that actually grants the doctor read access to
-- consenting patients. The two MUST list the same emails or a "doctor" can
-- reach the UI but see no data (RLS returns nothing).
--
-- Still DEMO-GRADE (hardcoded emails). Post-thesis this whole approach is
-- replaced by a proper role table — see 0002_doctor_demo.sql.
--
-- Run AFTER 0002_doctor_demo.sql (and any time you add a demo doctor email).
-- Safe to re-run.
-- ============================================

CREATE OR REPLACE FUNCTION public.is_demo_doctor()
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
    -- Lower-case both sides: Supabase stores emails lower-cased but the JWT
    -- claim can vary by how the account was created.
    SELECT LOWER(COALESCE(auth.jwt() ->> 'email', '')) IN (
        'doctor@dermatrack.demo',
        'dr.demo@dermatrack.demo'
    );
$$;

COMMENT ON FUNCTION public.is_demo_doctor()
    IS 'Returns true iff the current request''s JWT belongs to a demo doctor account. Keep in sync with kDoctorDemoEmails in auth_service.dart.';

-- ============================================
-- Sanity check
-- ============================================
-- SELECT prosrc FROM pg_proc WHERE proname = 'is_demo_doctor';


-- ####################### 0008_prescriptions.sql #######################
-- DermaTrack — doctor prescriptions (with image attachments)
-- ============================================
-- Doctor-authored prescriptions sent to a specific patient. Unlike the
-- single treatment_plans row (standing guidance), a patient can have many
-- prescriptions over time (a dated log). Each prescription has free-text
-- instructions plus zero or more image attachments (e.g. a photo of a
-- written script, a product label, an annotated reference) the doctor sends
-- to that patient.
--
-- Images live in a dedicated private bucket `prescription-images`, foldered
-- by the PATIENT's user_id so the existing folder-based storage RLS pattern
-- (foldername[1] = owner) extends cleanly: the patient reads their own
-- folder; the demo doctor writes into consenting patients' folders.
--
-- Visibility (mirrors doctor_notes / treatment_plans):
--   • Patient can SELECT their own prescriptions — always.
--   • Demo doctor can SELECT/INSERT/UPDATE/DELETE prescriptions for patients
--     with shared_with_doctor = true.
--   • Patient cannot write — prescriptions are doctor-authored.
--
-- Run AFTER 0002_doctor_demo.sql. Safe to re-run.
-- ============================================


-- ============================================
-- Table
-- ============================================
CREATE TABLE IF NOT EXISTS public.prescriptions (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    -- The patient this prescription is for.
    user_id     uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    body        text        NOT NULL,
    -- Storage paths in the `prescription-images` bucket, each of the form
    -- '{user_id}/{prescription_id}/{filename}'. Empty array = text-only.
    image_paths text[]      NOT NULL DEFAULT '{}'::text[],
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT prescriptions_not_blank CHECK (length(btrim(body)) > 0)
);

CREATE INDEX IF NOT EXISTS prescriptions_user_created_idx
    ON public.prescriptions (user_id, created_at DESC);

COMMENT ON TABLE public.prescriptions
    IS 'Dermatologist-authored prescriptions for a patient. Many per patient; image_paths reference the prescription-images bucket.';


-- ============================================
-- updated_at trigger (re-use helper from 0001)
-- ============================================
DROP TRIGGER IF EXISTS prescriptions_updated_at ON public.prescriptions;
CREATE TRIGGER prescriptions_updated_at
    BEFORE UPDATE ON public.prescriptions
    FOR EACH ROW EXECUTE PROCEDURE public.update_updated_at();


-- ============================================
-- RLS — table
-- ============================================
ALTER TABLE public.prescriptions ENABLE ROW LEVEL SECURITY;

-- ---- Patient read (own, always) ----
DROP POLICY IF EXISTS "Patient can read own prescriptions" ON public.prescriptions;
CREATE POLICY "Patient can read own prescriptions"
    ON public.prescriptions FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

-- ---- Doctor read ----
DROP POLICY IF EXISTS "Demo doctor can read consenting patients' prescriptions" ON public.prescriptions;
CREATE POLICY "Demo doctor can read consenting patients' prescriptions"
    ON public.prescriptions FOR SELECT
    TO authenticated
    USING (
        public.is_demo_doctor()
        AND EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = public.prescriptions.user_id
              AND p.shared_with_doctor = true
        )
    );

-- ---- Doctor insert ----
DROP POLICY IF EXISTS "Demo doctor can add prescriptions for consenting patients" ON public.prescriptions;
CREATE POLICY "Demo doctor can add prescriptions for consenting patients"
    ON public.prescriptions FOR INSERT
    TO authenticated
    WITH CHECK (
        public.is_demo_doctor()
        AND EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = public.prescriptions.user_id
              AND p.shared_with_doctor = true
        )
    );

-- ---- Doctor update ----
DROP POLICY IF EXISTS "Demo doctor can edit prescriptions for consenting patients" ON public.prescriptions;
CREATE POLICY "Demo doctor can edit prescriptions for consenting patients"
    ON public.prescriptions FOR UPDATE
    TO authenticated
    USING (
        public.is_demo_doctor()
        AND EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = public.prescriptions.user_id
              AND p.shared_with_doctor = true
        )
    )
    WITH CHECK (
        public.is_demo_doctor()
        AND EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = public.prescriptions.user_id
              AND p.shared_with_doctor = true
        )
    );

-- ---- Doctor delete ----
DROP POLICY IF EXISTS "Demo doctor can delete prescriptions for consenting patients" ON public.prescriptions;
CREATE POLICY "Demo doctor can delete prescriptions for consenting patients"
    ON public.prescriptions FOR DELETE
    TO authenticated
    USING (
        public.is_demo_doctor()
        AND EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = public.prescriptions.user_id
              AND p.shared_with_doctor = true
        )
    );


-- ============================================
-- Storage bucket + RLS for prescription images
-- ============================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('prescription-images', 'prescription-images', false)
ON CONFLICT (id) DO NOTHING;

-- Path convention: '{patient_user_id}/{prescription_id}/{filename}', so
-- (storage.foldername(name))[1] is the patient's user_id.

-- ---- Patient read (own folder, always) ----
DROP POLICY IF EXISTS "Patient can read own prescription images" ON storage.objects;
CREATE POLICY "Patient can read own prescription images"
    ON storage.objects FOR SELECT
    TO authenticated
    USING (
        bucket_id = 'prescription-images'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

-- ---- Doctor read (consenting patients' folders) ----
DROP POLICY IF EXISTS "Demo doctor can read consenting prescription images" ON storage.objects;
CREATE POLICY "Demo doctor can read consenting prescription images"
    ON storage.objects FOR SELECT
    TO authenticated
    USING (
        bucket_id = 'prescription-images'
        AND public.is_demo_doctor()
        AND EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id::text = (storage.foldername(name))[1]
              AND p.shared_with_doctor = true
        )
    );

-- ---- Doctor insert (into consenting patients' folders) ----
DROP POLICY IF EXISTS "Demo doctor can upload prescription images" ON storage.objects;
CREATE POLICY "Demo doctor can upload prescription images"
    ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'prescription-images'
        AND public.is_demo_doctor()
        AND EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id::text = (storage.foldername(name))[1]
              AND p.shared_with_doctor = true
        )
    );

-- ---- Doctor delete ----
DROP POLICY IF EXISTS "Demo doctor can delete prescription images" ON storage.objects;
CREATE POLICY "Demo doctor can delete prescription images"
    ON storage.objects FOR DELETE
    TO authenticated
    USING (
        bucket_id = 'prescription-images'
        AND public.is_demo_doctor()
        AND EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id::text = (storage.foldername(name))[1]
              AND p.shared_with_doctor = true
        )
    );


-- ============================================
-- Sanity checks
-- ============================================
-- SELECT polname FROM pg_policy WHERE polrelid = 'public.prescriptions'::regclass;  -- expect 5
-- SELECT id FROM storage.buckets WHERE id = 'prescription-images';


-- ####################### 0009_messages.sql #######################
-- DermaTrack — patient <-> dermatologist chat
-- ============================================
-- A simple one-thread-per-patient message log. Each row is one message in
-- the conversation between a patient and the demo dermatologist. patient_id
-- identifies the thread (always the patient, never the doctor); sender_id +
-- sender_role say who wrote it.
--
-- Visibility:
--   • Patient can read + send messages in their own thread (patient_id = self).
--   • Demo doctor can read + send in threads of consenting patients.
--   • Messages are immutable (no update/delete policies).
--
-- Realtime: the table is added to the supabase_realtime publication so the
-- Flutter client can stream new messages live.
--
-- Run AFTER 0002_doctor_demo.sql. Safe to re-run.
-- ============================================

CREATE TABLE IF NOT EXISTS public.messages (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    -- The patient whose conversation thread this message belongs to.
    patient_id  uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    -- Who actually wrote the message.
    sender_id   uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    sender_role text        NOT NULL CHECK (sender_role IN ('patient', 'doctor')),
    body        text        NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT messages_not_blank CHECK (length(btrim(body)) > 0)
);

CREATE INDEX IF NOT EXISTS messages_thread_idx
    ON public.messages (patient_id, created_at);

COMMENT ON TABLE public.messages
    IS 'Patient<->dermatologist chat. patient_id = thread; sender_role says who wrote it.';


-- ============================================
-- RLS
-- ============================================
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- ---- Patient: read own thread ----
DROP POLICY IF EXISTS "Patient can read own thread" ON public.messages;
CREATE POLICY "Patient can read own thread"
    ON public.messages FOR SELECT
    TO authenticated
    USING (auth.uid() = patient_id);

-- ---- Patient: send into own thread (as patient) ----
DROP POLICY IF EXISTS "Patient can send in own thread" ON public.messages;
CREATE POLICY "Patient can send in own thread"
    ON public.messages FOR INSERT
    TO authenticated
    WITH CHECK (
        auth.uid() = patient_id
        AND auth.uid() = sender_id
        AND sender_role = 'patient'
    );

-- ---- Doctor: read consenting patients' threads ----
DROP POLICY IF EXISTS "Demo doctor can read consenting threads" ON public.messages;
CREATE POLICY "Demo doctor can read consenting threads"
    ON public.messages FOR SELECT
    TO authenticated
    USING (
        public.is_demo_doctor()
        AND EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = public.messages.patient_id
              AND p.shared_with_doctor = true
        )
    );

-- ---- Doctor: send into consenting patients' threads (as doctor) ----
DROP POLICY IF EXISTS "Demo doctor can send in consenting threads" ON public.messages;
CREATE POLICY "Demo doctor can send in consenting threads"
    ON public.messages FOR INSERT
    TO authenticated
    WITH CHECK (
        public.is_demo_doctor()
        AND auth.uid() = sender_id
        AND sender_role = 'doctor'
        AND EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = public.messages.patient_id
              AND p.shared_with_doctor = true
        )
    );

-- No UPDATE/DELETE policies — messages are immutable once sent.


-- ============================================
-- Realtime
-- ============================================
-- Add to the realtime publication so clients can stream inserts. Guarded so
-- re-running is safe.
DO $$
BEGIN
    -- Supabase provisions the supabase_realtime publication by default, but
    -- create it if a fresh/edge-case project is missing it so the ADD below
    -- can't fail.
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        CREATE PUBLICATION supabase_realtime;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename = 'messages'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
    END IF;
END $$;


-- ============================================
-- Sanity check
-- ============================================
-- SELECT polname FROM pg_policy WHERE polrelid = 'public.messages'::regclass;  -- expect 4

