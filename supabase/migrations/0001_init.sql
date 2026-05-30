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
