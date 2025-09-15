-- ============================================================
-- DermaTrack - FULL schema for a new Supabase project
-- ============================================================
-- Paste this ENTIRE file into Dashboard -> SQL Editor -> New query and Run.
-- Applies migrations 0001-0009: tables, RLS, storage buckets, triggers,
-- the demo-doctor function, and the chat realtime publication.
-- Idempotent and non-destructive: safe to re-run, and it ADAPTS if a
-- profiles table already exists (e.g. from a Supabase starter template) by
-- adding any missing columns rather than failing.
-- ============================================================

-- ####################### 0001_init.sql #######################
-- DermaTrack — initial schema migration
-- ============================================
-- Run this in the Supabase SQL Editor (Studio → SQL Editor → New query).
-- Safe to re-run: every CREATE uses IF NOT EXISTS or OR REPLACE.
--
-- Companion doc: supabase/schema.md (read this first for design rationale).
-- ============================================

-- ============================================
-- Extensions
-- ============================================
-- gen_random_uuid() lives in pgcrypto. Supabase enables it by default but
-- this guard makes the migration safe to run on fresh projects.
CREATE EXTENSION IF NOT EXISTS pgcrypto;


-- ============================================
-- Tables
-- ============================================

-- public.profiles
-- One row per auth.users row, auto-created via trigger on signup.
CREATE TABLE IF NOT EXISTS public.profiles (
    id                    uuid        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    username              text        NOT NULL UNIQUE,
    display_name          text,
    profile_picture_path  text,
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT profiles_username_min_length CHECK (length(username) >= 3)
);

-- Defensive: if `public.profiles` already existed (e.g. a Supabase starter
-- template created one without these columns), the CREATE above was a no-op.
-- Add any missing columns so the rest of this migration (and the app) works
-- regardless of how the table got there. Non-destructive: existing columns
-- and data are untouched.
ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS username             text,
    ADD COLUMN IF NOT EXISTS display_name         text,
    ADD COLUMN IF NOT EXISTS profile_picture_path text,
    ADD COLUMN IF NOT EXISTS created_at           timestamptz NOT NULL DEFAULT now(),
    ADD COLUMN IF NOT EXISTS updated_at           timestamptz NOT NULL DEFAULT now();

-- Ensure username is unique (no-op if the constraint/index already exists).
CREATE UNIQUE INDEX IF NOT EXISTS profiles_username_key ON public.profiles (username);

COMMENT ON TABLE public.profiles
    IS 'App-specific user fields. 1:1 with auth.users; row auto-created by trigger on signup.';
COMMENT ON COLUMN public.profiles.username
    IS 'Stored lower-cased for case-insensitive uniqueness; display via display_name.';


-- public.scans
-- One row per scan submission.
CREATE TABLE IF NOT EXISTS public.scans (
    id                        uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                   uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    taken_at                  timestamptz NOT NULL DEFAULT now(),
    image_path                text        NOT NULL,
    cook_grade                integer,
    severity_label            text,
    inflammatory_count        integer     NOT NULL DEFAULT 0,
    non_inflammatory_count    integer     NOT NULL DEFAULT 0,
    post_acne_count           integer     NOT NULL DEFAULT 0,
    lesions                   jsonb       NOT NULL DEFAULT '[]'::jsonb,
    source_metadata           jsonb       NOT NULL DEFAULT '{}'::jsonb,
    notes                     text,
    created_at                timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT scans_cook_grade_range CHECK (cook_grade IS NULL OR (cook_grade BETWEEN -1 AND 8)),
    CONSTRAINT scans_counts_nonneg    CHECK (
        inflammatory_count >= 0
        AND non_inflammatory_count >= 0
        AND post_acne_count >= 0
    )
);

COMMENT ON TABLE public.scans
    IS 'One row per scan submission. Aggregate counts denormalized for fast dashboard reads.';
COMMENT ON COLUMN public.scans.cook_grade
    IS '-1 = Clear Skin (from skintelligent), 0-8 = Cook-style severity grade.';
COMMENT ON COLUMN public.scans.lesions
    IS 'Array of {class, bucket, confidence, bbox, image_size}. See schema.md for shape.';
COMMENT ON COLUMN public.scans.source_metadata
    IS 'Provenance: detection_model, classifier_model, raw_responses, latencies, thresholds.';


-- ============================================
-- Indexes
-- ============================================
-- Primary access pattern: a user's scans in reverse chronological order
-- (dashboard recent scans, gallery grid, severity timeline chart).
CREATE INDEX IF NOT EXISTS scans_user_taken_at_idx
    ON public.scans (user_id, taken_at DESC);

-- For severity-trend queries: "show me my last N scans grouped by grade."
CREATE INDEX IF NOT EXISTS scans_user_cook_grade_idx
    ON public.scans (user_id, cook_grade);


-- ============================================
-- Functions and triggers
-- ============================================

-- Auto-update updated_at on any UPDATE.
CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profiles_updated_at ON public.profiles;
CREATE TRIGGER profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE PROCEDURE public.update_updated_at();


-- Auto-create profile row when a new auth.users row is inserted.
-- Reads username + display_name from the user_meta_data the Flutter signup
-- call passes in. If no username supplied, falls back to the local-part
-- of the email so the trigger never fails for missing metadata.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    new_username    text;
    new_display     text;
BEGIN
    new_username := LOWER(COALESCE(
        NEW.raw_user_meta_data->>'username',
        SPLIT_PART(NEW.email, '@', 1)
    ));
    new_display := COALESCE(
        NEW.raw_user_meta_data->>'display_name',
        NEW.raw_user_meta_data->>'username',
        new_username
    );

    INSERT INTO public.profiles (id, username, display_name)
    VALUES (NEW.id, new_username, new_display);

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();


-- ============================================
-- Row-Level Security
-- ============================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scans    ENABLE ROW LEVEL SECURITY;

-- ---- profiles ----
DROP POLICY IF EXISTS "Profiles viewable by authenticated users" ON public.profiles;
CREATE POLICY "Profiles viewable by authenticated users"
    ON public.profiles FOR SELECT
    TO authenticated
    USING (true);

DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile"
    ON public.profiles FOR UPDATE
    TO authenticated
    USING (auth.uid() = id);

-- ---- scans ----
DROP POLICY IF EXISTS "Users can read own scans" ON public.scans;
CREATE POLICY "Users can read own scans"
    ON public.scans FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own scans" ON public.scans;
CREATE POLICY "Users can insert own scans"
    ON public.scans FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own scans" ON public.scans;
CREATE POLICY "Users can update own scans"
    ON public.scans FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own scans" ON public.scans;
CREATE POLICY "Users can delete own scans"
    ON public.scans FOR DELETE
    TO authenticated
    USING (auth.uid() = user_id);


-- ============================================
-- Storage buckets
-- ============================================

INSERT INTO storage.buckets (id, name, public)
VALUES
    ('profile-pictures', 'profile-pictures', false),
    ('scan-images',      'scan-images',      false)
ON CONFLICT (id) DO NOTHING;


-- ============================================
-- Storage RLS policies
-- ============================================
-- (storage.foldername(name))[1] = auth.uid()::text enforces
-- "first folder segment must equal your user_id".

-- ---- profile-pictures ----
DROP POLICY IF EXISTS "Own profile picture read" ON storage.objects;
CREATE POLICY "Own profile picture read"
    ON storage.objects FOR SELECT
    TO authenticated
    USING (
        bucket_id = 'profile-pictures'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

DROP POLICY IF EXISTS "Own profile picture insert" ON storage.objects;
CREATE POLICY "Own profile picture insert"
    ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'profile-pictures'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

DROP POLICY IF EXISTS "Own profile picture update" ON storage.objects;
CREATE POLICY "Own profile picture update"
    ON storage.objects FOR UPDATE
    TO authenticated
    USING (
        bucket_id = 'profile-pictures'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

DROP POLICY IF EXISTS "Own profile picture delete" ON storage.objects;
CREATE POLICY "Own profile picture delete"
    ON storage.objects FOR DELETE
    TO authenticated
    USING (
        bucket_id = 'profile-pictures'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

-- ---- scan-images ----
DROP POLICY IF EXISTS "Own scan image read" ON storage.objects;
CREATE POLICY "Own scan image read"
    ON storage.objects FOR SELECT
    TO authenticated
    USING (
        bucket_id = 'scan-images'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

DROP POLICY IF EXISTS "Own scan image insert" ON storage.objects;
CREATE POLICY "Own scan image insert"
    ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'scan-images'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

DROP POLICY IF EXISTS "Own scan image update" ON storage.objects;
CREATE POLICY "Own scan image update"
    ON storage.objects FOR UPDATE
    TO authenticated
    USING (
        bucket_id = 'scan-images'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

DROP POLICY IF EXISTS "Own scan image delete" ON storage.objects;
CREATE POLICY "Own scan image delete"
    ON storage.objects FOR DELETE
    TO authenticated
    USING (
        bucket_id = 'scan-images'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );


-- ============================================
-- Sanity-check queries (run these AFTER the migration to verify)
-- ============================================
-- Tables created:
--   SELECT table_name FROM information_schema.tables
--   WHERE table_schema = 'public' ORDER BY table_name;
--   -- expected: profiles, scans
--
-- RLS enabled on both:
--   SELECT relname, relrowsecurity FROM pg_class
--   WHERE relname IN ('profiles', 'scans');
--   -- expected: relrowsecurity = true for both
--
-- Storage buckets:
--   SELECT id, name, public FROM storage.buckets ORDER BY id;
--   -- expected: profile-pictures and scan-images, both public = false
--
-- Trigger present:
--   SELECT tgname FROM pg_trigger WHERE tgname = 'on_auth_user_created';
--   -- expected: one row


-- ####################### 0002_doctor_demo.sql #######################
-- DermaTrack — doctor demo migration
-- ============================================
-- Adds the minimal schema + RLS needed to demonstrate the patient↔doctor
-- exchange to a real dermatologist. DEMO-GRADE: the doctor email is
-- hard-coded both here and in the Flutter client (services/auth_service.dart).
-- This migration is intentionally separate from 0001_init.sql so it can be
-- rolled back / replaced once we design the production doctor model
-- (proper role table, patient↔doctor linking, audit log).
--
-- Run this in the Supabase SQL Editor AFTER 0001_init.sql.
-- Safe to re-run.
--
-- Companion code: app/lib/services/doctor_service.dart
-- ============================================


-- ============================================
-- 1. Schema change — opt-in flag on profiles
-- ============================================
-- The patient toggles this from the profile screen ("Share with my
-- dermatologist"). When true, the doctor demo account can SELECT their
-- profile + scans + scan-image storage objects. Defaults to false so
-- existing users keep their data private unless they explicitly opt in.
ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS shared_with_doctor boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.profiles.shared_with_doctor
    IS 'DEMO ONLY: when true, the hardcoded doctor demo account can read this user''s scans. Replace with a proper doctor-link table post-thesis.';


-- ============================================
-- 2. Demo doctor email — one place to change it
-- ============================================
-- Helper function returns the hard-coded doctor email. Centralising it here
-- means the policies below stay readable, and there's exactly one row to
-- update if you ever swap the email. Mirror any change in
-- app/lib/services/auth_service.dart (const kDoctorDemoEmail).
CREATE OR REPLACE FUNCTION public.is_demo_doctor()
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
    -- auth.jwt() reads the verified JWT from the current request. We lower
    -- both sides because Supabase stores emails lower-cased but the JWT
    -- claim sometimes preserves the user-typed casing.
    SELECT LOWER(COALESCE(auth.jwt() ->> 'email', '')) = 'doctor@dermatrack.demo';
$$;

COMMENT ON FUNCTION public.is_demo_doctor()
    IS 'Returns true iff the current request''s JWT belongs to the demo doctor account.';


-- ============================================
-- 3. RLS — doctor can read consenting patients
-- ============================================
-- profiles: 0001_init already lets any authenticated user SELECT profiles
-- (so usernames render in scan-detail / future social features). The doctor
-- demo account inherits that read. The shared_with_doctor flag is enforced
-- on the scans + storage policies below.

-- scans: doctor can SELECT scans of patients who have opted in.
DROP POLICY IF EXISTS "Demo doctor can read consenting patients' scans" ON public.scans;
CREATE POLICY "Demo doctor can read consenting patients' scans"
    ON public.scans FOR SELECT
    TO authenticated
    USING (
        public.is_demo_doctor()
        AND EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = public.scans.user_id
              AND p.shared_with_doctor = true
        )
    );

-- Note: scan inserts/updates/deletes are still owner-only (the doctor must
-- not be able to modify a patient's scans — only the patient can).


-- ============================================
-- 4. Storage RLS — doctor can read shared scan images
-- ============================================
-- The scan-images bucket stores objects under `{user_id}/{scan_id}.jpg`.
-- The existing "Own scan image read" policy ties reads to the user's own
-- folder; we add a second SELECT policy for the doctor. Postgres OR-combines
-- multiple SELECT policies for the same role, so this widens access without
-- breaking the owner path.
DROP POLICY IF EXISTS "Demo doctor can read consenting patients' scan images" ON storage.objects;
CREATE POLICY "Demo doctor can read consenting patients' scan images"
    ON storage.objects FOR SELECT
    TO authenticated
    USING (
        bucket_id = 'scan-images'
        AND public.is_demo_doctor()
        AND EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id::text = (storage.foldername(name))[1]
              AND p.shared_with_doctor = true
        )
    );

-- Profile pictures stay owner-only — the doctor doesn't need to see avatars
-- for the v1 demo and we keep that surface tight by default. Easy to widen
-- later if the dermatologist asks for it.


-- ============================================
-- Sanity-check queries
-- ============================================
-- Column added:
--   SELECT column_name, data_type, column_default
--   FROM information_schema.columns
--   WHERE table_schema = 'public' AND table_name = 'profiles'
--     AND column_name = 'shared_with_doctor';
--
-- Function present:
--   SELECT proname FROM pg_proc WHERE proname = 'is_demo_doctor';
--
-- Policies present:
--   SELECT polname FROM pg_policy
--   WHERE polname LIKE '%demo doctor%';
--
-- After running, in Supabase Auth → Users, create the demo doctor account:
--   email:    doctor@dermatrack.demo
--   password: (your choice — see app/lib/services/auth_service.dart)
-- The handle_new_user trigger will auto-create a profiles row for it. That's
-- fine — the doctor account just has a profile row of its own that nobody
-- reads.


-- ####################### 0003_doctor_notes.sql #######################
-- DermaTrack — doctor notes per scan
-- ============================================
-- Adds a 1:1 (zero-or-one) `doctor_notes` table keyed by scan_id. The
-- dermatologist (demo doctor account) can leave a clinical note on any
-- consenting patient's scan; the patient sees it on the scan detail screen
-- labelled "From your dermatologist".
--
-- Why a separate table instead of a column on `scans`:
--   - Postgres has column-level GRANT but not column-level RLS. With a
--     doctor_note column on scans, the patient's existing "Users can update
--     own scans" policy would let them edit the doctor's note. A separate
--     table with its own RLS keeps write authority cleanly with the doctor.
--   - The cascade-delete behavior we want (delete the scan → delete its
--     note) is the same with both designs.
--
-- Visibility rules:
--   - Patient can SELECT notes on their own scans (always — even after they
--     toggle sharing off, so previously-left notes don't disappear).
--   - Doctor can SELECT/INSERT/UPDATE/DELETE notes for scans whose owner
--     has shared_with_doctor = true. Turning sharing off freezes the
--     doctor's write access; existing notes remain visible to the patient.
--
-- Run AFTER 0002_doctor_demo.sql. Safe to re-run.
-- ============================================

-- ============================================
-- Table
-- ============================================
CREATE TABLE IF NOT EXISTS public.doctor_notes (
    -- PK == scan_id enforces the 1:1 (max one note per scan).
    scan_id     uuid        PRIMARY KEY REFERENCES public.scans(id) ON DELETE CASCADE,
    note        text        NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT doctor_notes_not_blank CHECK (length(btrim(note)) > 0)
);

COMMENT ON TABLE public.doctor_notes
    IS 'Dermatologist-authored note for a single scan. PK is scan_id so each scan has at most one note.';
COMMENT ON COLUMN public.doctor_notes.note
    IS 'Free-text clinical observation from the demo doctor account. NOT NULL + non-blank check — clear/delete the row to remove a note.';


-- ============================================
-- updated_at trigger (re-use existing helper from 0001)
-- ============================================
DROP TRIGGER IF EXISTS doctor_notes_updated_at ON public.doctor_notes;
CREATE TRIGGER doctor_notes_updated_at
    BEFORE UPDATE ON public.doctor_notes
    FOR EACH ROW EXECUTE PROCEDURE public.update_updated_at();


-- ============================================
-- RLS
-- ============================================
ALTER TABLE public.doctor_notes ENABLE ROW LEVEL SECURITY;

-- ---- Patient read ----
-- The owner of the scan can always see its doctor note (so revocation of
-- sharing doesn't make past notes vanish).
DROP POLICY IF EXISTS "Patient can read doctor notes on own scans" ON public.doctor_notes;
CREATE POLICY "Patient can read doctor notes on own scans"
    ON public.doctor_notes FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.scans s
            WHERE s.id = public.doctor_notes.scan_id
              AND s.user_id = auth.uid()
        )
    );

-- ---- Doctor read ----
-- The demo doctor can read notes for scans owned by consenting patients.
DROP POLICY IF EXISTS "Demo doctor can read notes for consenting patients" ON public.doctor_notes;
CREATE POLICY "Demo doctor can read notes for consenting patients"
    ON public.doctor_notes FOR SELECT
    TO authenticated
    USING (
        public.is_demo_doctor()
        AND EXISTS (
            SELECT 1
            FROM public.scans s
            JOIN public.profiles p ON p.id = s.user_id
            WHERE s.id = public.doctor_notes.scan_id
              AND p.shared_with_doctor = true
        )
    );

-- ---- Doctor write (insert) ----
DROP POLICY IF EXISTS "Demo doctor can add notes for consenting patients" ON public.doctor_notes;
CREATE POLICY "Demo doctor can add notes for consenting patients"
    ON public.doctor_notes FOR INSERT
    TO authenticated
    WITH CHECK (
        public.is_demo_doctor()
        AND EXISTS (
            SELECT 1
            FROM public.scans s
            JOIN public.profiles p ON p.id = s.user_id
            WHERE s.id = public.doctor_notes.scan_id
              AND p.shared_with_doctor = true
        )
    );

-- ---- Doctor write (update) ----
DROP POLICY IF EXISTS "Demo doctor can edit notes for consenting patients" ON public.doctor_notes;
CREATE POLICY "Demo doctor can edit notes for consenting patients"
    ON public.doctor_notes FOR UPDATE
    TO authenticated
    USING (
        public.is_demo_doctor()
        AND EXISTS (
            SELECT 1
            FROM public.scans s
            JOIN public.profiles p ON p.id = s.user_id
            WHERE s.id = public.doctor_notes.scan_id
              AND p.shared_with_doctor = true
        )
    );

-- ---- Doctor write (delete) ----
DROP POLICY IF EXISTS "Demo doctor can delete notes for consenting patients" ON public.doctor_notes;
CREATE POLICY "Demo doctor can delete notes for consenting patients"
    ON public.doctor_notes FOR DELETE
    TO authenticated
    USING (
        public.is_demo_doctor()
        AND EXISTS (
            SELECT 1
            FROM public.scans s
            JOIN public.profiles p ON p.id = s.user_id
            WHERE s.id = public.doctor_notes.scan_id
              AND p.shared_with_doctor = true
        )
    );

-- Patient deliberately has NO insert/update/delete policies — they cannot
-- author or modify doctor notes. PostgREST denies by default.


-- ============================================
-- Sanity-check queries
-- ============================================
-- Table present:
--   SELECT table_name FROM information_schema.tables
--   WHERE table_schema = 'public' AND table_name = 'doctor_notes';
--
-- RLS enabled:
--   SELECT relrowsecurity FROM pg_class WHERE relname = 'doctor_notes';
--
-- Policies present (expect five):
--   SELECT polname FROM pg_policy WHERE polrelid = 'public.doctor_notes'::regclass;


-- ####################### 0004_scan_regions.sql #######################
-- DermaTrack — scan regions + guided session grouping
-- ============================================
-- Adds two columns to public.scans:
--   region      — anatomical zone the scan captured. Five values:
--                   forehead, left_cheek, right_cheek, chin, full_face.
--                 This is the basis of the daily 5-step guided capture
--                 (forehead → left cheek → right cheek → chin → full face)
--                 that came out of the dermatologist consult on 2026-05-25.
--   session_id  — groups the five scans of one guided capture into a
--                 coherent snapshot the UI can render as a unit. NULL for
--                 ad-hoc single-region scans and for legacy rows predating
--                 region tracking.
--
-- Pre-migration scans are silently tagged as 'full_face' via the column
-- DEFAULT — they were full-face captures, so this is accurate, and
-- nothing in the existing UI breaks.
--
-- Run AFTER 0003_doctor_notes.sql. Safe to re-run.
-- ============================================

-- ============================================
-- Columns
-- ============================================
ALTER TABLE public.scans
    ADD COLUMN IF NOT EXISTS region     text NOT NULL DEFAULT 'full_face',
    ADD COLUMN IF NOT EXISTS session_id uuid;

-- Enum-style CHECK constraint. Preferred over a Postgres ENUM type because
-- if the dermatologist later asks for finer zones (forehead-left vs
-- forehead-right, jawline, nose, neck, etc.), updating a CHECK is a single
-- ALTER while updating an ENUM type requires ALTER TYPE + dependent code
-- changes. Same type safety either way at the row-write boundary.
ALTER TABLE public.scans
    DROP CONSTRAINT IF EXISTS scans_region_valid;
ALTER TABLE public.scans
    ADD CONSTRAINT scans_region_valid CHECK (
        region IN ('forehead', 'left_cheek', 'right_cheek', 'chin', 'nose', 'full_face')
    );

COMMENT ON COLUMN public.scans.region
    IS 'Anatomical zone captured. One of: forehead, left_cheek, right_cheek, chin, nose, full_face. The guided per-region session captures the five facial zones; full_face is the standalone quick scan.';
COMMENT ON COLUMN public.scans.session_id
    IS 'Groups the 5 scans of one guided daily-capture session. NULL for standalone single-region scans and for legacy rows predating session tracking.';


-- ============================================
-- Indexes
-- ============================================

-- Fast "scans in this session" lookup. Partial index — session_id is NULL
-- on legacy rows and standalone scans, no reason to index them.
CREATE INDEX IF NOT EXISTS scans_user_session_idx
    ON public.scans (user_id, session_id)
    WHERE session_id IS NOT NULL;

-- Fast "this user's most-recent forehead scans" lookup, which the future
-- per-region trend chart will hit on dashboard load. Includes taken_at DESC
-- so the planner can use index-only scans for the typical "last N scans of
-- this region" query.
CREATE INDEX IF NOT EXISTS scans_user_region_taken_at_idx
    ON public.scans (user_id, region, taken_at DESC);


-- ============================================
-- Sanity-check queries
-- ============================================
-- Columns present + defaults applied to existing rows:
--   SELECT region, count(*) FROM public.scans GROUP BY region;
--   -- expected: all existing rows → 'full_face'
--
-- Constraint enforced:
--   INSERT INTO public.scans (...) VALUES (..., 'eyebrow', ...);
--   -- expected: ERROR — new row violates CHECK constraint scans_region_valid
--
-- Indexes exist:
--   SELECT indexname FROM pg_indexes
--   WHERE tablename = 'scans' AND indexname LIKE 'scans_user_%';
--   -- expected: scans_user_taken_at_idx, scans_user_cook_grade_idx,
--               scans_user_session_idx, scans_user_region_taken_at_idx


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



-- DermaTrack â€” Role-based access control: roles, admin, break-glass, audit log
-- ============================================================================
-- Full RBAC overhaul, applied SAFELY so the existing demo keeps working:
--   * Adds a `role` column to profiles (patient | doctor | admin) and an
--     `is_active` flag for admin activation/deactivation.
--   * Backfills the existing demo doctor account(s) to role='doctor', so the
--     doctor side keeps working unchanged.
--   * Redefines is_demo_doctor() to be ROLE-BASED instead of email-based â€”
--     every existing doctor RLS policy now keys off the role column with no
--     policy rewrites.
--   * Adds is_admin() + admin management policies on profiles.
--   * Adds an audit_log table (doctor/admin/break-glass/privacy actions).
--   * Adds break_glass_sessions (time-limited, read-only emergency admin
--     access) + has_active_break_glass() + read policies gated on it.
--
-- Run AFTER 0010_scan_region_nose.sql. Idempotent / safe to re-run.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) Role + account status on profiles
-- ---------------------------------------------------------------------------
ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS role text NOT NULL DEFAULT 'patient',
    ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true;

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_valid;
ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_role_valid CHECK (role IN ('patient', 'doctor', 'admin'));

-- Backfill: the existing demo doctor account(s) become role='doctor' so the
-- doctor experience is unchanged after the switch from email- to role-based.
UPDATE public.profiles p
SET role = 'doctor'
FROM auth.users u
WHERE u.id = p.id
  AND LOWER(u.email) IN ('doctor@dermatrack.demo', 'dr.demo@dermatrack.demo')
  AND p.role <> 'doctor';

COMMENT ON COLUMN public.profiles.role
    IS 'Access role: patient | doctor | admin. Basis for is_demo_doctor()/is_admin() and all role-based RLS.';
COMMENT ON COLUMN public.profiles.is_active
    IS 'Admin-controlled account status. Deactivated accounts are blocked at the app layer.';

-- ---------------------------------------------------------------------------
-- 2) Role helper functions (SECURITY DEFINER: read role without tripping RLS)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT role FROM public.profiles WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(public.current_user_role() = 'admin', false);
$$;

-- Redefine the (historically email-based) doctor check to be ROLE-based.
-- Same signature, so every existing policy that calls it now keys off role.
CREATE OR REPLACE FUNCTION public.is_demo_doctor()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(public.current_user_role() = 'doctor', false);
$$;

COMMENT ON FUNCTION public.is_demo_doctor()
    IS 'True iff the current user has role=''doctor'' (role-based since 0011).';

-- ---------------------------------------------------------------------------
-- 3) Admin management of profiles (user/role management, activate/deactivate)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Admins can update any profile" ON public.profiles;
CREATE POLICY "Admins can update any profile"
    ON public.profiles FOR UPDATE
    TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

-- ---------------------------------------------------------------------------
-- 4) Audit log
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.audit_log (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id       uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    actor_role     text,
    action         text NOT NULL,
    target_user_id uuid,
    detail         text,
    created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS audit_log_created_idx ON public.audit_log (created_at DESC);
CREATE INDEX IF NOT EXISTS audit_log_target_idx ON public.audit_log (target_user_id);

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

-- Any authenticated user can write their own audit entries (the app logs
-- doctor/admin/break-glass/privacy actions as they happen).
DROP POLICY IF EXISTS "Audit: insert own entries" ON public.audit_log;
CREATE POLICY "Audit: insert own entries"
    ON public.audit_log FOR INSERT
    TO authenticated
    WITH CHECK (actor_id = auth.uid());

-- Admins read everything; a user can read entries they performed or that
-- target them.
DROP POLICY IF EXISTS "Audit: read admin or self" ON public.audit_log;
CREATE POLICY "Audit: read admin or self"
    ON public.audit_log FOR SELECT
    TO authenticated
    USING (public.is_admin() OR actor_id = auth.uid() OR target_user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 5) Break-glass emergency access (time-limited, read-only by default)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.break_glass_sessions (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id          uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    target_patient_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    reason            text NOT NULL CHECK (length(btrim(reason)) > 0),
    duration_minutes  integer NOT NULL CHECK (duration_minutes IN (15, 30, 60)),
    read_only         boolean NOT NULL DEFAULT true,
    granted_at        timestamptz NOT NULL DEFAULT now(),
    expires_at        timestamptz NOT NULL,
    revoked           boolean NOT NULL DEFAULT false
);
CREATE INDEX IF NOT EXISTS bg_admin_idx ON public.break_glass_sessions (admin_id, expires_at DESC);
CREATE INDEX IF NOT EXISTS bg_target_idx ON public.break_glass_sessions (target_patient_id);

ALTER TABLE public.break_glass_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Break-glass: admin insert" ON public.break_glass_sessions;
CREATE POLICY "Break-glass: admin insert"
    ON public.break_glass_sessions FOR INSERT
    TO authenticated
    WITH CHECK (public.is_admin() AND admin_id = auth.uid());

DROP POLICY IF EXISTS "Break-glass: admin read" ON public.break_glass_sessions;
CREATE POLICY "Break-glass: admin read"
    ON public.break_glass_sessions FOR SELECT
    TO authenticated
    USING (public.is_admin());

DROP POLICY IF EXISTS "Break-glass: admin revoke" ON public.break_glass_sessions;
CREATE POLICY "Break-glass: admin revoke"
    ON public.break_glass_sessions FOR UPDATE
    TO authenticated
    USING (public.is_admin() AND admin_id = auth.uid())
    WITH CHECK (public.is_admin() AND admin_id = auth.uid());

-- True iff the calling admin holds an active (non-revoked, non-expired)
-- break-glass session for patient p.
CREATE OR REPLACE FUNCTION public.has_active_break_glass(p uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.break_glass_sessions b
        WHERE b.admin_id = auth.uid()
          AND b.target_patient_id = p
          AND b.revoked = false
          AND b.expires_at > now()
    );
$$;

-- Read-only break-glass access to a patient's clinical data while a session
-- is active. (No write policies â€” break-glass is read-only.)
DROP POLICY IF EXISTS "Break-glass: admin read scans" ON public.scans;
CREATE POLICY "Break-glass: admin read scans"
    ON public.scans FOR SELECT
    TO authenticated
    USING (public.is_admin() AND public.has_active_break_glass(user_id));

DROP POLICY IF EXISTS "Break-glass: admin read histories" ON public.patient_histories;
CREATE POLICY "Break-glass: admin read histories"
    ON public.patient_histories FOR SELECT
    TO authenticated
    USING (public.is_admin() AND public.has_active_break_glass(user_id));

-- ---------------------------------------------------------------------------
-- Sanity checks
-- ---------------------------------------------------------------------------
--   SELECT role, count(*) FROM public.profiles GROUP BY role;
--   SELECT public.is_demo_doctor();   -- true only for role='doctor' callers
--   SELECT public.is_admin();         -- true only for role='admin' callers


-- DermaTrack â€” Messaging: edit/unsend + admin moderation + behavior restriction
-- ============================================================================
-- Builds on 0009_messages.sql and the RBAC from 0011.
--   * messages: edit (edited_at), unsend (deleted_at, soft delete), and
--     admin removal (removed_by_admin).
--   * profiles.messaging_restricted: admin moderation flag that blocks a user
--     from sending (enforced by a RESTRICTIVE insert policy).
--   * RLS: sender can edit/unsend OWN messages; admin can read all + moderate.
--
-- Run AFTER 0011. Idempotent / safe to re-run.
-- ============================================================================

-- 1) messages: edit / unsend / admin-removal columns
ALTER TABLE public.messages
    ADD COLUMN IF NOT EXISTS edited_at        timestamptz,
    ADD COLUMN IF NOT EXISTS deleted_at       timestamptz,
    ADD COLUMN IF NOT EXISTS removed_by_admin boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.messages.edited_at
    IS 'Set when the sender edits the message (Messenger-style edit).';
COMMENT ON COLUMN public.messages.deleted_at
    IS 'Set when unsent (soft delete). Body retained for moderation; hidden in normal UI.';
COMMENT ON COLUMN public.messages.removed_by_admin
    IS 'True when an admin/moderator removed the message.';

-- 2) profiles: messaging restriction (moderation)
ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS messaging_restricted boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN public.profiles.messaging_restricted
    IS 'Admin moderation flag: when true the user cannot send chat messages.';

-- 3) Helper: is the calling user restricted from messaging?
CREATE OR REPLACE FUNCTION public.is_messaging_restricted()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(
        (SELECT messaging_restricted FROM public.profiles WHERE id = auth.uid()),
        false);
$$;

-- 4) Sender can edit / unsend their OWN messages. WITH CHECK forbids touching a
--    message an admin already removed (so a user can't undo moderation).
DROP POLICY IF EXISTS "Sender can update own message" ON public.messages;
CREATE POLICY "Sender can update own message"
    ON public.messages FOR UPDATE
    TO authenticated
    USING (sender_id = auth.uid())
    WITH CHECK (sender_id = auth.uid() AND removed_by_admin = false);

-- 5) Admin moderation: read every thread + remove any message.
DROP POLICY IF EXISTS "Admin can read all messages" ON public.messages;
CREATE POLICY "Admin can read all messages"
    ON public.messages FOR SELECT
    TO authenticated
    USING (public.is_admin());

DROP POLICY IF EXISTS "Admin can moderate messages" ON public.messages;
CREATE POLICY "Admin can moderate messages"
    ON public.messages FOR UPDATE
    TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

-- 6) Block restricted users from SENDING. RESTRICTIVE => ANDs with the existing
--    permissive patient/doctor insert policies, so a restricted user is denied.
DROP POLICY IF EXISTS "Block restricted senders" ON public.messages;
CREATE POLICY "Block restricted senders"
    ON public.messages
    AS RESTRICTIVE
    FOR INSERT
    TO authenticated
    WITH CHECK (NOT public.is_messaging_restricted());

-- ============================================================================
-- Sanity checks
--   UPDATE messages SET edited_at = now() WHERE id = '<own msg>';      -- sender OK
--   UPDATE messages SET deleted_at = now() WHERE id = '<own msg>';     -- unsend OK
--   (restricted user) INSERT INTO messages ... -> violates RLS
--   (admin) SELECT * FROM messages;                                    -- all threads
-- ============================================================================


-- DermaTrack â€” Role switcher for designated accounts + close self-role-change hole
-- ============================================================================
-- Problem found: the "Users can update own profile" policy had WITH CHECK = null
-- (falls back to USING auth.uid()=id), letting ANY user change their own
-- `role` -> privilege escalation. This migration:
--   * Adds profiles.can_switch_roles (admin-granted) for "super" demo accounts.
--   * Adds a BEFORE UPDATE trigger that blocks non-admins from changing
--     role / is_active / messaging_restricted / can_switch_roles, EXCEPT an
--     account flagged can_switch_roles may change its OWN role (for the
--     in-app role switcher). Trusted server/migration context (auth.uid() IS
--     NULL) is allowed.
--
-- Run AFTER 0012. Idempotent.
-- ============================================================================

ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS can_switch_roles boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN public.profiles.can_switch_roles
    IS 'When true, the account may switch its own role between patient/doctor/admin (demo/dev super account).';

-- Reads the flag for the current user (SECURITY DEFINER to bypass RLS read).
CREATE OR REPLACE FUNCTION public.can_switch_roles()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(
        (SELECT can_switch_roles FROM public.profiles WHERE id = auth.uid()),
        false);
$$;

-- Guard: privileged columns may only change under the right authority.
CREATE OR REPLACE FUNCTION public.guard_profile_privileged_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Trusted server / migration / SQL-editor context has no JWT user.
    IF auth.uid() IS NULL THEN
        RETURN NEW;
    END IF;

    -- role: admins (any profile) or a can-switch account (its own) may change.
    IF NEW.role IS DISTINCT FROM OLD.role THEN
        IF NOT (public.is_admin() OR public.can_switch_roles()) THEN
            RAISE EXCEPTION 'Not authorized to change role';
        END IF;
    END IF;

    -- status / privilege flags: admins only.
    IF (NEW.is_active IS DISTINCT FROM OLD.is_active)
        OR (NEW.messaging_restricted IS DISTINCT FROM OLD.messaging_restricted)
        OR (NEW.can_switch_roles IS DISTINCT FROM OLD.can_switch_roles) THEN
        IF NOT public.is_admin() THEN
            RAISE EXCEPTION 'Not authorized to change account status fields';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profiles_guard_privileged ON public.profiles;
CREATE TRIGGER profiles_guard_privileged
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.guard_profile_privileged_fields();

-- ============================================================================
-- Sanity checks
--   (patient) UPDATE profiles SET role='admin' WHERE id = auth.uid();  -> ERROR
--   (can_switch account) UPDATE profiles SET role='doctor' WHERE id = auth.uid(); -> OK
--   (admin) UPDATE profiles SET role='doctor' WHERE id = <other>;      -> OK
-- ============================================================================


-- DermaTrack â€” Harden account deactivation (VT-23) + restrict profile enumeration (R-1)
-- ============================================================================
-- Findings from the security assessment:
--   VT-23/AF-05: account deactivation was enforced only in the app; a
--     deactivated user's JWT still passed RLS. Fix: block deactivated users
--     from clinical data at the database via a RESTRICTIVE policy.
--   R-1: profiles.SELECT was USING(true) -> any authenticated user could
--     enumerate all usernames/roles. Fix: scope SELECT to self, admin, or a
--     doctor for consenting patients.
--
-- Run AFTER 0013. Idempotent.
-- ============================================================================

-- is_account_active(): the caller's own active flag (default true if missing).
-- SECURITY DEFINER so it can read profiles even under the new restrictive rule.
CREATE OR REPLACE FUNCTION public.is_account_active()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE((SELECT is_active FROM public.profiles WHERE id = auth.uid()), true);
$$;

-- VT-23 fix: a deactivated user is blocked from all clinical data. RESTRICTIVE
-- => ANDs with the existing permissive policies. profiles is intentionally
-- EXCLUDED so the app can still read the caller's own row to detect/show the
-- deactivated state. The check is on the CALLER's status, so an active
-- doctor/admin reading a (deactivated) patient's data is unaffected.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['scans','patient_histories','treatment_plans','prescriptions','doctor_notes','messages']
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS "Active accounts only" ON public.%I;', t);
    EXECUTE format('CREATE POLICY "Active accounts only" ON public.%I AS RESTRICTIVE FOR ALL TO authenticated USING (public.is_account_active()) WITH CHECK (public.is_account_active());', t);
  END LOOP;
END $$;

-- R-1 fix: profiles no longer world-readable.
DROP POLICY IF EXISTS "Profiles viewable by authenticated users" ON public.profiles;
DROP POLICY IF EXISTS "Profiles readable by self, doctor or admin" ON public.profiles;
CREATE POLICY "Profiles readable by self, doctor or admin"
    ON public.profiles FOR SELECT
    TO authenticated
    USING (
        id = auth.uid()
        OR public.is_admin()
        OR (public.is_demo_doctor() AND shared_with_doctor = true)
    );

-- ============================================================================
-- Sanity checks
--   (deactivated user) SELECT own scans            -> 0 rows (blocked)
--   (patient)          SELECT profiles             -> only own row
--   (doctor)           SELECT profiles consenting  -> allowed
--   (admin)            SELECT profiles             -> all
-- ============================================================================
