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
