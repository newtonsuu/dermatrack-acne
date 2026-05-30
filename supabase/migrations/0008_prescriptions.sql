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
